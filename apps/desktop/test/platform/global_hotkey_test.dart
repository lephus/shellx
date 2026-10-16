import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/keybind_trigger.dart';
import 'package:shellx_desktop/src/platform/global_hotkey.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart'
    show settingsStoreProvider;
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/config_harness.dart';
import '../support/fake_local_sessions.dart';
import '../support/fakes.dart';
import '../support/memory_config_fs.dart';

class FakeGlobalHotkey implements GlobalHotkey {
  KeyChord? chord;
  void Function()? press;
  bool accept = true;
  bool throwOnRegister = false;
  int registers = 0;
  int unregisters = 0;

  @override
  Future<bool> register(KeyChord c, void Function() onPressed) async {
    registers++;
    if (throwOnRegister) throw StateError('native failure');
    if (!accept) return false;
    chord = c;
    press = onPressed;
    return true;
  }

  @override
  Future<void> unregister() async {
    unregisters++;
    chord = null;
    press = null;
  }
}

class Rig {
  Rig(this.fake, this.container, this.fs, this.now);
  final FakeGlobalHotkey fake;
  final ProviderContainer container;
  final MemoryConfigFs fs;
  DateTime now;
}

Future<void> pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<Rig> rigWith({
  String config = '',
  FakeGlobalHotkey? hotkey,
  bool start = true,
}) async {
  final fake = hotkey ?? FakeGlobalHotkey();
  final fs = MemoryConfigFs();
  if (config.isNotEmpty) fs.write(testConfigPaths().shellx, config);
  final h = TestHarness();
  late Rig rig;
  final container = ProviderContainer(
    overrides: [
      desktopServicesProvider.overrideWithValue(h.services()),
      localSessionsProvider.overrideWithValue(FakeLocalSessions()),
      appL10nProvider.overrideWithValue(
        lookupAppLocalizations(const Locale('en')),
      ),
      settingsStoreProvider.overrideWithValue(h.settings),
      globalHotkeyProvider.overrideWithValue(fake),
      globalHotkeyClockProvider.overrideWithValue(() => rig.now),
      ...configOverrides(fs),
    ],
  );
  rig = Rig(fake, container, fs, DateTime(2026, 10, 8, 12));
  addTearDown(() {
    try {
      container.dispose();
    } catch (_) {}
  });
  await container.read(shellxConfigProvider.notifier).load();
  if (start) container.read(globalHotkeyBinderProvider);
  await pump();
  return rig;
}

Future<void> reload(Rig r, String text) async {
  r.fs.write(testConfigPaths().shellx, text);
  await r.container.read(shellxConfigProvider.notifier).load(manual: true);
  await pump();
}

void main() {
  test('registers the configured chord, re-registers on change, unregisters '
      'when removed', () async {
    final r = await rigWith(config: 'global-hotkey = ctrl+alt+space');
    expect(r.fake.chord, parseKeyChord('ctrl+alt+space'));
    await reload(r, 'global-hotkey = ctrl+alt+j');
    expect(r.fake.chord, parseKeyChord('ctrl+alt+j'));
    await reload(r, '');
    expect(r.fake.chord, isNull);
    r.container.dispose();
    expect(r.fake.unregisters, greaterThanOrEqualTo(1));
  });

  test(
    'off by default: nothing is registered and nothing is unregistered',
    () async {
      final r = await rigWith();
      expect(r.fake.registers, 0);
      expect(r.fake.unregisters, 0);
      expect(r.fake.chord, isNull);
    },
  );

  test('an unrelated reload does not register again', () async {
    final r = await rigWith(config: 'global-hotkey = ctrl+alt+j');
    final before = r.fake.registers;
    await reload(r, 'global-hotkey = ctrl+alt+j\nfont-size = 14');
    expect(r.fake.registers, before);
  });

  test('disposing the binder unregisters (the quit path)', () async {
    final r = await rigWith(config: 'global-hotkey = ctrl+alt+j');
    expect(r.fake.chord, isNotNull);
    await r.container.read(globalHotkeyBinderProvider).dispose();
    expect(r.fake.chord, isNull);
  });

  test('pressing it hides a visible active window and shows a hidden '
      'one', () async {
    final r = await rigWith(config: 'global-hotkey = ctrl+alt+space');
    final c = r.container;
    c.read(windowRouterProvider.notifier).showTerminal();
    c.read(windowFocusProvider.notifier).set(true);
    r.fake.press!();
    await pump();
    expect(c.read(windowRouterProvider).visible, isFalse);

    r.now = r.now.add(const Duration(seconds: 1));
    final before = c.read(windowRouterProvider).raise;
    r.fake.press!();
    await pump();
    expect(c.read(windowRouterProvider).visible, isTrue);
    expect(c.read(windowRouterProvider).raise, greaterThan(before));
    expect(
      c.read(terminalTabsProvider).tabs,
      isNotEmpty,
      reason: 'showing opens a tab when there is none, like the tray',
    );
  });

  test('a visible window that is behind another app is brought forward, '
      'not hidden', () async {
    final r = await rigWith(config: 'global-hotkey = ctrl+alt+space');
    final c = r.container;
    c.read(windowRouterProvider.notifier).showTerminal();
    c.read(windowFocusProvider.notifier).set(false);
    final before = c.read(windowRouterProvider).raise;
    r.fake.press!();
    await pump();
    expect(c.read(windowRouterProvider).visible, isTrue);
    expect(c.read(windowRouterProvider).raise, greaterThan(before));
  });

  test('key repeat (Windows sends WM_HOTKEY again while held) toggles '
      'once', () async {
    final r = await rigWith(config: 'global-hotkey = ctrl+alt+space');
    final c = r.container;
    c.read(windowRouterProvider.notifier).showTerminal();
    c.read(windowFocusProvider.notifier).set(true);
    r.fake.press!();
    await pump();
    expect(c.read(windowRouterProvider).visible, isFalse);
    r.now = r.now.add(const Duration(milliseconds: 40));
    r.fake.press!();
    await pump();
    expect(
      c.read(windowRouterProvider).visible,
      isFalse,
      reason: 'a press 40 ms later is the same hold',
    );
  });

  test('a refused registration becomes a configuration problem, not a '
      'crash', () async {
    final fake = FakeGlobalHotkey()..accept = false;
    final r = await rigWith(
      config: 'global-hotkey = ctrl+alt+space',
      hotkey: fake,
    );
    final problems = r.container.read(shellxConfigProvider).runtimeProblems;
    expect(problems.single.code, ConfigProblemCode.unsupportedValue);
    expect(problems.single.key, 'global-hotkey');
    expect(problems.single.line, 1);
    expect(r.container.read(shellxConfigProvider).visibleProblemCount, 1);
  });

  test(
    'a throwing plugin is the same: a problem, never an exception',
    () async {
      final fake = FakeGlobalHotkey()..throwOnRegister = true;
      final r = await rigWith(
        config: 'global-hotkey = ctrl+alt+space',
        hotkey: fake,
      );
      expect(
        r.container.read(shellxConfigProvider).runtimeProblems.single.code,
        ConfigProblemCode.unsupportedValue,
      );
    },
  );

  test('the problem survives a reload that keeps the chord, and goes when '
      'the chord is fixed or removed', () async {
    final fake = FakeGlobalHotkey()..accept = false;
    final r = await rigWith(
      config: 'global-hotkey = ctrl+alt+space',
      hotkey: fake,
    );
    await reload(r, 'global-hotkey = ctrl+alt+space\nfont-size = 14');
    expect(
      r.container.read(shellxConfigProvider).runtimeProblems,
      hasLength(1),
    );
    fake.accept = true;
    await reload(r, 'global-hotkey = ctrl+alt+j');
    expect(r.container.read(shellxConfigProvider).runtimeProblems, isEmpty);
    expect(fake.chord, parseKeyChord('ctrl+alt+j'));
    fake.accept = false;
    await reload(r, 'global-hotkey = ctrl+alt+k');
    expect(
      r.container.read(shellxConfigProvider).runtimeProblems,
      hasLength(1),
    );
    await reload(r, '');
    expect(r.container.read(shellxConfigProvider).runtimeProblems, isEmpty);
  });

  test('nothing about the chord is logged', () async {
    final logged = <String>[];
    final old = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logged.add(m ?? '');
    try {
      final fake = FakeGlobalHotkey()..throwOnRegister = true;
      await rigWith(config: 'global-hotkey = ctrl+alt+zzz9', hotkey: fake);
      await rigWith(config: 'global-hotkey = ctrl+alt+j', hotkey: fake);
    } finally {
      debugPrint = old;
    }
    expect(logged.join(), isNot(contains('ctrl')));
    expect(logged.join(), isNot(contains('alt')));
  });

  group('the key map', () {
    test('knows the keys a user would pick', () {
      expect(physicalKeyFor(LogicalKeyboardKey.keyJ), PhysicalKeyboardKey.keyJ);
      expect(
        physicalKeyFor(LogicalKeyboardKey.space),
        PhysicalKeyboardKey.space,
      );
      expect(physicalKeyFor(LogicalKeyboardKey.f5), PhysicalKeyboardKey.f5);
      expect(
        physicalKeyFor(LogicalKeyboardKey.digit7),
        PhysicalKeyboardKey.digit7,
      );
      expect(
        physicalKeyFor(LogicalKeyboardKey.arrowUp),
        PhysicalKeyboardKey.arrowUp,
      );
      expect(
        physicalKeyFor(LogicalKeyboardKey.backquote),
        PhysicalKeyboardKey.backquote,
      );
      expect(physicalKeyFor(LogicalKeyboardKey.audioVolumeUp), isNull);
      expect(physicalKeyFor(LogicalKeyboardKey.f13), isNull);
    });

    test('covers every key the spec lists, each to its own physical key', () {
      final logical = <LogicalKeyboardKey>[
        for (var i = 0; i < 26; i++) ...[
          LogicalKeyboardKey.findKeyByKeyId(0x61 + i)!,
        ],
        LogicalKeyboardKey.digit0,
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
        LogicalKeyboardKey.digit7,
        LogicalKeyboardKey.digit8,
        LogicalKeyboardKey.digit9,
        LogicalKeyboardKey.f1,
        LogicalKeyboardKey.f2,
        LogicalKeyboardKey.f3,
        LogicalKeyboardKey.f4,
        LogicalKeyboardKey.f5,
        LogicalKeyboardKey.f6,
        LogicalKeyboardKey.f7,
        LogicalKeyboardKey.f8,
        LogicalKeyboardKey.f9,
        LogicalKeyboardKey.f10,
        LogicalKeyboardKey.f11,
        LogicalKeyboardKey.f12,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.comma,
        LogicalKeyboardKey.period,
        LogicalKeyboardKey.slash,
        LogicalKeyboardKey.semicolon,
        LogicalKeyboardKey.quote,
        LogicalKeyboardKey.bracketLeft,
        LogicalKeyboardKey.bracketRight,
        LogicalKeyboardKey.minus,
        LogicalKeyboardKey.equal,
        LogicalKeyboardKey.backquote,
        LogicalKeyboardKey.backslash,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.tab,
        LogicalKeyboardKey.escape,
      ];
      final physical = {for (final k in logical) physicalKeyFor(k)};
      expect(physical, isNot(contains(null)));
      expect(physical, hasLength(logical.length));
    });

    test('modifiers map one to one', () {
      expect(modifiersOf(parseKeyChord('ctrl+alt+shift+super+j')!).toSet(), {
        HotKeyModifier.control,
        HotKeyModifier.alt,
        HotKeyModifier.shift,
        HotKeyModifier.meta,
      });
      expect(modifiersOf(parseKeyChord('alt+j')!), [HotKeyModifier.alt]);
    });
  });

  group('the plugin wrapper', () {
    const channel = MethodChannel('dev.leanflutter.plugins/hotkey_manager');
    final calls = <MethodCall>[];

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return true;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('registers system-wide with the chord and clears first', () async {
      final h = HotkeyManagerHotkey();
      final ok = await h.register(parseKeyChord('ctrl+alt+j')!, () {});
      expect(ok, isTrue);
      expect(calls.map((c) => c.method), ['unregisterAll', 'register']);
      final args = calls.last.arguments as Map;
      expect(args['modifiers'], containsAll(['control', 'alt']));
      expect(args['scope'], 'system');
      await h.unregister();
      expect(calls.last.method, 'unregisterAll');
    });

    test(
      'a key it cannot map is refused without touching the plugin',
      () async {
        final h = HotkeyManagerHotkey();
        final ok = await h.register(
          const KeyChord(LogicalKeyboardKey.audioVolumeUp, control: true),
          () {},
        );
        expect(ok, isFalse);
        expect(calls, isEmpty);
      },
    );

    test('a platform error is false, never thrown', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'register') {
              throw PlatformException(code: 'boom');
            }
            return true;
          });
      final h = HotkeyManagerHotkey();
      expect(await h.register(parseKeyChord('ctrl+alt+j')!, () {}), isFalse);
    });
  });
}
