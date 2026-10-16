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

  test('V2-2b F19: an option named like one turns it on with any value but '
      'an off value — a select too, not only a switch', () {
    for (final id in ['yolo', 'clearAndBypass', 'allow-all-tools']) {
      for (final value in ['on', 'On', 'enabled', 'always', 'full']) {
        expect(
          aiTurnsOnNoApproval(configId: id, value: value),
          isTrue,
          reason: '$id=$value',
        );
      }
      // The off values, in any case and with any mark between the letters,
      // as the predicate reads an id.
      for (final value in [
        'off',
        'Off',
        'FALSE',
        'no',
        'disabled',
        ' Disabled ',
        '0',
        'none',
        'n-o-n-e',
      ]) {
        expect(
          aiTurnsOnNoApproval(configId: id, value: value),
          isFalse,
          reason: '$id=$value',
        );
      }
      // A switch as before: on turns it on, off does not.
      expect(
        aiTurnsOnNoApproval(configId: id, value: true),
        isTrue,
        reason: id,
      );
      expect(
        aiTurnsOnNoApproval(configId: id, value: false),
        isFalse,
        reason: id,
      );
      // Any other value is not an off value: it fails closed.
      expect(
        aiTurnsOnNoApproval(configId: id, value: null),
        isTrue,
        reason: id,
      );
    }
    // An option not named like one keeps its answers.
    expect(aiTurnsOnNoApproval(configId: 'model', value: 'opus'), isFalse);
    expect(aiTurnsOnNoApproval(configId: 'effort', value: 'on'), isFalse);
    expect(aiTurnsOnNoApproval(configId: 'thinking', value: true), isFalse);
    expect(aiTurnsOnNoApproval(configId: 'mode', value: 'yolo'), isTrue);
    expect(aiTurnsOnNoApproval(configId: 'mode', value: 'off'), isFalse);
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
