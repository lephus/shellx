import '../browser/browser_engine.dart';

/// Pages a frame of a tool may show besides http/https (an iframe of
/// `about:srcdoc`, `data:` or `blob:` content stays inside the page).
const Set<String> _frameSchemes = {'http', 'https', 'about', 'data', 'blob'};

/// Links the operating system answers (mail, phone).
const Set<String> _systemSchemes = {'mailto', 'tel'};

/// V2-3 D9: where a navigation of a tool's page goes.
/// - The top frame: any http/https page (an SSO round trip included);
///   `about:blank`; `mailto:`/`tel:` go outside; anything else (`file:`,
///   `javascript:`, `data:`, an unknown scheme) is blocked, silently.
/// - A new window (`target=_blank`, `window.open`): outside for http,
///   https, mailto and tel; blocked otherwise. Never inside the tool.
/// - Another frame: http/https/about/data/blob load; the rest is blocked.
NavigationVerdict toolNavigation(
  Uri? url, {
  required bool mainFrame,
  required bool newWindow,
}) {
  if (url == null) return NavigationVerdict.block;
  final scheme = url.scheme.toLowerCase();
  final web = (scheme == 'http' || scheme == 'https') && url.host.isNotEmpty;
  if (newWindow) {
    return web || _systemSchemes.contains(scheme)
        ? NavigationVerdict.outside
        : NavigationVerdict.block;
  }
  if (!mainFrame) {
    return _frameSchemes.contains(scheme)
        ? NavigationVerdict.allow
        : NavigationVerdict.block;
  }
  if (web || url.toString() == 'about:blank') return NavigationVerdict.allow;
  if (_systemSchemes.contains(scheme)) return NavigationVerdict.outside;
  return NavigationVerdict.block;
}
