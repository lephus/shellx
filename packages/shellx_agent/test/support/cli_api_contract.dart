import 'dart:async';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

import 'fake_ui_api.dart';

abstract interface class CliTestHost {
  /// Connected and authenticated as [role] (handshake done by the test).
  /// [token] goes in `auth` exactly as given (null: none).
  Future<MuxConnection> connect({String role = 'cli', String? token});

  /// The per-launch token the host accepts (A7 amendment).
  String get token;
  Uint8List get secret;
  Future<void> close();
}

const _notAShellXShell =
    'This terminal is not a ShellX shell. Allow it in the ShellX tray: '
    'Command line → Allow other terminals';

/// A7 D37a: one suite, every host.
void cliApiContract(
  String name,
  Future<CliTestHost> Function(
    FakeUiApi ui,
    bool Function() enabled,
    bool Function() allowExternal,
  )
  make,
) {
  group('CLI API contract — $name', () {
    late FakeUiApi ui;
    late CliTestHost host;
    var enabled = true;
    var external = false;

    setUp(() async {
      ui = FakeUiApi();
      enabled = true;
      external = false;
      host = await make(ui, () => enabled, () => external);
    });
    tearDown(() => host.close());

    /// A ShellX shell: carries the per-launch token.
    Future<MuxConnection> shell() => host.connect(token: host.token);

    Future<MuxMessage> ask(
      MuxConnection c,
      String t, [
      Map<String, Object?> f = const {},
    ]) {
      final answer = c.messages.firstWhere((m) => m.q == 77);
      c.send(MuxMessage(t, q: 77, fields: f));
      return answer.timeout(const Duration(seconds: 2));
    }

    test('api.version', () async {
      final c = await shell();
      final r = await ask(c, 'api.version');
      expect(r.type, 'result');
      expect(r.get<int>('api'), 1);
      expect(
        r.get<List<Object?>>('caps'),
        containsAll(['ui.ls', 'ui.pane.send', 'cli.notify']),
      );
      expect(r.get<String>('host'), anyOf('ui', 'daemon'));
    });

    test('forbidden types keep the connection', () async {
      final c = await shell();
      for (final t in [
        'sessions.open',
        'view.write',
        'agent.call',
        'daemon.quit',
      ]) {
        final r = await ask(c, t);
        expect(
          [r.type, r.get<String>('code')],
          ['error', 'forbidden'],
          reason: t,
        );
      }
      expect((await ask(c, 'api.version')).type, 'result');
    });

    test('ui.* reaches the UI; failures carry code and message', () async {
      final c = await shell();
      final r = await ask(c, 'ui.ls', {'x': 1});
      expect(r.get<String>('echo'), 'ui.ls');
      expect(ui.requests.single.get<int>('x'), 1);
      final e = await ask(c, 'ui.fail');
      expect(
        [e.get<String>('code'), e.get<String>('message')],
        ['not_found', 'no pane p1'],
      );
      expect((await ask(c, 'cli.nope')).get<String>('code'), 'unknown_type');
    });

    test(
      'switch off: ui.* and events refused, version and notify allowed (D26)',
      () async {
        enabled = false;
        final c = await shell();
        expect((await ask(c, 'ui.ls')).get<String>('code'), 'cli_disabled');
        expect(
          (await ask(c, 'cli.events.subscribe')).get<String>('code'),
          'cli_disabled',
        );
        expect((await ask(c, 'api.version')).type, 'result');
        expect((await ask(c, 'cli.notify', {'body': 'x'})).type, 'result');
        expect(ui.requests, isEmpty);
      },
    );

    test('cli.notify routes by pane (D23)', () async {
      final c = await shell();
      expect(
        (await ask(c, 'cli.notify', {
          'pane': 12,
          'title': 'CI',
          'body': 'ok',
        })).type,
        'result',
      );
      expect(ui.paneNotices.single, (12, 'CI', 'ok'));
      expect(
        (await ask(c, 'cli.notify', {
          'pane': 99,
          'body': 'x',
        })).get<String>('code'),
        'not_found',
      );
      expect((await ask(c, 'cli.notify', {'body': 'app'})).type, 'result');
      expect(ui.appNotices.single, (null, 'app'));
      expect(
        (await ask(c, 'cli.notify', {})).get<String>('code'),
        'bad_request',
      );
      final long = 'x' * 2000;
      await ask(c, 'cli.notify', {'body': long, 'title': 'y' * 300});
      expect(ui.appNotices.last.$2.length, 1024);
      expect(ui.appNotices.last.$1!.length, 128);
    });

    test('events stream after subscribe, filtered by kinds', () async {
      final c = await shell();
      expect(
        (await ask(c, 'cli.events.subscribe', {
          'kinds': ['tab.opened'],
        })).type,
        'result',
      );
      final got = c.messages.firstWhere((m) => m.type == 'event');
      ui.eventsOut.add({'kind': 'pane.closed', 'pane': 1});
      ui.eventsOut.add({'kind': 'tab.opened', 'tab': 5});
      final e = await got.timeout(const Duration(seconds: 2));
      expect([e.get<String>('kind'), e.get<int>('tab')], ['tab.opened', 5]);
    });

    test('requests on one connection run in order', () async {
      final c = await shell();
      ui.gate = Completer<void>();
      final order = <int>[];
      c.messages
          .where((m) => m.type == 'result')
          .listen((m) => order.add(m.q!));
      c.send(const MuxMessage('ui.a', q: 1));
      c.send(const MuxMessage('api.version', q: 2));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(order, isEmpty); // api.version waits behind ui.a
      ui.gate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(order, [1, 2]);
    });

    group('malformed requests get bad_request and keep the connection', () {
      test('no q', () async {
        final c = await shell();
        final e = c.messages.firstWhere((m) => m.type == 'error');
        c.send(const MuxMessage('api.version'));
        final r = await e.timeout(const Duration(seconds: 2));
        expect([r.q, r.get<String>('code')], [null, 'bad_request']);
        expect((await ask(c, 'api.version')).type, 'result');
      });

      test('wrong field types', () async {
        final c = await shell();
        for (final f in <Map<String, Object?>>[
          {'body': 5},
          {'body': 'x', 'pane': 'p12'},
          {'body': 'x', 'title': 3},
        ]) {
          expect(
            (await ask(c, 'cli.notify', f)).get<String>('code'),
            'bad_request',
            reason: '$f',
          );
        }
        expect(
          (await ask(c, 'cli.events.subscribe', {
            'kinds': 'tab.opened',
          })).get<String>('code'),
          'bad_request',
        );
        expect(ui.appNotices, isEmpty);
        expect(ui.paneNotices, isEmpty);
        expect((await ask(c, 'api.version')).type, 'result');
      });

      test('an answer over 64 KiB becomes an error, the host lives', () async {
        final c = await shell();
        ui.answer = {'big': 'x' * (70 * 1024)};
        final e = await ask(c, 'ui.ls');
        expect([e.type, e.get<String>('code')], ['error', 'internal']);
        ui.answer = null;
        expect((await ask(c, 'ui.ls')).type, 'result');
      });
    });

    group('ShellX shells only (A7 amendment)', () {
      Future<void> refusedAndClosed(
        MuxConnection c,
        String t, [
        Map<String, Object?> f = const {},
      ]) async {
        final r = await ask(c, t, f);
        expect(
          [r.type, r.q, r.get<String>('code'), r.get<String>('message')],
          ['error', 77, 'forbidden', _notAShellXShell],
          reason: t,
        );
        await c.done.timeout(const Duration(seconds: 2));
      }

      test('the token gives full access', () async {
        final c = await shell();
        expect((await ask(c, 'ui.ls')).type, 'result');
        expect((await ask(c, 'cli.events.subscribe')).type, 'result');
        expect(
          (await ask(c, 'cli.notify', {'pane': 12, 'body': 'x'})).type,
          'result',
        );
      });

      test('no token: api.version and a pane-less notify only', () async {
        final c = await host.connect();
        expect((await ask(c, 'api.version')).type, 'result');
        expect((await ask(c, 'cli.notify', {'body': 'hi'})).type, 'result');
        expect(ui.appNotices.single, (null, 'hi'));
        await refusedAndClosed(c, 'ui.ls');
        expect(ui.requests, isEmpty);
      });

      for (final (t, f) in <(String, Map<String, Object?>)>[
        ('ui.pane.send', {'pane': 12, 'text': 'rm -rf ~'}),
        ('cli.notify', {'pane': 12, 'body': 'x'}),
        ('cli.events.subscribe', {}),
        ('daemon.status', {}),
        ('sessions.open', {}),
        ('cli.nope', {}),
      ]) {
        test(
          'no token: $t is forbidden and closes; the UI is untouched',
          () async {
            final c = await host.connect();
            await refusedAndClosed(c, t, f);
            expect(ui.requests, isEmpty);
            expect(ui.paneNotices, isEmpty);
            expect(ui.appNotices, isEmpty);
          },
        );
      }

      test('a wrong token is the same as none', () async {
        final c = await host.connect(token: '${host.token}x');
        expect((await ask(c, 'api.version')).type, 'result');
        await refusedAndClosed(c, 'ui.ls');
        final d = await host.connect(token: '');
        await refusedAndClosed(d, 'ui.ls');
        expect(ui.requests, isEmpty);
      });

      test(
        '"Allow other terminals" gives full access without a token',
        () async {
          external = true;
          final c = await host.connect();
          expect((await ask(c, 'ui.ls')).type, 'result');
          final d = await host.connect(token: 'wrong');
          expect((await ask(d, 'ui.ls')).type, 'result');
          external = false;
          final e = await host.connect();
          await refusedAndClosed(e, 'ui.ls');
        },
      );

      test(
        'switch off: version and notify still work without a token (D26)',
        () async {
          enabled = false;
          final c = await host.connect();
          expect((await ask(c, 'api.version')).type, 'result');
          expect((await ask(c, 'cli.notify', {'body': 'x'})).type, 'result');
          await refusedAndClosed(c, 'ui.ls');
        },
      );

      test(
        'unticking refuses an open connection at its next request',
        () async {
          external = true;
          final c = await host.connect();
          expect((await ask(c, 'ui.ls')).type, 'result');
          external = false;
          await refusedAndClosed(c, 'ui.ls');
          expect(ui.requests, hasLength(1));
        },
      );

      test(
        'unticking ends a token-less subscription at its next event',
        () async {
          external = true;
          final c = await host.connect();
          expect((await ask(c, 'cli.events.subscribe')).type, 'result');
          external = false;
          final got = c.messages.first;
          ui.eventsOut.add({'kind': 'tab.opened', 'tab': 1});
          final e = await got.timeout(const Duration(seconds: 2));
          expect(
            [e.type, e.q, e.get<String>('code'), e.get<String>('message')],
            ['error', null, 'forbidden', _notAShellXShell],
          );
          await c.done.timeout(const Duration(seconds: 2));
        },
      );
    });

    test(
      'notify text made only of control characters is bad_request',
      () async {
        final c = await shell();
        expect(
          (await ask(c, 'cli.notify', {
            'body': '\x07\x1b\x00\x9b',
          })).get<String>('code'),
          'bad_request',
        );
        expect(ui.appNotices, isEmpty);
      },
    );

    test('a second subscribe replaces the filter', () async {
      final c = await shell();
      final first = await ask(c, 'cli.events.subscribe', {
        'kinds': ['tab.opened'],
      });
      expect(first.get<List<Object?>>('kinds'), ['tab.opened']);
      final second = await ask(c, 'cli.events.subscribe', {
        'kinds': ['pane.closed'],
      });
      expect(second.get<List<Object?>>('kinds'), ['pane.closed']);
      final got = c.messages.firstWhere((m) => m.type == 'event');
      ui.eventsOut.add({'kind': 'tab.opened', 'tab': 5});
      ui.eventsOut.add({'kind': 'pane.closed', 'pane': 6});
      final e = await got.timeout(const Duration(seconds: 2));
      expect(e.get<String>('kind'), 'pane.closed');
      final all = await ask(c, 'cli.events.subscribe');
      expect([all.type, all.fields.containsKey('kinds')], ['result', false]);
    });

    test('switch off ends an active subscription with cli_disabled; the '
        'connection stays (D26)', () async {
      final c = await shell();
      expect((await ask(c, 'cli.events.subscribe')).type, 'result');
      final seen = <MuxMessage>[];
      c.messages.listen(seen.add);
      enabled = false;
      ui.eventsOut.add({'kind': 'tab.opened', 'tab': 1});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        [
          for (final m in seen) [m.type, m.q, m.get<String>('code')],
        ],
        [
          ['error', null, 'cli_disabled'],
        ],
      );
      enabled = true;
      ui.eventsOut.add({'kind': 'tab.opened', 'tab': 2});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(seen, hasLength(1)); // the subscription is over
      expect((await ask(c, 'api.version')).type, 'result');
    });

    group('a client that does not read (D24, D32)', () {
      test(
        'events beyond 1000 waiting are dropped, then one overflow',
        () async {
          final c = await shell();
          expect((await ask(c, 'cli.events.subscribe')).type, 'result');
          final events = <MuxMessage>[];
          c.messages.where((m) => m.type == 'event').listen(events.add);
          c.pauseInput();
          for (var i = 0; i < 1500; i++) {
            ui.eventsOut.add({'kind': 'tab.opened', 'tab': i});
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
          c.resumeInput();
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(events, hasLength(1001));
          expect(events[999].get<int>('tab'), 999);
          expect(
            [events.last.get<String>('kind'), events.last.get<int>('dropped')],
            ['overflow', 500],
          );
          ui.eventsOut.add({'kind': 'tab.opened', 'tab': 2000});
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(events.last.get<int>('tab'), 2000);
        },
      );

      test('answers piling up stop request intake until it reads', () async {
        final c = await shell();
        ui.answer = {'big': 'x' * 40000};
        final results = <int>[];
        c.messages
            .where((m) => m.type == 'result')
            .listen((m) => results.add(m.q!));
        c.pauseInput();
        for (var q = 1; q <= 30; q++) {
          c.send(MuxMessage('ui.ls', q: q));
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
        // 256 KiB of unread answers: about seven 40 KB ones.
        expect(ui.requests.length, inInclusiveRange(6, 8));
        c.resumeInput();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(results, [for (var q = 1; q <= 30; q++) q]);
      });

      test('at most 64 requests wait per connection', () async {
        final c = await shell();
        ui.gate = Completer<void>();
        final busy = <int>[];
        final results = <int>[];
        c.messages.listen((m) {
          if (m.type == 'error' && m.get<String>('code') == 'busy') {
            busy.add(m.q!);
          } else if (m.type == 'result') {
            results.add(m.q!);
          }
        });
        for (var q = 1; q <= 70; q++) {
          c.send(MuxMessage('ui.ls', q: q));
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(busy, [65, 66, 67, 68, 69, 70]);
        expect(ui.requests, hasLength(1));
        ui.gate!.complete();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(results, [for (var q = 1; q <= 64; q++) q]);
      });
    });
  });
}
