import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/keybind_actions.dart';
import 'package:shellx_desktop/src/config/keybindings.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';

import '../support/config_harness.dart';
import '../support/fakes.dart';
import '../support/memory_config_fs.dart';

void main() {
  late MemoryConfigFs fs;
  late TestHarness h;
  late ProviderContainer container;
  final paths = testConfigPaths();

  setUp(() {
    fs = MemoryConfigFs();
    h = TestHarness();
    container = ProviderContainer(
      overrides: [
        desktopServicesProvider.overrideWithValue(h.services()),
        ...configOverrides(fs),
      ],
    );
  });
  tearDown(() {
    container.dispose();
    labelBindings = null;
  });

  const fontProblem = ConfigProblem(
    file: '/f',
    line: 1,
    severity: ConfigSeverity.warning,
    code: ConfigProblemCode.fontNotFound,
    value: 'Nope',
  );

  ConfigController controller() =>
      container.read(shellxConfigProvider.notifier);
  ConfigState state() => container.read(shellxConfigProvider);

  test('before any load: the defaults, generation 0', () {
    expect(state().generation, 0);
    expect(state().config.fontSize, isNull);
    expect(state().bindings.labelOf(const KeyAction('new_tab')), '⌘T');
  });

  test('no files: defaults, no problems, the files to watch', () async {
    final s = await controller().load();
    expect(s.generation, 1);
    expect(s.problems, isEmpty);
    expect(s.files, containsAll([paths.shellx, ...paths.ghostty]));
    expect(s.lastLoad!.problemsChanged, isFalse);
    expect(labelBindings, same(s.bindings));
  });

  test('values, theme and bindings are published together', () async {
    fs.write(
      paths.shellx,
      'font-size = 16\nbackground = #000000\nkeybind = super+k=new_tab\n',
    );
    final s = await controller().load();
    expect(s.config.fontSize, 16);
    expect(s.theme.background, const Color(0xFF000000));
    // Task 4 ruling: the user's own single chord labels the action.
    expect(s.bindings.labelOf(const KeyAction('new_tab')), '⌘K');
    expect(s.bindings.triggersOf(const KeyAction('new_tab')), hasLength(2));
  });

  test('an unreadable file keeps the previous configuration (D8)', () async {
    fs.write(paths.shellx, 'font-size = 16\n');
    await controller().load();
    fs.unreadable.add(paths.shellx);
    final s = await controller().load();
    expect(s.config.fontSize, 16);
    expect(s.problems.single.code, ConfigProblemCode.unreadable);
    expect(s.lastLoad!.problemsChanged, isTrue);
    expect(s.generation, 2);
  });

  List<String> captureLogs() {
    final logs = <String>[];
    final original = debugPrint;
    debugPrint = (m, {wrapWidth}) => logs.add(m ?? '');
    addTearDown(() => debugPrint = original);
    return logs;
  }

  test('a parser error is internal, never thrown (D10)', () async {
    fs.write(paths.shellx, 'font-size = 16\n');
    await controller().load();
    final logs = captureLogs();
    fs.readError = StateError('boom: secret-token');
    final s = await controller().load();
    expect(s.config.fontSize, 16);
    expect(s.problems.single.code, ConfigProblemCode.internal);
    // The type only: never the message or the file contents.
    expect(logs, ['ShellX: config load failed: StateError']);
  });

  test('problemsChanged only when the set changes (D36)', () async {
    fs.write(paths.shellx, 'font-size = to\n');
    expect((await controller().load()).lastLoad!.problemsChanged, isTrue);
    expect((await controller().load()).lastLoad!.problemsChanged, isFalse);
    expect((await controller().load(manual: true)).lastLoad!.manual, isTrue);
    fs.write(paths.shellx, 'font-size = 12\n');
    expect((await controller().load()).lastLoad!.problemsChanged, isTrue);
  });

  test('a listener that acknowledges the notice while a load is being '
      'announced leaves it acknowledged', () async {
    fs.write(paths.ghostty[1], 'font-family = Fira Code\n');
    container.listen(shellxConfigProvider, (_, next) {
      if (next.ghosttyNoticePending) controller().ackGhosttyNotice();
    });
    await controller().load();
    expect(state().ghosttyNoticePending, isFalse);
    expect((await controller().load()).ghosttyNoticePending, isFalse);
  });

  test(
    'Ghostty: read when enabled, a one-time notice, off with ghostty-config = false',
    () async {
      fs.write(paths.ghostty[1], 'font-family = Fira Code\n');
      var s = await controller().load();
      expect(s.config.fontFamilies, ['Fira Code']);
      expect(s.ghosttyUsed, isTrue);
      expect(s.ghosttyNoticePending, isTrue);
      // Nothing is written while loading: only the UI's ack records it.
      expect(h.settings.values[SettingKeys.configGhosttyNoticeShown], isNull);
      s = await controller().load();
      expect(s.ghosttyNoticePending, isTrue);
      controller().ackGhosttyNotice();
      expect(state().ghosttyNoticePending, isFalse);
      expect(h.settings.values[SettingKeys.configGhosttyNoticeShown], isTrue);
      s = await controller().load();
      expect(s.ghosttyNoticePending, isFalse);
      fs.write(paths.shellx, 'ghostty-config = false\n');
      final reads = fs.reads;
      s = await controller().load();
      expect(s.config.fontFamilies, isEmpty);
      expect(s.ghosttyUsed, isFalse);
      expect(fs.reads - reads, 1); // only the ShellX file
    },
  );

  test('the Ghostty notice is published even when the load has problems '
      '(preflight D8)', () async {
    fs.write(paths.ghostty[0], 'font-size = 15\n');
    fs.write(paths.shellx, 'font-size = to\n');
    final s = await controller().load();
    expect(s.problems, isNotEmpty);
    expect(s.lastLoad!.problemsChanged, isTrue);
    expect(s.ghosttyNoticePending, isTrue);
  });

  test('the Ghostty notice stays pending until acknowledged (I1)', () async {
    fs.write(paths.ghostty[0], 'font-size = 15\n');
    await controller().load();
    controller().reportRuntimeProblems(
      1,
      {ConfigProblemCode.fontNotFound},
      [fontProblem],
    );
    expect(state().ghosttyNoticePending, isTrue);
    fs.write(paths.shellx, 'ghostty-config = false\n');
    await controller().load();
    expect(state().ghosttyNoticePending, isTrue);
    controller().ackGhosttyNotice();
    expect(state().ghosttyNoticePending, isFalse);
    expect(h.settings.values[SettingKeys.configGhosttyNoticeShown], isTrue);
  });

  test('a notice already shown on an earlier launch is not pending', () async {
    h.settings.values[SettingKeys.configGhosttyNoticeShown] = true;
    fs.write(paths.ghostty[0], 'font-size = 15\n');
    expect((await controller().load()).ghosttyNoticePending, isFalse);
  });

  test('no notice, no flag, when the ShellX file is unreadable', () async {
    fs.write(paths.ghostty[0], 'font-size = 15\n');
    fs.unreadable.add(paths.shellx);
    final s = await controller().load();
    expect(s.ghosttyNoticePending, isFalse);
    expect(h.settings.values[SettingKeys.configGhosttyNoticeShown], isNull);
  });

  test('Ghostty files are read in ConfigPaths.ghostty order', () async {
    fs.write(paths.ghostty[0], 'font-size = 12\nbackground = #111111\n');
    fs.write(paths.ghostty[1], 'font-size = 13\n');
    fs.write(paths.ghostty[3], 'font-size = 15\n');
    final s = await controller().load();
    expect(s.config.fontSize, 15);
    expect(s.theme.background, const Color(0xFF111111));
    // ShellX lines win over every Ghostty file.
    fs.write(paths.shellx, 'font-size = 20\n');
    expect((await controller().load()).config.fontSize, 20);
  });

  test('paths are compared ignoring case on macOS', () async {
    final a = '${paths.shellxDir}/Extra';
    fs.write(a, 'font-size = 14\n');
    fs.write(
      paths.shellx,
      'config-file = $a\nconfig-file = ${paths.shellxDir}/extra\n',
    );
    final s = await controller().load();
    expect(s.config.fontSize, 14);
    expect(s.files, contains(a));
    expect(s.files, isNot(contains('${paths.shellxDir}/extra')));
    expect(s.problems, isEmpty);
  });

  test('check() reports without applying', () async {
    fs.write(paths.shellx, 'font-size = 16\n');
    await controller().load();
    fs.write(paths.shellx, 'font-size = to\n');
    final problems = await controller().check();
    expect(problems.single.code, ConfigProblemCode.badValue);
    expect(state().config.fontSize, 16);
    expect(state().problems, isEmpty);
  });

  test('loads run one at a time, in order (preflight D10)', () async {
    final gate = Completer<void>();
    fs.readGate = gate.future;
    fs.write(paths.shellx, 'font-size = 14\n');
    final first = controller().load();
    await pumpEventQueue();
    expect(fs.reads, 1); // the first load is waiting on its first read
    final second = controller().load();
    await pumpEventQueue();
    expect(fs.reads, 1); // the second has not started
    fs.write(paths.shellx, 'font-size = 15\n');
    gate.complete();
    final results = await Future.wait([first, second]);
    expect(results.map((s) => s.generation), [1, 2]);
    expect(results.map((s) => s.config.fontSize), [14, 15]);
    expect(state().config.fontSize, 15);
  });

  test('a load after a failed one still runs', () async {
    captureLogs();
    fs.readError = StateError('boom');
    await controller().load();
    fs.readError = null;
    fs.write(paths.shellx, 'font-size = 17\n');
    final s = await controller().load();
    expect(s.config.fontSize, 17);
    expect(s.problems, isEmpty);
  });

  test('runtime problems (font probe) join the current generation only; '
      'lastLoad stays the load event (I3)', () async {
    await controller().load();
    final loaded = state().lastLoad;
    controller().reportRuntimeProblems(
      1,
      {ConfigProblemCode.fontNotFound},
      [fontProblem],
    );
    expect(state().problems, [fontProblem]);
    expect(state().runtimeProblems, [fontProblem]);
    expect(state().lastLoad, same(loaded));
    final before = state();
    controller().reportRuntimeProblems(
      1,
      {ConfigProblemCode.fontNotFound},
      [fontProblem],
    );
    expect(state(), same(before)); // identical report: nothing published
    controller().reportRuntimeProblems(0, {
      ConfigProblemCode.fontNotFound,
    }, const []);
    expect(state().problems, [fontProblem]); // stale generation ignored
  });

  test('load problems survive a later empty font report (I3)', () async {
    fs.write(paths.shellx, 'font-size = to\n');
    await controller().load(manual: true);
    controller().reportRuntimeProblems(1, {
      ConfigProblemCode.fontNotFound,
    }, const []);
    expect(state().problems.single.code, ConfigProblemCode.badValue);
    expect(state().errorCount, 1);
    expect(state().lastLoad!.manual, isTrue);
    expect(state().lastLoad!.problemsChanged, isTrue);
  });

  test('a new configuration drops the runtime problems of the old', () async {
    await controller().load();
    controller().reportRuntimeProblems(
      1,
      {ConfigProblemCode.fontNotFound},
      [fontProblem],
    );
    fs.write(paths.shellx, 'font-size = 14\n');
    final s = await controller().load();
    expect(s.problems, isEmpty);
    expect(s.lastLoad!.problemsChanged, isTrue);
  });

  test('disposed while a read is in flight: load completes, never throws '
      '(I2)', () async {
    final gate = Completer<void>();
    fs.readGate = gate.future;
    final pending = controller().load();
    await pumpEventQueue();
    container.dispose();
    gate.complete();
    final s = await pending;
    expect(s.generation, 0);
    // A load asked of a disposed controller does not throw either.
    container = ProviderContainer(overrides: configOverrides(fs));
  });

  test('only configOverrides (no desktop services): a Ghostty load works '
      '(I2)', () async {
    final bare = ProviderContainer(overrides: configOverrides(fs));
    addTearDown(bare.dispose);
    fs.write(paths.ghostty[0], 'font-size = 15\n');
    final s = await bare.read(shellxConfigProvider.notifier).load();
    expect(s.config.fontSize, 15);
    expect(s.problems, isEmpty);
  });

  test('a read that never ends times out after 10 s; the queue moves on '
      '(M4)', () {
    fakeAsync((async) {
      final logs = captureLogs();
      fs.write(paths.shellx, 'font-size = 16\n');
      ConfigState? first;
      controller().load().then((s) => first = s);
      async.flushMicrotasks();
      expect(first!.config.fontSize, 16);
      fs.readGate = Completer<void>().future; // never completes
      ConfigState? stuck;
      ConfigState? next;
      controller().load().then((s) => stuck = s);
      controller().load().then((s) => next = s);
      async.elapse(const Duration(seconds: 9));
      expect(stuck, isNull);
      async.elapse(const Duration(seconds: 1));
      expect(stuck!.config.fontSize, 16);
      expect(stuck!.problems.single.code, ConfigProblemCode.unreadable);
      fs.readGate = null;
      async.elapse(const Duration(seconds: 10));
      expect(next, isNotNull);
      expect(logs, everyElement(startsWith('ShellX: config load')));
    });
  });

  test('watching reloads after a save (D9)', () {
    fakeAsync((async) {
      controller().load();
      async.flushMicrotasks();
      controller().startWatching();
      async.flushMicrotasks();
      fs.write(paths.shellx, 'font-size = 18\n');
      async.elapse(const Duration(milliseconds: 1300));
      async.flushMicrotasks();
      expect(state().config.fontSize, 18);
    });
  });

  test('disposing one container leaves another one\'s label table', () async {
    final other = ProviderContainer(overrides: configOverrides(fs));
    addTearDown(other.dispose);
    final s = await other.read(shellxConfigProvider.notifier).load();
    await controller().load();
    final mine = labelBindings;
    expect(mine, isNot(same(s.bindings)));
    other.dispose();
    expect(labelBindings, same(mine));
  });

  test('a rebuilt provider starts without the old label table', () async {
    await controller().load();
    expect(labelBindings, isNotNull);
    container.invalidate(shellxConfigProvider);
    container.read(shellxConfigProvider);
    expect(labelBindings, isNull);
  });

  test('disposing clears the label table', () async {
    await controller().load();
    container.dispose();
    expect(labelBindings, isNull);
    container = ProviderContainer(overrides: configOverrides(fs));
  });

  test('a home that is not absolute: defaults and a problem, never a crash '
      '(Task 2 note)', () async {
    final logs = captureLogs();
    final bad = ProviderContainer(
      overrides: [
        desktopServicesProvider.overrideWithValue(h.services()),
        configFsProvider.overrideWithValue(fs),
        homeDirectoryProvider.overrideWithValue(''),
        configPlatformProvider.overrideWithValue(TargetPlatform.macOS),
      ],
    );
    addTearDown(bad.dispose);
    final s = await bad.read(shellxConfigProvider.notifier).load();
    expect(s.config.fontSize, isNull);
    expect(s.problems.single.code, ConfigProblemCode.internal);
    expect(s.files, isEmpty);
    expect(
      (await bad.read(shellxConfigProvider.notifier).check()).single.code,
      ConfigProblemCode.internal,
    );
    expect(fs.reads, 0);
    expect(logs, isNotEmpty);
    expect(logs, everyElement(endsWith('ArgumentError')));
  });
}
