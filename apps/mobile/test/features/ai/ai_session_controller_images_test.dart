import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart' show kAiMaxBlobPartBytes;
import 'package:shellx_mobile/features/ai/domain/ai_attachments.dart';
import 'package:shellx_mobile/features/ai/domain/ai_drafts.dart';
import 'package:shellx_mobile/features/ai/domain/ai_words.dart';
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_session_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

import '../../support/fake_image_source.dart';
import '../../support/fakes.dart';

const sid = 'e.-1';

/// V2-2b B12, B13: a message with images and files, from the session page's controller.
void main() {
  late FakeBackend backend;
  late FakeMachineSession machine;
  late FakeSessionHolder session;
  late AiSessionController controller;

  setUp(() {
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    session = FakeSessionHolder(backend);
    machine.ai
      ..protocolValue = 2
      ..emitListing(const AiListing(features: {AiFeature.blob, AiFeature.files}));
    controller = AiSessionController(agentA, sid, session, AiDrafts(), WorkspaceRegistry(session.backend));
    machine.ai.session(sid).sync();
  });

  tearDown(() => controller.dispose());

  AiPickedImage png() => AiPickedImage(kTinyPng, 'image/png');

  test('each image goes up as a blob of its own, then the message names them in order, with its files', () async {
    expect(await controller.send('Xem hai ảnh', images: [png(), png()], files: const ['src/a.ts']), isNull);
    expect(machine.ai.uploads, [(1, 'image/png', kTinyPng.length), (2, 'image/png', kTinyPng.length)]);
    expect(machine.ai.prompts.single, (sid, 'Xem hai ảnh'));
    expect(machine.ai.promptBlobs.single, [1, 2]);
    expect(machine.ai.promptFiles.single, ['src/a.ts']);
    expect(controller.upload.value, isNull);
  });

  test('images alone make a message; nothing at all is refused, sending nothing', () async {
    expect(await controller.send('  ', images: [png()]), isNull);
    expect(machine.ai.promptBlobs.single, [1]);
    expect(await controller.send('   '), 'refused');
    expect(machine.ai.prompts, hasLength(1));
  });

  test('an image that does not go up: no message is sent, nothing is tried again by itself (V2-2 D13)', () async {
    machine.ai.uploadError = const MachineConnectionException(MachineConnectionFailure.agentOffline);
    expect(await controller.send('Xem', images: [png(), png()]), AiWords.imageFailed);
    expect(machine.ai.uploads, hasLength(1), reason: 'the second image is not tried after the first failed');
    expect(machine.ai.prompts, isEmpty);
    expect((controller.upload.value, controller.sending.value), (null, false));
    // The user's next tap tries again, with new numbers.
    machine.ai.uploadError = null;
    expect(await controller.send('Xem', images: [png()]), isNull);
    expect(machine.ai.promptBlobs.single, [2]);
  });

  test('the progress counts the parts of every image of the message', () async {
    final big = AiPickedImage(Uint8List(kAiMaxBlobPartBytes * 2 + 1)..setAll(0, [0xFF, 0xD8, 0xFF]), 'image/jpeg');
    final seen = <({int sent, int parts})?>[];
    final stop = controller.upload.subscribe(seen.add);
    addTearDown(stop);
    expect(await controller.send('x', images: [png(), big]), isNull);
    expect(seen, [
      null,
      (sent: 0, parts: 4),
      (sent: 1, parts: 4),
      (sent: 2, parts: 4),
      (sent: 3, parts: 4),
      (sent: 4, parts: 4),
      null,
    ]);
  });

  test('a refusal of the message itself keeps its code (an agent that takes no images)', () async {
    machine.ai.failWith = 'no_images';
    expect(await controller.send('x', images: [png()]), 'no_images');
    expect(machine.ai.uploads, hasLength(1));
  });

  test('files for @: the computer\'s matches; none when it fails, or does not offer them', () async {
    machine.ai.fileHits = const ['src/main.ts'];
    expect(await controller.files('ma'), ['src/main.ts']);
    expect(machine.ai.fileQueries.single, (sid, 'ma'));
    machine.ai.failWith = 'busy';
    expect(await controller.files('ma'), isEmpty);
    machine.ai
      ..failWith = null
      ..emitListing(const AiListing()); // a window that offers no files any more
    expect(await controller.files('ma'), isEmpty);
    expect(machine.ai.fileQueries, hasLength(2), reason: 'nothing asked of a computer that does not offer it');
  });
}
