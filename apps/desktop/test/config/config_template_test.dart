import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/config/config_template.dart';
import 'package:shellx_desktop/src/config/keybindings.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';

void main() {
  for (final mac in [true, false]) {
    test('the template is all comments: it changes nothing (mac: $mac)', () {
      final text = configTemplate(
        mac: mac,
        ghosttyFiles: const ['/h/.config/ghostty/config'],
      );
      final problems = <ConfigProblem>[];
      expect(parseConfigText(text, file: '/c', problems: problems), isEmpty);
      expect(problems, isEmpty);
      expect(text, contains('/h/.config/ghostty/config'));
      expect(
        text,
        contains(
          mac
              ? 'super+shift+t=new_split:down'
              : 'ctrl+shift+alt+t=new_split:down',
        ),
      );
    });
  }

  for (final mac in [true, false]) {
    test('every commented "# key = value" example resolves without a problem '
        '(keybinds included; mac: $mac)', () {
      final text = configTemplate(mac: mac, ghosttyFiles: const []);
      final examples = [
        for (final line in text.split('\n'))
          if (RegExp(r'^# [a-z-]+ = ').hasMatch(line))
            line.substring(2).split('  (').first,
      ].join('\n');
      final problems = <ConfigProblem>[];
      final config = buildShellxConfig(
        ghostty: const [],
        shellx: parseConfigText(examples, file: '/c', problems: problems),
        problems: problems,
        macos: mac,
        home: '/h',
      );
      resolveKeyBindings(
        platform: mac ? TargetPlatform.macOS : TargetPlatform.windows,
        entries: config.keybinds,
        commandNames: {for (final c in config.commands) c.name},
        optionAsAlt: config.optionAsAlt,
        problems: problems,
      );
      expect(config.keybinds, isNotEmpty);
      expect(config.commands, isNotEmpty);
      expect(problems.where((p) => p.severity != ConfigSeverity.info), isEmpty);
    });
  }
}
