@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

late Directory temp;
late String home;

/// A fake login shell named [name] that prints its arguments, ZDOTDIR,
/// SHELLX_TMUX and its folder, so the script's `exec` can be checked.
String fakeShell(String name) {
  final bin = Directory('${temp.path}/bin')..createSync(recursive: true);
  final file = File('${bin.path}/$name')
    ..writeAsStringSync(
      '#!/bin/sh\n'
      'printf "ARGS:%s\\n" "\$*"\n'
      'printf "ZDOTDIR:%s\\n" "\${ZDOTDIR-unset}"\n'
      'printf "USERZ:%s\\n" "\${SHELLX_USER_ZDOTDIR-unset}"\n'
      'printf "BASHLOGIN:%s\\n" "\${SHELLX_BASH_LOGIN-unset}"\n'
      'printf "TMUX:%s\\n" "\${SHELLX_TMUX-unset}"\n'
      'printf "REMOTE:%s\\n" "\${SHELLX_REMOTE-unset}"\n'
      'printf "PWD:%s\\n" "\$(pwd -P)"\n',
    );
  Process.runSync('/bin/chmod', ['755', file.path]);
  return file.path;
}

Future<ProcessResult> run(
  RemoteBootstrap b,
  String shell, {
  Map<String, String>? env,
}) => Process.run(
  '/bin/sh',
  ['-c', remoteExecCommand(remoteBootstrapScript(b))],
  environment: {'HOME': home, 'SHELL': shell, 'PATH': '/usr/bin:/bin', ...?env},
  includeParentEnvironment: false,
);

void main() {
  setUp(() {
    temp = Directory.systemTemp.createTempSync('shellx-a8-boot-');
    home = (Directory(
      '${temp.path}/home',
    )..createSync()).resolveSymbolicLinksSync();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('zsh: hello, pid, home, hooks written private, ZDOTDIR restored '
      'through SHELLX_USER_ZDOTDIR, login shell', () async {
    final shell = fakeShell('zsh');
    final r = await run(
      const RemoteBootstrap(),
      shell,
      env: {'ZDOTDIR': '/u/z'},
    );
    final out = r.stdout as String;
    expect(out, startsWith('\x1b]6973;hello=1\x07\x1b]6973;pid='));
    expect(out, contains('\x1b]6973;home=$home\x07'));
    final dir = '$home/.cache/shellx/remote-$remoteHookVersion';
    expect(out, contains('ARGS:-l\n'));
    expect(out, contains('ZDOTDIR:$dir/zsh\n'));
    expect(out, contains('USERZ:/u/z\n'));
    expect(out, contains('REMOTE:1\n'));
    expect(File('$dir/zsh/.zshenv').readAsStringSync(), remoteZshHook);
    expect(File('$dir/bash/rc.bash').readAsStringSync(), remoteBashHook);
    expect(File('$dir/.ok').existsSync(), isTrue);
    final mode =
        Process.runSync('/bin/ls', [
              '-ld',
              '$home/.cache/shellx',
              '$dir/zsh/.zshenv',
            ]).stdout
            as String;
    expect(mode, contains('drwx------'));
    expect(mode, contains('-rw-------'));
    expect(
      Directory('$dir/zsh').listSync().map((e) => e.path.split('/').last),
      ['.zshenv'],
    );
  });

  test('bash: --rcfile of the hook, login files requested', () async {
    final r = await run(const RemoteBootstrap(cwd: '/'), fakeShell('bash'));
    final dir = '$home/.cache/shellx/remote-$remoteHookVersion';
    expect(r.stdout, contains('ARGS:--rcfile $dir/bash/rc.bash -i\n'));
    expect(r.stdout, contains('BASHLOGIN:1\n'));
    expect(r.stdout, contains('PWD:/\n'));
  });

  test('fish and other shells: plain login shell, still hello', () async {
    final r = await run(const RemoteBootstrap(), fakeShell('fish'));
    expect(r.stdout, contains('\x1b]6973;hello=1\x07'));
    expect(r.stdout, contains('ARGS:-l\n'));
    expect(r.stdout, contains('ZDOTDIR:unset\n'));
  });

  test('a read-only home: no hooks, still a login shell', () async {
    Process.runSync('/bin/chmod', ['555', home]);
    addTearDown(() => Process.runSync('/bin/chmod', ['755', home]));
    final r = await run(const RemoteBootstrap(), fakeShell('zsh'));
    expect(r.stdout, contains('ARGS:-l\n'));
    expect(r.stdout, contains('ZDOTDIR:unset\n'));
  });

  test('.ok without its files is not trusted', () async {
    final dir = Directory('$home/.cache/shellx/remote-$remoteHookVersion')
      ..createSync(recursive: true);
    File('${dir.path}/.ok').writeAsStringSync('');
    final r = await run(const RemoteBootstrap(), fakeShell('zsh'));
    expect(r.stdout, contains('ZDOTDIR:${dir.path}/zsh\n'));
    expect(File('${dir.path}/zsh/.zshenv').existsSync(), isTrue);
  });

  test('cwd: missing folder → home; ~/ expands', () async {
    Directory('$home/w x').createSync();
    final a = await run(
      const RemoteBootstrap(cwd: '/does/not/exist'),
      fakeShell('zsh'),
    );
    expect(a.stdout, contains('PWD:$home\n'));
    final b = await run(const RemoteBootstrap(cwd: '~/w x'), fakeShell('zsh'));
    expect(b.stdout, contains('PWD:$home/w x\n'));
  });

  test(
    'tmux: the login shell runs tmux with the name from the environment',
    () async {
      final r = await run(
        const RemoteBootstrap(tmuxSession: r'a $(id)', writeHooks: false),
        fakeShell('zsh'),
      );
      expect(
        r.stdout,
        contains(r'ARGS:-l -c exec tmux attach-session -t "=$SHELLX_TMUX"'),
      );
      expect(r.stdout, contains(r'TMUX:a $(id)'));
      expect(Directory('$home/.cache/shellx').existsSync(), isFalse);
    },
  );

  test('a huge cwd runs: falls back to home (I2)', () async {
    final r = await run(
      RemoteBootstrap(cwd: '/${"'" * 4000}'),
      fakeShell('zsh'),
    );
    expect(r.stdout, contains('PWD:$home\n'));
  });
}
