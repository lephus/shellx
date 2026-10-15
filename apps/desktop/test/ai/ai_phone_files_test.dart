import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shellx_acp/shellx_acp.dart' show TextBlock;
import 'package:shellx_agent/shellx_agent.dart' show AiPhonePrompt, AiRefused;
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/ai/ai_phone.dart' show DesktopAiSource;
import 'package:shellx_desktop/src/ai/ai_phone_files.dart';
import 'package:shellx_desktop/src/ai/ai_project_files.dart';

import '../support/ai_phone_rig.dart';
import '../support/ai_tabs.dart';
import '../support/fake_project.dart';

/// A second source over the same window, to drive a control directly (past
/// the hub's own check).
final _source = Provider<DesktopAiSource>((ref) {
  final source = DesktopAiSource(ref);
  ref.onDispose(source.dispose);
  return source;
});

/// A project index that counts its reads (no disk).
final class _Counting implements AiProjectFiles {
  _Counting(this.paths);

  final List<String> paths;
  var reads = 0;

  @override
  Future<List<String>> index(String root) async {
    reads++;
    return paths;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// V2-2b B13, R18 on the real window: `@` from the phone.
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('shellx-b13-');
    File(p.join(dir.path, 'src', 'main.ts'))
      ..createSync(recursive: true)
      ..writeAsStringSync('main');
    File(p.join(dir.path, 'secret.txt')).writeAsStringSync('secret');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// A window whose `@` offers [offered] in [dir], with a tab there whose
  /// agent runs; and that tab's session id.
  Future<(PhoneHubRig, String)> ready(List<String> offered) async {
    final rig = PhoneHubRig(
      const FakeScenario(),
      more: [
        aiProjectFilesProvider.overrideWithValue(
          FakeProject(dir.path, {for (final f in offered) f: ''}),
        ),
      ],
    );
    final tab = openTestAiTab(rig.c, cwd: dir.path, select: false);
    final sid = rig.sidOf(tab);
    rig.say(AiAttach(sid: sid));
    await rig.until(() => rig.stateOf(tab).phase == AgentPhase.ready);
    return (rig, sid);
  }

  test("@ on the phone: the folder's files the composer offers, the best "
      'first', () async {
    final (rig, sid) = await ready(['README.md', 'src/main.ts', 'src/map.ts']);
    rig.say(AiFiles(sid: sid, rid: 1, query: 'ma'));
    final r = await rig.answer(1);
    // Names starting with the query first; the shorter path among equals.
    expect(jStrings(decodeBody(r.body)!, 'files'), [
      'src/map.ts',
      'src/main.ts',
    ]);
  });

  test('a prompt with a file: the agent gets its resource_link after the '
      'text, as from the composer', () async {
    final (rig, sid) = await ready(['src/main.ts']);
    rig.say(
      AiPrompt(
        sid: sid,
        rid: 2,
        text: 'xem @src/main.ts',
        files: const ['src/main.ts', 'src/main.ts'],
      ),
    );
    expect((await rig.answer(2)).ok, isTrue);
    await rig.until(() => rig.fakes.agent().params['session/prompt'] != null);
    expect(rig.fakes.agent().params['session/prompt']!['prompt'], [
      {'type': 'text', 'text': 'xem @src/main.ts'},
      {
        'type': 'resource_link',
        'uri': Uri.file(p.join(dir.path, 'src/main.ts')).toString(),
        'name': 'main.ts',
        'title': 'src/main.ts',
      },
    ]);
  });

  test('refused, and nothing sent: a file `@` does not offer, one no longer '
      'there, a path out of the folder', () async {
    final (rig, sid) = await ready(['src/main.ts', 'src/gone.ts']);
    rig
      ..say(AiPrompt(sid: sid, rid: 1, text: 'x', files: const ['secret.txt']))
      ..say(AiPrompt(sid: sid, rid: 2, text: 'x', files: const ['src/gone.ts']))
      ..say(
        AiPrompt(sid: sid, rid: 3, text: 'x', files: const ['../secret.txt']),
      );
    for (final rid in [1, 2, 3]) {
      expect((await rig.answer(rid)).code, 'refused', reason: 'request $rid');
    }
    expect(rig.fakes.agent().params['session/prompt'], isNull);
  });

  test('the window checks again by itself (R18): a path out of the folder '
      'is refused even when the index names it and it is there', () async {
    final folder = p.join(dir.path, 'project');
    Directory(folder).createSync();
    final outside = p.join(dir.path, 'secret.txt'); // there, out of [folder]
    final rig = PhoneHubRig(
      const FakeScenario(),
      more: [
        aiProjectFilesProvider.overrideWithValue(
          FakeProject(folder, {'../secret.txt': '', outside: ''}),
        ),
      ],
    );
    final tab = openTestAiTab(rig.c, cwd: folder, select: false);
    rig.say(AiAttach(sid: rig.sidOf(tab)));
    await rig.until(() => rig.stateOf(tab).phase == AgentPhase.ready);
    final control = rig.c.read(_source).control(tab.ai!.id)!;
    for (final path in ['../secret.txt', outside]) {
      await expectLater(
        control.send(AiPhonePrompt('x', files: [path])),
        throwsA(isA<AiRefused>().having((r) => r.code, 'code', 'refused')),
        reason: path,
      );
    }
    expect(rig.fakes.agent().params['session/prompt'], isNull);
  });

  test('the index is read once per folder, and again once a turn '
      'ended', () async {
    final project = _Counting(['src/a.ts', 'lib/b.dart']);
    final index = AiPhoneFileIndex(project);
    final s = AiSessionState(agentId: 'claude', agentName: 'Claude', cwd: '/w');
    expect(await index.match(s, 'a'), ['src/a.ts', 'lib/b.dart']);
    expect(await index.match(s, 'b'), ['lib/b.dart']);
    expect(project.reads, 1);
    s.beginTurn([const TextBlock('x')], DateTime.utc(2026, 10, 15));
    await index.files(s);
    expect(project.reads, 1, reason: 'no turn has ended yet');
    s.endTurn(outcome: TurnOutcome.finished, at: DateTime.utc(2026, 10, 15));
    await index.files(s);
    expect(project.reads, 2);
    s.cwd = '/other';
    await index.files(s);
    expect(project.reads, 3);
  });
}
