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

  test('it fails closed: an id nobody listed still matches when it says '
      'bypass, yolo, full access, skip permission, no approval or '
      '"dangerously" (a false positive only adds a question)', () {
    for (final id in [
      'clearAndBypass',
      'bypass_all_checks',
      'YOLO-mode',
      'yoloMode',
      'super yolo',
      'sandbox:danger-full-access',
      'fullAccessNoPrompt',
      'Full-Access (unsafe)',
      'skip-permission-prompts',
      'SkipPermissions',
      'no_approval_needed',
      'No Approval',
      'dangerously-bypass-approvals-and-sandbox',
      'dangerouslyAllowEverything',
    ]) {
      expect(aiIsNoApprovalMode(id), isTrue, reason: id);
    }
    // A switch named like one is one when turned on, too.
    expect(
      aiTurnsOnNoApproval(configId: 'clearAndBypass', value: true),
      isTrue,
    );
    expect(aiTurnsOnNoApproval(configId: 'YOLO-mode', value: true), isTrue);
    expect(aiTurnsOnNoApproval(configId: 'YOLO-mode', value: false), isFalse);
    expect(
      aiTurnsOnNoApproval(configId: 'mode', value: 'dangerously-allow'),
      isTrue,
    );
  });

  test('the modes people use every day do not match', () {
    for (final id in [
      'default',
      'acceptEdits',
      'plan',
      'auto',
      'auto_edit',
      'auto-edit',
      'read-only',
      'ask',
      'code',
      'architect',
      'build',
      'on-request',
      'untrusted',
      'workspace-write',
    ]) {
      expect(aiIsNoApprovalMode(id), isFalse, reason: id);
    }
    expect(aiTurnsOnNoApproval(configId: 'thinking', value: true), isFalse);
    expect(aiTurnsOnNoApproval(configId: 'auto', value: true), isFalse);
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
