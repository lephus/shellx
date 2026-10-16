/// A server to SSH to (A8 D4, D5): an alias from `~/.ssh/config`, a DNS
/// name or an IP address, with an optional user and port. Only text that
/// can never be read as an `ssh` option gets through [parse]; the host is
/// always passed after `--` ([destinationArgs]).
final class SshTarget {
  const SshTarget._(this.host, this.user, this.port);

  /// Alias, DNS name, IPv4 or IPv6 (without brackets).
  final String host;
  final String? user;
  final int? port;

  static final _host = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9._-]{0,252}$');
  static final _ipv6 = RegExp(
    r'^[0-9A-Fa-f.]*:[0-9A-Fa-f:.]*(%[A-Za-z0-9._-]+)?$',
  );
  static final _user = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9._-]{0,31}$');
  static final _digits = RegExp(r'^[0-9]{1,5}$');

  static bool _control(int rune) =>
      rune <= 0x20 || rune == 0x7F || (rune >= 0x80 && rune <= 0x9F);

  /// Null for anything outside D4: whitespace or control characters, a
  /// leading `-` or `.`, two `@`, a bad port, over 255 characters.
  static SshTarget? parse(String input) {
    var text = input.trim();
    if (text.isEmpty || text.length > 255 || text.runes.any(_control)) {
      return null;
    }
    if (text.toLowerCase().startsWith('ssh://')) {
      text = text.substring('ssh://'.length);
      if (text.endsWith('/')) text = text.substring(0, text.length - 1);
    }
    String? user;
    final at = text.indexOf('@');
    if (at >= 0) {
      if (text.indexOf('@', at + 1) >= 0) return null;
      user = text.substring(0, at);
      if (!_user.hasMatch(user)) return null;
      text = text.substring(at + 1);
    }
    if (text.startsWith('[')) {
      final close = text.indexOf(']');
      if (close < 0) return null;
      final host = text.substring(1, close);
      if (!_ipv6.hasMatch(host)) return null;
      final rest = text.substring(close + 1);
      if (rest.isEmpty) return SshTarget._(host, user, null);
      if (!rest.startsWith(':')) return null;
      final port = _port(rest.substring(1));
      return port == null ? null : SshTarget._(host, user, port);
    }
    final colons = ':'.allMatches(text).length;
    if (colons > 1) {
      return _ipv6.hasMatch(text) ? SshTarget._(text, user, null) : null;
    }
    var host = text;
    int? port;
    if (colons == 1) {
      final i = text.indexOf(':');
      host = text.substring(0, i);
      port = _port(text.substring(i + 1));
      if (port == null) return null;
    }
    if (!_host.hasMatch(host)) return null;
    return SshTarget._(host, user, port);
  }

  /// Only the canonical [key] spelling (no `ssh://`, no padding): what
  /// saved layouts, workspaces and recent-server lists hold.
  static SshTarget? parseKey(String key) {
    final parsed = parse(key);
    return parsed != null && parsed.key == key ? parsed : null;
  }

  static int? _port(String text) {
    if (!_digits.hasMatch(text)) return null;
    final value = int.parse(text);
    return value >= 1 && value <= 65535 ? value : null;
  }

  /// D5: `[user@]host[:port]`, IPv6 in brackets when a port follows.
  String get key {
    final h = host.contains(':') && port != null ? '[$host]' : host;
    return '${user == null ? '' : '$user@'}$h${port == null ? '' : ':$port'}';
  }

  /// `[-l user] [-p port] -- host` (D4).
  List<String> get destinationArgs => [
    if (user case final u?) ...['-l', u],
    if (port case final p?) ...['-p', '$p'],
    '--',
    host,
  ];

  @override
  bool operator ==(Object other) => other is SshTarget && other.key == key;

  @override
  int get hashCode => key.hashCode;

  /// Never the host (D37).
  @override
  String toString() => 'SshTarget(…)';
}
