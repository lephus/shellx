import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

import '../support/session_rig.dart';

const esc = '\x1b';
const bel = '\x07';

void main() {
  late SessionRig rig;
  late List<SessionNotice> got;

  Future<void> boot({Duration? threshold}) async {
    rig = SessionRig(commandNoticeThreshold: () => threshold);
    got = [];
    rig.manager.notices.listen(got.add);
    await rig.manager.open(cols: 80, rows: 24);
  }

  Future<void> emit(String text) async {
    rig.pty(0).emit(text);
    await pumpEventQueue();
  }

  test(
    'OSC 9, 777 and 99 become message notices with the session id',
    () async {
      await boot();
      final id = rig.manager.sessions.single.id;
      await emit('$esc]9;nine$bel');
      await emit('$esc]777;notify;CI;green$bel');
      await emit('$esc]99;;kitty$esc\\');
      expect(got.map((n) => (n.sessionId, n.kind, n.title, n.body)), [
        (id, SessionNoticeKind.message, null, 'nine'),
        (id, SessionNoticeKind.message, 'CI', 'green'),
        (id, SessionNoticeKind.message, null, 'kitty'),
      ]);
      expect(got.first.at, rig.now);
    },
  );

  test('a bell rings at most once per 5 s (D3)', () async {
    await boot();
    await emit('$bel$bel$bel');
    expect(got.map((n) => n.kind), [SessionNoticeKind.bell]);
    rig.now = rig.now.add(const Duration(seconds: 4));
    await emit(bel);
    expect(got, hasLength(1));
    rig.now = rig.now.add(const Duration(seconds: 1));
    await emit(bel);
    expect(got, hasLength(2));
  });

  test('a command over the threshold becomes a command notice (D5)', () async {
    await boot(threshold: const Duration(seconds: 10));
    await emit('$esc]633;E;sleep 11\\x3b false$bel$esc]133;C$bel');
    rig.now = rig.now.add(const Duration(seconds: 11));
    await emit('$esc]133;D;1$bel');
    final notice = got.single;
    expect(notice.kind, SessionNoticeKind.command);
    expect(notice.command!.exitCode, 1);
    expect(notice.command!.commandLine, 'sleep 11; false');
    expect(notice.command!.duration, const Duration(seconds: 11));
    // runningCommand still follows 133 C/D (A1 D15).
    expect(rig.manager.sessions.single.runningCommand, isFalse);
  });

  test('no threshold ("Tắt") or a short command: no command notice', () async {
    await boot();
    await emit('$esc]133;C$bel');
    rig.now = rig.now.add(const Duration(minutes: 5));
    await emit('$esc]133;D;0$bel');
    expect(got, isEmpty);
  });

  test('at most 30 message notices per 60 s per session (D6)', () async {
    await boot();
    await emit([for (var i = 0; i < 31; i++) '$esc]9;$i$bel'].join());
    expect(got, hasLength(30));
    rig.now = rig.now.add(const Duration(seconds: 60));
    await emit('$esc]9;again$bel');
    expect(got.last.body, 'again');
  });

  test('a closing session emits nothing', () async {
    await boot();
    final id = rig.manager.sessions.single.id;
    rig.manager.close(id);
    await emit('$esc]9;late$bel');
    expect(got, isEmpty);
  });

  test('toString never contains the text (N9)', () {
    final n = SessionNotice(
      sessionId: 1,
      kind: SessionNoticeKind.message,
      at: DateTime(2026),
      title: 'secret',
      body: 'secret',
    );
    expect(n.toString(), isNot(contains('secret')));
  });

  group('NoticeLimiter', () {
    test('bell gap and window are independent', () {
      final l = NoticeLimiter(maxPerWindow: 1);
      final t = DateTime(2026);
      expect(l.allow(SessionNoticeKind.message, t), isTrue);
      expect(l.allow(SessionNoticeKind.command, t), isFalse);
      expect(l.allow(SessionNoticeKind.bell, t), isTrue);
      expect(l.dropped, 1);
    });
  });
}
