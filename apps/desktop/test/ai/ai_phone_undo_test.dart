import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/ai/ai_phone.dart';
import 'package:shellx_desktop/src/ai/ai_phone_reverts.dart';
import 'package:shellx_desktop/src/ai/ai_project_files.dart';
import 'package:shellx_desktop/src/ai/ai_runtimes.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../cli/support/cli_container.dart';
import '../support/ai_fakes.dart';
import '../support/ai_tabs.dart';
import '../support/fake_local_sessions.dart';
import '../support/fake_project.dart';

const _phone = '33333333-3333-4333-8333-333333333333';

/// Just under the 1 MiB the diff page reads: quotes, backslashes and a
/// control character on every line (2.6 times its size once escaped).
final _big = '"\x01\\x\n' * ((1 << 20) ~/ 5 - 10);

/// V2-2b B19: a phone's view of the changes, one file's diff and a revert,
/// over real runtimes (fake agents) and a project in memory.
void main() {
  late ProviderContainer c;
  late FakeAiRuntimes fakes;
  late FakeProject files;
  late AiPhoneHub hub;
  final out = <OutboundMessage>[];

  /// Turn 1 edits `lib/a.dart` and `big.txt`, adds `new.txt` and deletes
  /// `old.txt`; `huge.txt` is over 1 MiB.
  void boot({List<List<Map<String, Object?>>>? turns, UndoOff? off}) {
    out.clear();
    files = FakeProject(testAiCwd, {
      'lib/a.dart': 'one\n',
      'old.txt': 'gone\n',
      'big.txt': _big,
      'huge.txt': 'h' * ((1 << 20) + 1),
    })..off = off;
    files.onSnapshot = (ref) {
      if (!ref.endsWith('/1')) return;
      files.files
        ..['lib/a.dart'] = 'one\ntwo\n'
        ..['new.txt'] = 'hi\n'
        ..['big.txt'] = 'A${_big.substring(1, _big.length - 1)}B'
        ..['huge.txt'] = 'H${files.files['huge.txt']!.substring(1)}'
        ..remove('old.txt');
    };
    fakes = FakeAiRuntimes(
      FakeScenario(
        turns:
            turns ??
            [
              [FakeSteps.text('Done.')],
            ],
      ),
      checkpoints: files,
    );
    c = cliContainer(
      FakeLocalSessions(),
      overrides: [
        ...fakes.overrides,
        aiProjectFilesProvider.overrideWithValue(files),
      ],
    );
    hub = c.read(aiPhoneHubProvider);
    hub.outbound.listen(out.add);
  }

  Map<int, AiResult> results() => {
    for (final o in out)
      if (o.message case final AiResult r) r.rid: r,
  };

  Future<void> until(bool Function() test) async {
    for (var i = 0; i < 400 && !test(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(test(), isTrue, reason: 'condition not reached');
  }

  /// The answer to request [rid], once it came.
  Future<AiResult> answer(int rid) async {
    await until(() => results().containsKey(rid));
    return results()[rid]!;
  }

  AiSessionState stateOf(TerminalTab tab) =>
      c.read(aiRuntimesProvider.notifier).existing(tab.ai!.id)!.state;

  /// An AI tab the phone opened and whose first turn it asked for; its sid.
  Future<(String, TerminalTab)> afterTurn() async {
    final tab = openTestAiTab(c, cwd: testAiCwd, select: false);
    final sid = hub.sidOf(tab.ai!.id);
    hub.handle(_phone, AiAttach(sid: sid));
    await until(
      () =>
          c
              .read(aiRuntimesProvider.notifier)
              .existing(tab.ai!.id)
              ?.state
              .phase ==
          AgentPhase.ready,
    );
    hub.handle(_phone, AiPrompt(sid: sid, rid: 1, text: 'go'));
    await until(
      () => stateOf(tab).timeline.items.whereType<TurnEndItem>().isNotEmpty,
    );
    return (sid, tab);
  }

  test('the phone reads the turn\'s changes and their diffs, as the Changes '
      'panel shows them; a file not among them is refused (R18)', () async {
    boot();
    final (sid, _) = await afterTurn();
    hub.handle(_phone, AiChanges(sid: sid, rid: 2, turn: 1));
    final view = AiChangesView.fromJson(decodeBody((await answer(2)).body)!);
    expect(
      [for (final f in view.files) (f.path, f.kind)],
      [
        ('big.txt', 'm'),
        ('huge.txt', 'm'),
        ('lib/a.dart', 'm'),
        ('new.txt', 'a'),
        ('old.txt', 'd'),
      ],
    );
    expect(
      (view.scope, view.turn, view.first, view.last, view.done),
      ('turn', 1, 1, 1, 1),
    );
    expect(view.after, isEmpty);

    hub
      ..handle(_phone, AiDiff(sid: sid, rid: 3, turn: 1, path: 'lib/a.dart'))
      ..handle(_phone, AiDiff(sid: sid, rid: 4, turn: 1, path: 'new.txt'))
      ..handle(_phone, AiDiff(sid: sid, rid: 5, turn: 1, path: 'old.txt'))
      ..handle(
        _phone,
        AiDiff(sid: sid, rid: 6, turn: 1, path: 'lib/nope.dart'),
      );
    final edit = aiFileDiffOf(decodeBody((await answer(3)).body)!)!;
    expect((edit.oldText, edit.newText, edit.plus), ('one', 'one\ntwo', 1));
    expect(
      aiFileDiffOf(decodeBody((await answer(4)).body)!)!.oldText,
      isNull,
      reason: 'a new file',
    );
    final gone = aiFileDiffOf(decodeBody((await answer(5)).body)!)!;
    expect((gone.oldText, gone.newText), ('gone', ''));
    expect((await answer(6)).code, 'refused');
  });

  test('a file of nearly 1 MiB fits one message; one over is too_big '
      '(Review Focus 3)', () async {
    boot();
    final (sid, _) = await afterTurn();
    hub
      ..handle(_phone, AiDiff(sid: sid, rid: 2, turn: 1, path: 'big.txt'))
      ..handle(_phone, AiDiff(sid: sid, rid: 3, turn: 1, path: 'huge.txt'));
    final big = await answer(2);
    expect(big.ok, isTrue);
    expect(encodeBatch([big]).length, lessThan(kMaxSealedBatchBytes));
    expect(aiFileDiffOf(decodeBody(big.body)!)!.cut, isTrue);
    expect((await answer(3)).code, 'too_big');
  });

  test('the phone reverts the turn; the pane is told', () async {
    boot();
    final (sid, tab) = await afterTurn();
    final told = <AiPhoneRevert>[];
    c.read(aiPhoneRevertsProvider).stream.listen(told.add);
    hub.handle(_phone, AiRevert(sid: sid, rid: 2, turn: 1));
    expect(decodeBody((await answer(2)).body), {'reverted': 5});
    expect(files.files, {
      'lib/a.dart': 'one\n',
      'old.txt': 'gone\n',
      'big.txt': _big,
      'huge.txt': 'h' * ((1 << 20) + 1),
    });
    await until(() => told.isNotEmpty);
    expect(told, [(paneId: tab.ai!.id, count: 5)]);
  });

  test('a file the computer changed after the phone looked asks first; '
      '"clean" leaves it (Review Focus 4)', () async {
    boot();
    final (sid, _) = await afterTurn();
    hub.handle(_phone, AiChanges(sid: sid, rid: 2, turn: 1));
    await answer(2);
    files.files['new.txt'] = 'mine\n'; // someone at the computer, meanwhile
    hub.handle(_phone, AiRevert(sid: sid, rid: 3, turn: 1));
    final ask = await answer(3);
    expect((ask.ok, ask.code), (false, 'confirm'));
    final question = AiRevertConfirm.fromJson(decodeBody(ask.body)!);
    expect(question.touched, ['new.txt']);
    expect((question.someClean, question.files), (true, 5));
    expect(files.restored, isEmpty, reason: 'nothing before the answer');
    hub.handle(_phone, AiRevert(sid: sid, rid: 4, turn: 1, keep: 'clean'));
    expect(decodeBody((await answer(4)).body), {'reverted': 4});
    expect(files.files['new.txt'], 'mine\n');
    expect(files.files['lib/a.dart'], 'one\n');
  });

  test('"all" puts back the files changed after the turn too '
      '(Review Focus 4)', () async {
    boot();
    final (sid, _) = await afterTurn();
    files.files['new.txt'] = 'mine\n';
    hub.handle(_phone, AiRevert(sid: sid, rid: 2, turn: 1, keep: 'all'));
    expect(decodeBody((await answer(2)).body), {'reverted': 5});
    expect(files.files.containsKey('new.txt'), isFalse);
    expect(files.files['lib/a.dart'], 'one\n');
  });

  test('"clean" when every file changed after the turn: nothing goes back, '
      'the phone hears 0 and the pane nothing (Review Focus 4)', () async {
    boot();
    final (sid, _) = await afterTurn();
    final told = <AiPhoneRevert>[];
    c.read(aiPhoneRevertsProvider).stream.listen(told.add);
    // Someone at the computer touched every file of the turn meanwhile
    // (`old.txt`, which the turn deleted, made again).
    for (final path in [
      'big.txt',
      'huge.txt',
      'lib/a.dart',
      'new.txt',
      'old.txt',
    ]) {
      files.files[path] = 'mine\n';
    }
    hub.handle(_phone, AiRevert(sid: sid, rid: 2, turn: 1));
    final question = AiRevertConfirm.fromJson(
      decodeBody((await answer(2)).body)!,
    );
    expect((question.touchedCount, question.someClean), (5, false));
    hub.handle(_phone, AiRevert(sid: sid, rid: 3, turn: 1, keep: 'clean'));
    final done = await answer(3);
    expect(done.ok, isTrue);
    expect(decodeBody(done.body), {'reverted': 0});
    expect(files.restored, isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(told, isEmpty);
  });

  test('while a turn runs a revert is busy_turn, and nothing goes back '
      '(Review Focus 4)', () async {
    boot(
      turns: [
        [FakeSteps.text('Done.')],
        [FakeSteps.waitCancel()],
      ],
    );
    final (sid, tab) = await afterTurn();
    hub.handle(_phone, AiPrompt(sid: sid, rid: 2, text: 'two'));
    await until(() => stateOf(tab).turn != null);
    hub.handle(_phone, AiRevert(sid: sid, rid: 3, turn: 1));
    expect((await answer(3)).code, 'busy_turn');
    expect(files.restored, isEmpty);
    c.read(aiRuntimesProvider.notifier).existing(tab.ai!.id)!.cancel();
  });

  test('undo off: the view says why, a revert is undo_off', () async {
    boot(off: UndoOff.noGit);
    final (sid, _) = await afterTurn();
    hub
      ..handle(_phone, AiChanges(sid: sid, rid: 2))
      ..handle(_phone, AiRevert(sid: sid, rid: 3))
      ..handle(_phone, AiDiff(sid: sid, rid: 4, path: 'lib/a.dart'));
    final view = AiChangesView.fromJson(decodeBody((await answer(2)).body)!);
    expect(view.files, isEmpty);
    expect(view.off, 'noGit');
    expect((await answer(3)).code, 'undo_off');
    expect((await answer(4)).code, 'undo_off');
  });
}
