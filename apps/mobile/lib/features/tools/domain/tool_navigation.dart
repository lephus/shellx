/// V2-4 E12: what the tool page's web view does with a navigation.
sealed class ToolNavigation {
  const ToolNavigation();
}

/// Go on: a page this phone serves, a frame inside the page, `about:blank`.
final class ToolGo extends ToolNavigation {
  const ToolGo();
}

/// Go to [url] instead: another loopback spelling of a served port, as `localhost` (where the gate
/// cookie is; E2).
final class ToolGoInstead extends ToolNavigation {
  const ToolGoInstead(this.url);
  final Uri url;
}

/// Another http(s) site: ask, then open it in the phone's browser.
final class ToolAskExternal extends ToolNavigation {
  const ToolAskExternal(this.url);
  final Uri url;
}

/// A port of this phone's loopback that is not served (a tool not on for phone, E4): stopped, and
/// the page says which.
final class ToolOtherLocal extends ToolNavigation {
  const ToolOtherLocal(this.port);
  final int port;
}

/// Anything else (`javascript:`, `file:`, `intent:`, `data:` at the top): stopped, silently.
final class ToolBlock extends ToolNavigation {
  const ToolBlock();
}

const _loopback = {'localhost', '127.0.0.1', '::1'};

/// V2-4 E12: the main frame stays on what this phone serves ([origins], `http://localhost:<port>`);
/// another http(s) page asks first and opens in the browser; any other scheme is stopped. Frames
/// inside the page go where the page says.
ToolNavigation toolNavigation(String url, {required bool mainFrame, required Set<String> origins}) {
  if (!mainFrame || url == 'about:blank') return const ToolGo();
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return const ToolBlock();
  }
  if (uri.scheme == 'http' && _loopback.contains(uri.host)) {
    if (!origins.contains('http://localhost:${uri.port}')) return ToolOtherLocal(uri.port);
    return uri.host == 'localhost' ? const ToolGo() : ToolGoInstead(uri.replace(host: 'localhost'));
  }
  return ToolAskExternal(uri);
}
