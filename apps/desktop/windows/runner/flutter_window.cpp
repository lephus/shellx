#include "flutter_window.h"

#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cstdint>
#include <optional>
#include <variant>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // ShellX starts hidden in the tray; Dart shows the window via window_manager.
  flutter_controller_->engine()->SetNextFrameCallback([&]() {});

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  // A4 D19. Explorer sends this when the window's taskbar button is
  // (re)created, e.g. when the window comes back from the tray.
  taskbar_button_created_ = RegisterWindowMessage(L"TaskbarButtonCreated");
  // An elevated ShellX would otherwise never get it from (non-elevated)
  // Explorer: UIPI filters registered messages sent from lower integrity.
  if (taskbar_button_created_ != 0) {
    ChangeWindowMessageFilterEx(GetHandle(), taskbar_button_created_,
                                MSGFLT_ALLOW, nullptr);
  }
  taskbar_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "pro.shellx.desktop/taskbar",
          &flutter::StandardMethodCodec::GetInstance());
  taskbar_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleTaskbar(call, std::move(result)); });

  // A5a D18: tells Dart the session is ending so it saves the restore files.
  app_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "pro.shellx.desktop/app",
          &flutter::StandardMethodCodec::GetInstance());

  return true;
}

void FlutterWindow::OnDestroy() {
  // No call may reach `this` while the channel goes away.
  if (taskbar_channel_) {
    taskbar_channel_->SetMethodCallHandler(nullptr);
    taskbar_channel_ = nullptr;
  }
  app_channel_ = nullptr;
  save_pending_ = false;
  if (taskbar_) {
    taskbar_->Release();
    taskbar_ = nullptr;
  }
  if (unread_icon_) {
    DestroyIcon(unread_icon_);
    unread_icon_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  if (taskbar_channel_ && taskbar_button_created_ != 0 &&
      message == taskbar_button_created_) {
    ApplyOverlay();
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_QUERYENDSESSION:
      // A5a D18: never blocks the shut down; Dart starts saving now.
      SaveBeforeExit();
      return TRUE;
    case WM_ENDSESSION:
      if (wparam) {
        // The process may end once this returns.
        WaitForSave();
      } else if (app_channel_) {
        // Shut down cancelled: Dart goes on saving (A5a D12).
        app_channel_->InvokeMethod("exitCancelled", nullptr);
      }
      return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::SaveBeforeExit() {
  if (!app_channel_ || save_pending_) return;
  save_pending_ = true;
  auto done = [this]() { save_pending_ = false; };
  app_channel_->InvokeMethod(
      "saveBeforeExit", nullptr,
      std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
          [done](const flutter::EncodableValue*) { done(); },
          [done](const std::string&, const std::string&,
                 const flutter::EncodableValue*) { done(); },
          [done]() { done(); }));
}

void FlutterWindow::WaitForSave() {
  // The engine's tasks (and so Dart's answer) arrive as window messages:
  // pump them until Dart answered, for at most 3 s.
  const ULONGLONG deadline = GetTickCount64() + 3000;
  while (save_pending_) {
    const ULONGLONG now = GetTickCount64();
    if (now >= deadline) return;
    MsgWaitForMultipleObjects(0, nullptr, FALSE,
                              static_cast<DWORD>(deadline - now), QS_ALLINPUT);
    MSG msg;
    while (save_pending_ && PeekMessage(&msg, nullptr, 0, 0, PM_REMOVE)) {
      if (msg.message == WM_QUIT) {
        PostQuitMessage(static_cast<int>(msg.wParam));
        return;
      }
      TranslateMessage(&msg);
      DispatchMessage(&msg);
    }
  }
}

// 16 px accent (#5FD4E2) dot, drawn once (no .ico asset).
HICON FlutterWindow::UnreadIcon() {
  if (unread_icon_) return unread_icon_;
  const int size = 16;
  BITMAPV5HEADER bi = {};
  bi.bV5Size = sizeof(bi);
  bi.bV5Width = size;
  bi.bV5Height = -size;  // top-down
  bi.bV5Planes = 1;
  bi.bV5BitCount = 32;
  bi.bV5Compression = BI_BITFIELDS;
  bi.bV5RedMask = 0x00FF0000;
  bi.bV5GreenMask = 0x0000FF00;
  bi.bV5BlueMask = 0x000000FF;
  bi.bV5AlphaMask = 0xFF000000;
  HDC dc = GetDC(nullptr);
  void* bits = nullptr;
  HBITMAP color = CreateDIBSection(dc, reinterpret_cast<BITMAPINFO*>(&bi),
                                   DIB_RGB_COLORS, &bits, nullptr, 0);
  ReleaseDC(nullptr, dc);
  if (!color) return nullptr;
  if (!bits) {
    DeleteObject(color);
    return nullptr;
  }
  auto* px = static_cast<uint32_t*>(bits);
  const double c = (size - 1) / 2.0;
  const double r = size / 2.0 - 1;
  for (int y = 0; y < size; ++y) {
    for (int x = 0; x < size; ++x) {
      const double dx = x - c;
      const double dy = y - c;
      const bool in = dx * dx + dy * dy <= r * r;
      // Premultiplied ARGB: opaque accent inside, transparent outside.
      px[y * size + x] = in ? 0xFF5FD4E2u : 0x00000000u;
    }
  }
  // Monochrome mask, rows WORD-aligned; all zero so the alpha channel
  // decides. CreateBitmap leaves the bits undefined without a buffer.
  const size_t mask_bytes = static_cast<size_t>(((size + 15) / 16) * 2 * size);
  std::vector<BYTE> mask_bits(mask_bytes, 0);
  HBITMAP mask = CreateBitmap(size, size, 1, 1, mask_bits.data());
  if (!mask) {
    DeleteObject(color);
    return nullptr;
  }
  ICONINFO info = {};
  info.fIcon = TRUE;
  info.hbmColor = color;
  info.hbmMask = mask;
  // CreateIconIndirect copies both bitmaps.
  unread_icon_ = CreateIconIndirect(&info);
  DeleteObject(color);
  DeleteObject(mask);
  return unread_icon_;
}

HRESULT FlutterWindow::ApplyOverlay() {
  if (!taskbar_) {
    ITaskbarList3* list = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TaskbarList, nullptr,
                                  CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&list));
    if (FAILED(hr)) return hr;
    hr = list->HrInit();
    if (FAILED(hr)) {
      list->Release();
      return hr;
    }
    taskbar_ = list;
  }
  if (unread_count_ <= 0) {
    return taskbar_->SetOverlayIcon(GetHandle(), nullptr, nullptr);
  }
  HICON icon = UnreadIcon();
  if (!icon) return E_FAIL;
  return taskbar_->SetOverlayIcon(GetHandle(), icon,
                                  unread_description_.c_str());
}

void FlutterWindow::HandleTaskbar(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  HWND hwnd = GetHandle();
  if (call.method_name() == "flash") {
    if (hwnd && GetForegroundWindow() != hwnd) {
      FLASHWINFO info = {};
      info.cbSize = sizeof(info);
      info.hwnd = hwnd;
      info.dwFlags = FLASHW_TRAY | FLASHW_TIMERNOFG;
      FlashWindowEx(&info);
    }
    result->Success();
    return;
  }
  if (call.method_name() != "setUnread") {
    result->NotImplemented();
    return;
  }
  int count = 0;
  std::string description;
  if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
    auto c = args->find(flutter::EncodableValue("count"));
    if (c != args->end()) {
      // The standard codec sends small Dart ints as int32, large as int64.
      if (const auto* v = std::get_if<int32_t>(&c->second)) {
        count = *v;
      } else if (const auto* w = std::get_if<int64_t>(&c->second)) {
        count = static_cast<int>(std::min<int64_t>(*w, INT32_MAX));
      }
    }
    auto d = args->find(flutter::EncodableValue("description"));
    if (d != args->end()) {
      if (const auto* s = std::get_if<std::string>(&d->second)) {
        description = *s;
      }
    }
  }
  // UTF-8 (Dart) to UTF-16 (Win32): the description can be Vietnamese.
  std::wstring wide;
  int n = MultiByteToWideChar(CP_UTF8, 0, description.c_str(), -1, nullptr, 0);
  if (n > 1) {
    wide.resize(static_cast<size_t>(n - 1));
    MultiByteToWideChar(CP_UTF8, 0, description.c_str(), -1, wide.data(), n);
  }
  unread_count_ = count;
  unread_description_ = std::move(wide);
  // A failure with a taskbar list means no taskbar button yet (window in
  // the tray): the count is kept and applied on "TaskbarButtonCreated",
  // so it is not an error for Dart.
  ApplyOverlay();
  if (!taskbar_) {
    result->Error("taskbar", "ITaskbarList3 unavailable");
    return;
  }
  result->Success();
}
