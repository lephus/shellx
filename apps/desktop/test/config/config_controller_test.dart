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
  tearDown(() => container.dispose());

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

  test(
    'Ghostty: read when enabled, a one-time notice, off with ghostty-config = false',
    () async {
      fs.write(paths.ghostty[1], 'font-family = Fira Code\n');
      var s = await controller().load();
      expect(s.config.fontFamilies, ['Fira Code']);
      expect(s.ghosttyUsed, isTrue);
      expect(s.lastLoad!.firstGhostty, isTrue);
      expect(h.settings.values[SettingKeys.configGhosttyNoticeShown], isTrue);
      s = await controller().load();
      expect(s.lastLoad!.firstGhostty, isFalse);
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
    expect(s.lastLoad!.firstGhostty, isTrue);
    expect(h.settings.values[SettingKeys.configGhosttyNoticeShown], isTrue);
  });

  test('no notice, no flag, when the ShellX file is unreadable', () async {
    fs.write(paths.ghostty[0], 'font-size = 15\n');
    fs.unreadable.add(paths.shellx);
    final s = await controller().load();
    expect(s.lastLoad!.firstGhostty, isFalse);
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

  test(
    'runtime problems (font probe) join the current generation only',
    () async {
      await controller().load();
      const font = ConfigProblem(
        file: '/f',
        line: 1,
        severity: ConfigSeverity.warning,
        code: ConfigProblemCode.fontNotFound,
        value: 'Nope',
      );
      controller().reportRuntimeProblems(
        1,
        {ConfigProblemCode.fontNotFound},
        [font],
      );
      expect(state().problems, [font]);
      expect(state().lastLoad!.problemsChanged, isTrue);
      controller().reportRuntimeProblems(
        1,
        {ConfigProblemCode.fontNotFound},
        [font],
      );
      expect(state().lastLoad!.problemsChanged, isFalse);
      controller().reportRuntimeProblems(0, {
        ConfigProblemCode.fontNotFound,
      }, const []);
      expect(state().problems, [font]); // stale generation ignored
    },
  );

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
    expect(logs, everyElement(endsWith('ArgumentError')));
  });
}
