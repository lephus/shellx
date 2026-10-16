import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_desktop/src/ai/ai_no_approval.dart';

PermissionOption _option(String id, PermissionKind kind) =>
    PermissionOption(optionId: id, name: id, kind: kind);

/// V2-1 D10, R6: the one rule for a permission answer that turns on a mode
/// acting without asking — the desktop's bar asks first, a phone never gives
/// it (V2-2 D13).
void main() {
  test('an answer that is not a reject and names such a mode', () {
    for (final kind in [
      PermissionKind.allowOnce,
      PermissionKind.allowAlways,
      PermissionKind.other,
    ]) {
      for (final id in ['bypassPermissions', 'full-access', 'yolo']) {
        expect(
          aiOptionEnablesNoApproval(_option(id, kind)),
          isTrue,
          reason: '$id, $kind',
        );
      }
    }
  });

  test('a reject never does, nor an answer that names no such mode', () {
    for (final kind in [
      PermissionKind.rejectOnce,
      PermissionKind.rejectAlways,
    ]) {
      expect(
        aiOptionEnablesNoApproval(_option('bypassPermissions', kind)),
        isFalse,
      );
    }
    for (final id in ['default', 'acceptEdits', 'plan', 'allow-once']) {
      expect(
        aiOptionEnablesNoApproval(_option(id, PermissionKind.allowAlways)),
        isFalse,
        reason: id,
      );
    }
  });
}
