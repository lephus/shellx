import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';

({ShellxConfig config, List<ConfigProblem> problems}) build(
  Map<String, String> kv, {
  bool ghostty = false,
  String file = '/c',
  String? mainFile,
}) {
  final problems = <ConfigProblem>[];
  var n = 0;
  final entries = [
    for (final e in kv.entries)
      ConfigEntry(file: file, line: ++n, key: e.key, value: e.value),
  ];
  final config = buildShellxConfig(
    ghostty: ghostty ? entries : const [],
    shellx: ghostty ? const [] : entries,
    problems: problems,
    macos: true,
    home: '/Users/me',
    mainFile: mainFile,
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

  group('pr-status (A12 D16)', () {
    test('off by default; true turns it on; a Ghostty file never sets it', () {
      expect(build({}).config.prStatus, isFalse);
      expect(build({'pr-status': 'true'}).config.prStatus, isTrue);
      expect(build({'pr-status': 'false'}).config.prStatus, isFalse);
      expect(build({'pr-status': ''}).config.prStatus, isFalse);
      expect(kGhosttyKeys.contains('pr-status'), isFalse);
      expect(
        build({'pr-status': 'true'}, ghostty: true).config.prStatus,
        isFalse,
      );
    });

    test('anything else is a bad value and keeps the default', () {
      final r = build({'pr-status': 'yes'});
      expect(r.config.prStatus, isFalse);
      expect(r.problems.single.code, ConfigProblemCode.badValue);
    });
  });

  group('agent-event-command (A12 D17)', () {
    test('empty by default; the main file sets it', () {
      expect(build({}).config.agentEventCommand, '');
      final r = build({
        'agent-event-command': '~/bin/on-agent --fast',
      }, mainFile: '/c');
      expect(r.config.agentEventCommand, '~/bin/on-agent --fast');
      expect(r.problems, isEmpty);
      expect(
        build({
          'agent-event-command': '',
        }, mainFile: '/c').config.agentEventCommand,
        '',
      );
    });

    test(
      'with no main file named (a single value being checked) it counts',
      () {
        expect(
          build({'agent-event-command': 'x'}).config.agentEventCommand,
          'x',
        );
      },
    );

    test('a value from an include is ignored and reported', () {
      final r = build(
        {'agent-event-command': '/tmp/evil'},
        file: '/c/extra',
        mainFile: '/c/shellx',
      );
      expect(r.config.agentEventCommand, '');
      final p = r.problems.single;
      expect(p.code, ConfigProblemCode.unsupportedValue);
      expect(p.key, 'agent-event-command');
      expect(p.file, '/c/extra');
      // The command is the user's: the problem does not echo it.
      expect(p.value ?? '', isNot(contains('evil')));
    });

    test('an include cannot replace what the main file set', () {
      final main = ConfigEntry(
        file: '/c/shellx',
        line: 1,
        key: 'agent-event-command',
        value: 'good',
      );
      final inc = ConfigEntry(
        file: '/c/extra',
        line: 1,
        key: 'agent-event-command',
        value: 'evil',
      );
      final problems = <ConfigProblem>[];
      final config = buildShellxConfig(
        ghostty: const [],
        shellx: [main, inc],
        problems: problems,
        macos: true,
        home: '/h',
        mainFile: '/c/shellx',
      );
      expect(config.agentEventCommand, 'good');
      expect(problems, hasLength(1));
    });

    test('a Ghostty file never sets it', () {
      expect(kGhosttyKeys.contains('agent-event-command'), isFalse);
      expect(
        build(
          {'agent-event-command': 'x'},
          ghostty: true,
          mainFile: '/c',
        ).config.agentEventCommand,
        '',
      );
    });

    test('too long or with a line break is a bad value', () {
      final long = build({'agent-event-command': 'a' * 5000}, mainFile: '/c');
      expect(long.config.agentEventCommand, '');
      expect(long.problems.single.code, ConfigProblemCode.badValue);
      final nl = build({'agent-event-command': 'a\nb'}, mainFile: '/c');
      expect(nl.config.agentEventCommand, '');
    });
  });
}
