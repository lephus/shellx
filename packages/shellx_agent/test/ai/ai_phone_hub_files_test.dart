import 'package:shellx_ai/remote.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/ai_rig.dart';

const _phone = 'b0000000-0000-4000-8000-000000000002';

Future<AiResult> _ask(HubRig rig, AiMessage m) async {
  rig.hub.handle(_phone, m);
  await pumpEventQueue();
  return rig.last<AiResult>(_phone);
}

List<String> _paths(AiResult r) => jStrings(decodeBody(r.body)!, 'files');

AiPrompt _prompt(int rid, List<String> files) =>
    AiPrompt(sid: 'ep.-1', rid: rid, text: 'xem', files: files);

/// V2-2b B13, R18: `@` from the phone on the hub.
void main() {
  test('the listing offers files', () {
    final rig = HubRig()..source.add(-1);
    rig.hub.handle(_phone, const AiList());
    final r = rig.last<AiListResult>(_phone);
    expect(
      AiListing.fromJson(decodeBody(r.body)!, available: r.available).features,
      contains(AiFeature.files),
    );
  });

  test('ai.files: what the window matches, eight at most; a path the phone '
      'could not send back is left out', () async {
    final rig = HubRig()..source.add(-1);
    final control = rig.source.controls[-1]!
      ..projectFiles = [for (var i = 0; i < 12; i++) 'src/a$i.ts'];
    final r = await _ask(rig, const AiFiles(sid: 'ep.-1', rid: 1, query: 'a'));
    expect(_paths(r), [for (var i = 0; i < 8; i++) 'src/a$i.ts']);
    expect(control.queries, ['a']);
    control.projectFiles = [
      'a/${'x' * 1100}.ts',
      r'a\b.ts',
      '../a.ts',
      'a/${'"' * 600}.ts', // within 1 KiB, but not once in JSON
      'ok/a.ts',
    ];
    final again = await _ask(
      rig,
      const AiFiles(sid: 'ep.-1', rid: 2, query: 'a'),
    );
    expect(_paths(again), ['ok/a.ts']);
  });

  test('a query over 200 bytes is too_large, and the window is not asked; '
      'no session is not_found', () async {
    final rig = HubRig()..source.add(-1);
    final control = rig.source.controls[-1]!;
    final long = await _ask(
      rig,
      AiFiles(sid: 'ep.-1', rid: 1, query: 'a' * 201),
    );
    expect(long.code, 'too_large');
    expect(control.queries, isEmpty);
    final none = await _ask(
      rig,
      const AiFiles(sid: 'ep.-9', rid: 2, query: 'a'),
    );
    expect(none.code, 'not_found');
  });

  test('a prompt takes the files `@` offered; the window gets them as they '
      'came', () async {
    final rig = HubRig()..source.add(-1);
    final control = rig.source.controls[-1]!
      ..projectFiles = ['src/a.ts', 'lib/b.dart'];
    final r = await _ask(rig, _prompt(1, ['src/a.ts', 'lib/b.dart']));
    expect(r.ok, isTrue);
    expect(control.prompts.single.files, ['src/a.ts', 'lib/b.dart']);
  });

  test('R18: a path not relative to the folder, or leaving it, is refused, '
      'and nothing is sent', () async {
    final rig = HubRig()..source.add(-1);
    final control = rig.source.controls[-1]!..projectFiles = ['a.ts'];
    final bad = [
      '../secret',
      '/etc/hosts',
      'src/../../x',
      'C:/x',
      'c:x',
      r'src\a.ts',
      r'..\x',
      '',
      'src//a.ts',
      './a.ts',
      'a/.',
      'a/',
      'a\u0000b',
      'x' * 1025,
    ];
    for (final (i, path) in bad.indexed) {
      final r = await _ask(rig, _prompt(i + 1, ['a.ts', path]));
      expect(r.code, 'refused', reason: path);
    }
    expect(control.prompts, isEmpty);
  });

  test('more than 20 files: too_large; a file the window does not offer: '
      'refused', () async {
    final rig = HubRig()..source.add(-1);
    final control = rig.source.controls[-1]!
      ..projectFiles = [for (var i = 0; i < 21; i++) 'f$i.ts'];
    final many = await _ask(
      rig,
      _prompt(1, [for (var i = 0; i < 21; i++) 'f$i.ts']),
    );
    expect(many.code, 'too_large');
    final gone = await _ask(rig, _prompt(2, ['src/gone.ts']));
    expect(gone.code, 'refused');
    expect(control.prompts, isEmpty);
  });
}
