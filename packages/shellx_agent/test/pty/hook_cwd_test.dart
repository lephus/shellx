@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

import '../support/fake_pty.dart' show FixedShellResolver;

final _plain = RegExp(r'^[-/._~A-Za-z0-9]$');

/// The hooks' encoding: every byte outside `-/._~A-Za-z0-9` as `%XX`.
String _encode(String path) {
  final out = StringBuffer();
  for (final byte in utf8.encode(path)) {
    final c = String.fromCharCode(byte);
    if (byte < 0x80 && _plain.hasMatch(c)) {
      out.write(c);
    } else {
      out.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return out.toString();
}

void main() {
  for (final shell in const [
    ShellCommand(executable: '/bin/zsh', arguments: ['-i'], name: 'zsh'),
    ShellCommand(executable: '/bin/bash', arguments: ['-i'], name: 'bash'),
  ]) {
    test('${shell.name}: the first prompt and every later one print OSC 7 '
        'with the percent-encoded directory (A2 C1)', () async {
      final temp = Directory.systemTemp.createTempSync('shellx-osc7-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final home = Directory('${temp.path}/home')..createSync();
      final target = Directory('${temp.path}/a b/Tài liệu 100%')
        ..createSync(recursive: true);
      final manager = SessionManager(
        ptyFactory: const ProcessPtyFactory(),
        shellResolver: FixedShellResolver(shell),
        homeDirectory: home.path,
        baseEnvironment: {
          'HOME': home.path,
          'PATH': '/usr/bin:/bin',
          'LANG': 'en_US.UTF-8',
          'BASH_SILENCE_DEPRECATION_WARNING': '1',
        },
        shellIntegration: ShellIntegration(directory: '${temp.path}/hooks'),
      );
      addTearDown(manager.closeAll);
      final id = await manager.open(cols: 80, rows: 24);
      final view = manager.view(id);
      final text = StringBuffer();
      final sub = view.output.listen(
        (data) => text.write(utf8.decode(data, allowMalformed: true)),
      );
      addTearDown(sub.cancel);

      Future<void> waitFor(String needle) async {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (!text.toString().contains(needle)) {
          if (DateTime.now().isAfter(deadline)) {
            fail('no ${jsonEncode(needle)} in the output');
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      await waitFor('${_encode(home.path)}\x07'); // first prompt, in $HOME
      view.write(utf8.encode("cd '${target.path}'\n"));
      await waitFor('${_encode(target.path)}\x07');
      expect(text.toString(), contains('\x1b]7;file://'));
    });
  }
}
