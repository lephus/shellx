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

/// V2-2b B17, B18 on the phone's client.
void main() {
  late TestKeys keys;
  setUpAll(() async => keys = await TestKeys.generate());

  test('history: a page as the computer sent it; the next one asked with its '
      'cursor', () {
    fakeAsync((async) {
      final desktop = ScriptedDesktop(features: {AiFeature.history});
      desktop.answer = (m) => switch (m) {
        AiHistory(:final rid, cursor: null) => AiResult(
          rid: rid,
          ok: true,
          body: encodeBody({
            'sessions': [
              {'acp': 'old-1', 'title': 'Nút đăng xuất'},
            ],
            'next': 'c2',
            'current': 'sess-1',
          }),
        ),
        AiHistory(:final rid) => AiResult(
          rid: rid,
          ok: true,
          body: encodeBody({'sessions': <Object?>[]}),
        ),
        _ => null,
      };
      final h = Harness(async, keys, ai: desktop);
      final ai = readyAi(h);
      final first = h.run(ai.history(_sid));
      expect([for (final s in first.sessions) s.acp], ['old-1']);
      expect((first.next, first.current), ('c2', 'sess-1'));
      expect(h.run(ai.history(_sid, cursor: 'c2')).sessions, isEmpty);
      expect(
        [for (final m in desktop.got<AiHistory>()) m.cursor],
        [null, 'c2'],
      );
      desktop.answer = (m) => m is AiHistory
          ? AiResult(rid: m.rid, ok: false, code: 'not_ready')
          : null;
      expect(() => h.run(ai.history(_sid)), throwsA(_aiError('not_ready')));
    });
  });

  test('resume: an ai.open that names the earlier session; its sid', () {
    fakeAsync((async) {
      final desktop = ScriptedDesktop(features: {AiFeature.history});
      desktop.answer = (m) =>
          m is AiOpen ? AiResult(rid: m.rid, ok: true, sid: 'ep.-5') : null;
      final h = Harness(async, keys, ai: desktop);
      final ai = readyAi(h);
      expect(h.run(ai.resume('claude', 'ws:a', 'old-1')), 'ep.-5');
      final open = desktop.got<AiOpen>().single;
      expect(
        (open.agent, open.folder, open.resume),
        ('claude', 'ws:a', 'old-1'),
      );
      desktop.answer = (m) =>
          m is AiOpen ? AiResult(rid: m.rid, ok: true) : null;
      expect(
        () => h.run(ai.resume('claude', 'ws:a', 'old-1')),
        throwsA(_aiError('refused')),
        reason: 'ok without a session is no session',
      );
    });
  });

  test(
    "chooseFolder: the key; the computer's refusal comes back as its code",
    () {
      fakeAsync((async) {
        final desktop = ScriptedDesktop(features: {AiFeature.folder});
        desktop.answer = (m) => m is AiFolder
            ? AiResult(
                rid: m.rid,
                ok: m.folder == 'ws:a',
                code: m.folder == 'ws:a' ? null : 'refused',
              )
            : null;
        final h = Harness(async, keys, ai: desktop);
        final ai = readyAi(h);
        h.run(ai.chooseFolder(_sid, 'ws:a'));
        expect(
          () => h.run(ai.chooseFolder(_sid, 'path:/x')),
          throwsA(_aiError('refused')),
        );
        expect(
          [for (final m in desktop.got<AiFolder>()) (m.sid, m.folder)],
          [(_sid, 'ws:a'), (_sid, 'path:/x')],
        );
      });
    },
  );

  test('a computer that cannot (ai 1, or a listing without the feature): '
      'nothing is sent, unsupported at once (B1, Review Focus 2)', () {
    for (final (protocol, features) in [
      (1, {AiFeature.history, AiFeature.folder}),
      (kAiProtocol, <String>{}),
    ]) {
      fakeAsync((async) {
        final desktop = ScriptedDesktop(features: features);
        final h = Harness(async, keys, ai: desktop, aiProtocol: protocol);
        final ai = readyAi(h);
        expect(() => h.run(ai.history(_sid)), throwsA(_aiError('unsupported')));
        expect(
          () => h.run(ai.resume('claude', 'ws:a', 'old-1')),
          throwsA(_aiError('unsupported')),
        );
        expect(
          () => h.run(ai.chooseFolder(_sid, 'ws:a')),
          throwsA(_aiError('unsupported')),
        );
        expect(desktop.got<AiHistory>(), isEmpty);
        expect(desktop.got<AiOpen>(), isEmpty);
        expect(desktop.got<AiFolder>(), isEmpty);
      });
    }
  });
}
