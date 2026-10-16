import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/keybind_trigger.dart';
import 'package:shellx_desktop/src/config/keybindings.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/tools/tool_keys.dart';
import 'package:shellx_desktop/src/ui/terminal/key_sequence.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_intents.dart';

import '../support/config_harness.dart';
import '../support/memory_config_fs.dart';

KeyBindings bindingsFor(
  TargetPlatform platform, [
  List<String> lines = const [],
]) {
  final problems = <ConfigProblem>[];
  var n = 0;
  return resolveKeyBindings(
    platform: platform,
    entries: [
      for (final l in lines)
        KeybindEntry(
          l,
          ConfigEntry(file: '/c', line: ++n, key: 'keybind', value: l),
        ),
    ],
    commandNames: const {},
    optionAsAlt: OptionAsAlt.off,
    problems: problems,
  );
}

void main() {
  const mac = TargetPlatform.macOS;

  test('the forwarded chords are the window keymap (Review Focus 2): ⌘T, '
      '⌘W, ⌘1…9, ⌘⇧E, ⌘⇧P, ⌘⇧B forward; ⌘C/⌘V/⌘A/⌘X/⌘Z and the prompt '
      'keys stay with the page (D10)', () {
    final chords = toolForwardedChords(KeyBindings.defaults(mac));
    for (final c in [
      'super+t',
      'super+w',
      'super+1',
      'super+9',
      'shift+super+e',
      'shift+super+p',
      'shift+super+b',
      'alt+super+arrow_right',
      'ctrl+f6',
    ]) {
      expect(chords, contains(c), reason: c);
    }
    for (final c in [
      'super+c',
      'super+v',
      'super+a',
      'super+x',
      'super+z',
      'shift+super+z',
      'super+arrow_left',
      'super+backspace',
      'alt+backspace',
    ]) {
      expect(chords, isNot(contains(c)), reason: c);
    }
  });

  test("the user's own keys count, and a sequence's first step forwards "
      '(D10)', () {
    final b = bindingsFor(mac, [
      'super+shift+j=new_tab',
      'ctrl+a>c=new_tab',
      'super+t=unbind',
    ]);
    final chords = toolForwardedChords(b);
    expect(chords, contains('shift+super+j'));
    expect(chords, contains('ctrl+a'));
    expect(chords, isNot(contains('super+t')));
  });

  test('every forwarded chord reads back as the chord it came from', () {
    for (final platform in [mac, TargetPlatform.windows]) {
      for (final text in toolForwardedChords(KeyBindings.defaults(platform))) {
        expect(chordConfigText(parseKeyChord(text)!), text, reason: text);
      }
    }
  });

  test('resolveToolChord: a binding gives its intent, a first step its '
      'prefix, anything else nothing', () {
    final b = bindingsFor(mac, ['ctrl+a>c=new_tab']);
    expect(
      (resolveToolChord(b, 'super+t')! as ToolChordIntent).intent,
      isA<NewTabIntent>(),
    );
    expect(
      (resolveToolChord(b, 'shift+super+b')! as ToolChordIntent).intent,
      isA<ToggleToolsIntent>(),
    );
    expect(
      (resolveToolChord(b, 'ctrl+a')! as ToolChordPrefix).prefix,
      const KeyChord(LogicalKeyboardKey.keyA, control: true),
    );
    expect(resolveToolChord(b, 'super+c'), isNull, reason: 'the page’s');
    expect(resolveToolChord(b, 'shift+super+q'), isNull);
    expect(resolveToolChord(b, 'not a chord'), isNull);
  });

  test('KeySequence.arm starts the wait for a known first step only', () async {
    final fs = MemoryConfigFs()
      ..write(testConfigPaths().shellx, 'keybind = ctrl+a>c=new_tab\n');
    final c = ProviderContainer.test(overrides: configOverrides(fs));
    await loadConfig(c);
    final seq = c.read(keySequenceProvider.notifier);
    expect(
      seq.arm(const KeyChord(LogicalKeyboardKey.keyB, control: true)),
      isFalse,
    );
    expect(c.read(keySequenceProvider), isNull);
    expect(
      seq.arm(const KeyChord(LogicalKeyboardKey.keyA, control: true)),
      isTrue,
    );
    expect(
      c.read(keySequenceProvider),
      const KeyChord(LogicalKeyboardKey.keyA, control: true),
    );
  });
}
