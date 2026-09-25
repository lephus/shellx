import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/src/service/agent_channel.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/drive.dart';

const agentId = 'a0000000-0000-4000-8000-000000000001';
const phoneId = 'b0000000-0000-4000-8000-000000000002';

/// Two ends of an established IK channel: (agent side, phone side).
Future<(SecureChannel, SecureChannel)> securePair() async {
  final agentKey = await NoiseKeyPair.generate();
  final phoneKey = await NoiseKeyPair.generate();
  final prologue = buildPrologue(
    agentDeviceId: agentId,
    mobileDeviceId: phoneId,
  );
  final initiator = NoiseHandshake.initiator(
    pattern: NoisePattern.ik,
    localStatic: phoneKey,
    remoteStatic: agentKey.publicKey,
    prologue: prologue,
  );
  final responder = NoiseHandshake.responder(
    pattern: NoisePattern.ik,
    localStatic: agentKey,
    prologue: prologue,
  );
  await responder.readMessage(await initiator.writeMessage());
  await initiator.readMessage(await responder.writeMessage());
  return (SecureChannel(responder.split()), SecureChannel(initiator.split()));
}

OutputMessage output(int seq, int length) =>
    OutputMessage(id: 1, seq: seq, data: Uint8List(length));

void main() {
  late ChannelId channelId;

  setUp(() {
    channelId = ChannelId.random(Random(5));
  });

  AgentChannel newChannel(
    SecureChannel agentSide,
    List<DataFrame> sent, {
    Uint8List? pairingSecret,
    bool Function(DataFrame frame)? sendResult,
    void Function()? onFailure,
  }) => AgentChannel(
    mobileId: phoneId,
    channelId: channelId,
    name: 'Pixel',
    remoteStatic: Uint8List(32),
    secure: agentSide,
    send: (frame) {
      sent.add(frame as DataFrame);
      return sendResult == null ? true : sendResult(frame);
    },
    pairingSecret: pairingSecret,
    onFailure: onFailure,
  );

  List<AppMessage> openFrame(
    FakeAsync async,
    SecureChannel phoneSide,
    DataFrame frame,
  ) {
    final payload = ChannelPayload.decode(frame.payload);
    expect(payload.kind, PayloadKind.transport);
    return drive(async, phoneSide.open(payload.noiseMessage));
  }

  // NOTE: securePair() is built *inside* each fakeAsync block (via drive),
  // not in setUp(). NoiseTransport.encrypt/decrypt serialize calls through
  // an internal `Future`-based queue that starts as `Future.value()`
  // (packages/shellx_core/lib/src/noise/handshake.dart NoiseTransport). A
  // Future created outside a fakeAsync zone never resolves a `.then()`
  // chained onto it from inside that zone (verified with a minimal
  // fake_async-only repro, unrelated to shellx_core) — so a SecureChannel
  // built in `setUp()` (real zone) hangs forever the first time `seal()`/
  // `open()` is awaited inside `fakeAsync`. See task-7-report.md.

  test('messages queued within 16 ms go out together in one TRANSPORT', () {
    fakeAsync((async) {
      final (agentSide, phoneSide) = drive(async, securePair());
      final sent = <DataFrame>[];
      final channel = newChannel(agentSide, sent);
      channel.enqueue(output(0, 10));
      async.elapse(const Duration(milliseconds: 5));
      channel.enqueue(const SessionAttached(id: 1));
      async.elapse(const Duration(milliseconds: 10));
      expect(sent, isEmpty);
      async.elapse(const Duration(milliseconds: 1));

      expect(sent, hasLength(1));
      expect(sent.single.peer, phoneId);
      expect(sent.single.channel, channelId);
      final batch = openFrame(async, phoneSide, sent.single);
      expect(batch.map((m) => m.type), ['output', 'session.attached']);
    });
  });

  test('pending output reaching 16 KiB is flushed immediately', () {
    fakeAsync((async) {
      final (agentSide, phoneSide) = drive(async, securePair());
      final sent = <DataFrame>[];
      final channel = newChannel(agentSide, sent);
      channel.enqueue(output(0, 10 * 1024));
      async.flushMicrotasks();
      expect(sent, isEmpty);
      channel.enqueue(output(10 * 1024, 6 * 1024));
      async.flushMicrotasks();

      expect(sent, hasLength(1));
      expect(openFrame(async, phoneSide, sent.single), hasLength(2));
    });
  });

  test('a burst of full chunks is split into payloads that fit a frame', () {
    fakeAsync((async) {
      final (agentSide, phoneSide) = drive(async, securePair());
      final sent = <DataFrame>[];
      final channel = newChannel(agentSide, sent);
      for (var i = 0; i < 5; i++) {
        channel.enqueue(output(i * 16 * 1024, 16 * 1024));
      }
      async.flushMicrotasks();

      final batches = [
        for (final frame in sent) openFrame(async, phoneSide, frame),
      ];
      expect([for (final b in batches) b.length], [3, 2]);
      for (final frame in sent) {
        expect(frame.encode().length, lessThanOrEqualTo(kMaxFrameBytes));
      }
      expect(
        [
          for (final b in batches)
            for (final m in b) (m as OutputMessage).seq,
        ],
        [for (var i = 0; i < 5; i++) i * 16 * 1024],
      );
    });
  });

  test('splitIntoBatches measures encoded sizes', () {
    final small = [for (var i = 0; i < 50; i++) SessionAttached(id: i)];
    expect(splitIntoBatches(small), hasLength(1));
    final big = [for (var i = 0; i < 7; i++) output(0, 16 * 1024)];
    final batches = splitIntoBatches(big);
    expect([for (final b in batches) b.length], [3, 3, 1]);
    for (final batch in batches) {
      expect(
        encodeBatch(batch).length,
        lessThanOrEqualTo(kMaxSealedBatchBytes),
      );
    }
  });

  test('batches are sealed and sent in order', () {
    fakeAsync((async) {
      final (agentSide, phoneSide) = drive(async, securePair());
      final sent = <DataFrame>[];
      final channel = newChannel(agentSide, sent);
      channel.enqueue(output(0, 1));
      async.elapse(const Duration(milliseconds: 16));
      channel.enqueue(output(1, 16 * 1024));
      channel.enqueue(output(16 * 1024 + 1, 1));
      async.elapse(const Duration(milliseconds: 16));

      expect(sent, hasLength(2));
      final seqs = [
        for (final frame in sent)
          for (final m in openFrame(async, phoneSide, frame))
            (m as OutputMessage).seq,
      ];
      expect(seqs, [0, 1, 16 * 1024 + 1]);
    });
  });

  test('close drops pending messages and stops sending', () {
    fakeAsync((async) {
      final (agentSide, _) = drive(async, securePair());
      final sent = <DataFrame>[];
      final channel = newChannel(agentSide, sent);
      channel.enqueue(output(0, 1));
      channel.close();
      channel.enqueue(output(1, 1));
      async.elapse(const Duration(milliseconds: 50));
      expect(sent, isEmpty);
    });
  });

  test('the relay rejecting a send marks the channel failed and calls '
      'onFailure once', () {
    fakeAsync((async) {
      final (agentSide, _) = drive(async, securePair());
      final sent = <DataFrame>[];
      var failures = 0;
      final channel = newChannel(
        agentSide,
        sent,
        sendResult: (_) => false,
        onFailure: () => failures++,
      );
      channel.enqueue(output(0, 1));
      async.elapse(const Duration(milliseconds: 16));

      expect(sent, hasLength(1));
      expect(failures, 1);

      // Further activity is a no-op: enqueue/flush stop working like close().
      channel.enqueue(output(1, 1));
      async.elapse(const Duration(milliseconds: 50));
      expect(sent, hasLength(1));
      expect(failures, 1);
    });
  });

  test('a batch too large to seal marks the channel failed and calls '
      'onFailure once, without sending', () {
    fakeAsync((async) {
      final (agentSide, _) = drive(async, securePair());
      final sent = <DataFrame>[];
      var failures = 0;
      final channel = newChannel(agentSide, sent, onFailure: () => failures++);

      // A single message this large makes splitIntoBatches hand
      // SecureChannel.seal a batch over kMaxSealedBatchBytes, which throws
      // ArgumentError — exercised through the public enqueue()/flush() API,
      // no shellx_core change or test double needed.
      channel.enqueue(output(0, kMaxSealedBatchBytes + 1024));
      async.flushMicrotasks();

      expect(sent, isEmpty);
      expect(failures, 1);

      channel.enqueue(output(1, 1));
      async.elapse(const Duration(milliseconds: 50));
      expect(sent, isEmpty);
      expect(failures, 1);
    });
  });

  test('close during an in-flight seal sends nothing and does not call '
      'onFailure', () {
    fakeAsync((async) {
      final (agentSide, _) = drive(async, securePair());
      final sent = <DataFrame>[];
      var failures = 0;
      final channel = newChannel(agentSide, sent, onFailure: () => failures++);

      channel.enqueue(output(0, 1));
      channel.flush();
      // Runs after flush()'s _sendChain.then() has started sealing but
      // before that seal (a genuinely async Noise encrypt) resolves.
      scheduleMicrotask(channel.close);
      async.flushMicrotasks();

      expect(sent, isEmpty);
      expect(failures, 0);
    });
  });

  test(
    'isPairing is true only for channels created with a pairing secret',
    () async {
      final (agentSide, _) = await securePair();
      expect(newChannel(agentSide, []).isPairing, isFalse);
      expect(
        newChannel(agentSide, [], pairingSecret: Uint8List(32)).isPairing,
        isTrue,
      );
    },
  );
}
