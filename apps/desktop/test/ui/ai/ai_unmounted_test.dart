import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart' show TextBlock;
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_project_files.dart';
import 'package:shellx_desktop/src/ui/ai/ai_changes_panel.dart';
import 'package:shellx_desktop/src/ui/ai/ai_diff_overlay.dart';
import 'package:shellx_desktop/src/ui/ai/ai_images.dart';
import 'package:shellx_desktop/src/ui/ai/ai_scope.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';
import '../../support/fake_project.dart';

/// A project whose file reads and restores wait until the test lets them go:
/// the window in which a tab is closed or an overlay is dismissed.
final class _GatedStore implements Checkpoints {
  _GatedStore(this.project);

  final FakeProject project;

  /// While set, [fileAt] and [restore] wait for it.
  Completer<void>? gate;

  Future<void> _wait() async {
    final g = gate;
    if (g != null) await g.future;
  }

  @override
  UndoOff? get off => project.off;

  @override
  Future<Checkpoint?> snapshot(String ref) => project.snapshot(ref);

  @override
  Future<String?> currentTree() => project.currentTree();

  @override
  Future<List<FileChange>> changes(String fromTree, [String? toTree]) =>
      project.changes(fromTree, toTree);

  @override
  Future<Set<String>> changedSince(String tree) => project.changedSince(tree);

  @override
  Future<List<int>?> fileAt(String treeish, String path) async {
    await _wait();
    return project.fileAt(treeish, path);
  }

  @override
  Future<void> restore(String treeish, Iterable<String> paths) async {
    await _wait();
    return project.restore(treeish, paths);
  }
}

/// M-6 of the final review: async UI code that outlives its widget (a tab
/// closed, an overlay dismissed while git works) touches nothing afterwards —
/// in debug and profile builds a notifier or a `ref` used after dispose is an
/// unhandled async error.
void main() {
  /// A runtime whose first turn changed `a.txt`, over [store].
  Future<(AiRuntime, FakeProject, _GatedStore)> afterTurn(
    WidgetTester t,
  ) async {
    final project = FakeProject(testAiCwd, {'a.txt': 'one\n'});
    project.onSnapshot = (ref) {
      if (ref.endsWith('/1')) project.files['a.txt'] = 'two\n';
    };
    final store = _GatedStore(project);
    final fakes = FakeAiRuntimes(
      FakeScenario(
        turns: [
          [FakeSteps.text('Done.')],
        ],
      ),
      checkpoints: store,
    );
    final runtime = partRuntime(fakes);
    await runtime.start();
    expect(await runtime.send([const TextBlock('go')]), isTrue);
    await runtime.whenIdle();
    for (var i = 0; i < 5; i++) {
      await t.pump();
    }
    expect(runtime.checkpointOf(1), isNotNull, reason: 'turn 1 has a restore');
    return (runtime, project, store);
  }

  testWidgets('a revert that ends after the panel is gone does not touch the '
      'pane\'s note or its panel', (t) async {
    final (runtime, project, store) = await afterTurn(t);
    late StateSetter swap;
    late BuildContext inner;
    var shown = true;
    final part = await pumpAiPart(
      t,
      StatefulBuilder(
        builder: (context, setState) {
          swap = setState;
          return shown
              ? Builder(
                  builder: (context) {
                    inner = context;
                    return const SizedBox();
                  },
                )
              : const SizedBox();
        },
      ),
      runtime: runtime,
    );
    store.gate = Completer<void>();
    final done = aiRevert(inner, runtime, part.ui, turn: 1);
    for (var i = 0; i < 5; i++) {
      await t.pump();
    }
    expect(project.restored, isEmpty, reason: 'git is still at work');
    swap(() => shown = false);
    await t.pump();
    expect(inner.mounted, isFalse);
    store.gate!.complete();
    await done;
    expect(t.takeException(), isNull);
    expect(project.restored.single.$2, ['a.txt'], reason: 'it was asked for');
    expect(part.ui.note.value, isNull, reason: 'nobody is there to read it');
    expect(part.ui.changes.value, 0);
    await runtime.dispose();
  });

  testWidgets('a diff whose overlay was closed while the file was read '
      'uses no ref afterwards', (t) async {
    final (runtime, project, store) = await afterTurn(t);
    late StateSetter swap;
    var shown = false;
    await pumpAiPart(
      t,
      StatefulBuilder(
        builder: (context, setState) {
          swap = setState;
          return shown
              ? const AiDiffOverlay(path: 'a.txt', turn: 1, session: false)
              : const SizedBox();
        },
      ),
      runtime: runtime,
      overrides: [aiProjectFilesProvider.overrideWithValue(project)],
    );
    // The overlay opens, and its first read (the file before the turn) waits.
    store.gate = Completer<void>();
    swap(() => shown = true);
    await t.pump();
    await t.pump();
    expect(find.byType(AiDiffOverlay), findsOneWidget);
    // Esc or × closes it meanwhile.
    swap(() => shown = false);
    await t.pump();
    expect(find.byType(AiDiffOverlay), findsNothing);
    store.gate!.complete();
    for (var i = 0; i < 5; i++) {
      await t.pump();
    }
    expect(t.takeException(), isNull);
    await runtime.dispose();
  });

  /// An `AiImageInput` in a pane that a test can take away; [shown] says
  /// whether it is there. The context is that of something inside it.
  Future<({AiPaneUi ui, void Function() close, BuildContext Function() inner})>
  pasteTarget(WidgetTester t, AiRuntime runtime) async {
    late StateSetter swap;
    late BuildContext inner;
    var shown = true;
    final part = await pumpAiPart(
      t,
      StatefulBuilder(
        builder: (context, setState) {
          swap = setState;
          return shown
              ? AiImageInput(
                  child: Builder(
                    builder: (context) {
                      inner = context;
                      return const SizedBox();
                    },
                  ),
                )
              : const SizedBox();
        },
      ),
      runtime: runtime,
    );
    return (
      ui: part.ui,
      close: () => swap(() => shown = false),
      inner: () => inner,
    );
  }

  testWidgets('a paste that the clipboard answers after the pane is gone '
      'writes nothing', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    await runtime.start();
    final answer = Completer<Map<String, Object?>?>();
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? await answer.future : null,
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final target = await pasteTarget(t, runtime);
    Actions.invoke(target.inner(), const AiPasteIntent());
    await t.pump();
    target.close();
    await t.pump();
    expect(target.inner().mounted, isFalse);
    answer.complete({'text': 'late text'});
    for (var i = 0; i < 5; i++) {
      await t.pump();
    }
    expect(t.takeException(), isNull);
    expect(target.ui.paste.value, isNull, reason: 'nobody left to paste into');
    await runtime.dispose();
  });

  testWidgets('a picture that is read after the pane is gone is not '
      'attached', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    await runtime.start();
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null, // a screenshot: no text
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final target = await pasteTarget(t, runtime);
    final read = Completer<Uint8List?>();
    target.ui.clipboardImage = () => read.future;
    Actions.invoke(target.inner(), const AiPasteIntent());
    await t.pump();
    await t.pump();
    target.close();
    await t.pump();
    read.complete(
      Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
    );
    for (var i = 0; i < 5; i++) {
      await t.pump();
    }
    expect(t.takeException(), isNull);
    expect(target.ui.images.items, isEmpty);
    expect(target.ui.images.note, isNull);
    await runtime.dispose();
  });

  testWidgets('files that the clipboard names after the pane is gone are '
      'not read, attached or pasted', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    await runtime.start();
    final target = await pasteTarget(t, runtime);
    final named = Completer<List<String>>();
    final read = <String>[];
    target.ui.clipboardFiles = () => named.future;
    target.ui.readImageFile = (path) async {
      read.add(path);
      return _png;
    };
    Actions.invoke(target.inner(), const AiPasteIntent());
    await t.pump();
    target.close();
    await t.pump();
    named.complete(['/shots/a.png']);
    for (var i = 0; i < 5; i++) {
      await t.pump();
    }
    expect(t.takeException(), isNull);
    expect(read, isEmpty);
    expect(target.ui.images.items, isEmpty);
    expect(target.ui.images.note, isNull);
    expect(target.ui.paste.value, isNull);
    await runtime.dispose();
  });

  testWidgets('a copied picture file that is read after the pane is gone '
      'is not attached', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    await runtime.start();
    final target = await pasteTarget(t, runtime);
    final read = Completer<Uint8List?>();
    target.ui.clipboardFiles = () async => ['/shots/a.png'];
    target.ui.readImageFile = (path) => read.future;
    Actions.invoke(target.inner(), const AiPasteIntent());
    await t.pump();
    await t.pump();
    target.close();
    await t.pump();
    read.complete(_png);
    for (var i = 0; i < 5; i++) {
      await t.pump();
    }
    expect(t.takeException(), isNull);
    expect(target.ui.images.items, isEmpty);
    expect(target.ui.images.note, isNull);
    await runtime.dispose();
  });
}

/// The first bytes of a PNG: all `aiImageMime` looks at.
final _png = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
]);
