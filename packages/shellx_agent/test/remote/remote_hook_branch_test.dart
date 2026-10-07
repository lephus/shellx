@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

import '../support/fake_pty.dart' show FixedShellResolver;

void main() {
  for (final kind in ['bash', 'zsh']) {
    final exe = '/bin/$kind';
    test('$kind: OSC 6973 branch at the first prompt, on cd, on a worktree '
        '.git file, once per change (A8 D15)', () async {
      final temp = Directory.systemTemp.createTempSync('shellx-a8-branch-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final home = Directory('${temp.path}/home')..createSync();
      final repo = Directory('${temp.path}/repo/.git')
        ..createSync(recursive: true);
      File('${repo.path}/HEAD').writeAsStringSync('ref: refs/heads/feat/x\n');
      final wt = Directory('${temp.path}/wt/sub')..createSync(recursive: true);
      Directory('${temp.path}/gitdirs/wt').createSync(recursive: true);
      File(
        '${temp.path}/gitdirs/wt/HEAD',
      ).writeAsStringSync('0123456789abcdef\n');
      File(
        '${temp.path}/wt/.git',
      ).writeAsStringSync('gitdir: ${temp.path}/gitdirs/wt\n');
      final hooks = Directory('${temp.path}/hooks')..createSync();
      final ShellCommand command;
      final env = <String, String>{
        'HOME': home.path,
        'PATH': '/usr/bin:/bin',
        'LANG': 'en_US.UTF-8',
        'BASH_SILENCE_DEPRECATION_WARNING': '1',
      };
      if (kind == 'bash') {
        File('${hooks.path}/rc.bash').writeAsStringSync(remoteBashHook);
        command = ShellCommand(
          executable: exe,
          arguments: ['--rcfile', '${hooks.path}/rc.bash', '-i'],
          name: 'bash',
        );
      } else {
        File('${hooks.path}/.zshenv').writeAsStringSync(remoteZshHook);
        env['ZDOTDIR'] = hooks.path;
        command = ShellCommand(executable: exe, arguments: ['-i'], name: 'zsh');
      }
      final manager = SessionManager(
        ptyFactory: const ProcessPtyFactory(),
        shellResolver: FixedShellResolver(command),
        homeDirectory: home.path,
        baseEnvironment: env,
      );
      addTearDown(manager.closeAll);
      final view = manager.view(await manager.open(cols: 100, rows: 30));
      final text = StringBuffer();
      final sub = view.output.listen(
        (d) => text.write(utf8.decode(d, allowMalformed: true)),
      );
      addTearDown(sub.cancel);
      Future<void> waitFor(String needle, {int from = 0}) async {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (!text.toString().substring(from).contains(needle)) {
          if (DateTime.now().isAfter(deadline)) {
            fail('no ${jsonEncode(needle)}');
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      await waitFor('\x1b]6973;branch=\x07'); // home: not a repository
      var mark = text.length;
      view.write(utf8.encode("cd '${temp.path}/repo'\n"));
      await waitFor('\x1b]6973;branch=feat/x\x07', from: mark);
      mark = text.length;
      view.write(utf8.encode('true\n'));
      await waitFor('\x1b]7;', from: mark);
      expect(text.toString().substring(mark), isNot(contains('6973;branch')));
      mark = text.length;
      view.write(utf8.encode("cd '${wt.path}'\n"));
      await waitFor('\x1b]6973;branch=0123456\x07', from: mark);
    });
  }
}
