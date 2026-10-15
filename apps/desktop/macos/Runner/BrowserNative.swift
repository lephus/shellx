import Cocoa
import FlutterMacOS
import WebKit
import webview_flutter_wkwebview

/// A6 Task 7, taken for V2-3 tools: what webview_flutter's Dart API lacks —
/// stop, clearing the app's website data, and handing ShellX chords and
/// clicks back to Flutter while a page has the keyboard. No script, no
/// snapshot (V2-3 D16). Channel "pro.shellx.desktop/browser". Never logs
/// URLs, titles or page content. V2-3 Task 5 reviews and hardens it.
final class BrowserNative: NSObject {
  private let channel: FlutterMethodChannel
  private let controller: FlutterViewController
  /// Web view id → chords to forward. An id is known once Dart called
  /// setForwardedChords for it (every engine does at setup).
  private var forwarded: [Int64: Set<String>] = [:]
  private var keyMonitor: Any?
  private var mouseMonitor: Any?

  init(controller: FlutterViewController) {
    self.controller = controller
    channel = FlutterMethodChannel(
      name: "pro.shellx.desktop/browser",
      binaryMessenger: controller.engine.binaryMessenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result) ?? result(nil)
    }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
      [weak self] event in
      guard let self, let id = self.paneWebViewId(firstResponderOf: event),
        let chord = BrowserNative.chord(event),
        self.forwarded[id]?.contains(chord) == true
      else { return event }
      self.channel.invokeMethod("shortcut", arguments: ["id": id, "chord": chord])
      return nil  // the page never sees a ShellX chord
    }
    mouseMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] event in
      if let self, let id = self.paneWebViewId(under: event) {
        self.channel.invokeMethod("pointerDown", arguments: ["id": id])
      }
      return event
    }
  }

  deinit {
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
  }

  /// The WKWebView behind a Dart `WebKitWebViewController.webViewIdentifier`
  /// (the plugin's public native API, stable across its versions).
  private func webView(_ id: Int64) -> WKWebView? {
    FWFWebViewFlutterWKWebViewExternalAPI.webView(
      forIdentifier: id, withPluginRegistry: controller)
  }

  private func paneWebViewId(firstResponderOf event: NSEvent) -> Int64? {
    guard let view = event.window?.firstResponder as? NSView else { return nil }
    return paneWebViewId(containing: view)
  }

  private func paneWebViewId(under event: NSEvent) -> Int64? {
    guard let content = event.window?.contentView,
      let hit = content.hitTest(event.locationInWindow)
    else { return nil }
    return paneWebViewId(containing: hit)
  }

  private func paneWebViewId(containing view: NSView) -> Int64? {
    var current: NSView? = view
    while let v = current, !(v is WKWebView) { current = v.superview }
    guard let web = current as? WKWebView else { return nil }
    return forwarded.keys.first { webView($0) === web }
  }

  /// Same format as Dart's `chordString`: alt, ctrl, meta, shift, key.
  static func chord(_ event: NSEvent) -> String? {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let key: String
    switch event.keyCode {
    case 123: key = "left"
    case 124: key = "right"
    case 125: key = "down"
    case 126: key = "up"
    case 53: key = "escape"
    case 36: key = "enter"
    case 48: key = "tab"
    case 96: key = "f5"
    case 97: key = "f6"
    default:
      guard let c = event.charactersIgnoringModifiers?.lowercased(), c.count == 1
      else { return nil }
      key = c
    }
    var parts: [String] = []
    if flags.contains(.option) { parts.append("alt") }
    if flags.contains(.control) { parts.append("ctrl") }
    if flags.contains(.command) { parts.append("meta") }
    if flags.contains(.shift) { parts.append("shift") }
    parts.append(key)
    return parts.joined(separator: "+")
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let id = (args["id"] as? NSNumber)?.int64Value
    switch call.method {
    case "clearWebsiteData":
      WKWebsiteDataStore.default().removeData(
        ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
        modifiedSince: .distantPast
      ) { result(nil) }
      return
    case "setForwardedChords":
      if let id { forwarded[id] = Set(args["chords"] as? [String] ?? []) }
      result(nil)
      return
    case "forget":
      if let id { forwarded.removeValue(forKey: id) }
      result(nil)
      return
    default:
      break
    }
    guard let id, let web = webView(id) else {
      result(FlutterError(code: "not_found", message: nil, details: nil))
      return
    }
    switch call.method {
    case "stop":
      web.stopLoading()
      result(nil)
    case "focus":
      web.window?.makeFirstResponder(web)
      result(nil)
    case "blur":
      // Back to the Flutter view, so the next keys reach Flutter (D16).
      if let responder = web.window?.firstResponder as? NSView,
        responder === web || responder.isDescendant(of: web)
      {
        web.window?.makeFirstResponder(controller.view)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
