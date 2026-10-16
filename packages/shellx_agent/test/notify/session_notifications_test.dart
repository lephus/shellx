import 'dart:convert';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/desktop_rig.dart' as desk show windowInfo;
import '../support/fake_term_link.dart';
import '../support/fake_pty.dart';
import '../support/session_rig.dart' show outputText, phone;

const esc = '\x1b';
const bel = '\x07';

final class _Clock {
  DateTime now = DateTime.utc(2026, 10, 5, 12);
  void advance(Duration d) => now = now.add(d);
}

/// Notifications over a fake relay; [bodies] are the POSTed JSON bodies.
final class _Push {
  _Push({this.threshold = Duration.zero, int maxPerWindow = 6}) {
    final api = ShellxApi(
      baseUri: Uri.parse('https://relay.test'),
      httpClient: MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{"sent":1}', 202);
      }),
    )..token = 'agent';
    notifications = AgentNotifications(
      sender: NotificationSender(
        api: api,
        maxPerWindow: maxPerWindow,
        now: () => clock.now,
      ),
      NotificationsConfig(
        api: api,
        threshold: () => threshold,
        machineName: () => machine,
        locale: () => locale,
      ),
      now: () => clock.now,
    );
  }

  final clock = _Clock();
  final bodies = <Map<String, dynamic>>[];
  Duration? threshold;
  String locale = 'en_US';

  String machine = 'MacBook';
  late final AgentNotifications notifications;
}

void main() {
  group('SessionManager (ShellX sessions)', () {
    late _Push push;
    late FakePtyFactory factory;
    late SessionManager manager;
    final sent = <OutboundMessage>[];

    setUp(() {
      push = _Push(threshold: const Duration(seconds: 30));
      factory = FakePtyFactory();
      sent.clear();
      manager = SessionManager(
        ptyFactory: factory,
        shellResolver: const FixedShellResolver(),
        homeDirectory: '/Users/test',
        baseEnvironment: const {'PATH': '/usr/bin'},
        random: Random(1),
        notifications: push.notifications,
      );
      manager.outbound.listen(sent.add);
    });

    Future<int> open() async {
      await manager.handle(phone, const SessionOpen(cols: 80, rows: 24));
      return sent.map((o) => o.message).whereType<SessionOpened>().last.id;
    }

    test('LocalSessions.notify pushes exactly like OSC 777 (A7 D23)', () async {
      final id = await open();
      expect(manager.notify(id, title: 'CI', body: 'Build xong'), isTrue);
      await push.notifications.sender.idle;
      expect(push.bodies.single['title'], 'CI');
      expect(push.bodies.single['body'], 'Build xong');
      expect((push.bodies.single['data'] as Map)['kind'], 'message');
      expect((push.bodies.single['data'] as Map)['session_id'], '$id');
    });

    test('notify pushes nothing once the limiter refuses (31 calls → 30 '
        'pushes)', () async {
      // The machine-wide sender limit (6/min) is lifted so only the
      // per-session limiter (30/min) decides.
      push = _Push(maxPerWindow: 100);
      manager = SessionManager(
        ptyFactory: factory,
        shellResolver: const FixedShellResolver(),
        homeDirectory: '/Users/test',
        baseEnvironment: const {'PATH': '/usr/bin'},
        random: Random(3),
        notifications: push.notifications,
      );
      manager.outbound.listen(sent.add);
      final id = await open();
      for (var i = 0; i < 31; i++) {
        manager.notify(id, title: 'CI', body: 'n$i');
      }
      await push.notifications.sender.idle;
      expect(push.bodies, hasLength(30));
      expect(push.bodies.map((b) => b['body']), [
        for (var i = 0; i < 30; i++) 'n$i',
      ]);
    });

    test('a long command in the live output becomes a notification; the '
        'bytes still reach the phone unchanged', () async {
      final id = await open();
      final pty = factory.ptys.single;
      final start = '$esc]633;E;npm test$bel$esc]133;C$bel';
      final end = '$esc]133;D;1$bel';
      pty.emit('${start}running\r\n');
      await Future<void>.delayed(Duration.zero);
      push.clock.advance(const Duration(minutes: 3, seconds: 12));
      pty.emit('done$end');
      await Future<void>.delayed(Duration.zero);
      await push.notifications.sender.idle;
      expect(push.bodies, [
        {
          'title': 'MacBook · Session 1',
          'body': '✗ npm test · exit 1 · 3 min 12 s',
          'data': {'session_id': '$id', 'kind': 'command'},
        },
      ]);
      expect(
        outputText([for (final o in sent) o.message], id),
        '${start}running\r\ndone$end',
      );
    });

    test(
      'a short command is not reported; OSC 9 always is, in Vietnamese',
      () async {
        push.locale = 'vi_VN';
        await open();
        final pty = factory.ptys.single;
        pty.emit('$esc]133;C$bel');
        await Future<void>.delayed(Duration.zero);
        push.clock.advance(const Duration(seconds: 5));
        pty.emit('$esc]133;D;0$bel$esc]9;Build xong$bel');
        await Future<void>.delayed(Duration.zero);
        await push.notifications.sender.idle;
        expect(push.bodies.single['title'], 'MacBook · Phiên 1');
        expect(push.bodies.single['body'], 'Build xong');
        expect((push.bodies.single['data'] as Map)['kind'], 'message');
      },
    );

    test(
      'OSC 99 and BEL never reach push; OSC 9/777 still do (A4 N8)',
      () async {
        await open();
        final pty = factory.ptys.single;
        pty.emit('$esc]99;;kitty$esc\\$bel$bel');
        await Future<void>.delayed(Duration.zero);
        await push.notifications.sender.idle;
        expect(push.bodies, isEmpty);
        pty.emit('$esc]9;nine$bel$esc]777;notify;T;seven$bel');
        await Future<void>.delayed(Duration.zero);
        await push.notifications.sender.idle;
        expect(push.bodies.map((b) => b['body']), ['nine', 'seven']);
      },
    );

    test('without notifications nothing is sent (the default)', () async {
      final plain = SessionManager(
        ptyFactory: factory,
        shellResolver: const FixedShellResolver(),
        homeDirectory: '/Users/test',
        baseEnvironment: const {},
        random: Random(2),
      );
      await plain.handle(phone, const SessionOpen(cols: 80, rows: 24));
      factory.ptys.last.emit('$esc]9;hello$bel');
      await Future<void>.delayed(Duration.zero);
      expect(push.bodies, isEmpty);
    });
  });

  group('DesktopSessionManager (shared terminals)', () {
    test('the snapshot never notifies (N11); live out does, titled with app '
        'and window title', () {
      fakeAsync((async) {
        final push = _Push();
        var next = 100;
        final manager = DesktopSessionManager(
          nextId: () => next++,
          notifications: push.notifications,
        );
        manager.outbound.listen((_) {});
        final link = FakeTermLink(desk.windowInfo(1, app: 'iTerm2'));
        manager.addLink(link);
        link.snapshot(
          '$esc]2;build$bel$esc]133;C$bel$esc]133;D;0$bel$esc]9;old$bel',
        );
        async.flushMicrotasks();
        expect(push.bodies, isEmpty);
        link.out('$esc]133;C${bel}x$esc]133;D;0$bel');
        link.out('$esc]777;notify;Claude;Xong$bel');
        async.flushMicrotasks();
        expect(push.bodies.map((b) => [b['title'], b['body']]), [
          ['MacBook · iTerm2 — build', '✓ Command · 0 s'],
          ['Claude', 'Xong'],
        ]);
        expect(push.bodies.first['data'], {
          'session_id': '100',
          'kind': 'command',
        });
      });
    });

    test('a snapshot whose last command event is an end forgets the running '
        'command; one that ends with a start keeps it', () {
      fakeAsync((async) {
        final push = _Push();
        var next = 100;
        final manager = DesktopSessionManager(
          nextId: () => next++,
          notifications: push.notifications,
        );
        manager.outbound.listen((_) {});
        FakeTermLink reconnect(String snapshot) {
          final link = FakeTermLink(desk.windowInfo(1));
          manager.addLink(link);
          link.snapshot(snapshot);
          async.flushMicrotasks();
          return link;
        }

        var link = reconnect('');
        link.out('$esc]133;C$bel');
        async.flushMicrotasks();
        link.drop();
        async.flushMicrotasks();
        // The command ended (and a prompt came back) while the link was down.
        link = reconnect('$esc]133;C${bel}x$esc]133;D;0$bel\$ ');
        link.out('$esc]133;D;0$bel');
        async.flushMicrotasks();
        expect(push.bodies, isEmpty);

        link.out('$esc]133;C$bel');
        async.flushMicrotasks();
        link.drop();
        async.flushMicrotasks();
        link = reconnect('$esc]133;D;0$bel$esc]133;C${bel}still running');
        link.out('$esc]133;D;4$bel');
        async.flushMicrotasks();
        expect(push.bodies.map((b) => b['body']), ['✗ Command · exit 4 · 0 s']);
      });
    });

    test('a sequence cut by a reconnection is dropped; a command started '
        'before it still ends after it', () {
      fakeAsync((async) {
        final push = _Push();
        var next = 100;
        final manager = DesktopSessionManager(
          nextId: () => next++,
          notifications: push.notifications,
        );
        manager.outbound.listen((_) {});
        final first = FakeTermLink(desk.windowInfo(1));
        manager.addLink(first);
        first.snapshot('');
        first.out('$esc]133;C$bel$esc]9;cut-');
        async.flushMicrotasks();
        first.drop();
        async.flushMicrotasks();
        final second = FakeTermLink(desk.windowInfo(1));
        manager.addLink(second);
        second.snapshot('screen');
        second.out('off$bel$esc]133;D;3$bel');
        async.flushMicrotasks();
        expect(push.bodies.map((b) => b['body']), ['✗ Command · exit 3 · 0 s']);
      });
    });
  });
}
