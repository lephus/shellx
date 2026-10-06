import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// macOS is logging out, restarting or shutting down: never hold it up.
  private var poweringOff = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(willPowerOff(_:)),
      name: NSWorkspace.willPowerOffNotification, object: nil)
    super.applicationDidFinishLaunching(notification)
  }

  @objc private func willPowerOff(_ notification: Notification) {
    poweringOff = true
  }

  // ShellX lives in the menu bar; closing or hiding its window must not quit it.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Opening ShellX again (Finder, Spotlight, Launchpad, Dock) while it runs
  // reopens this process instead of starting a second one. Dart decides what
  // to show (lib/src/ui/activation.dart).
  override func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    AppChannel.reopen()
    return false
  }

  // ⌘Q and the app menu's Quit (shown while the Dock icon is, A1 D10) go
  // through Dart's quit flow: confirm, close every shell tree, then exit(0),
  // which never comes back here. Log out / shut down is never blocked.
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if poweringOff || !AppChannel.isReady {
      return .terminateNow
    }
    AppChannel.quitRequested()
    return .terminateCancel
  }
}

/// `pro.shellx.desktop/app` (lib/src/platform/app_reopen.dart).
enum AppChannel {
  private static var channel: FlutterMethodChannel?

  static var isReady: Bool { channel != nil }

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "pro.shellx.desktop/app", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "setDockVisible":
        // `.regular` while the terminal window is visible (Dock icon, ⌘Tab,
        // menu bar with ⌘Q), `.accessory` (menu bar app) while it is hidden.
        let visible = call.arguments as? Bool ?? false
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
        if visible {
          NSApp.activate(ignoringOtherApps: true)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  static func reopen() {
    channel?.invokeMethod("reopen", arguments: nil)
  }

  static func quitRequested() {
    channel?.invokeMethod("quitRequested", arguments: nil)
  }
}
