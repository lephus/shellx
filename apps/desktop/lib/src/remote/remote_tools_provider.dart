import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

/// A8: what `main.dart` resolved once (`resolveRemoteTools`); empty until
/// overridden (tests, early startup).
final remoteToolsProvider = Provider<RemoteTools>((ref) => const RemoteTools());

final commandRunnerProvider = Provider<CommandRunner>((ref) => runCommand);

/// D6: `~/.ssh/config` hosts, read fresh each time the dialog opens.
final sshConfigHostsProvider = Provider<Future<List<String>> Function()>(
  (ref) =>
      () => readSshConfigHosts(
        home:
            Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ??
            '',
        windows: Platform.isWindows,
      ),
);

/// Startup must never wait on, or fail because of, ssh/tmux discovery: at
/// most 2 s, and any error gives no tools (SSH panes then say so).
Future<RemoteTools> resolveRemoteToolsSafe(
  Future<RemoteTools> Function() resolve,
) async {
  try {
    return await resolve().timeout(const Duration(seconds: 2));
  } catch (error) {
    debugPrint('ShellX ssh: tools not resolved: ${error.runtimeType}');
    return const RemoteTools();
  }
}
