#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <shobjidl.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // A4 D19: taskbar overlay dot + flash (pro.shellx.desktop/taskbar).
  void HandleTaskbar(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  // Sets the overlay for the last count Dart sent. Fails while the window
  // has no taskbar button (hidden in the tray); "TaskbarButtonCreated"
  // calls it again when the button comes back.
  HRESULT ApplyOverlay();
  HICON UnreadIcon();
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      taskbar_channel_;

  // A5a D18: pro.shellx.desktop/app. WM_QUERYENDSESSION asks Dart to save
  // the restore files; WM_ENDSESSION waits (at most 3 s) for the answer
  // (then, for Restart Manager, asks Dart to quit), or tells Dart the shut
  // down was cancelled.
  void SaveBeforeExit();
  void WaitForSave();
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      app_channel_;
  bool save_pending_ = false;
  ITaskbarList3* taskbar_ = nullptr;
  HICON unread_icon_ = nullptr;
  UINT taskbar_button_created_ = 0;
  int unread_count_ = 0;
  std::wstring unread_description_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
