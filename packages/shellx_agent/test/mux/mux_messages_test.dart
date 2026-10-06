import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

void main() {
  test('round trip through frames, split across chunks', () {
    final m = MuxMessage(
      MuxType.viewWrite,
      q: 7,
      fields: {
        'id': 3,
        'data': Uint8List.fromList([1, 2, 255]),
        'future': 'ignored by old peers',
      },
    );
    final frame = encodeMux(m);
    final d = MuxFrameDecoder();
    expect(d.add(frame.sublist(0, 5)), isEmpty);
    final out = d.add(frame.sublist(5)).single;
    expect(out.type, MuxType.viewWrite);
    expect(out.q, 7);
    expect(out.get<int>('id'), 3);
    expect(out.get<Uint8List>('data'), [1, 2, 255]);
  });

  test('oversize frame and garbage are rejected', () {
    final big = Uint8List(4)..buffer.asByteData().setUint32(0, 65537);
    expect(() => MuxFrameDecoder().add(big), throwsFormatException);
    final junk = Uint8List.fromList([0, 0, 0, 2, 0xff, 0xff]);
    expect(() => MuxFrameDecoder().add(junk), throwsFormatException);
    final notMap = encodeCborFrame([1, 2]);
    expect(() => MuxFrameDecoder().add(notMap), throwsFormatException);
  });

  test('golden bytes of the frozen hello (D7)', () {
    final hello = encodeMux(
      MuxMessage(
        MuxType.hello,
        fields: {
          'protocol': 1,
          'app': '1.0.0',
          'role': 'ui',
          'nonce': Uint8List(32),
        },
      ),
    );
    expect(bytesToHex(hello.sublist(0, 4)), '0000004d');
    expect(hello.length, 4 + 0x4d);
  });

  test('SessionSummary and SessionNotice survive the wire', () {
    final s = SessionSummary(
      id: 4,
      index: 2,
      shell: 'zsh',
      createdAt: DateTime.utc(2026, 10, 7),
      attachedMobileId: 'm1',
      origin: SessionOrigin.desktop,
      title: 'vim',
      driver: DriverSide.desktop,
      runningCommand: true,
      cwd: '/w',
      gitBranch: 'main',
      ports: const [3000, 5173],
    );
    final back = summaryFromWire(summaryToWire(s));
    expect(
      [
        back.id,
        back.index,
        back.shell,
        back.attachedMobileId,
        back.origin,
        back.title,
        back.driver,
        back.runningCommand,
        back.cwd,
        back.gitBranch,
        back.ports,
      ],
      [
        4,
        2,
        'zsh',
        'm1',
        SessionOrigin.desktop,
        'vim',
        DriverSide.desktop,
        true,
        '/w',
        'main',
        [3000, 5173],
      ],
    );
    expect(back.createdAt, s.createdAt);
    final n = SessionNotice(
      sessionId: 4,
      kind: SessionNoticeKind.command,
      at: DateTime.utc(2026),
      command: const CompletedCommand(
        commandLine: 'make',
        exitCode: 2,
        duration: Duration(seconds: 11),
      ),
    );
    final nb = noticeFromWire(noticeToWire(n));
    expect(nb.kind, SessionNoticeKind.command);
    expect(nb.command!.exitCode, 2);
    expect(nb.command!.duration, const Duration(seconds: 11));
  });
}

Uint8List encodeCborFrame(Object value) {
  final body = encodeCbor(value);
  return termFrame(body);
}
