import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';
import 'package:shellx_desktop/src/terminal/resume_offers.dart';

void main() {
  test('the four commands, exactly', () {
    expect(resumeCommand(AgentKind.claude, 'abc'), 'claude --resume abc');
    expect(resumeCommand(AgentKind.codex, 'abc'), 'codex resume abc');
    expect(resumeCommand(AgentKind.gemini, 'abc'), 'gemini --resume abc');
    expect(resumeCommand(AgentKind.opencode, 'abc'), 'opencode --session abc');
  });

  test('a hostile or malformed id makes no command at all', () {
    final hostile = [
      'a; rm -rf ~',
      r'$(x)',
      '`x`',
      'a b',
      '-r',
      '--help',
      'a\nb',
      'a\rb',
      'a|b',
      'a&b',
      "a'b",
      'a"b',
      r'a\b',
      'a>b',
      'a<b',
      '~',
      '.hidden;x',
      'é',
      'a' * 129,
      '',
    ];
    for (final kind in AgentKind.values) {
      for (final id in hostile) {
        expect(resumeCommand(kind, id), isNull, reason: '$kind $id');
      }
    }
  });

  test('ids the four agents really use pass, at the 128 limit too', () {
    final valid = [
      '3f2b8c1e-9a47-4d6e-b0c5-1a2b3c4d5e6f', // Claude, Gemini: UUID
      '0199abcd-1234-7def-8abc-0123456789ab', // Codex: UUIDv7
      'ses_01abcDEFghiJKL23456789mnop', // OpenCode
      '2026-10-07T14.32.11', // date-like
      'a' * 128,
      '0',
    ];
    for (final kind in AgentKind.values) {
      for (final id in valid) {
        final c = resumeCommand(kind, id);
        expect(c, isNotNull, reason: '$kind $id');
        expect(c, endsWith(' $id'));
        // Nothing but the fixed words and the id: one line, no quoting.
        expect(c, isNot(contains('\n')));
      }
    }
  });

  test('ResumeOffer shows nothing in toString', () {
    expect(
      const ResumeOffer(AgentKind.claude, 'secret-session-id').toString(),
      '…',
    );
  });
}
