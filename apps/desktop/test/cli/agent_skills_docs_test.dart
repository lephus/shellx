import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shellx_desktop/src/config/shellx_config.dart';

/// The agent skills (`agent-skills/`, embedded in the `shellx` binary as
/// `shellx skills print`) say what the app does. These pin what V2-1 added.
String skill(String path) => File(
  p.join(Directory.current.path, '..', '..', 'agent-skills', path),
).readAsStringSync();

/// The line of a markdown table that starts with [first] (a key's row).
String row(String text, String first) =>
    text.split('\n').singleWhere((l) => l.startsWith('| `$first`'));

void main() {
  group('shellx-config lists the AI keys (V2-1 D4, D12, D21)', () {
    late String config;
    setUpAll(() => config = skill('shellx-config/SKILL.md'));

    test('new-tab-kind: terminal or ai, terminal by default', () {
      final line = row(config, 'new-tab-kind');
      for (final kind in NewTabKind.values) {
        expect(line, contains('`${kind.name}`'));
      }
      expect(line, endsWith('| `terminal` |'));
      expect(const ShellxConfig().newTabKind, NewTabKind.terminal);
    });

    test('ai-agent-claude: on or off, on by default', () {
      final line = row(config, 'ai-agent-claude');
      expect(line, contains('`on`'));
      expect(line, contains('`off`'));
      expect(line, endsWith('| `on` |'));
      expect(const ShellxConfig().aiAgentClaude, isTrue);
    });

    test('ai-checkpoint-days: the range and the default of the code', () {
      final line = row(config, 'ai-checkpoint-days');
      expect(line, contains('$kAiCheckpointDaysMin to $kAiCheckpointDaysMax'));
      expect(line, endsWith('| $kAiCheckpointDaysDefault |'));
    });
  });

  test('the CLI reference documents the kind and cwd of a tab in ls (D19)', () {
    final reference = skill('shellx/reference.md');
    final ls = reference.substring(
      reference.indexOf('## shellx ls'),
      reference.indexOf('## shellx new-tab'),
    );
    // The JSON example carries the key; the words say what it is.
    expect(ls, contains('"tabs":[{"id":"t1712","kind":"terminal"'));
    expect(ls, contains('`"kind"`'));
    expect(ls, contains('`"ai"`'));
    expect(ls, contains('`"cwd"`'));
    expect(ls, contains('AI tab'));
  });
}
