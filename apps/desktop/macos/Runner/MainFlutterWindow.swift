import Cocoa
import FlutterMacOS
import ServiceManagement
import window_manager

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    LaunchAtLoginChannel.register(
      messenger: flutterViewController.engine.binaryMessenger)
    AppReopenChannel.register(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  // Keep the window hidden at launch; Dart decides when to show it.
  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}

/// Implements the `launch_at_startup` channel expected by package
/// launch_at_startup on macOS: SMAppService on macOS 13+, a per-user
/// LaunchAgent plist on macOS 12.
enum LaunchAtLoginChannel {
  static let label = "pro.shellx.desktop"

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "launch_at_startup", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "launchAtStartupIsEnabled":
        result(isEnabled())
      case "launchAtStartupSetEnabled":
        let enabled = (call.arguments as? [String: Any])?["setEnabledValue"] as? Bool ?? false
        do {
          try setEnabled(enabled)
          result(nil)
        } catch {
          result(FlutterError(code: "launch_at_login", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static var agentPlistURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents/\(label).plist")
  }

  static func isEnabled() -> Bool {
    if #available(macOS 13.0, *) {
      return SMAppService.mainApp.status == .enabled
    }
    return FileManager.default.fileExists(atPath: agentPlistURL.path)
  }

  static func setEnabled(_ enabled: Bool) throws {
    if #available(macOS 13.0, *) {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      return
    }
    let url = agentPlistURL
    if enabled {
      let plist: [String: Any] = [
        "Label": label,
        "ProgramArguments": [Bundle.main.executablePath ?? ""],
        "RunAtLoad": true,
        "ProcessType": "Interactive",
      ]
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let data = try PropertyListSerialization.data(
        fromPropertyList: plist, format: .xml, options: 0)
      try data.write(to: url, options: .atomic)
    } else if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }
}
