import 'package:shellx_acp/shellx_acp.dart' show PermissionOption;

// V2-1 D11, ruling R6, V2-2b B7: the one rule for a mode that lets an agent
// act without asking. It lives here, in the pure-Dart library the phone hub
// reads too (a push never offers such an answer as a button, B7; a phone is
// never offered such a mode, B11); the desktop re-exports it from
// `apps/desktop/lib/src/ai/ai_no_approval.dart`.

/// The ids (in the spelling of [_normal]: letters and digits only, lower case)
/// that let an agent act without asking: Claude's `bypassPermissions`, Codex's
/// `full-access` and `danger-full-access`, Gemini CLI's `yolo`, and the same
/// said another way.
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
/// `YOLO-mode`, `sandbox:danger-full-access`, `allow-all-tools`…), in the same
/// spelling as [_noApproval]: the ids of agents change between versions, and an
/// id that says one of these is taken for a mode that acts without asking. A
/// false positive only adds a confirmation; a miss would let an agent act
/// without one.
const _noApprovalWords = [
  'bypass',
  'yolo',
  'fullaccess',
  'skippermission',
  'noapproval',
  'dangerously',
  'allowall',
  'trustall',
  'autoapprove',
  'approveall',
];

/// Everything that is not a letter or a digit: whatever an agent puts between
/// the words of an id (`-`, `_`, a space, `.`, `:`, `/`…) is nothing.
final _notAlphanumeric = RegExp(r'[^a-z0-9]');

/// [value] as [_noApproval] and [_noApprovalWords] spell their words: lower
/// case, letters and digits only.
String _normal(String value) =>
    value.toLowerCase().replaceAll(_notAlphanumeric, '');

/// V2-1 D11, ruling R6 (never auto-allow): whether [value] — a mode id, an
/// option id of a permission bar answer — turns on a mode in which the agent
/// edits files and runs commands without asking. Whichever agent's word for
/// it: Claude `bypassPermissions`, Codex `full-access` / `danger-full-access`,
/// Gemini CLI `yolo`. Only text can be one.
///
/// It fails closed: besides the ids above, an id that merely says `bypass`,
/// `yolo`, `full access`, `skip permission`, `no approval`, `dangerously`,
/// `allow all`, `trust all`, `auto approve` or `approve all` counts too — with
/// any case and any marks between the words (`full.access`, `skip:permissions`,
/// `allow-all-tools`, `approveAll`).
///
/// Such a choice always asks first (Bypass confirmation), is never
/// remembered and never re-applied from what an older version stored.
bool aiIsNoApprovalMode(Object? value) {
  if (value is! String) return false;
  final id = _normal(value);
  return _noApproval.contains(id) || _noApprovalWords.any(id.contains);
}

/// The values that leave an option off, in the spelling of [_normal].
const _offValues = {'off', 'false', 'no', 'disabled', '0', 'none'};

/// V2-2b F19: whether [value] leaves an option off: `false`, or text that
/// says `off`, `false`, `no`, `disabled`, `0` or `none` — with any case and
/// any marks between the letters, as [aiIsNoApprovalMode] reads an id
/// (`Off`, `FALSE`, ` Disabled `). Anything else (`on`, `true`, `always`,
/// nothing) is not.
bool _isOff(Object? value) =>
    value == false || (value is String && _offValues.contains(_normal(value)));

/// [aiIsNoApprovalMode] for a setting of the agent: [value] is one, or the
/// option is named like one ([configId]) and [value] is not an off value
/// (`false`; `off`, `false`, `no`, `disabled`, `0`, `none` in any spelling).
/// So a switch named `yolo` turns it on when set to `true`, and a select
/// named `yolo` (V2-2b F19) when set to `on`, `always` or any choice but an
/// off one. It fails closed: a value that is not an off value counts as on.
bool aiTurnsOnNoApproval({required String configId, required Object? value}) =>
    aiIsNoApprovalMode(value) ||
    (aiIsNoApprovalMode(configId) && !_isOff(value));

/// V2-1 D10, R6: whether picking permission [option] turns on a mode acting
/// without asking: an answer that is not a reject and whose id is one
/// ([aiIsNoApprovalMode]). Claude's ExitPlanMode offers "Yes, and bypass
/// permissions" as the option `bypassPermissions`. The permission bar asks
/// the Bypass question first; a phone never gives such an answer (V2-2 D13).
bool aiOptionEnablesNoApproval(PermissionOption option) =>
    !option.kind.isReject && aiIsNoApprovalMode(option.optionId);
