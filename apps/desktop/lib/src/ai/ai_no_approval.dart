/// V2-1 D11, ruling R6: whether a mode, a setting or a permission answer lets
/// an agent act without asking. V2-2b B7 moved the rule to
/// `package:shellx_ai/remote.dart`, where the phone hub reads it too (a push
/// never offers such an answer as a button); the desktop keeps importing it
/// from here.
library;

export 'package:shellx_ai/remote.dart'
    show aiIsNoApprovalMode, aiOptionEnablesNoApproval, aiTurnsOnNoApproval;
