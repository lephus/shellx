import 'dart:io';

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
