import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'session_rig.dart';

/// A [LocalSessions] under test with the fake PTYs behind it.
final class LocalSessionsHarness {
  LocalSessionsHarness(this.sessions, this.rig, this._dispose);
  final LocalSessions sessions;
  final SessionRig rig;
  final Future<void> Function() _dispose;
  Future<void> dispose() => _dispose();
}

/// Polls [condition] until it holds (the wire coalesces `sessions.changed`).
Future<void> eventually(bool Function() condition) async {
  for (var i = 0; i < 400 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue, reason: 'condition never held');
}

/// A5b D28: what every [LocalSessions] does, whether the sessions are in
/// this process or behind the mux wire. [make] must build a harness whose
/// rig allows two sessions, has SSH/tmux tools, and finds the directory
/// `/w`.
void runLocalSessionsContract(
  String name,
  Future<LocalSessionsHarness> Function() make,
) {
  group(name, () {
    late LocalSessionsHarness h;
    late LocalSessions sessions;
    late SessionRig rig;

    setUp(() async {
      h = await make();
      sessions = h.sessions;
      rig = h.rig;
    });
    tearDown(() => h.dispose());

    Future<String> collect(
      LocalSessionView view,
      String until, {
      Uint8List? first,
    }) async {
      final text = StringBuffer(utf8.decode(first ?? view.backlog));
      view.output.listen((d) => text.write(utf8.decode(d)));
      await eventually(() => text.toString().length >= until.length);
      return text.toString();
    }

    test('open → listed in sessions and changes fires', () async {
      final changed = sessions.changes.first;
      final id = await sessions.open(cols: 80, rows: 24);
      await changed.timeout(const Duration(seconds: 2));
      await eventually(() => sessions.sessions.length == 1);
      expect(sessions.sessions.single.id, id);
      expect(sessions.sessions.single.origin, SessionOrigin.desktop);
    });

    test('open(cwd:) uses the directory when it exists', () async {
      await sessions.open(cols: 80, rows: 24, cwd: '/w');
      expect(rig.pty(0).workingDirectory, '/w');
      await sessions.open(cols: 80, rows: 24, cwd: '/missing');
      expect(rig.pty(1).workingDirectory, '/Users/test');
    });

    test(
      'open carries cols, rows and tabId to the PTY and its shell',
      () async {
        final id = await sessions.open(cols: 101, rows: 33, tabId: 9);
        expect(rig.pty(0).initialCols, 101);
        expect(rig.pty(0).initialRows, 33);
        expect(rig.pty(0).environment['SHELLX_TAB_ID'], '9');
        expect(rig.pty(0).environment['SHELLX_PANE_ID'], '$id');
      },
    );

    test('backlog + output carry everything printed, in order', () async {
      final id = await sessions.open(cols: 80, rows: 24);
      rig.pty(0).emit('one');
      await pumpEventQueue();
      final view = sessions.view(id);
      final all = collect(view, 'onetwo');
      rig.pty(0).emit('two');
      expect(await all, 'onetwo');
      view.dispose();
    });

    test('write reaches the PTY; resize reaches the PTY', () async {
      final id = await sessions.open(cols: 80, rows: 24);
      final view = sessions.view(id);
      view
        ..write(Uint8List.fromList(utf8.encode('ls\r')))
        ..resize(100, 30);
      await eventually(() => rig.pty(0).writtenText == 'ls\r');
      await eventually(() => rig.pty(0).resizes.contains((100, 30)));
      view.dispose();
    });

    test('reply is written while the desktop drives', () async {
      final id = await sessions.open(cols: 80, rows: 24);
      final view = sessions.view(id);
      view.reply(Uint8List.fromList(utf8.encode('\x1b[1;1R')));
      await eventually(() => rig.pty(0).writtenText == '\x1b[1;1R');
      view.dispose();
    });

    test('driver stream reports desktop after a write', () async {
      final id = await rig.open(phone); // a phone session: the phone drives
      final view = sessions.view(id);
      final desktop = view.driver.firstWhere((d) => d == DriverSide.desktop);
      view
        ..write(Uint8List.fromList(utf8.encode('x')))
        ..resize(100, 30);
      expect(await desktop.timeout(const Duration(seconds: 2)), isNotNull);
      view.dispose();
    });

    test(
      'exitCode completes with the shell code; closedOnRequest false',
      () async {
        final id = await sessions.open(cols: 80, rows: 24);
        final view = sessions.view(id);
        view.output.listen((_) {});
        await pumpEventQueue();
        rig.pty(0).exit(3);
        expect(await view.exitCode.timeout(const Duration(seconds: 2)), 3);
        expect(view.closedOnRequest, isFalse);
      },
    );

    test('close(id) ends the session with closedOnRequest true', () async {
      final id = await sessions.open(cols: 80, rows: 24);
      final view = sessions.view(id);
      view.output.listen((_) {});
      await pumpEventQueue();
      sessions.close(id);
      await view.exitCode.timeout(const Duration(seconds: 2));
      expect(view.closedOnRequest, isTrue);
      expect(rig.pty(0).killed, isTrue);
    });

    test('limit → SessionLimitException', () async {
      await sessions.open(cols: 80, rows: 24);
      await sessions.open(cols: 80, rows: 24);
      await expectLater(
        sessions.open(cols: 80, rows: 24),
        throwsA(isA<SessionLimitException>().having((e) => e.max, 'max', 2)),
      );
    });

    test('spawn failure → SpawnFailedException', () async {
      rig.factory.failWith = StateError('no shell');
      await expectLater(
        sessions.open(cols: 80, rows: 24),
        throwsA(isA<SpawnFailedException>()),
      );
    });

    test(
      'notices: an OSC 9 from the shell arrives as a SessionNotice',
      () async {
        final id = await sessions.open(cols: 80, rows: 24);
        final notice = sessions.notices.first;
        rig.pty(0).emit('\x1b]9;hi\x07');
        final n = await notice.timeout(const Duration(seconds: 2));
        expect(n.sessionId, id);
        expect(n.kind, SessionNoticeKind.message);
        expect(n.body, 'hi');
      },
    );

    test('notify is true for a listed session and shows as a notice; '
        'false for an unknown id', () async {
      final id = await sessions.open(cols: 80, rows: 24);
      await eventually(() => sessions.sessions.any((s) => s.id == id));
      final notice = sessions.notices.first;
      expect(sessions.notify(id, title: 't', body: 'b'), isTrue);
      final n = await notice.timeout(const Duration(seconds: 2));
      expect((n.title, n.body), ('t', 'b'));
      expect(sessions.notify(id + 100, body: 'b'), isFalse);
    });

    test('an SSH launch opens ssh and the summary says remote', () async {
      final target = SshTarget.parse('devbox')!;
      final id = await sessions.open(
        cols: 80,
        rows: 24,
        launch: SshLaunch(target, remoteCwd: '/srv'),
      );
      expect(rig.pty(0).command.executable, '/usr/bin/ssh');
      await eventually(() => sessions.sessions.any((s) => s.id == id));
      var s = sessions.sessions.single;
      expect(s.shell, 'ssh');
      expect(s.remote!.launch, SshLaunch(target, remoteCwd: '/srv'));
      expect(s.remote!.connected, isFalse);
      expect(s.remote!.home, isNull);
      final osc = '\x1b]6973;hello=1\x07\x1b]6973;home=/home/me\x07';
      rig.pty(0).emit(osc);
      await eventually(() => sessions.sessions.single.remote!.connected);
      s = sessions.sessions.single;
      expect(s.remote!.home, '/home/me');
    });

    test('a tmux launch opens and a local session has no remote', () async {
      await sessions.open(cols: 80, rows: 24, launch: const TmuxLaunch('main'));
      await sessions.open(cols: 80, rows: 24);
      await eventually(() => sessions.sessions.length == 2);
      expect(sessions.sessions.first.remote!.isTmux, isTrue);
      expect(sessions.sessions.first.remote!.tmuxSession, 'main');
      expect(sessions.sessions.last.remote, isNull);
    });

    test('a bad launch → SpawnFailedException', () async {
      // The host in a launch must be a valid target; without tools the
      // launch cannot start. Here: tmux session names with a newline.
      await expectLater(
        sessions.open(cols: 80, rows: 24, launch: const TmuxLaunch('a\nb')),
        throwsA(
          isA<SpawnFailedException>().having(
            (e) => e.message,
            'message',
            'bad_launch',
          ),
        ),
      );
    });

    test('view of an unknown id ends at once or throws StateError', () async {
      try {
        final view = sessions.view(404);
        final ended = Completer<void>();
        view.output.listen((_) {}, onDone: ended.complete);
        await ended.future.timeout(const Duration(seconds: 2));
        expect(await view.exitCode, -1);
      } on StateError {
        // also allowed
      }
    });
  });
}
