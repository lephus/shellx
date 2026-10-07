import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/config/keybind_actions.dart';
import 'package:shellx_desktop/src/config/keybind_trigger.dart';
import 'package:shellx_desktop/src/config/keybindings.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_intents.dart';

const mac = TargetPlatform.macOS;
const win = TargetPlatform.windows;

(KeyBindings, List<ConfigProblem>) resolve(
  String text, {
  TargetPlatform platform = mac,
  Set<String> commands = const {},
  OptionAsAlt option = OptionAsAlt.off,
}) {
  final problems = <ConfigProblem>[];
  final entries = [
    for (final e in parseConfigText(text, file: '/c', problems: []))
      if (e.key == 'keybind') KeybindEntry(e.value, e),
  ];
  final b = resolveKeyBindings(
    platform: platform,
    entries: entries,
    commandNames: commands,
    optionAsAlt: option,
    problems: problems,
  );
  return (b, problems);
}

Intent? lookup(
  KeyBindings b,
  String chord, {
  KeyScope scope = KeyScope.window,
}) {
  final c = parseKeyChord(chord)!;
  for (final e in b.map(scope).entries) {
    final a = e.key as SingleActivator;
    if (a.trigger == c.key &&
        a.control == c.control &&
        a.alt == c.alt &&
        a.shift == c.shift &&
        a.meta == c.meta) {
      return e.value;
    }
  }
  return null;
}

List<(int, ConfigProblemCode, ConfigSeverity)> codes(List<ConfigProblem> p) => [
  for (final x in p) (x.line, x.code, x.severity),
];

void main() {
  test('no lines: the defaults', () {
    final (b, problems) = resolve('');
    expect(problems, isEmpty);
    expect(b.all, hasLength(defaultKeyBindings(mac).length));
    expect(lookup(b, 'super+t'), isA<NewTabIntent>());
    expect(lookup(b, 'super+shift+p'), isA<CommandPaletteIntent>());
    expect(lookup(b, 'super+,'), isA<OpenConfigIntent>());
    expect(lookup(b, 'super+shift+,'), isA<ReloadConfigIntent>());
    final (w, _) = resolve('', platform: win);
    expect(lookup(w, 'ctrl+shift+p'), isA<CommandPaletteIntent>());
    expect(lookup(w, 'ctrl+,'), isA<OpenConfigIntent>());
  });

  test('a new chord adds; the default stays (criterion 5)', () {
    final (b, problems) = resolve('keybind = super+shift+t=new_split:down');
    expect(problems, isEmpty);
    expect(
      lookup(b, 'super+shift+t'),
      isA<SplitPaneIntent>().having((i) => i.axis, 'axis', SplitAxis.column),
    );
    expect(lookup(b, 'super+shift+d'), isA<SplitPaneIntent>());
    // Controller ruling (criterion 5): the user's own trigger labels it.
    expect(b.labelOf(const KeyAction('new_split', 'down')), '⌘⇧T');
    expect(b.labelOf(const KeyAction('new_split', 'right')), '⌘D');
  });

  test('unbind, clear, ignore, empty value', () {
    var (b, _) = resolve('keybind = super+d=unbind');
    expect(lookup(b, 'super+d'), isNull);
    expect(b.labelOf(const KeyAction('new_split', 'right')), isNull);
    (b, _) = resolve('keybind = clear\nkeybind = super+k=new_tab');
    expect(b.all, hasLength(1));
    expect(lookup(b, 'super+t'), isNull);
    (b, _) = resolve('keybind = super+k=ignore');
    expect(lookup(b, 'super+k'), isA<IgnoreKeyIntent>());
  });

  test('later lines win; two user lines on one chord leave a note (D27)', () {
    final (b, problems) = resolve(
      'keybind = super+k=new_tab\nkeybind = super+k=new_workspace\nkeybind = super+t=new_workspace',
    );
    expect(lookup(b, 'super+k'), isA<NewWorkspaceIntent>());
    expect(lookup(b, 'super+t'), isA<NewWorkspaceIntent>());
    expect(codes(problems), [
      (2, ConfigProblemCode.duplicate, ConfigSeverity.info),
    ]);
    expect(problems.single.detail, '1');
  });

  test('D25 errors drop the line', () {
    final (b, problems) = resolve('''
keybind = super+q=new_tab
keybind = ctrl+space=new_tab
keybind = a=new_tab
keybind = shift+a=new_tab
keybind = f6=new_tab
keybind = shift+f6=new_tab
keybind = escape=new_tab
keybind = f1=new_tab
''');
    expect(codes(problems), [
      (1, ConfigProblemCode.reservedTrigger, ConfigSeverity.error),
      (2, ConfigProblemCode.reservedTrigger, ConfigSeverity.error),
      (3, ConfigProblemCode.plainKeyTrigger, ConfigSeverity.error),
      (4, ConfigProblemCode.plainKeyTrigger, ConfigSeverity.error),
      (5, ConfigProblemCode.regionTrigger, ConfigSeverity.error),
      (6, ConfigProblemCode.regionTrigger, ConfigSeverity.error),
      (7, ConfigProblemCode.plainKeyTrigger, ConfigSeverity.error),
    ]);
    expect(problems.first.value, '⌘Q');
    expect(lookup(b, 'f1'), isA<NewTabIntent>());
    expect(lookup(b, 'super+q'), isNull);
    final (_, w) = resolve(
      'keybind = super+d=new_tab\nkeybind = alt+f4=new_tab',
      platform: win,
    );
    expect(codes(w), [
      (1, ConfigProblemCode.reservedTrigger, ConfigSeverity.error),
      (2, ConfigProblemCode.reservedTrigger, ConfigSeverity.error),
    ]);
  });

  test('D25 notes keep the binding', () {
    final (b, problems) = resolve(
      'keybind = ctrl+c=new_tab\nkeybind = alt+e=new_tab\nkeybind = ctrl+left=new_tab',
    );
    expect(codes(problems), [
      (1, ConfigProblemCode.shellKeyTrigger, ConfigSeverity.info),
      (2, ConfigProblemCode.optionKeyTrigger, ConfigSeverity.info),
      (3, ConfigProblemCode.missionControlTrigger, ConfigSeverity.info),
    ]);
    expect(lookup(b, 'ctrl+c'), isA<NewTabIntent>());
    final (_, withAlt) = resolve(
      'keybind = alt+e=new_tab',
      option: OptionAsAlt.both,
    );
    expect(withAlt, isEmpty);
    final (_, altGr) = resolve('keybind = ctrl+alt+q=new_tab', platform: win);
    expect(codes(altGr), [
      (1, ConfigProblemCode.altGrTrigger, ConfigSeverity.info),
    ]);
  });

  test('bad triggers, actions, parameters, prefixes', () {
    final (b, problems) = resolve('''
keybind = super+foo=new_tab
keybind = super+k=frobnicate
keybind = super+k=new_split:left
keybind = super+k=new_tab:x
keybind = global:super+k=new_tab
keybind = performable:super+j=new_tab
keybind = super+k
keybind = super+k=increase_font_size:9
''');
    expect(codes(problems), [
      (1, ConfigProblemCode.badTrigger, ConfigSeverity.error),
      (2, ConfigProblemCode.unknownAction, ConfigSeverity.error),
      (3, ConfigProblemCode.badActionParam, ConfigSeverity.error),
      (4, ConfigProblemCode.badActionParam, ConfigSeverity.error),
      (5, ConfigProblemCode.unsupportedPrefix, ConfigSeverity.error),
      (6, ConfigProblemCode.unsupportedPrefix, ConfigSeverity.info),
      (7, ConfigProblemCode.badTrigger, ConfigSeverity.error),
      (8, ConfigProblemCode.badActionParam, ConfigSeverity.error),
    ]);
    expect(problems[2].hint, 'right, down');
    expect(lookup(b, 'super+j'), isA<NewTabIntent>());
  });

  test('sequences: two steps, too long, a prefix shadows a single chord', () {
    final (b, problems) = resolve('''
keybind = ctrl+a=new_workspace
keybind = ctrl+a>c=new_tab
keybind = ctrl+a>b>c=new_tab
''');
    expect(b.sequences.single.sequence, [
      parseKeyChord('ctrl+a'),
      parseKeyChord('c'),
    ]);
    expect(lookup(b, 'ctrl+a'), isNull);
    // Task 4 ruling: a default single chord still bound beats a sequence.
    expect(b.labelOf(const KeyAction('new_tab')), '⌘T');
    // ctrl+a=new_workspace was shadowed: the default labels it again.
    expect(b.labelOf(const KeyAction('new_workspace')), '⌘⇧N');
    expect(codes(problems), [
      (1, ConfigProblemCode.shellKeyTrigger, ConfigSeverity.info),
      (2, ConfigProblemCode.shellKeyTrigger, ConfigSeverity.info),
      (3, ConfigProblemCode.sequenceTooLong, ConfigSeverity.error),
      (2, ConfigProblemCode.sequencePrefixShadows, ConfigSeverity.warning),
    ]);
    expect(problems.last.value, '⌃A');
  });

  test('a sequence repeating its prefix gets a note (it cannot fire)', () {
    final (b, problems) = resolve('keybind = ctrl+a>ctrl+a=new_tab\n');
    expect(b.sequences, hasLength(1));
    expect(
      problems.where((p) => p.code == ConfigProblemCode.sequenceRepeatsPrefix),
      [
        isA<ConfigProblem>()
            .having((p) => p.line, 'line', 1)
            .having((p) => p.severity, 'severity', ConfigSeverity.info)
            .having((p) => p.value, 'value', '⌃A'),
      ],
    );
  });

  test('run_command, text, csi, esc, resize amount, font step', () {
    final (b, problems) = resolve(
      r'''
keybind = super+l=run_command:Lint
keybind = super+m=run_command:Nope
keybind = ctrl+g=text:git status\n
keybind = super+u=csi:A
keybind = super+i=esc:b
keybind = super+o=text:\q
keybind = super+alt+left=resize_split:left,10
keybind = super+9=increase_font_size:2
''',
      commands: {'Lint'},
    );
    expect(
      lookup(b, 'super+l'),
      isA<RunUserCommandIntent>().having((i) => i.name, 'name', 'Lint'),
    );
    expect(
      lookup(b, 'ctrl+g'),
      isA<SendTextIntent>().having((i) => i.text, 'text', 'git status\n'),
    );
    expect(
      lookup(b, 'super+u'),
      isA<SendTextIntent>().having((i) => i.text, 'text', '\x1b[A'),
    );
    expect(
      lookup(b, 'super+i'),
      isA<SendTextIntent>().having((i) => i.text, 'text', '\x1bb'),
    );
    expect(lookup(b, 'super+alt+left'), isA<ResizePaneIntent>());
    expect(
      lookup(b, 'super+9'),
      isA<FontBiggerIntent>().having((i) => i.step, 'step', 2),
    );
    expect(codes(problems), [
      (2, ConfigProblemCode.unknownCommand, ConfigSeverity.warning),
      (3, ConfigProblemCode.shellKeyTrigger, ConfigSeverity.info),
      (6, ConfigProblemCode.badActionParam, ConfigSeverity.error),
      (7, ConfigProblemCode.unsupportedValue, ConfigSeverity.info),
    ]);
  });

  test('splitKeybind splits at the first "=" not right after "+" or ">"', () {
    expect(splitKeybind('super+==increase_font_size'), (
      trigger: 'super+=',
      action: 'increase_font_size',
    ));
    expect(splitKeybind('ctrl+a>==new_tab'), (
      trigger: 'ctrl+a>=',
      action: 'new_tab',
    ));
    expect(splitKeybind('ctrl+g=text:a=b'), (
      trigger: 'ctrl+g',
      action: 'text:a=b',
    ));
    expect(splitKeybind('nothing'), isNull);
    expect(splitKeybind('ctrl+g='), isNull);
  });

  test('labels on Windows; sequences', () {
    final (b, _) = resolve('keybind = ctrl+shift+k>n=new_tab', platform: win);
    expect(b.labelOf(const KeyAction('new_tab')), 'Ctrl+Shift+T');
    expect(b.labelOf(const KeyAction('new_workspace')), 'Ctrl+Shift+N');
    expect(
      sequenceLabel(b.sequences.single.sequence, mac: false),
      'Ctrl+Shift+K N',
    );
  });

  test('browser actions are unknown until A6 merges; Esc stays plain', () {
    final (b, problems) = resolve(
      'keybind = super+shift+b=open_browser\nkeybind = super+l=browser_reload\n'
      'keybind = escape=browser_stop\n',
    );
    expect(codes(problems), [
      (1, ConfigProblemCode.unknownAction, ConfigSeverity.error),
      (2, ConfigProblemCode.unknownAction, ConfigSeverity.error),
      (3, ConfigProblemCode.unknownAction, ConfigSeverity.error),
    ]);
    expect(b.map(KeyScope.browser), isEmpty);
    final (_, esc) = resolve('keybind = escape=new_tab');
    expect(codes(esc), [
      (1, ConfigProblemCode.plainKeyTrigger, ConfigSeverity.error),
    ]);
  });

  test('labels: user single > default single > user sequence > default', () {
    var (b, _) = resolve(
      'keybind = ctrl+a>c=new_tab\nkeybind = super+k=new_tab',
    );
    expect(b.labelOf(const KeyAction('new_tab')), '⌘K');
    (b, _) = resolve('keybind = ctrl+a>c=new_tab');
    expect(b.labelOf(const KeyAction('new_tab')), '⌘T');
    (b, _) = resolve('keybind = super+t=unbind\nkeybind = ctrl+a>c=new_tab');
    expect(b.labelOf(const KeyAction('new_tab')), '⌃A C');
  });

  test('text, csi, esc: at most 4096 UTF-8 bytes of the text sent', () {
    ConfigProblemCode? problem(String a) => parseKeyAction(a).problem;
    expect(problem('text:${'a' * 4096}'), isNull);
    expect(problem('text:${'a' * 4097}'), ConfigProblemCode.badActionParam);
    // Vietnamese and CJK: 3 bytes each, so far fewer than 4096 characters.
    expect(problem('text:${'ệ' * 1365}'), isNull);
    expect(problem('text:${'ệ' * 1366}'), ConfigProblemCode.badActionParam);
    expect(problem('text:${'中' * 1366}'), ConfigProblemCode.badActionParam);
    // The prefixes count: ESC [ is two bytes, ESC one.
    expect(problem('csi:${'a' * 4094}'), isNull);
    expect(problem('csi:${'a' * 4095}'), ConfigProblemCode.badActionParam);
    expect(problem('esc:${'a' * 4095}'), isNull);
    expect(problem('esc:${'a' * 4096}'), ConfigProblemCode.badActionParam);
  });

  test('only resize_split takes an amount', () {
    expect(
      parseKeyAction('goto_split:left,10').problem,
      ConfigProblemCode.badActionParam,
    );
    expect(parseKeyAction('resize_split:left,10').action?.param, 'left');
  });

  test('a binding\'s sequence cannot be changed', () {
    final d = defaultKeyBindings(mac).first;
    expect(() => d.sequence.add(d.sequence.first), throwsUnsupportedError);
    final (b, _) = resolve('keybind = ctrl+a>c=new_tab');
    expect(() => b.sequences.single.sequence.clear(), throwsUnsupportedError);
  });

  test('every default resolves to a spec and passes its own trigger rules', () {
    for (final platform in [mac, win]) {
      for (final d in defaultKeyBindings(platform)) {
        expect(kActionSpecs[d.action.name], isNotNull, reason: d.action.text);
        expect(
          parseKeyAction(d.action.text).action,
          d.action,
          reason: d.action.text,
        );
        final rule = checkTrigger(
          d.sequence,
          d.action,
          mac: platform == mac,
          optionAsAlt: OptionAsAlt.off,
        );
        expect(rule.error, isNull, reason: '${d.sequence} ${d.action}');
      }
    }
  });
}
