import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/config/settings_schema.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/ui/settings/pages/page_parts.dart'
    show settingById;

({ShellxConfig config, List<ConfigProblem> problems}) build(
  Map<String, String> kv,
) {
  final problems = <ConfigProblem>[];
  var n = 0;
  final config = buildShellxConfig(
    ghostty: const [],
    shellx: [
      for (final e in kv.entries)
        ConfigEntry(file: '/c', line: ++n, key: e.key, value: e.value),
    ],
    problems: problems,
    macos: true,
    home: '/Users/me',
  );
  return (config: config, problems: problems);
}

void main() {
  test('defaults: terminal tabs, Claude on, 14 days (D4, D21, D12)', () {
    final c = build({}).config;
    expect(c.newTabKind, NewTabKind.terminal);
    expect(c.aiAgentClaude, isTrue);
    expect(c.aiCheckpointDays, 14);
  });

  test('values and bad values', () {
    expect(build({'new-tab-kind': 'ai'}).config.newTabKind, NewTabKind.ai);
    expect(build({'ai-agent-claude': 'off'}).config.aiAgentClaude, isFalse);
    expect(build({'ai-agent-claude': 'on'}).config.aiAgentClaude, isTrue);
    expect(build({'ai-checkpoint-days': '30'}).config.aiCheckpointDays, 30);
    for (final (key, value) in [
      ('new-tab-kind', 'browser'),
      ('ai-agent-claude', 'maybe'),
      ('ai-checkpoint-days', 'x'),
    ]) {
      final r = build({key: value});
      expect(r.problems.single.code, ConfigProblemCode.badValue, reason: key);
    }
    final far = build({'ai-checkpoint-days': '400'});
    expect(far.config.aiCheckpointDays, kAiCheckpointDaysMax);
  });

  test('the rows: new-tab-kind on General, the AI keys on Agents', () {
    expect(settingById('new-tab-kind').page, SettingPage.general);
    expect(settingById('ai-agent-claude').page, SettingPage.agents);
    expect(settingById('ai-checkpoint-days').page, SettingPage.agents);
  });

  test('the AI keys of the settings store are the UI\'s (A5b D13)', () {
    for (final key in [
      SettingKeys.aiIntroShown,
      SettingKeys.aiDefaultAgent,
      SettingKeys.aiCustomAgents,
      SettingKeys.aiAgentConfig,
    ]) {
      expect(SettingKeys.all, contains(key));
      expect(UiSettingKeys.all, contains(key));
      expect(DaemonSettingKeys.all, isNot(contains(key)));
    }
  });
}
