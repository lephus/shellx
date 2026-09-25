import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // ShellX lives in the menu bar; closing or hiding its window must not quit it.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Opening ShellX again (Finder, Spotlight, Launchpad) while it runs reopens
  // this process instead of starting a second one, so the single-instance
  // signal never fires. Dart decides what to show (lib/src/ui/activation.dart);
  // AppKit's own reopen handling has nothing to add for a menu bar app.
  override func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    AppReopenChannel.reopen()
    return false
  }
}

/// `pro.shellx.desktop/app` (lib/src/platform/app_reopen.dart): tells Dart
/// that the running app was opened again.
enum AppReopenChannel {
  private static var channel: FlutterMethodChannel?

  static func register(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "pro.shellx.desktop/app", binaryMessenger: messenger)
  }

  static func reopen() {
    channel?.invokeMethod("reopen", arguments: nil)
  }
}
