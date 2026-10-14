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

final _separators = RegExp(r'[\s_\-]');

/// V2-1 D11, ruling R6 (never auto-allow): whether [value] — a mode id, an
/// option id of a permission bar answer — turns on a mode in which the agent
/// edits files and runs commands without asking. Whichever agent's word for
/// it: Claude `bypassPermissions`, Codex `full-access` / `danger-full-access`,
/// Gemini CLI `yolo`. Only text can be one.
///
/// Such a choice always asks first (Bypass confirmation), is never
/// remembered and never re-applied from what an older version stored.
bool aiIsNoApprovalMode(Object? value) =>
    value is String &&
    _noApproval.contains(value.toLowerCase().replaceAll(_separators, ''));

/// [aiIsNoApprovalMode] for a setting of the agent: [value] is one, or a
/// switch ([value] `true`) that is named like one (`yolo`).
bool aiTurnsOnNoApproval({required String configId, required Object? value}) =>
    aiIsNoApprovalMode(value) ||
    (value == true && aiIsNoApprovalMode(configId));
