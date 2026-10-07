// A5b D3: headless shellx-mux — one FlutterEngine, no window.
#include "daemon_runner.h"

#include <flutter/flutter_engine.h>
#include <windows.h>

#include <flutter_secure_storage_windows/flutter_secure_storage_windows_plugin.h>
#include <local_notifier/local_notifier_plugin.h>

int RunDaemon(flutter::DartProject project) {
  project.set_dart_entrypoint("daemonMain");
  flutter::FlutterEngine engine(project);
  if (!engine.Run("daemonMain")) {
    return EXIT_FAILURE;
  }
  FlutterSecureStorageWindowsPluginRegisterWithRegistrar(
      engine.GetRegistrarForPlugin("FlutterSecureStorageWindowsPlugin"));
  LocalNotifierPluginRegisterWithRegistrar(
      engine.GetRegistrarForPlugin("LocalNotifierPlugin"));

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }
  return EXIT_SUCCESS;
}
