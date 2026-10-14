import 'package:shellx_acp/shellx_acp.dart' show PermissionOption;

/// The ids (without case, `-`, `_` or spaces) that let an agent act without
/// asking: Claude's `bypassPermissions`, Codex's `full-access` and
/// `danger-full-access`, Gemini CLI's `yolo`, and the same said another way.
const _noApproval = {
  'bypasspermissions',
  'bypass',
  'dangerouslyskippermissions',
  'dangerouslybypassapprovalsandsandbox',
  'skippermissions',
  'fullaccess',
  'dangerfullaccess',
  'yolo',
  'allowall',
  'trustall',
  'noapproval',
};

/// What an id says when it is one nobody listed (`clearAndBypass`,
/// `YOLO-mode`, `sandbox:danger-full-access`…), in the same spelling as
/// [_noApproval]: the ids of agents change between versions, and an id that
/// says one of these is taken for a mode that acts without asking. A false
/// positive only adds a confirmation; a miss would let an agent act without
/// one.
const _noApprovalWords = [
  'bypass',
  'yolo',
  'fullaccess',
  'skippermission',
  'noapproval',
  'dangerously',
];

final _separators = RegExp(r'[\s_\-]');

/// V2-1 D11, ruling R6 (never auto-allow): whether [value] — a mode id, an
/// option id of a permission bar answer — turns on a mode in which the agent
/// edits files and runs commands without asking. Whichever agent's word for
/// it: Claude `bypassPermissions`, Codex `full-access` / `danger-full-access`,
/// Gemini CLI `yolo`. Only text can be one.
///
/// It fails closed: besides the ids above, an id that merely says
/// `bypass`, `yolo`, `fullaccess`, `skippermission`, `noapproval` or
/// `dangerously` (without case, `-`, `_` or spaces) counts too.
///
/// Such a choice always asks first (Bypass confirmation), is never
/// remembered and never re-applied from what an older version stored.
bool aiIsNoApprovalMode(Object? value) {
  if (value is! String) return false;
  final id = value.toLowerCase().replaceAll(_separators, '');
  return _noApproval.contains(id) || _noApprovalWords.any(id.contains);
}

/// [aiIsNoApprovalMode] for a setting of the agent: [value] is one, or a
/// switch ([value] `true`) that is named like one (`yolo`).
bool aiTurnsOnNoApproval({required String configId, required Object? value}) =>
    aiIsNoApprovalMode(value) ||
    (value == true && aiIsNoApprovalMode(configId));

/// V2-1 D10, R6: whether picking permission [option] turns on a mode acting
/// without asking: an answer that is not a reject and whose id is one
/// ([aiIsNoApprovalMode]). Claude's ExitPlanMode offers "Yes, and bypass
/// permissions" as the option `bypassPermissions`. The permission bar asks
/// the Bypass question first; a phone never gives such an answer (V2-2 D13).
bool aiOptionEnablesNoApproval(PermissionOption option) =>
    !option.kind.isReject && aiIsNoApprovalMode(option.optionId);
