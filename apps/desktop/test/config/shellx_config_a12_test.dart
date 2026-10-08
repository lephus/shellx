import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';

({ShellxConfig config, List<ConfigProblem> problems}) build(
  Map<String, String> kv, {
  bool ghostty = false,
}) {
  final problems = <ConfigProblem>[];
  var n = 0;
  final entries = [
    for (final e in kv.entries)
      ConfigEntry(file: '/c', line: ++n, key: e.key, value: e.value),
  ];
  final config = buildShellxConfig(
    ghostty: ghostty ? entries : const [],
    shellx: ghostty ? const [] : entries,
    problems: problems,
    macos: true,
    home: '/Users/me',
  );
  return (config: config, problems: problems);
}

void main() {
  group('agent-resume (A12 D13)', () {
    test('ask is the default; off turns the offer off', () {
      expect(build({}).config.agentResume, AgentResume.ask);
      expect(
        build({'agent-resume': 'ask'}).config.agentResume,
        AgentResume.ask,
      );
      expect(build({'agent-resume': ''}).config.agentResume, AgentResume.ask);
      final off = build({'agent-resume': 'off'});
      expect(off.config.agentResume, AgentResume.off);
      expect(off.problems, isEmpty);
    });

    test('anything else is a bad value and keeps the default', () {
      for (final v in ['maybe', 'on', 'auto', 'true', 'OFF ; x']) {
        final r = build({'agent-resume': v});
        expect(r.config.agentResume, AgentResume.ask, reason: v);
        expect(r.problems.single.code, ConfigProblemCode.badValue, reason: v);
      }
    });

    test('the later line wins', () {
      expect(
        build({'agent-resume': 'off'}).config.agentResume,
        AgentResume.off,
      );
    });

    test('a Ghostty file never sets it', () {
      expect(kGhosttyKeys.contains('agent-resume'), isFalse);
      expect(
        build({'agent-resume': 'off'}, ghostty: true).config.agentResume,
        AgentResume.ask,
      );
    });
  });
}
