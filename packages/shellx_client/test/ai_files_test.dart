import 'package:fake_async/fake_async.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/harness.dart';
import 'support/scripted_desktop.dart';

const _sid = 'ep.-1';

Matcher _aiError(String code) =>
    isA<AiRequestException>().having((e) => e.code, 'code', code);

/// V2-2b B13 on the phone's client: `@`.
void main() {
  late TestKeys keys;
  setUpAll(() async => keys = await TestKeys.generate());

  test('files: the paths the computer offered for a query', () {
    fakeAsync((async) {
      final desktop = ScriptedDesktop(features: {AiFeature.files});
      desktop.answer = (m) => m is AiFiles
          ? AiResult(
              rid: m.rid,
              ok: true,
              body: encodeBody({
                'files': ['src/main.ts', 'src/map.ts'],
              }),
            )
          : null;
      final h = Harness(async, keys, ai: desktop);
      final ai = readyAi(h);
      expect(h.run(ai.files(_sid, 'ma')), ['src/main.ts', 'src/map.ts']);
      final asked = desktop.got<AiFiles>().single;
      expect((asked.sid, asked.query), (_sid, 'ma'));
    });
  });

  test('a query over 200 bytes (the computer refuses it too): too_large at '
      'once, nothing sent — a long one would make the channel drop', () {
    fakeAsync((async) {
      final desktop = ScriptedDesktop(features: {AiFeature.files});
      desktop.answer = (m) => m is AiFiles
          ? AiResult(rid: m.rid, ok: true, body: encodeBody({'files': []}))
          : null;
      final h = Harness(async, keys, ai: desktop);
      final ai = readyAi(h);
      expect(
        () => h.run(ai.files(_sid, 'a' * 201)),
        throwsA(_aiError('too_large')),
      );
      expect(desktop.got<AiFiles>(), isEmpty);
      expect(h.run(ai.files(_sid, 'a' * 200)), isEmpty);
      expect(desktop.got<AiFiles>(), hasLength(1));
    });
  });

  test('a prompt names its files, with images or without', () {
    fakeAsync((async) {
      final desktop = ScriptedDesktop(
        features: {AiFeature.blob, AiFeature.files},
      );
      desktop.answer = (m) =>
          m is AiPrompt ? AiResult(rid: m.rid, ok: true) : null;
      final h = Harness(async, keys, ai: desktop);
      final ai = readyAi(h);
      h.run(ai.prompt(_sid, 'xem @src/main.ts', files: ['src/main.ts']));
      h.run(ai.prompt(_sid, 'cả hai', blobs: [1], files: ['a.ts']));
      final sent = desktop.got<AiPrompt>();
      expect(
        [for (final p in sent) p.files],
        [
          ['src/main.ts'],
          ['a.ts'],
        ],
      );
      expect(
        [for (final p in sent) p.blobs],
        [
          <int>[],
          [1],
        ],
      );
    });
  });

  test('too many files, or a path too long: too_large, nothing sent', () {
    fakeAsync((async) {
      final desktop = ScriptedDesktop(features: {AiFeature.files});
      final h = Harness(async, keys, ai: desktop);
      final ai = readyAi(h);
      expect(
        () => h.run(
          ai.prompt(
            _sid,
            'x',
            files: [for (var i = 0; i <= kAiMaxPromptFiles; i++) 'f$i.ts'],
          ),
        ),
        throwsA(_aiError('too_large')),
      );
      expect(
        () => h.run(ai.prompt(_sid, 'x', files: ['x' * (kAiMaxPathBytes + 1)])),
        throwsA(_aiError('too_large')),
      );
      expect(desktop.got<AiPrompt>(), isEmpty);
    });
  });

  test('a computer that offers no files: unsupported at once, nothing sent; '
      'images still go (B1, R15)', () {
    fakeAsync((async) {
      final desktop = ScriptedDesktop(features: {AiFeature.blob});
      desktop.answer = (m) =>
          m is AiPrompt ? AiResult(rid: m.rid, ok: true) : null;
      final h = Harness(async, keys, ai: desktop);
      final ai = readyAi(h);
      expect(
        () => h.run(ai.files(_sid, 'ma')),
        throwsA(_aiError('unsupported')),
      );
      expect(
        () => h.run(ai.prompt(_sid, 'x', files: ['a.ts'])),
        throwsA(_aiError('unsupported')),
      );
      h.run(ai.prompt(_sid, 'ảnh', blobs: [1]));
      expect(desktop.got<AiFiles>(), isEmpty);
      expect(
        [for (final p in desktop.got<AiPrompt>()) p.blobs],
        [
          [1],
        ],
      );
    });
  });
}
