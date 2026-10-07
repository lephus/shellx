import 'dart:convert';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  final devbox = SshTarget.parse('me@devbox:2222')!;

  group('SessionLaunch JSON (A8 D29)', () {
    test('round trip', () {
      for (final launch in <SessionLaunch>[
        SshLaunch(devbox),
        SshLaunch(devbox, remoteCwd: '/srv/app', hook: false),
        SshLaunch(devbox, remoteCwd: '~/work'),
        const TmuxLaunch('main'),
        TmuxLaunch('build 2', host: devbox, create: true, hook: false),
      ]) {
        final json = jsonDecode(jsonEncode(launch.toJson()));
        expect(SessionLaunch.fromJson(json), launch);
      }
    });

    test('bad data from a file is refused', () {
      for (final bad in <Object?>[
        null,
        'ssh',
        <String, Object?>{'kind': 'ftp'},
        <String, Object?>{'kind': 'ssh'},
        <String, Object?>{'kind': 'ssh', 'target': '-oProxyCommand=x'},
        <String, Object?>{'kind': 'ssh', 'target': 'devbox', 'cwd': 'rel'},
        <String, Object?>{'kind': 'ssh', 'target': 'devbox', 'cwd': '/a\u0007'},
        <String, Object?>{'kind': 'ssh', 'target': 'devbox', 'cwd': 7},
        <String, Object?>{'kind': 'ssh', 'target': 'devbox', 'hook': 'yes'},
        <String, Object?>{'kind': 'tmux', 'session': 'a:b'},
        <String, Object?>{'kind': 'tmux', 'session': ''},
        <String, Object?>{'kind': 'tmux', 'session': 'x' * 65},
        <String, Object?>{'kind': 'tmux', 'session': 'main', 'host': 'a b'},
        <String, Object?>{'kind': 'tmux', 'session': 'main', 'create': 1},
      ]) {
        expect(SessionLaunch.fromJson(bad), isNull, reason: '$bad');
      }
    });

    test('an entry without "hook" uses the hook', () {
      expect(
        SessionLaunch.fromJson({'kind': 'ssh', 'target': 'devbox'}),
        SshLaunch(SshTarget.parse('devbox')!),
      );
    });
  });

  group('split and reconnect (A8 D21, D24)', () {
    test('an SSH pane splits onto the same server, in its folder', () {
      expect(
        SshLaunch(devbox, hook: false).forSplit('/srv/app'),
        SshLaunch(devbox, remoteCwd: '/srv/app', hook: false),
      );
      expect(
        SshLaunch(devbox, remoteCwd: '/x').forSplit(null),
        SshLaunch(devbox),
      );
      expect(SshLaunch(devbox).forSplit(r'C:\x'), SshLaunch(devbox));
    });

    test('a tmux pane splits into a plain shell on the same machine', () {
      expect(
        TmuxLaunch('main', host: devbox).forSplit('/x'),
        SshLaunch(devbox),
      );
      expect(
        TmuxLaunch('main', host: devbox, hook: false).forSplit(null),
        SshLaunch(devbox, hook: false),
      );
      expect(const TmuxLaunch('main').forSplit('/x'), isNull);
    });

    test('reconnect keeps the launch and the last folder; tmux attaches', () {
      expect(
        SshLaunch(devbox, remoteCwd: '/a').forReconnect('/b'),
        SshLaunch(devbox, remoteCwd: '/b'),
      );
      expect(
        SshLaunch(devbox, remoteCwd: '/a').forReconnect(null),
        SshLaunch(devbox, remoteCwd: '/a'),
      );
      expect(
        TmuxLaunch('main', host: devbox, create: true).forReconnect('/b'),
        TmuxLaunch('main', host: devbox),
      );
    });
  });

  test('tmux names (D25, D11) and remote folders (D14)', () {
    expect(isValidTmuxName('main'), isTrue);
    expect(isValidTmuxName('my session 2'), isTrue);
    for (final bad in ['', 'a:b', 'a.b', 'x' * 65, 'a\u001bb']) {
      expect(isValidTmuxName(bad), isFalse, reason: bad);
    }
    expect(isPlainTmuxName('build-2_x'), isTrue);
    expect(isPlainTmuxName('my session'), isFalse);
    expect(isValidRemoteCwd('/srv/app'), isTrue);
    expect(isValidRemoteCwd('~'), isTrue);
    expect(isValidRemoteCwd('~/w'), isTrue);
    expect(isValidRemoteCwd('~root'), isFalse);
    expect(isValidRemoteCwd('rel/x'), isFalse);
  });

  test('labels and SessionRemote', () {
    expect(SshLaunch(devbox).hostLabel, 'me@devbox:2222');
    expect(const TmuxLaunch('main').hostLabel, '');
    final remote = SessionRemote(launch: TmuxLaunch('main', host: devbox));
    expect(remote.isTmux, isTrue);
    expect(remote.tmuxSession, 'main');
    expect(remote.hostKey, 'me@devbox:2222');
    expect(remote.connected, isFalse);
    expect('$remote', isNot(contains('devbox')));
  });

  test('usesHook and withHook (preflight T1)', () {
    expect(SshLaunch(devbox).usesHook, isTrue);
    expect(SshLaunch(devbox).withHook(false), SshLaunch(devbox, hook: false));
    final tmux = TmuxLaunch('main', host: devbox, create: true);
    expect(
      tmux.withHook(false),
      TmuxLaunch('main', host: devbox, create: true, hook: false),
    );
    expect(tmux.withHook(false).usesHook, isFalse);
  });

  test('a tmux host must be written canonically', () {
    for (final host in ['ssh://devbox', ' devbox', 'me@devbox:2222']) {
      final launch = SessionLaunch.fromJson({
        'kind': 'tmux',
        'session': 'main',
        'host': host,
      });
      expect(launch == null, host != 'me@devbox:2222', reason: host);
    }
  });
}
