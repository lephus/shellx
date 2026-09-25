import 'dart:async';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/fake_pty.dart';
import '../support/session_rig.dart';

void main() {
  test(
    'attach inside the buffer replays from last_seq, then session.attached',
    () async {
      final rig = SessionRig();
      final id = await rig.open(phone);
      rig.pty(0).emit('0123456789');
      await pumpEventQueue();
      rig.manager.mobileDisconnected(phone);
      rig.pty(0).emit('ABC');
      await pumpEventQueue();
      rig.clear();

      await rig.manager.handle(
        phone,
        SessionAttach(id: id, cols: 80, rows: 24, lastSeq: 4),
      );

      final messages = rig.to(phone);
      expect(messages.first, isA<OutputMessage>());
      expect((messages.first as OutputMessage).seq, 4);
      expect(outputText(messages, id), '456789ABC');
      expect(messages.last, isA<SessionAttached>());
      expect(messages.whereType<SessionReset>(), isEmpty);
    },
  );

  test(
    'attach with last_seq before start resets and replays from start',
    () async {
      final rig = SessionRig(bufferCapacity: 8);
      final id = await rig.open(phone);
      rig.manager.mobileDisconnected(phone);
      rig.pty(0).emit('0123456789ABCD'); // 14 bytes: start = 6
      await pumpEventQueue();
      rig.clear();

      await rig.manager.handle(
        phone,
        SessionAttach(id: id, cols: 80, rows: 24, lastSeq: 2),
      );

      final messages = rig.to(phone);
      expect(messages.first, isA<SessionReset>());
      expect((messages[1] as OutputMessage).seq, 6);
      expect(outputText(messages, id), '6789ABCD');
      expect(messages.last, isA<SessionAttached>());
    },
  );

  test(
    'attach with last_seq beyond end resets and replays from start',
    () async {
      final rig = SessionRig();
      final id = await rig.open(phone);
      rig.pty(0).emit('hello');
      await pumpEventQueue();
      rig.clear();

      await rig.manager.handle(
        phone,
        SessionAttach(id: id, cols: 80, rows: 24, lastSeq: 5000),
      );

      final messages = rig.to(phone);
      expect(messages.first, isA<SessionReset>());
      expect((messages[1] as OutputMessage).seq, 0);
      expect(outputText(messages, id), 'hello');
      expect(messages.last, isA<SessionAttached>());
    },
  );

  test(
    'attach to an unknown id answers session_not_found with that id',
    () async {
      final rig = SessionRig();
      await rig.manager.handle(
        phone,
        const SessionAttach(id: 42, cols: 80, rows: 24, lastSeq: 0),
      );

      final error = rig.to(phone).single as ErrorMessage;
      expect((error.code, error.id), (AppErrorCode.sessionNotFound, 42));
    },
  );

  test(
    'attach with an unchanged size nudges the height to force a redraw',
    () async {
      final rig = SessionRig();
      final id = await rig.open(phone, cols: 80, rows: 24);
      await rig.manager.handle(
        phone,
        SessionAttach(id: id, cols: 80, rows: 24, lastSeq: 0),
      );
      expect(rig.pty(0).resizes, [(80, 23), (80, 24)]);

      await rig.manager.handle(
        phone,
        SessionAttach(id: id, cols: 100, rows: 30, lastSeq: 0),
      );
      expect(rig.pty(0).resizes, [(80, 23), (80, 24), (100, 30)]);

      final tiny = await rig.open(phone, cols: 0, rows: 0);
      await rig.manager.handle(
        phone,
        SessionAttach(id: tiny, cols: 0, rows: 0, lastSeq: 0),
      );
      expect(rig.pty(1).resizes, [(1, 2), (1, 1)]);
    },
  );

  test(
    'attach from another phone detaches the first one with taken_over',
    () async {
      final rig = SessionRig();
      final id = await rig.open(phone);
      rig.clear();
      await rig.manager.handle(
        tablet,
        SessionAttach(id: id, cols: 80, rows: 24, lastSeq: 0),
      );
      rig.pty(0).emit('for tablet');
      await pumpEventQueue();
      await rig.manager.handle(
        phone,
        InputMessage(id: id, data: Uint8List.fromList('ignored'.codeUnits)),
      );

      final toPhone = rig.to(phone);
      expect(toPhone, hasLength(1));
      final detached = toPhone.single as SessionDetached;
      expect((detached.id, detached.reason), (id, DetachReason.takenOver));
      expect(outputText(rig.to(tablet), id), 'for tablet');
      expect(rig.pty(0).writes, isEmpty);
      expect(rig.manager.sessions.single.attachedMobileId, tablet);
    },
  );

  test(
    'send window: stops at 256 KiB unacknowledged, resumes on ack',
    () async {
      final rig = SessionRig(bufferCapacity: 1024 * 1024);
      final id = await rig.open(phone);
      rig.pty(0).emitBytes(List.filled(300 * 1024, 0x78));
      await pumpEventQueue();
      expect(outputBytes(rig.to(phone), id), 256 * 1024);

      await rig.manager.handle(phone, AckMessage(id: id, seq: 64 * 1024));
      expect(outputBytes(rig.to(phone), id), 300 * 1024);
      final last = rig.to(phone).whereType<OutputMessage>().last;
      expect(last.seq + last.data.length, 300 * 1024);
    },
  );

  test(
    'data overwritten while blocked is replaced by reset + replay from start',
    () async {
      final rig = SessionRig(bufferCapacity: 64 * 1024, sendWindow: 16 * 1024);
      final id = await rig.open(phone);
      rig.pty(0).emitBytes(List.filled(16 * 1024, 0x61));
      await pumpEventQueue();
      rig.pty(0).emitBytes(List.filled(100 * 1024, 0x62)); // start = 52 KiB
      await pumpEventQueue();
      rig.clear();

      await rig.manager.handle(phone, AckMessage(id: id, seq: 16 * 1024));

      final messages = rig.to(phone);
      expect(messages.first, isA<SessionReset>());
      final output = messages[1] as OutputMessage;
      expect((output.seq, output.data.length), (52 * 1024, 16 * 1024));
      expect(output.data.every((b) => b == 0x62), isTrue);
    },
  );

  test('acks beyond what was sent are clamped', () async {
    final rig = SessionRig(sendWindow: 8);
    final id = await rig.open(phone);
    rig.pty(0).emit('0123456789abcdef');
    await pumpEventQueue();
    await rig.manager.handle(phone, AckMessage(id: id, seq: 1 << 40));
    expect(outputText(rig.to(phone), id), '0123456789abcdef');

    // The bogus ack must have been clamped to what was actually sent (16),
    // not taken at face value: otherwise `acked` is now permanently far
    // ahead of `sent` and the send window never closes again.
    rig.clear();
    rig.pty(0).emitBytes(List.filled(100, 0x7a));
    await pumpEventQueue();
    expect(outputBytes(rig.to(phone), id), 0);

    await rig.manager.handle(phone, AckMessage(id: id, seq: 16));
    await pumpEventQueue();
    expect(outputBytes(rig.to(phone), id), 8);
  });

  test('mobileDisconnected detaches silently; closeSessionsAttachedTo kills '
      'only that phone’s sessions', () async {
    final rig = SessionRig();
    await rig.open(phone);
    await rig.open(tablet);
    rig.clear();
    rig.manager.mobileDisconnected(phone);
    expect(rig.sent, isEmpty);
    expect(rig.manager.sessions.first.attachedMobileId, isNull);

    rig.manager.closeSessionsAttachedTo(tablet);
    await pumpEventQueue();
    expect(rig.pty(0).killed, isFalse);
    expect(rig.pty(1).killed, isTrue);
    expect(rig.manager.sessions, hasLength(1));
  });

  test('attach racing a tray close answers session_not_found and keeps the '
      'original phone as exitRecipient', () async {
    final rig = SessionRig();
    final id = await rig.open(phone);
    rig.clear();

    // The tray closes the session (sends closed_by_host, kills the
    // shell) but the exit code hasn't landed yet: a rogue attach in that
    // window must not steal the session or its exitRecipient.
    rig.manager.closeSession(id);
    await rig.manager.handle(
      tablet,
      SessionAttach(id: id, cols: 80, rows: 24, lastSeq: 0),
    );

    final tabletError = rig.to(tablet).single as ErrorMessage;
    expect(
      (tabletError.code, tabletError.id),
      (AppErrorCode.sessionNotFound, id),
    );
    expect(rig.to(tablet).whereType<SessionAttached>(), isEmpty);

    // The original phone still gets session.exited once the kill lands.
    await pumpEventQueue();
    final phoneMessages = rig.to(phone);
    expect(phoneMessages.last, isA<SessionExited>());
    expect(
      (phoneMessages.last as SessionExited).exitCode,
      FakePty.killExitCode,
    );
    expect(rig.manager.sessions, isEmpty);
  });

  test(
    'a synchronous ack from an outbound listener sees sent already advanced '
    '(outbound is a sync broadcast stream, so this must not reenter add())',
    () async {
      final rig = SessionRig(sendWindow: 8);
      final id = await rig.open(phone);
      rig.manager.outbound.listen((o) {
        final message = o.message;
        if (message is OutputMessage && message.id == id) {
          // A client that acks the instant it receives a chunk, calling
          // back into the manager synchronously from this sync broadcast
          // callback, must see `sent` already advanced past this chunk: if
          // `_send` fires before `sent` is updated, this nested `handle`
          // call sees the stale (pre-chunk) `sent`, wrongly concludes there
          // is still unsent data below the window, and tries to send it —
          // a second, reentrant `add()` on the same sync broadcast
          // controller, which throws `Bad state: Cannot fire new event.`
          unawaited(
            rig.manager.handle(
              phone,
              AckMessage(id: id, seq: message.seq + message.data.length),
            ),
          );
        }
      });
      rig.clear();
      // Exactly one window's worth: the whole point is that after this one
      // chunk, sent == buffer.end, so a correctly-ordered nested pump finds
      // nothing left to (re-)send.
      rig.pty(0).emitBytes(List.filled(8, 0x61));
      await pumpEventQueue();

      expect(outputBytes(rig.to(phone), id), 8);
      expect(outputText(rig.to(phone), id), 'a' * 8);
    },
  );
}
