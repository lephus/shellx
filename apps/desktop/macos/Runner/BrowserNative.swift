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

  /// What the US layout types on each typewriter key (ANSI key codes
  /// 0x00–0x32; Return, Tab and Space are named keys).
  static let usCharacters: [UInt16: String] = [
    0x00: "a", 0x01: "s", 0x02: "d", 0x03: "f", 0x04: "h", 0x05: "g",
    0x06: "z", 0x07: "x", 0x08: "c", 0x09: "v", 0x0B: "b", 0x0C: "q",
    0x0D: "w", 0x0E: "e", 0x0F: "r", 0x10: "y", 0x11: "t", 0x12: "1",
    0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=",
    0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
    0x1F: "o", 0x20: "u", 0x21: "[", 0x22: "i", 0x23: "p", 0x25: "l",
    0x26: "j", 0x27: "'", 0x28: "k", 0x29: ";", 0x2A: "\\", 0x2B: ",",
    0x2C: "/", 0x2D: "n", 0x2E: "m", 0x2F: ".", 0x32: "`",
  ]

  /// The key of [event] as Dart's `chordConfigText` writes it; nil for a
  /// key Dart has no name for.
  static func keyName(_ event: NSEvent) -> String? {
    keyName(
      code: event.keyCode,
      unshifted: event.characters(byApplyingModifiers: []),
      shifted: event.characters(byApplyingModifiers: .shift))
  }

  /// D10: a key named as Flutter names its logical key, so a chord pressed
  /// in a page is the keymap's chord on any layout. Named keys go by key
  /// code. A typewriter key (0x00–0x32) is, in this order:
  /// (a) the ASCII letter or digit it types without Shift, else with Shift
  ///     (AZERTY's and Czech's digit rows give 1…0);
  /// (b) when it types nothing in Latin-1 with or without Shift (Russian,
  ///     Greek), the US key at its place: ⌘T is "t";
  /// (c) else what it types without Shift, as every other key: ⌘⇧= is "=".
  static func keyName(code: UInt16, unshifted: String?, shifted: String?) -> String? {
    if let named = namedKeys[code] { return named }
    if code <= 0x32 {
      if let c = asciiAlnum(unshifted?.lowercased()) ?? asciiAlnum(shifted) {
        return c
      }
      if !latin1(unshifted), !latin1(shifted), let us = usCharacters[code] {
        return characterName(us)
      }
    }
    guard let raw = unshifted, raw.count == 1 else { return nil }
    return characterName(raw.lowercased())
  }

  /// An ASCII letter or digit as typed (Flutter's layout goals: a–z, 0–9).
  static func asciiAlnum(_ c: String?) -> String? {
    guard let c, c.unicodeScalars.count == 1,
      let v = c.unicodeScalars.first?.value,
      (0x61...0x7a).contains(v) || (0x30...0x39).contains(v)
    else { return nil }
    return c
  }

  /// Latin-1 as Flutter's layout check counts it: no character counts too.
  static func latin1(_ c: String?) -> Bool {
    guard let v = c?.unicodeScalars.first?.value else { return true }
    return v < 0x100
  }

  /// One character as Dart's `chordConfigText` writes it: punctuation by
  /// name, an ASCII letter or digit as itself, a layout's own letter as
  /// itself; nil for any other ASCII.
  static func characterName(_ c: String) -> String? {
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
        // D5: a closed or unloaded tool stops at once (scripts, sockets,
        // sound), although the plugin keeps the view until Dart lets go.
        // Its id is unknown by now, and Dart's engine is closed: nothing of
        // this blank page reaches it.
        if let web, let blank = URL(string: "about:blank") {
          web.stopLoading()
          web.load(URLRequest(url: blank))
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
        let guardian = DownloadGuard(
          inner: inner,
          onDownload: { [weak self] url in
            self?.send("download", id: id, url: url)
          },
          onNewWindow: { [weak self] url in
            self?.send("newWindow", id: id, url: url)
          })
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

/// V2-3 D9: a tool never downloads, and a page's new window never opens in
/// it. The plugin's navigation delegate lets every response show (a zip
/// would replace the page) and judges a new window's link as a frame's. This
/// guard stands in front of it:
/// - a link the page asks to download (`<a download>`) is cancelled and
///   handed to Dart as `download`; then a link to a new window
///   (`target=_blank`) as `newWindow`, the message NewWindowGuard sends for
///   `window.open`;
/// - a top-frame response that is a download (an attachment, or a type
///   WebKit cannot show) is cancelled and handed to Dart as `download`;
/// - every other call goes on to the plugin's delegate. The pinned plugin
///   implements only the navigation-action call without `preferences:`, so
///   WebKit asks this one (R4: re-check on an upgrade).
final class DownloadGuard: NSObject, WKNavigationDelegate {
  let inner: WKNavigationDelegate
  private let onDownload: (URL?) -> Void
  private let onNewWindow: (URL?) -> Void

  init(
    inner: WKNavigationDelegate,
    onDownload: @escaping (URL?) -> Void,
    onNewWindow: @escaping (URL?) -> Void
  ) {
    self.inner = inner
    self.onDownload = onDownload
    self.onNewWindow = onNewWindow
    super.init()
  }

  /// A download link's URL for Dart; none for `blob:` and `data:`, which
  /// mean nothing outside the page.
  static func downloadURL(_ url: URL?) -> URL? {
    let scheme = url?.scheme?.lowercased()
    return scheme == "blob" || scheme == "data" ? nil : url
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    if navigationAction.shouldPerformDownload {
      onDownload(DownloadGuard.downloadURL(navigationAction.request.url))
      decisionHandler(.cancel)
      return
    }
    if navigationAction.targetFrame == nil {
      onNewWindow(navigationAction.request.url)
      decisionHandler(.cancel)
      return
    }
    let answered: Void? = inner.webView?(
      webView, decidePolicyFor: navigationAction, decisionHandler: decisionHandler)
    if answered == nil { decisionHandler(.allow) }
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
