import 'dart:convert';
import 'dart:io';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_agent/src/pty/shell_hook_scripts.dart';
import 'package:test/test.dart';

String _decode(String command) {
  final b64 = RegExp(r'b=([A-Za-z0-9+/=]+);').firstMatch(command)![1]!;
  return utf8.decode(base64.decode(b64));
}

void main() {
  test('the outer command is safe in every login shell (D10)', () {
    final command = remoteExecCommand(
      remoteBootstrapScript(const RemoteBootstrap(cwd: "/srv/it's here")),
    );
    expect(command, startsWith("/bin/sh -c 'eval "));
    expect(command, endsWith("'"));
    final inner = command.substring("/bin/sh -c '".length, command.length - 1);
    expect(inner, isNot(contains("'")));
    expect(command, isNot(contains('!')));
    expect(command.codeUnits.every((c) => c >= 0x20 && c < 0x7F), isTrue);
    expect(command.length, lessThan(kMaxBootstrapBytes + 400));
  });

  test('script and command sizes stay under the limits (D39)', () {
    final script = remoteBootstrapScript(const RemoteBootstrap(cwd: '/srv'));
    expect(utf8.encode(script).length, lessThan(kMaxBootstrapBytes));
    // Windows command line limit is 32,767 characters.
    expect(remoteExecCommand(script).length, lessThan(32767 - 2000));
  });

  test('the hooks are the local hooks byte for byte, plus the add-on', () {
    expect(remoteZshHook, startsWith(zshHookEnv));
    expect(remoteBashHook, startsWith(bashHookRc));
    expect(remoteZshHook, contains('__shellx_remote_meta'));
    expect(remoteBashHook, contains('__shellx_remote_meta'));
    expect(remoteHookVersion, matches(RegExp(r'^[0-9a-f]{12}$')));
    final script = remoteBootstrapScript(const RemoteBootstrap());
    expect(script, contains(zshHookEnv));
    expect(script, contains(bashHookRc));
    expect(zshHookEnv, isNot(contains('__SHELLX_EOF_')));
    expect(bashHookRc, isNot(contains('__SHELLX_EOF_')));
  });

  test('user text only through shQuote and the environment (D38b)', () {
    final script = remoteBootstrapScript(
      const RemoteBootstrap(cwd: r"/x'; rm -rf ~ #$(id)"),
    );
    expect(script, contains(shQuote(r"/x'; rm -rf ~ #$(id)")));
    final tmux = remoteBootstrapScript(
      const RemoteBootstrap(tmuxSession: r'a $(id) "b"', writeHooks: false),
    );
    expect(tmux, contains("SHELLX_TMUX=${shQuote(r'a $(id) "b"')}"));
    expect(tmux, contains(r'attach-session -t "=$SHELLX_TMUX"'));
    expect(tmux, isNot(contains('__SHELLX_EOF_ZSH__')));
    final create = remoteBootstrapScript(
      const RemoteBootstrap(
        tmuxSession: 'main',
        tmuxCreate: true,
        writeHooks: false,
      ),
    );
    expect(create, contains(r'new-session -A -s "$SHELLX_TMUX"'));
    expect(_decode(remoteExecCommand(tmux)), tmux);
  });

  test('~ folders expand on the server', () {
    expect(
      remoteBootstrapScript(const RemoteBootstrap(cwd: '~/w x')),
      contains('cd -- "\$HOME"/${shQuote('w x')} 2>/dev/null || cd'),
    );
    expect(
      remoteBootstrapScript(const RemoteBootstrap(cwd: '~')),
      contains('\ncd\n'),
    );
  });

  test('every script parses with sh -n', () async {
    for (final b in const [
      RemoteBootstrap(),
      RemoteBootstrap(cwd: '/a b'),
      RemoteBootstrap(tmuxSession: 'main', writeHooks: false),
    ]) {
      final r = await Process.run('/bin/sh', [
        '-n',
        '-c',
        remoteBootstrapScript(b),
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
    }
    final r = await Process.run('/bin/sh', [
      '-n',
      '-c',
      remoteTmuxListScript(),
    ]);
    expect(r.exitCode, 0);
  }, testOn: 'mac-os || linux');

  test('shQuote survives sh', () async {
    for (final value in ["it's", r'$HOME', 'a\nb', '', '"\\']) {
      final r = await Process.run('/bin/sh', [
        '-c',
        'printf %s ${shQuote(value)}',
      ]);
      expect(r.stdout, value);
    }
  }, testOn: 'mac-os || linux');
}
