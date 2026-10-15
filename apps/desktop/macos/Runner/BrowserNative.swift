import Cocoa
import FlutterMacOS
import WebKit
import webview_flutter_wkwebview

/// V2-3 (A6 Task 7, taken for tools): what webview_flutter's Dart API
/// lacks — stopping a load, clearing the app's website data, keeping a page's
/// new windows out of the tool, and handing ShellX chords and clicks back to
/// Flutter while a page has the keyboard (spec D8, D9, D10). Channel
/// "pro.shellx.desktop/browser". No script, no snapshot (D16). Never logs a
/// URL, a title or page content.
final class BrowserNative: NSObject {
  private let channel: FlutterMethodChannel
  private let controller: FlutterViewController
  /// Web view id → chords to forward (config spelling, Dart's
  /// `chordConfigText`). An id is known once Dart attached it.
  private var forwarded: [Int64: Set<String>] = [:]
  /// Web view id → the guards standing in front of the plugin's delegates.
  private var windowGuards: [Int64: NewWindowGuard] = [:]
  private var downloadGuards: [Int64: DownloadGuard] = [:]
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
      guard let self, let id = self.toolWebViewId(firstResponderOf: event),
        let chord = BrowserNative.chord(event),
        self.forwarded[id]?.contains(chord) == true
      else { return event }
      self.channel.invokeMethod("shortcut", arguments: ["id": id, "chord": chord])
      return nil  // D10: the page never sees a ShellX chord
    }
    mouseMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] event in
      guard let self else { return event }
      if let id = self.toolWebViewId(under: event) {
        self.channel.invokeMethod("pointerDown", arguments: ["id": id])
      } else if self.toolWebViewId(firstResponderOf: event) != nil {
        // D10: a click anywhere outside the page gives the keyboard back to
        // Flutter, whatever was clicked.
        event.window?.makeFirstResponder(self.controller.view)
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

  private func toolWebViewId(firstResponderOf event: NSEvent) -> Int64? {
    guard let view = event.window?.firstResponder as? NSView else { return nil }
    return toolWebViewId(containing: view)
  }

  private func toolWebViewId(under event: NSEvent) -> Int64? {
    guard let content = event.window?.contentView,
      let hit = content.hitTest(event.locationInWindow)
    else { return nil }
    return toolWebViewId(containing: hit)
  }

  private func toolWebViewId(containing view: NSView) -> Int64? {
    var current: NSView? = view
    while let v = current, !(v is WKWebView) { current = v.superview }
    guard let web = current as? WKWebView else { return nil }
    return forwarded.keys.first { webView($0) === web }
  }

  /// Keys named by their code (layout-independent), in Dart's config
  /// spelling (`keybind_trigger.dart` `_names`, first name of each key).
  static let namedKeys: [UInt16: String] = [
    36: "enter", 76: "kp_enter", 48: "tab", 53: "escape", 49: "space",
    51: "backspace", 117: "delete", 114: "insert", 115: "home", 119: "end",
    116: "page_up", 121: "page_down", 123: "arrow_left", 124: "arrow_right",
    125: "arrow_down", 126: "arrow_up", 122: "f1", 120: "f2", 99: "f3",
    118: "f4", 96: "f5", 97: "f6", 98: "f7", 100: "f8", 101: "f9",
    109: "f10", 103: "f11", 111: "f12", 105: "f13", 107: "f14", 113: "f15",
    106: "f16", 64: "f17", 79: "f18", 80: "f19", 90: "f20", 69: "kp_add",
    78: "kp_subtract", 82: "kp_0", 83: "kp_1", 84: "kp_2", 85: "kp_3",
    86: "kp_4", 87: "kp_5", 88: "kp_6", 89: "kp_7", 91: "kp_8", 92: "kp_9",
  ]

  /// Punctuation by the character the key types without modifiers.
  static let punctuation: [String: String] = [
    "=": "equal", "-": "minus", "+": "plus", ",": "comma", ".": "period",
    "/": "slash", "\\": "backslash", ";": "semicolon", "'": "quote",
    "`": "backquote", "[": "bracket_left", "]": "bracket_right",
  ]

  /// The key of [event] as Dart's `chordConfigText` writes it; nil for a
  /// key Dart has no name for.
  static func keyName(_ event: NSEvent) -> String? {
    if let named = namedKeys[event.keyCode] { return named }
    // The character without Shift, Option or Command: ⌘⇧1 is "1", ⌘⇧= is
    // "=", as Flutter's logical key is.
    guard let raw = event.characters(byApplyingModifiers: []), raw.count == 1
    else { return nil }
    let c = raw.lowercased()
    if let p = punctuation[c] { return p }
    guard let scalar = c.unicodeScalars.first else { return nil }
    if scalar.value < 0x80 {
      let letter = scalar.value >= 0x61 && scalar.value <= 0x7a
      let digit = scalar.value >= 0x30 && scalar.value <= 0x39
      return letter || digit ? c : nil
    }
    return c  // a layout's own letter (ö, é), as Dart writes it
  }

  /// [event] as Dart's `chordConfigText` writes a chord: ctrl, alt, shift,
  /// super, then the key.
  static func chord(_ event: NSEvent) -> String? {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard let key = keyName(event) else { return nil }
    var parts: [String] = []
    if flags.contains(.control) { parts.append("ctrl") }
    if flags.contains(.option) { parts.append("alt") }
    if flags.contains(.shift) { parts.append("shift") }
    if flags.contains(.command) { parts.append("super") }
    parts.append(key)
    return parts.joined(separator: "+")
  }

  private func send(_ method: String, id: Int64, url: URL?) {
    var arguments: [String: Any] = ["id": id]
    if let url { arguments["url"] = url.absoluteString }
    channel.invokeMethod(method, arguments: arguments)
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let id = (args["id"] as? NSNumber)?.int64Value
    switch call.method {
    case "clearWebsiteData":
      // D8, D22: the app's default store — every tool's cookies and storage.
      WKWebsiteDataStore.default().removeData(
        ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
        modifiedSince: .distantPast
      ) { result(nil) }
      return
    case "setForwardedChords":
      if let id, forwarded[id] != nil {
        forwarded[id] = Set(args["chords"] as? [String] ?? [])
      }
      result(nil)
      return
    case "forget":
      if let id {
        forwarded.removeValue(forKey: id)
        let web = webView(id)
        if let guardian = windowGuards.removeValue(forKey: id),
          let web, web.uiDelegate === guardian
        {
          web.uiDelegate = guardian.inner
        }
        if let guardian = downloadGuards.removeValue(forKey: id),
          let web, web.navigationDelegate === guardian
        {
          web.navigationDelegate = guardian.inner
        }
      }
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
    case "attach":
      if forwarded[id] == nil { forwarded[id] = [] }
      if windowGuards[id] == nil, let inner = web.uiDelegate {
        let guardian = NewWindowGuard(inner: inner) { [weak self] url in
          self?.send("newWindow", id: id, url: url)
        }
        windowGuards[id] = guardian
        web.uiDelegate = guardian
      }
      if downloadGuards[id] == nil, let inner = web.navigationDelegate {
        let guardian = DownloadGuard(inner: inner) { [weak self] url in
          self?.send("download", id: id, url: url)
        }
        downloadGuards[id] = guardian
        web.navigationDelegate = guardian
      }
      result(nil)
    case "stop":
      web.stopLoading()
      result(nil)
    case "focus":
      web.window?.makeFirstResponder(web)
      result(nil)
    case "blur":
      // D10: back to the Flutter view, so the next keys reach Flutter.
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

/// V2-3 D9: a page's new window (`target=_blank`, `window.open`) never opens
/// in the tool. The plugin's own UI delegate would load it in the same view;
/// this guard answers "no window" and hands the URL to Dart, and passes every
/// other call (JavaScript dialogs, media permissions) on to the plugin's
/// delegate. WKWebView holds its delegate weakly: BrowserNative keeps the
/// guard, the guard keeps the plugin's delegate.
final class NewWindowGuard: NSObject, WKUIDelegate {
  let inner: WKUIDelegate
  private let onNewWindow: (URL?) -> Void

  init(inner: WKUIDelegate, onNewWindow: @escaping (URL?) -> Void) {
    self.inner = inner
    self.onNewWindow = onNewWindow
    super.init()
  }

  func webView(
    _ webView: WKWebView,
    createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction,
    windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    onNewWindow(navigationAction.request.url)
    return nil
  }

  override func responds(to aSelector: Selector!) -> Bool {
    super.responds(to: aSelector) || inner.responds(to: aSelector)
  }

  override func forwardingTarget(for aSelector: Selector!) -> Any? {
    inner.responds(to: aSelector) ? inner : super.forwardingTarget(for: aSelector)
  }
}

/// V2-3 D9: a tool never downloads. The plugin's navigation delegate lets
/// every response show (a zip would replace the page); this guard stops a
/// top-frame response that is a download — an attachment, or a type WebKit
/// cannot show — and hands its URL to Dart, and passes every other call on
/// to the plugin's delegate.
final class DownloadGuard: NSObject, WKNavigationDelegate {
  let inner: WKNavigationDelegate
  private let onDownload: (URL?) -> Void

  init(inner: WKNavigationDelegate, onDownload: @escaping (URL?) -> Void) {
    self.inner = inner
    self.onDownload = onDownload
    super.init()
  }

  static func isDownload(_ response: WKNavigationResponse) -> Bool {
    guard response.isForMainFrame else { return false }
    if !response.canShowMIMEType { return true }
    guard let http = response.response as? HTTPURLResponse,
      let disposition = http.value(forHTTPHeaderField: "Content-Disposition")
    else { return false }
    return disposition.trimmingCharacters(in: .whitespaces).lowercased()
      .hasPrefix("attachment")
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationResponse: WKNavigationResponse,
    decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
  ) {
    if DownloadGuard.isDownload(navigationResponse) {
      onDownload(navigationResponse.response.url)
      decisionHandler(.cancel)
      return
    }
    let answered: Void? = inner.webView?(
      webView, decidePolicyFor: navigationResponse, decisionHandler: decisionHandler)
    if answered == nil { decisionHandler(.allow) }
  }

  override func responds(to aSelector: Selector!) -> Bool {
    super.responds(to: aSelector) || inner.responds(to: aSelector)
  }

  override func forwardingTarget(for aSelector: Selector!) -> Any? {
    inner.responds(to: aSelector) ? inner : super.forwardingTarget(for: aSelector)
  }
}
