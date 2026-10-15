import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:test/test.dart';

PermissionOption _option(String id, PermissionKind kind) =>
    PermissionOption(optionId: id, name: id, kind: kind);

/// V2-1 D11, R6, V2-2b B7: the rule for a mode that lets an agent act without
/// asking, where the phone hub reads it (the desktop keeps its own, fuller
/// tests of it through its re-export).
void main() {
  test('every agent\'s word for it, and the words nobody listed that say '
      'it, with any mark between them', () {
    for (final id in [
      'bypassPermissions',
      'full-access',
      'danger-full-access',
      'yolo',
      'clearAndBypass',
      'YOLO-mode',
      'skip:permissions',
      'allow-all-tools',
      'auto approve',
      'dangerously-skip-permissions',
      'full access',
    ]) {
      expect(aiIsNoApprovalMode(id), isTrue, reason: id);
    }
  });

  test('the everyday modes and values do not match; only text can be one', () {
    for (final id in [
      'default',
      'acceptEdits',
      'plan',
      'auto',
      'auto_edit',
      'read-only',
      'workspace-write',
      'opus',
      '',
    ]) {
      expect(aiIsNoApprovalMode(id), isFalse, reason: id);
    }
    expect(aiIsNoApprovalMode(null), isFalse);
    expect(aiIsNoApprovalMode(true), isFalse);
  });

  test('a switch named like one turns it on only when it is on', () {
    expect(aiTurnsOnNoApproval(configId: 'yolo', value: true), isTrue);
    expect(aiTurnsOnNoApproval(configId: 'yolo', value: false), isFalse);
    expect(
      aiTurnsOnNoApproval(configId: 'mode', value: 'bypassPermissions'),
      isTrue,
    );
    expect(aiTurnsOnNoApproval(configId: 'model', value: 'opus'), isFalse);
  });

  test('a permission answer turns it on when it is no reject and names such '
      'a mode', () {
    expect(
      aiOptionEnablesNoApproval(
        _option('bypassPermissions', PermissionKind.allowOnce),
      ),
      isTrue,
    );
    expect(
      aiOptionEnablesNoApproval(
        _option('bypassPermissions', PermissionKind.rejectOnce),
      ),
      isFalse,
    );
    expect(
      aiOptionEnablesNoApproval(_option('allow', PermissionKind.allowOnce)),
      isFalse,
    );
  });
}
