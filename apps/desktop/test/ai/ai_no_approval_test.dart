import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/ai/ai_no_approval.dart';

/// V2-1 D11, ruling R6: ShellX never lets an agent act without asking by
/// itself, whichever agent's word for it.
void main() {
  test('the modes that let an agent act without asking, in every agent\'s '
      'words', () {
    for (final id in [
      'bypassPermissions', // Claude, and the ExitPlanMode answer
      'full-access', // Codex
      'danger-full-access', // Codex, the sandbox
      'yolo', // Gemini CLI
      'YOLO',
      'Full Access',
      'full_access',
      'bypass-permissions',
      'dangerously-skip-permissions',
    ]) {
      expect(aiIsNoApprovalMode(id), isTrue, reason: id);
    }
  });

  test('every other value is an ordinary choice', () {
    for (final id in [
      'default',
      'acceptEdits',
      'plan',
      'auto',
      'read-only',
      'workspace-write',
      'opus',
      'sonnet',
      'high',
      '',
    ]) {
      expect(aiIsNoApprovalMode(id), isFalse, reason: id);
    }
    expect(aiIsNoApprovalMode(null), isFalse);
    expect(aiIsNoApprovalMode(true), isFalse);
    expect(aiIsNoApprovalMode(3), isFalse);
  });

  test('a switch named like a no-approval mode is one when turned on', () {
    expect(aiTurnsOnNoApproval(configId: 'yolo', value: true), isTrue);
    expect(aiTurnsOnNoApproval(configId: 'yolo', value: false), isFalse);
    expect(aiTurnsOnNoApproval(configId: 'mode', value: 'yolo'), isTrue);
    expect(aiTurnsOnNoApproval(configId: 'model', value: 'opus'), isFalse);
    expect(aiTurnsOnNoApproval(configId: 'thinking', value: true), isFalse);
  });
}
