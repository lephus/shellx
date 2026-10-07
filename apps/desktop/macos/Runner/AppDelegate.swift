import Cocoa
import FlutterMacOS
import flutter_secure_storage_darwin
import local_notifier
import package_info_plus
import shared_preferences_foundation

/// A5b D2: the same binary started with `--daemon` is the headless
/// `shellx-mux`: no window, no Dock icon, no menu bar.
let isDaemon = CommandLine.arguments.contains("--daemon")

@main
class AppDelegate: FlutterAppDelegate {
  private var daemonEngine: FlutterEngine?

  /// Fallback for a quit without a readable reason: macOS announced a log
  /// out, restart or shut down a moment ago. Reset after a while, because a
  /// log out that another app cancels never tells us.
  private var poweringOff = false
  private var poweringOffReset: DispatchWorkItem?

  override func applicationWillFinishLaunching(_ notification: Notification) {
    if isDaemon { NSApp.setActivationPolicy(.prohibited) }
    super.applicationWillFinishLaunching(notification)
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if isDaemon {
      let engine = FlutterEngine(name: "shellx-mux", project: nil, allowHeadlessExecution: true)
      engine.run(withEntrypoint: "daemonMain")
      DaemonPlugins.register(engine)
      LaunchAtLoginChannel.register(messenger: engine.binaryMessenger)
      daemonEngine = engine
      return
    }
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(willPowerOff(_:)),
      name: NSWorkspace.willPowerOffNotification, object: nil)
    super.applicationDidFinishLaunching(notification)
  }

  @objc private func willPowerOff(_ notification: Notification) {
    poweringOff = true
    poweringOffReset?.cancel()
    let reset = DispatchWorkItem { [weak self] in self?.poweringOff = false }
    poweringOffReset = reset
    DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: reset)
  }

  /// The `quit` Apple Event that asks us to terminate says why: log out,
  /// restart, shut down or a quit-all (never held up), or nothing for ⌘Q / menu Quit.
  private var quitIsForPowerOff: Bool {
    let reasons: [OSType] = [
      OSType(kAELogOut), OSType(kAEReallyLogOut),
      OSType(kAEShowRestartDialog), OSType(kAERestart),
      OSType(kAEShowShutdownDialog), OSType(kAEShutDown),
      // An installer or system update quitting every app.
      OSType(kAEQuitAll),
    ]
    guard
      let reason = NSAppleEventManager.shared().currentAppleEvent?
        .attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue
    else { return false }
    return reasons.contains(reason)
  }

  // ShellX lives in the menu bar; closing or hiding its window must not quit it.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Opening ShellX again (Finder, Spotlight, Launchpad, Dock) while it runs
  // reopens this process instead of starting a second one. Returning false
  // skips AppKit's own handling, so a window minimized with ⌘M is brought
  // back here; Dart decides what else to show (lib/src/ui/activation.dart).
  override func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    if isDaemon {
      DaemonForwarder.openUi()
      return false
    }
    for window in sender.windows where window.isMiniaturized {
      window.deminiaturize(nil)
    }
    AppChannel.reopen()
    return false
  }

  // ⌘Q and the app menu's Quit (shown while the Dock icon is, A1 D10) go
  // through Dart's quit flow: confirm, save, close every shell tree, then
  // exit(0), which never comes back here. Log out / shut down is never held
  // up for more than 3 s: Dart saves the restore files first (A5a D18).
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if isDaemon { return .terminateNow }
    if quitIsForPowerOff || poweringOff {
      guard AppChannel.isReady else { return .terminateNow }
      var replied = false
      let reply = {
        if replied { return }
        replied = true
        NSApp.reply(toApplicationShouldTerminate: true)
        // Still running 10 s after agreeing: the terminate stalled or did
        // not happen (AppKit gives no callback for a cancelled one), so
        // Dart goes on saving (A5a D12). A heuristic; harmless once the
        // process has exited.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
          AppChannel.exitCancelled()
        }
      }
      AppChannel.saveBeforeExit { reply() }
      DispatchQueue.main.asyncAfter(deadline: .now() + 3) { reply() }
      return .terminateLater
    }
    if !AppChannel.isReady { return .terminateNow }
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
      case "activate":
        // In front of the app the user was in (a tray click, the Dock, a
        // second launch): window_manager's focus() does not ignore other apps.
        NSApp.activate(ignoringOtherApps: true)
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

  /// A5a D18: `done` runs once Dart has saved (or failed to).
  static func saveBeforeExit(_ done: @escaping () -> Void) {
    guard let channel else {
      done()
      return
    }
    channel.invokeMethod("saveBeforeExit", arguments: nil) { _ in done() }
  }

  static func exitCancelled() {
    channel?.invokeMethod("exitCancelled", arguments: nil)
  }
}

/// LaunchServices may route a Finder/Dock/Spotlight "open" to the daemon
/// (same bundle id). The daemon then starts the UI instead.
enum DaemonForwarder {
  static func openUi() {
    let config = NSWorkspace.OpenConfiguration()
    config.createsNewApplicationInstance = true
    config.activates = true
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config)
  }
}

/// Only what the daemon uses (no window_manager, tray_manager,
/// screen_retriever: they need a view).
enum DaemonPlugins {
  static func register(_ registry: FlutterPluginRegistry) {
    FlutterSecureStorageDarwinPlugin.register(
      with: registry.registrar(forPlugin: "FlutterSecureStorageDarwinPlugin"))
    LocalNotifierPlugin.register(with: registry.registrar(forPlugin: "LocalNotifierPlugin"))
    FPPPackageInfoPlusPlugin.register(with: registry.registrar(forPlugin: "FPPPackageInfoPlusPlugin"))
    SharedPreferencesPlugin.register(with: registry.registrar(forPlugin: "SharedPreferencesPlugin"))
  }
}
