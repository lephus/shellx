import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import 'remote_tools_provider.dart';

/// What `ssh -G` resolved for a destination: where the TCP connection goes,
/// and whether a jump host or proxy command is in the way.
typedef ResolvedSshTarget = ({String host, int port, bool proxied});

final _unsafe = RegExp(r'[\s\x00-\x1f\x7f]');

/// Reads `hostname`, `port`, `proxyjump` and `proxycommand` from `ssh -G`
/// output; null when there is no `hostname` line or the host or port is
/// not valid (callers treat that as reachable).
ResolvedSshTarget? parseSshG(String stdout) {
  String? host;
  var port = 22;
  var proxied = false;
  for (final line in stdout.split('\n')) {
    final at = line.indexOf(' ');
    if (at < 0) continue;
    final key = line.substring(0, at).toLowerCase();
    final value = line.substring(at + 1).trim();
    switch (key) {
      case 'hostname':
        host = value;
      case 'port':
        port = int.tryParse(value) ?? 0;
      case 'proxyjump' || 'proxycommand':
        if (value.isNotEmpty && value.toLowerCase() != 'none') proxied = true;
    }
  }
  if (host == null || host.isEmpty || host.length > 253) return null;
  if (_unsafe.hasMatch(host) || port < 1 || port > 65535) return null;
  return (host: host, port: port, proxied: proxied);
}

/// How [sshReachabilityProvider] connects (replaced in tests).
typedef TcpProbe =
    Future<bool> Function(String host, int port, Duration timeout);

Future<bool> _tcpProbe(String host, int port, Duration timeout) async {
  try {
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

/// A8 D20: before an automatic reconnect, can this computer reach the
/// server at all (Wi-Fi off, server rebooting)? Hosts behind a jump host or
/// proxy command, and anything that cannot be resolved, count as reachable.
/// No ssh is started and nothing is logged.
final sshReachabilityProvider = Provider<Future<bool> Function(SshTarget)>((
  ref,
) {
  final ssh = ref.watch(remoteToolsProvider).sshPath;
  final run = ref.watch(commandRunnerProvider);
  return (target) async {
    if (ssh == null) return true;
    try {
      final r = await run(ssh, [
        '-G',
        ...target.destinationArgs,
      ], timeout: const Duration(seconds: 2));
      final resolved = r.exitCode == 0 && !r.timedOut
          ? parseSshG(r.stdout)
          : null;
      if (resolved == null || resolved.proxied) return true;
      return await _tcpProbe(
        resolved.host,
        resolved.port,
        const Duration(seconds: 5),
      );
    } catch (_) {
      return true;
    }
  };
});
