// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a en locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'en';

  static String m0(agent) => "${agent} asks you";

  static String m1(n) =>
      "${Intl.plural(n, one: '1 more file — see it on the computer.', other: '${n} more files — see them on the computer.')}";

  static String m2(agent) => "Message ${agent}…";

  static String m3(percent) => "Context ${percent}%";

  static String m4(count) => "${count} lines in all; the middle is on the computer";

  static String m5(turn) => "Compared with the start of turn ${turn}";

  static String m6(n) => "${Intl.plural(n, one: '1 image', other: '${n} images')}";

  static String m7(part, parts) => "Loading ${part}/${parts}";

  static String m8(count) => "${Intl.plural(count, one: '+1 more file', other: '+${count} more files')}";

  static String m9(agent) => "${agent} doesn\'t take images.";

  static String m10(agent, code) => "${agent} stopped unexpectedly (exit ${code}).";

  static String m11(agent) => "${agent} sent output ShellX cannot read and was stopped.";

  static String m12(agent) => "${agent} needs you to sign in, on the computer.";

  static String m13(agent) => "${agent} was not found on the computer.";

  static String m14(agent, version) => "${agent} needs Node.js ${version} or newer on the computer.";

  static String m15(agent) => "${agent} is not installed on the computer.";

  static String m16(agent) => "${agent} could not start.";

  static String m17(reason) => "Undo is off for this project (${reason}).";

  static String m18(reason) => "Undo is off for this turn (${reason}).";

  static String m19(count) => "${count} more waiting";

  static String m20(agent) => "${agent} asks:";

  static String m21(done, total) => "Plan · ${done}/${total}";

  static String m22(title) => "Allowed: ${title}";

  static String m23(title) => "Denied: ${title}";

  static String m24(reason) => "The computer did not take it (${reason}).";

  static String m25(n, turn) =>
      "${Intl.plural(n, one: 'Revert 1 file to before turn ${turn}?', other: 'Revert ${n} files to before turn ${turn}?')}";

  static String m26(n) =>
      "${Intl.plural(n, one: 'Revert 1 file to before the session?', other: 'Revert ${n} files to before the session?')}";

  static String m27(n) =>
      "${Intl.plural(n, one: '1 file changed after this turn.', other: '${n} files changed after this turn.')}";

  static String m28(n) => "${Intl.plural(n, one: 'Reverted 1 file.', other: 'Reverted ${n} files.')}";

  static String m29(agent, state) => "${agent} · ${state}";

  static String m30(max) => "Too long to send from the phone (${max} KB at most).";

  static String m31(target) => "Create ${target}";

  static String m32(target) => "Delete ${target}";

  static String m33(target) => "Edit ${target}";

  static String m34(target) => "Run ${target}";

  static String m35(target) => "Fetch ${target}";

  static String m36(target) => "Rename ${target}";

  static String m37(target) => "Read ${target}";

  static String m38(time) => "running · ${time}";

  static String m39(target) => "Search ${target}";

  static String m40(n) => "Turn ${n} failed";

  static String m41(count) => "${Intl.plural(count, one: '1 file changed', other: '${count} files changed')}";

  static String m42(n) => "Turn ${n} interrupted";

  static String m43(n, time) => "Stopped turn ${n} · ${time}";

  static String m44(n, time) => "Turn ${n} · ${time}";

  static String m45(option) => "You chose: ${option}";

  static String m46(email) => "Deletes the account ${email} with all its devices and pairings.";

  static String m47(site) => "Install ShellX on your computer (macOS or Windows) from ${site}.";

  static String m48(menu) => "Click the ShellX icon, choose ${menu}, then scan the code.";

  static String m49(reason) => "Couldn\'t start the shell: ${reason}";

  static String m50(code) => "Something went wrong (${code}).";

  static String m51(day, month, time) => "${month}/${day}, ${time}";

  static String m52(count) => "${Intl.plural(count, one: '1 minute ago', other: '${count} minutes ago')}";

  static String m53(time) => "today, ${time}";

  static String m54(time) => "yesterday, ${time}";

  static String m55(method) => "Unlock with ${method}";

  static String m56(n, w) =>
      "✦ ${Intl.plural(n, one: '1 AI session', other: '${n} AI sessions')} · ${Intl.plural(w, one: '1 needs you', other: '${w} need you')}";

  static String m57(n) => "✦ ${Intl.plural(n, one: '1 AI session', other: '${n} AI sessions')}";

  static String m58(when) => "Last online: ${when}";

  static String m59(count) => "${Intl.plural(count, one: '1 tab', other: '${count} tabs')}";

  static String m60(tabs, unseen) =>
      "${Intl.plural(tabs, one: '1 tab', other: '${tabs} tabs')} · ${unseen} with new output";

  static String m61(name) => "${name} now trusts this phone. From now on, just tap the computer to open a terminal.";

  static String m62(count) =>
      "${Intl.plural(count, one: '1 more character needed.', other: '${count} more characters needed.')}";

  static String m63(count) =>
      "${Intl.plural(count, one: '1 character too many.', other: '${count} characters too many.')}";

  static String m64(name) => "${name} · done";

  static String m65(name) => "${name} · waiting";

  static String m66(name) => "${name} · needs your answer";

  static String m67(name) => "${name} · running";

  static String m68(when) => "opened ${when}";

  static String m69(count) =>
      "${Intl.plural(count, one: 'This computer has 1 session', other: 'This computer has ${count} sessions')}";

  static String m70(number) => "Option ${number}";

  static String m71(menu) =>
      "macOS: click the ShellX icon in the menu bar. Windows: click the icon in the system tray. Choose ${menu}";

  static String m72(code) =>
      "The last command exited with code ${code}. The output above can still be read and copied.";

  static String m73(method) => "Lock with ${method}";

  static String m74(name) => "Unpair ${name}? You\'ll need to scan a QR code again to use this computer.";

  static String m75(version, build) => "ShellX ${version} (${build})";

  static String m76(terms, privacy) => "By creating an account you agree to the ${terms} and the ${privacy}.";

  static String m77(length) => "Password must be at least ${length} characters.";

  static String m78(length) => "Must be at most ${length} characters.";

  static String m79(length) => "Must be at least ${length} characters.";

  static String m80(lines) => "Showing the last ${lines} lines";

  static String m81(target) => "To: ${target}";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "actionCancel": MessageLookupByLibrary.simpleMessage("Cancel"),
    "actionClose": MessageLookupByLibrary.simpleMessage("Close"),
    "actionLater": MessageLookupByLibrary.simpleMessage("Later"),
    "actionScanCode": MessageLookupByLibrary.simpleMessage("Scan code"),
    "agentDotNeedsInput": MessageLookupByLibrary.simpleMessage(
      "An agent needs your answer",
    ),
    "agentDotRunning": MessageLookupByLibrary.simpleMessage(
      "An agent is running",
    ),
    "aiAgentNotReady": MessageLookupByLibrary.simpleMessage(
      "set up on the computer",
    ),
    "aiAnsweredElsewhere": MessageLookupByLibrary.simpleMessage(
      "Already answered on another device.",
    ),
    "aiAskAnswered": MessageLookupByLibrary.simpleMessage("Answered"),
    "aiAskCancelled": MessageLookupByLibrary.simpleMessage("Cancelled"),
    "aiAskDecline": MessageLookupByLibrary.simpleMessage("Decline"),
    "aiAskDeclined": MessageLookupByLibrary.simpleMessage("Declined"),
    "aiAskOnComputer": MessageLookupByLibrary.simpleMessage(
      "Answer this question on the computer.",
    ),
    "aiAskSubmit": MessageLookupByLibrary.simpleMessage("Send answer"),
    "aiAskTitle": m0,
    "aiAskUnsupported": MessageLookupByLibrary.simpleMessage(
      "This question uses an answer type ShellX does not support yet.",
    ),
    "aiAskWaiting": MessageLookupByLibrary.simpleMessage(
      "Waiting for your answer below",
    ),
    "aiAttach": MessageLookupByLibrary.simpleMessage("Add photos"),
    "aiAttachPhoto": MessageLookupByLibrary.simpleMessage("Photo library"),
    "aiBinaryFile": MessageLookupByLibrary.simpleMessage("binary"),
    "aiBusy": MessageLookupByLibrary.simpleMessage(
      "Too many requests at once. Wait a moment, then try again.",
    ),
    "aiChangedAfter": MessageLookupByLibrary.simpleMessage(
      "changed after this turn",
    ),
    "aiChanges": MessageLookupByLibrary.simpleMessage("Changes"),
    "aiChangesEmpty": MessageLookupByLibrary.simpleMessage("Nothing changed."),
    "aiChangesMore": m1,
    "aiChooseFolder": MessageLookupByLibrary.simpleMessage(
      "Choose a folder for this session",
    ),
    "aiChromeTooltip": MessageLookupByLibrary.simpleMessage("AI sessions"),
    "aiClosedDesktop": MessageLookupByLibrary.simpleMessage(
      "ShellX was closed on the computer. Open ShellX on the computer, then open the session again.",
    ),
    "aiClosedGone": MessageLookupByLibrary.simpleMessage(
      "This AI session was closed on the computer.",
    ),
    "aiClosedUnreadable": MessageLookupByLibrary.simpleMessage(
      "The phone cannot read this AI session. See it on the computer.",
    ),
    "aiComposerHint": m2,
    "aiConfigEffort": MessageLookupByLibrary.simpleMessage("Thinking"),
    "aiConfigMode": MessageLookupByLibrary.simpleMessage("Mode"),
    "aiConfigModel": MessageLookupByLibrary.simpleMessage("Model"),
    "aiConfigMore": MessageLookupByLibrary.simpleMessage(
      "More choices on the computer.",
    ),
    "aiConfigOnComputer": MessageLookupByLibrary.simpleMessage(
      "Choose this on the computer.",
    ),
    "aiConfigTitle": MessageLookupByLibrary.simpleMessage("Mode and model"),
    "aiContext": m3,
    "aiCreated": MessageLookupByLibrary.simpleMessage("new file"),
    "aiCutLines": m4,
    "aiCutText": MessageLookupByLibrary.simpleMessage(
      "The rest of this message is on the computer.",
    ),
    "aiDiffBinary": MessageLookupByLibrary.simpleMessage(
      "Binary file — see it on the computer.",
    ),
    "aiDiffMissing": MessageLookupByLibrary.simpleMessage(
      "This file is not there, before or now.",
    ),
    "aiDiffVsSession": MessageLookupByLibrary.simpleMessage(
      "Compared with the start of the session",
    ),
    "aiDiffVsTurn": m5,
    "aiEmpty": MessageLookupByLibrary.simpleMessage(
      "No messages yet. Write the first one below.",
    ),
    "aiForceStop": MessageLookupByLibrary.simpleMessage("Force stop"),
    "aiFromComputerOnly": MessageLookupByLibrary.simpleMessage(
      "Too large for the phone. Open it on the computer.",
    ),
    "aiFromPhone": MessageLookupByLibrary.simpleMessage("from phone"),
    "aiGroup": MessageLookupByLibrary.simpleMessage("AI sessions"),
    "aiHistory": MessageLookupByLibrary.simpleMessage("Session history"),
    "aiHistoryEmpty": MessageLookupByLibrary.simpleMessage(
      "No earlier sessions in this folder.",
    ),
    "aiHistoryMore": MessageLookupByLibrary.simpleMessage("Load more"),
    "aiHistoryNotReady": MessageLookupByLibrary.simpleMessage(
      "The history shows once the agent runs.",
    ),
    "aiImageFailed": MessageLookupByLibrary.simpleMessage(
      "The image wasn\'t sent. Retry",
    ),
    "aiImageTooBig": MessageLookupByLibrary.simpleMessage(
      "This image is over 10 MB.",
    ),
    "aiImageType": MessageLookupByLibrary.simpleMessage(
      "Only JPEG, PNG, GIF or WebP images can be sent.",
    ),
    "aiImagesCount": m6,
    "aiImagesTooMuch": MessageLookupByLibrary.simpleMessage(
      "One message can carry at most 20 MB of images.",
    ),
    "aiItemChanging": MessageLookupByLibrary.simpleMessage(
      "It is still changing on the computer. Try again in a moment.",
    ),
    "aiItemOnComputer": MessageLookupByLibrary.simpleMessage(
      "This kind of item is not supported on the phone yet. See it on the computer.",
    ),
    "aiJumpLatest": MessageLookupByLibrary.simpleMessage("Latest"),
    "aiLoadEarlier": MessageLookupByLibrary.simpleMessage("Load earlier"),
    "aiLoadingParts": m7,
    "aiMicTooltip": MessageLookupByLibrary.simpleMessage("Speak a message"),
    "aiModeAcceptEdits": MessageLookupByLibrary.simpleMessage("Edit files"),
    "aiModeAuto": MessageLookupByLibrary.simpleMessage("Auto"),
    "aiModeBypass": MessageLookupByLibrary.simpleMessage("Bypass permissions"),
    "aiModeDefault": MessageLookupByLibrary.simpleMessage("Ask first"),
    "aiModePlan": MessageLookupByLibrary.simpleMessage("Plan"),
    "aiMoreDiffs": m8,
    "aiNewAgent": MessageLookupByLibrary.simpleMessage("Agent"),
    "aiNewFolder": MessageLookupByLibrary.simpleMessage("Folder"),
    "aiNewNoAgents": MessageLookupByLibrary.simpleMessage(
      "No agent is ready on the computer. Set one up in Settings › Agents.",
    ),
    "aiNewNoFolders": MessageLookupByLibrary.simpleMessage(
      "Set a folder for a project on the computer first (Settings › Projects).",
    ),
    "aiNewSession": MessageLookupByLibrary.simpleMessage("New AI session"),
    "aiNewStart": MessageLookupByLibrary.simpleMessage("Start"),
    "aiNoImages": m9,
    "aiNoOutput": MessageLookupByLibrary.simpleMessage("No output"),
    "aiNoticeCannotResume": MessageLookupByLibrary.simpleMessage(
      "This agent cannot reopen the old session; a new one was started.",
    ),
    "aiNoticeExited": m10,
    "aiNoticeFolderMissing": MessageLookupByLibrary.simpleMessage(
      "The session\'s folder is gone. Choose one on the computer.",
    ),
    "aiNoticeInvalid": m11,
    "aiNoticeLogin": m12,
    "aiNoticeMissing": m13,
    "aiNoticeNode": m14,
    "aiNoticeNotInstalled": m15,
    "aiNoticeOther": MessageLookupByLibrary.simpleMessage(
      "A notice from the computer.",
    ),
    "aiNoticeStartFailed": m16,
    "aiNoticeUndoOff": MessageLookupByLibrary.simpleMessage(
      "Undo is off for this project.",
    ),
    "aiNoticeUndoOffReason": m17,
    "aiNoticeUndoOffTurn": m18,
    "aiOpenList": MessageLookupByLibrary.simpleMessage("Open the session list"),
    "aiOpenOutcomeUnknown": MessageLookupByLibrary.simpleMessage(
      "The new session may not have been created. Check the list before trying again.",
    ),
    "aiOutcomeUnknown": MessageLookupByLibrary.simpleMessage(
      "This may not have been sent — the connection dropped. Check the session before trying again.",
    ),
    "aiPermAllowAlways": MessageLookupByLibrary.simpleMessage("Always allow"),
    "aiPermAllowOnce": MessageLookupByLibrary.simpleMessage("Allow"),
    "aiPermDetails": MessageLookupByLibrary.simpleMessage("Details"),
    "aiPermMore": m19,
    "aiPermOnComputer": MessageLookupByLibrary.simpleMessage(
      "Answer this request on the computer.",
    ),
    "aiPermOption": MessageLookupByLibrary.simpleMessage("Option"),
    "aiPermRejectAlways": MessageLookupByLibrary.simpleMessage("Always reject"),
    "aiPermRejectOnce": MessageLookupByLibrary.simpleMessage("Reject"),
    "aiPermTitle": m20,
    "aiPickFailed": MessageLookupByLibrary.simpleMessage(
      "Couldn\'t open the photos. Check ShellX\'s access in Settings.",
    ),
    "aiPlan": m21,
    "aiPushAllowed": m22,
    "aiPushAnsweredElsewhere": MessageLookupByLibrary.simpleMessage(
      "This request was already answered elsewhere.",
    ),
    "aiPushDenied": m23,
    "aiPushMaybeNotSent": MessageLookupByLibrary.simpleMessage(
      "It may not have been sent. Check the session.",
    ),
    "aiQueue": MessageLookupByLibrary.simpleMessage("Queue"),
    "aiQueueFull": MessageLookupByLibrary.simpleMessage(
      "5 messages are already waiting.",
    ),
    "aiQueued": MessageLookupByLibrary.simpleMessage("Queued"),
    "aiReattached": MessageLookupByLibrary.simpleMessage(
      "Reconnected after ShellX restarted.",
    ),
    "aiReconnecting": MessageLookupByLibrary.simpleMessage(
      "Reconnecting… what you see may be behind.",
    ),
    "aiRefused": MessageLookupByLibrary.simpleMessage(
      "The computer did not accept this request.",
    ),
    "aiRemoveImage": MessageLookupByLibrary.simpleMessage("Remove image"),
    "aiRemoveQueued": MessageLookupByLibrary.simpleMessage("Remove from queue"),
    "aiRequestFailed": m24,
    "aiRevertAll": MessageLookupByLibrary.simpleMessage("Revert all"),
    "aiRevertBusy": MessageLookupByLibrary.simpleMessage(
      "Wait for the turn to finish.",
    ),
    "aiRevertConfirm": m25,
    "aiRevertConfirmSession": m26,
    "aiRevertOnlyClean": MessageLookupByLibrary.simpleMessage(
      "Only unchanged files",
    ),
    "aiRevertSession": MessageLookupByLibrary.simpleMessage(
      "Revert the whole session",
    ),
    "aiRevertTouched": m27,
    "aiRevertTurn": MessageLookupByLibrary.simpleMessage("Revert this turn"),
    "aiReverted": m28,
    "aiRowSubtitle": m29,
    "aiSend": MessageLookupByLibrary.simpleMessage("Send"),
    "aiStateAgentOff": MessageLookupByLibrary.simpleMessage(
      "Agent off on the computer",
    ),
    "aiStateClosed": MessageLookupByLibrary.simpleMessage("Closed"),
    "aiStateFailed": MessageLookupByLibrary.simpleMessage("Error"),
    "aiStateIdle": MessageLookupByLibrary.simpleMessage("Waiting"),
    "aiStateNeedsAuth": MessageLookupByLibrary.simpleMessage(
      "Sign in on the computer",
    ),
    "aiStateNeedsInput": MessageLookupByLibrary.simpleMessage(
      "Needs your answer",
    ),
    "aiStateNoFolder": MessageLookupByLibrary.simpleMessage(
      "Choose a folder on the computer",
    ),
    "aiStateRunning": MessageLookupByLibrary.simpleMessage("Running"),
    "aiStateStarting": MessageLookupByLibrary.simpleMessage("Starting"),
    "aiStateStopped": MessageLookupByLibrary.simpleMessage("Not started"),
    "aiStop": MessageLookupByLibrary.simpleMessage("Stop"),
    "aiStopping": MessageLookupByLibrary.simpleMessage("Stopping…"),
    "aiTakePhoto": MessageLookupByLibrary.simpleMessage("Camera"),
    "aiThisTurn": MessageLookupByLibrary.simpleMessage("This turn"),
    "aiThought": MessageLookupByLibrary.simpleMessage("Thinking"),
    "aiTooLong": m30,
    "aiToolAwaiting": MessageLookupByLibrary.simpleMessage("waiting for you"),
    "aiToolCreate": m31,
    "aiToolDelete": m32,
    "aiToolDone": MessageLookupByLibrary.simpleMessage("done"),
    "aiToolEdit": m33,
    "aiToolExecute": m34,
    "aiToolFailed": MessageLookupByLibrary.simpleMessage("error"),
    "aiToolFetch": m35,
    "aiToolMove": m36,
    "aiToolPending": MessageLookupByLibrary.simpleMessage("waiting"),
    "aiToolRead": m37,
    "aiToolRejected": MessageLookupByLibrary.simpleMessage("rejected"),
    "aiToolRunningFor": m38,
    "aiToolSearch": m39,
    "aiToolStopped": MessageLookupByLibrary.simpleMessage("stopped"),
    "aiToolSwitchMode": MessageLookupByLibrary.simpleMessage("Switch mode"),
    "aiTurnFailed": m40,
    "aiTurnFiles": m41,
    "aiTurnInterrupted": m42,
    "aiTurnStopped": m43,
    "aiTurnSummary": m44,
    "aiUnavailable": MessageLookupByLibrary.simpleMessage(
      "Open ShellX on the computer to use AI sessions.",
    ),
    "aiUndoBroadFolder": MessageLookupByLibrary.simpleMessage(
      "this folder is your home folder or a disk root",
    ),
    "aiUndoFailed": MessageLookupByLibrary.simpleMessage("a snapshot failed"),
    "aiUndoGitTooOld": MessageLookupByLibrary.simpleMessage(
      "git is older than 2.26",
    ),
    "aiUndoNoCommandLineTools": MessageLookupByLibrary.simpleMessage(
      "the Command Line Tools are not installed",
    ),
    "aiUndoNoGit": MessageLookupByLibrary.simpleMessage("git was not found"),
    "aiUndoTooManyFiles": MessageLookupByLibrary.simpleMessage(
      "more than 200,000 files",
    ),
    "aiUndoTooSlow": MessageLookupByLibrary.simpleMessage(
      "the first snapshot took over 30 s",
    ),
    "aiUntitled": MessageLookupByLibrary.simpleMessage("New AI session"),
    "aiUpdateDesktop": MessageLookupByLibrary.simpleMessage(
      "Update ShellX on the computer to use AI sessions from your phone.",
    ),
    "aiUploading": MessageLookupByLibrary.simpleMessage("Sending images…"),
    "aiUseFolder": MessageLookupByLibrary.simpleMessage("Use this folder"),
    "aiViewAll": MessageLookupByLibrary.simpleMessage("View all"),
    "aiWholeSession": MessageLookupByLibrary.simpleMessage("Whole session"),
    "aiYouChose": m45,
    "appTitle": MessageLookupByLibrary.simpleMessage("ShellX"),
    "arrowPadDown": MessageLookupByLibrary.simpleMessage("Down"),
    "arrowPadLabel": MessageLookupByLibrary.simpleMessage(
      "Arrow pad. Drag to move the cursor.",
    ),
    "arrowPadLeft": MessageLookupByLibrary.simpleMessage("Left"),
    "arrowPadRight": MessageLookupByLibrary.simpleMessage("Right"),
    "arrowPadUp": MessageLookupByLibrary.simpleMessage("Up"),
    "backToMachines": MessageLookupByLibrary.simpleMessage("Back to computers"),
    "bannerReconnectButton": MessageLookupByLibrary.simpleMessage("Reconnect"),
    "bannerReconnecting": MessageLookupByLibrary.simpleMessage(
      "Connection lost, retrying…",
    ),
    "bannerReplaced": MessageLookupByLibrary.simpleMessage(
      "Another instance of the app has connected.",
    ),
    "biometricFaceId": MessageLookupByLibrary.simpleMessage("Face ID"),
    "biometricFingerprint": MessageLookupByLibrary.simpleMessage("fingerprint"),
    "biometricGeneric": MessageLookupByLibrary.simpleMessage("biometrics"),
    "biometricPasscode": MessageLookupByLibrary.simpleMessage(
      "device passcode",
    ),
    "biometricTouchId": MessageLookupByLibrary.simpleMessage("Touch ID"),
    "closeTab": MessageLookupByLibrary.simpleMessage("Close tab"),
    "copied": MessageLookupByLibrary.simpleMessage("Copied"),
    "copyAction": MessageLookupByLibrary.simpleMessage("Copy"),
    "createAccountLink": MessageLookupByLibrary.simpleMessage("Create one"),
    "deleteAccountButton": MessageLookupByLibrary.simpleMessage(
      "Delete permanently",
    ),
    "deleteAccountLoseAccount": m46,
    "deleteAccountLoseComputers": MessageLookupByLibrary.simpleMessage(
      "Every computer signed in to it is signed out.",
    ),
    "deleteAccountLoseSessions": MessageLookupByLibrary.simpleMessage(
      "Open terminal sessions are closed.",
    ),
    "deleteAccountPasswordLabel": MessageLookupByLibrary.simpleMessage(
      "Enter your password to confirm",
    ),
    "deleteAccountTitle": MessageLookupByLibrary.simpleMessage(
      "Delete account",
    ),
    "deleteAccountWarningTitle": MessageLookupByLibrary.simpleMessage(
      "This can\'t be undone",
    ),
    "desktopClosedByHost": MessageLookupByLibrary.simpleMessage(
      "The computer disconnected this phone from this terminal.",
    ),
    "desktopDriverBanner": MessageLookupByLibrary.simpleMessage(
      "The computer is using this terminal",
    ),
    "desktopDriverTakeOver": MessageLookupByLibrary.simpleMessage(
      "Tap to take over",
    ),
    "desktopStillRunning": MessageLookupByLibrary.simpleMessage(
      "The terminal is still running on the computer.",
    ),
    "desktopTerminalGone": MessageLookupByLibrary.simpleMessage(
      "Lost the connection to this terminal on the computer.",
    ),
    "desktopTerminalLabel": MessageLookupByLibrary.simpleMessage(
      "Terminal on the computer",
    ),
    "desktopWindowClosed": MessageLookupByLibrary.simpleMessage(
      "The terminal window on the computer was closed.",
    ),
    "emailHint": MessageLookupByLibrary.simpleMessage("email@example.com"),
    "emailLabel": MessageLookupByLibrary.simpleMessage("Email"),
    "emptyStep1": m47,
    "emptyStep2": MessageLookupByLibrary.simpleMessage(
      "Sign in with this same account.",
    ),
    "emptyStep3": m48,
    "emptyTitle": MessageLookupByLibrary.simpleMessage("No computers yet"),
    "errorAgentOffline": MessageLookupByLibrary.simpleMessage(
      "The computer is offline. Open ShellX on the computer and try again.",
    ),
    "errorDisposableEmail": MessageLookupByLibrary.simpleMessage(
      "Disposable email addresses can\'t be used. Please use a real email.",
    ),
    "errorEmailTaken": MessageLookupByLibrary.simpleMessage(
      "This email is already registered.",
    ),
    "errorInvalidCredentials": MessageLookupByLibrary.simpleMessage(
      "Incorrect email or password.",
    ),
    "errorInvalidEmail": MessageLookupByLibrary.simpleMessage(
      "Invalid email address.",
    ),
    "errorNetwork": MessageLookupByLibrary.simpleMessage(
      "Can\'t reach the server. Check your connection and try again.",
    ),
    "errorNotInAccount": MessageLookupByLibrary.simpleMessage(
      "This computer doesn\'t belong to your account. Sign in with the same account on the computer.",
    ),
    "errorQrInvalid": MessageLookupByLibrary.simpleMessage(
      "The QR code is invalid or has expired. Create a new code on your computer.",
    ),
    "errorRateLimited": MessageLookupByLibrary.simpleMessage(
      "Try again in a few minutes.",
    ),
    "errorSessionLimit": MessageLookupByLibrary.simpleMessage(
      "This computer already has the maximum of 10 sessions open. Close some sessions first.",
    ),
    "errorSpawnFailed": m49,
    "errorTimeout": MessageLookupByLibrary.simpleMessage(
      "The computer didn\'t respond. Please try again.",
    ),
    "errorUnknown": m50,
    "errorUntrusted": MessageLookupByLibrary.simpleMessage(
      "This computer no longer trusts this phone. Please pair again.",
    ),
    "errorWeakPassword": MessageLookupByLibrary.simpleMessage(
      "Password must be 8–128 characters.",
    ),
    "errorWrongPassword": MessageLookupByLibrary.simpleMessage(
      "Incorrect password.",
    ),
    "fontSizeTooltip": MessageLookupByLibrary.simpleMessage("Font size"),
    "forbiddenTitle": MessageLookupByLibrary.simpleMessage(
      "You don\'t have permission to access this feature",
    ),
    "forgotPasswordHint": MessageLookupByLibrary.simpleMessage(
      "Forgot your password? Change it in ShellX on a computer that is signed in.",
    ),
    "keyArrowDown": MessageLookupByLibrary.simpleMessage("Down arrow"),
    "keyArrowLeft": MessageLookupByLibrary.simpleMessage("Left arrow"),
    "keyArrowRight": MessageLookupByLibrary.simpleMessage("Right arrow"),
    "keyArrowUp": MessageLookupByLibrary.simpleMessage("Up arrow"),
    "keyMinus": MessageLookupByLibrary.simpleMessage("Hyphen"),
    "keyPaste": MessageLookupByLibrary.simpleMessage("Paste"),
    "keyPipe": MessageLookupByLibrary.simpleMessage("Vertical bar"),
    "keySlash": MessageLookupByLibrary.simpleMessage("Slash"),
    "keyTilde": MessageLookupByLibrary.simpleMessage("Tilde"),
    "keyboardTooltip": MessageLookupByLibrary.simpleMessage("Keyboard"),
    "lastSeenDate": m51,
    "lastSeenJustNow": MessageLookupByLibrary.simpleMessage("just now"),
    "lastSeenMinutes": m52,
    "lastSeenToday": m53,
    "lastSeenUnknown": MessageLookupByLibrary.simpleMessage("unknown"),
    "lastSeenYesterday": m54,
    "linkSheetCopy": MessageLookupByLibrary.simpleMessage("Copy link"),
    "linkSheetOpen": MessageLookupByLibrary.simpleMessage("Open"),
    "linkSheetTitle": MessageLookupByLibrary.simpleMessage("Open link?"),
    "loadMoreFailPleaseTryAgain": MessageLookupByLibrary.simpleMessage(
      "Load more failed\nPlease try again",
    ),
    "lockReason": MessageLookupByLibrary.simpleMessage("Unlock ShellX"),
    "lockSubtitle": MessageLookupByLibrary.simpleMessage(
      "Unlock to see your computers and terminal sessions.",
    ),
    "lockTitle": MessageLookupByLibrary.simpleMessage("ShellX is locked"),
    "lockUnlockWith": m55,
    "loginButton": MessageLookupByLibrary.simpleMessage("Sign in"),
    "loginSubtitle": MessageLookupByLibrary.simpleMessage(
      "Use the same account as ShellX on your computer.",
    ),
    "loginTitle": MessageLookupByLibrary.simpleMessage("Sign in"),
    "machineAiLine": m56,
    "machineAiSessions": m57,
    "machineLastOnline": m58,
    "machineLastUsed": MessageLookupByLibrary.simpleMessage("Last used"),
    "machineNewOutput": MessageLookupByLibrary.simpleMessage("New output"),
    "machineNotPaired": MessageLookupByLibrary.simpleMessage("Not paired"),
    "machineOffline": MessageLookupByLibrary.simpleMessage(
      "This computer is offline.",
    ),
    "machineOnline": MessageLookupByLibrary.simpleMessage("Online"),
    "machineTabs": m59,
    "machineTabsActivity": m60,
    "machineWaiting": MessageLookupByLibrary.simpleMessage(
      "Waiting for connection",
    ),
    "machinesCheckConnection": MessageLookupByLibrary.simpleMessage(
      "Check your internet connection.",
    ),
    "machinesErrorTitle": MessageLookupByLibrary.simpleMessage(
      "Couldn’t load your computers",
    ),
    "machinesOfflineHeader": MessageLookupByLibrary.simpleMessage("Offline"),
    "machinesReload": MessageLookupByLibrary.simpleMessage("Reload"),
    "machinesRetry": MessageLookupByLibrary.simpleMessage("Try again"),
    "machinesTitle": MessageLookupByLibrary.simpleMessage("Your computers"),
    "networkError": MessageLookupByLibrary.simpleMessage("Network Error"),
    "noAccountPrompt": MessageLookupByLibrary.simpleMessage("No account yet?"),
    "notFound": MessageLookupByLibrary.simpleMessage("Not Found"),
    "openAppStore": MessageLookupByLibrary.simpleMessage("Open the App Store"),
    "openPlayStore": MessageLookupByLibrary.simpleMessage("Open Google Play"),
    "openSettings": MessageLookupByLibrary.simpleMessage("Open Settings"),
    "openTerminal": MessageLookupByLibrary.simpleMessage("Open terminal"),
    "pairNewMachine": MessageLookupByLibrary.simpleMessage(
      "Pair a new computer",
    ),
    "pairPhoneMenuItem": MessageLookupByLibrary.simpleMessage("Pair phone…"),
    "pairingFailedTitle": MessageLookupByLibrary.simpleMessage(
      "Couldn\'t pair",
    ),
    "pairingSucceeded": MessageLookupByLibrary.simpleMessage("Paired"),
    "pairingSucceededBody": m61,
    "passwordHide": MessageLookupByLibrary.simpleMessage("Hide password"),
    "passwordHint": MessageLookupByLibrary.simpleMessage("Password"),
    "passwordLabel": MessageLookupByLibrary.simpleMessage("Password"),
    "passwordMissing": m62,
    "passwordRule": MessageLookupByLibrary.simpleMessage(
      "8 to 128 characters.",
    ),
    "passwordShow": MessageLookupByLibrary.simpleMessage("Show password"),
    "passwordTooLong": m63,
    "pickerAgentDone": m64,
    "pickerAgentIdle": m65,
    "pickerAgentNeedsInput": m66,
    "pickerAgentRunning": m67,
    "pickerAttachedElsewhere": MessageLookupByLibrary.simpleMessage(
      "open on another device",
    ),
    "pickerDesktopGroup": MessageLookupByLibrary.simpleMessage(
      "Terminals on the computer",
    ),
    "pickerHintOpenNewWindow": MessageLookupByLibrary.simpleMessage(
      "Only terminal windows opened after sharing was turned on show up here. Open a new terminal window on the computer.",
    ),
    "pickerHintSharingOff": MessageLookupByLibrary.simpleMessage(
      "Turn on \'Share terminals with phone\' in the ShellX menu on the computer to see its open terminals here.",
    ),
    "pickerHintUpdateDesktop": MessageLookupByLibrary.simpleMessage(
      "Update ShellX on the computer to see its open terminals.",
    ),
    "pickerNewSession": MessageLookupByLibrary.simpleMessage("New session"),
    "pickerOpen": MessageLookupByLibrary.simpleMessage("Open"),
    "pickerShellxGroup": MessageLookupByLibrary.simpleMessage(
      "ShellX sessions",
    ),
    "pickerStarted": m68,
    "pickerSubtitle": MessageLookupByLibrary.simpleMessage(
      "Reopen a session to continue where you left off, or start a new one.",
    ),
    "pickerTitle": m69,
    "privacyLink": MessageLookupByLibrary.simpleMessage("Privacy Policy"),
    "pushActionAllow": MessageLookupByLibrary.simpleMessage("Allow"),
    "pushActionReject": MessageLookupByLibrary.simpleMessage("Deny"),
    "registerButton": MessageLookupByLibrary.simpleMessage("Create account"),
    "registerSubtitle": MessageLookupByLibrary.simpleMessage(
      "One account for your phone and all your computers.",
    ),
    "registerTitle": MessageLookupByLibrary.simpleMessage("Create account"),
    "replyBarLabel": MessageLookupByLibrary.simpleMessage(
      "Quick replies to the agent",
    ),
    "replyKeyEnter": MessageLookupByLibrary.simpleMessage("Enter"),
    "replyKeyEscape": MessageLookupByLibrary.simpleMessage("Escape"),
    "replyKeyNo": MessageLookupByLibrary.simpleMessage("No"),
    "replyKeyOption": m70,
    "replyKeyYes": MessageLookupByLibrary.simpleMessage("Yes"),
    "replyShowExtraKeys": MessageLookupByLibrary.simpleMessage(
      "Show the extra keys",
    ),
    "retry": MessageLookupByLibrary.simpleMessage("Retry"),
    "scanAgain": MessageLookupByLibrary.simpleMessage("Scan again"),
    "scanQrButton": MessageLookupByLibrary.simpleMessage("Scan QR code"),
    "scannerCameraDenied": MessageLookupByLibrary.simpleMessage(
      "Camera access is needed to scan the QR code. Allow it in your phone\'s Settings.",
    ),
    "scannerCameraError": MessageLookupByLibrary.simpleMessage(
      "Couldn\'t start the camera.",
    ),
    "scannerCardBody": m71,
    "scannerCardTitle": MessageLookupByLibrary.simpleMessage(
      "The code is on your computer",
    ),
    "scannerPairing": MessageLookupByLibrary.simpleMessage("Pairing…"),
    "scannerTitle": MessageLookupByLibrary.simpleMessage("Scan pairing code"),
    "sessionEnded": MessageLookupByLibrary.simpleMessage("Session ended"),
    "sessionExitedBody": m72,
    "sessionGoneBody": MessageLookupByLibrary.simpleMessage(
      "The computer no longer has this session. The output above can still be read and copied.",
    ),
    "sessionsLoading": MessageLookupByLibrary.simpleMessage(
      "Getting the session list…",
    ),
    "settingsAccountGroup": MessageLookupByLibrary.simpleMessage("Account"),
    "settingsAppGroup": MessageLookupByLibrary.simpleMessage("App"),
    "settingsBiometricUnavailable": MessageLookupByLibrary.simpleMessage(
      "No passcode or biometrics are set up on this device",
    ),
    "settingsDeleteAccount": MessageLookupByLibrary.simpleMessage(
      "Delete account",
    ),
    "settingsEmail": MessageLookupByLibrary.simpleMessage("Email"),
    "settingsFixedHeight": MessageLookupByLibrary.simpleMessage(
      "Keep terminal size when the keyboard opens",
    ),
    "settingsFixedHeightHint": MessageLookupByLibrary.simpleMessage(
      "The keyboard covers the terminal instead of shrinking it.",
    ),
    "settingsFontSize": MessageLookupByLibrary.simpleMessage(
      "Default font size",
    ),
    "settingsLicenses": MessageLookupByLibrary.simpleMessage(
      "Open-source licences",
    ),
    "settingsLockFootnote": MessageLookupByLibrary.simpleMessage(
      "Asked when the app opens and when you come back after more than 5 minutes.",
    ),
    "settingsLockWith": m73,
    "settingsLogout": MessageLookupByLibrary.simpleMessage("Sign out"),
    "settingsLogoutConfirm": MessageLookupByLibrary.simpleMessage(
      "Sign out of ShellX? Paired computers are kept for your next sign-in.",
    ),
    "settingsNoPairedMachines": MessageLookupByLibrary.simpleMessage(
      "No paired computers.",
    ),
    "settingsNotifications": MessageLookupByLibrary.simpleMessage(
      "Push notifications",
    ),
    "settingsNotificationsFootnote": MessageLookupByLibrary.simpleMessage(
      "Tells you when a long-running command finishes on a computer, or when a program sends a notification. Choose the time threshold in the ShellX menu on the computer.",
    ),
    "settingsNotificationsGroup": MessageLookupByLibrary.simpleMessage(
      "Notifications",
    ),
    "settingsNotificationsOff": MessageLookupByLibrary.simpleMessage("Off"),
    "settingsNotificationsOffFootnote": MessageLookupByLibrary.simpleMessage(
      "Notifications are off — open the system settings to turn them on.",
    ),
    "settingsNotificationsOn": MessageLookupByLibrary.simpleMessage("On"),
    "settingsNotificationsOpenSystem": MessageLookupByLibrary.simpleMessage(
      "Open system settings",
    ),
    "settingsNotificationsTurnOn": MessageLookupByLibrary.simpleMessage(
      "Turn on notifications",
    ),
    "settingsPairedMachines": MessageLookupByLibrary.simpleMessage(
      "Paired computers",
    ),
    "settingsPrivacy": MessageLookupByLibrary.simpleMessage("Privacy policy"),
    "settingsSecurityGroup": MessageLookupByLibrary.simpleMessage("Security"),
    "settingsTerminalGroup": MessageLookupByLibrary.simpleMessage("Terminal"),
    "settingsTerms": MessageLookupByLibrary.simpleMessage("Terms of use"),
    "settingsTheme": MessageLookupByLibrary.simpleMessage("Appearance"),
    "settingsThemeDark": MessageLookupByLibrary.simpleMessage("Dark"),
    "settingsThemeLight": MessageLookupByLibrary.simpleMessage("Light"),
    "settingsThemeSystem": MessageLookupByLibrary.simpleMessage("System"),
    "settingsTitle": MessageLookupByLibrary.simpleMessage("Settings"),
    "settingsTooltip": MessageLookupByLibrary.simpleMessage("Settings"),
    "settingsUnpair": MessageLookupByLibrary.simpleMessage("Unpair"),
    "settingsUnpairConfirm": m74,
    "settingsUnpairFailed": MessageLookupByLibrary.simpleMessage(
      "Couldn\'t unpair yet.",
    ),
    "settingsVersion": m75,
    "signedOutAccountDeleted": MessageLookupByLibrary.simpleMessage(
      "Your account has been deleted.",
    ),
    "signedOutExpired": MessageLookupByLibrary.simpleMessage(
      "Your sign-in has expired. Please sign in again.",
    ),
    "somethingWentWrong": MessageLookupByLibrary.simpleMessage(
      "Something went wrong",
    ),
    "somethingWentWrongPleaseTryAgain": MessageLookupByLibrary.simpleMessage(
      "Something went wrong, please try again",
    ),
    "tabClosedByHost": MessageLookupByLibrary.simpleMessage(
      "The session was closed on the computer.",
    ),
    "tabReattach": MessageLookupByLibrary.simpleMessage("Reattach"),
    "tabTakenOver": MessageLookupByLibrary.simpleMessage(
      "This session was opened on another device.",
    ),
    "terminalCloseConfirm": MessageLookupByLibrary.simpleMessage(
      "Close this session? Programs running in it will be stopped.",
    ),
    "terminalCloseTab": MessageLookupByLibrary.simpleMessage("Close session"),
    "terminalConnected": MessageLookupByLibrary.simpleMessage(
      "Connected · end-to-end encrypted",
    ),
    "terminalConnecting": MessageLookupByLibrary.simpleMessage("Connecting…"),
    "terminalFailedTabTitle": MessageLookupByLibrary.simpleMessage("shell"),
    "terminalNoTabs": MessageLookupByLibrary.simpleMessage("No open sessions."),
    "terminalOpenNew": MessageLookupByLibrary.simpleMessage(
      "Open a new session",
    ),
    "termsLink": MessageLookupByLibrary.simpleMessage("Terms"),
    "termsNotice": m76,
    "unauthorized": MessageLookupByLibrary.simpleMessage("Unauthorized"),
    "unknownError": MessageLookupByLibrary.simpleMessage("Unknown Error"),
    "unknownMachine": MessageLookupByLibrary.simpleMessage("Unknown computer"),
    "untrustedTitle": MessageLookupByLibrary.simpleMessage("Pair again"),
    "updateRequiredBody": MessageLookupByLibrary.simpleMessage(
      "This version can no longer connect to your computers. Update to keep using ShellX.",
    ),
    "updateRequiredTitle": MessageLookupByLibrary.simpleMessage(
      "App update required",
    ),
    "validationEmailInvalid": MessageLookupByLibrary.simpleMessage(
      "Please enter a valid email address.",
    ),
    "validationEmailRequired": MessageLookupByLibrary.simpleMessage(
      "Email is required.",
    ),
    "validationPasswordConfirmRequired": MessageLookupByLibrary.simpleMessage(
      "Please confirm your password.",
    ),
    "validationPasswordDigit": MessageLookupByLibrary.simpleMessage(
      "Password must contain at least one number.",
    ),
    "validationPasswordLowercase": MessageLookupByLibrary.simpleMessage(
      "Password must contain at least one lowercase letter.",
    ),
    "validationPasswordMinLength": m77,
    "validationPasswordNotMatch": MessageLookupByLibrary.simpleMessage(
      "Passwords do not match.",
    ),
    "validationPasswordRequired": MessageLookupByLibrary.simpleMessage(
      "Password is required.",
    ),
    "validationPasswordSpecialChar": MessageLookupByLibrary.simpleMessage(
      "Password must contain at least one special character.",
    ),
    "validationPasswordUppercase": MessageLookupByLibrary.simpleMessage(
      "Password must contain at least one uppercase letter.",
    ),
    "validationPhoneInvalid": MessageLookupByLibrary.simpleMessage(
      "Please enter a valid phone number.",
    ),
    "validationPhoneRequired": MessageLookupByLibrary.simpleMessage(
      "Phone number is required.",
    ),
    "validationTextMaxLength": m78,
    "validationTextMinLength": m79,
    "validationTextRequired": MessageLookupByLibrary.simpleMessage(
      "This field is required.",
    ),
    "viewAsTextCopyAll": MessageLookupByLibrary.simpleMessage("Copy all"),
    "viewAsTextEmpty": MessageLookupByLibrary.simpleMessage(
      "Nothing to show yet",
    ),
    "viewAsTextRefresh": MessageLookupByLibrary.simpleMessage("Refresh"),
    "viewAsTextTitle": MessageLookupByLibrary.simpleMessage("Terminal text"),
    "viewAsTextTooltip": MessageLookupByLibrary.simpleMessage("View as text"),
    "viewAsTextTruncated": m80,
    "voiceClose": MessageLookupByLibrary.simpleMessage("Close"),
    "voiceDetached": MessageLookupByLibrary.simpleMessage(
      "This session was disconnected from the phone — reattach to send",
    ),
    "voiceDraftSaved": MessageLookupByLibrary.simpleMessage("Draft saved"),
    "voiceEnded": MessageLookupByLibrary.simpleMessage(
      "Session ended — open a new session to send",
    ),
    "voiceFailed": MessageLookupByLibrary.simpleMessage(
      "Couldn\'t recognize that, try again",
    ),
    "voiceHintEn": MessageLookupByLibrary.simpleMessage(
      "Speak or type… say “send” to send",
    ),
    "voiceHintVi": MessageLookupByLibrary.simpleMessage(
      "Speak or type… say “gửi” to send",
    ),
    "voiceLanguageEn": MessageLookupByLibrary.simpleMessage("English"),
    "voiceLanguageVi": MessageLookupByLibrary.simpleMessage("Vietnamese"),
    "voiceListeningAnnounce": MessageLookupByLibrary.simpleMessage("Listening"),
    "voiceListeningEn": MessageLookupByLibrary.simpleMessage(
      "Listening… say “send” to send",
    ),
    "voiceListeningVi": MessageLookupByLibrary.simpleMessage(
      "Listening… say “gửi” to send",
    ),
    "voiceLocaleUnavailableEn": MessageLookupByLibrary.simpleMessage(
      "This phone can\'t recognize English yet — try VI",
    ),
    "voiceLocaleUnavailableVi": MessageLookupByLibrary.simpleMessage(
      "This phone can\'t recognize Vietnamese yet — try EN",
    ),
    "voiceMicTooltip": MessageLookupByLibrary.simpleMessage("Speak a command"),
    "voiceNetwork": MessageLookupByLibrary.simpleMessage(
      "Speech recognition needs a network connection",
    ),
    "voiceNoPermission": MessageLookupByLibrary.simpleMessage(
      "ShellX needs microphone and speech recognition access to take spoken commands",
    ),
    "voiceNotLive": MessageLookupByLibrary.simpleMessage(
      "The session isn\'t connected — you can send once it reconnects",
    ),
    "voiceSend": MessageLookupByLibrary.simpleMessage("Send"),
    "voiceSendEnter": MessageLookupByLibrary.simpleMessage("Send Enter"),
    "voiceStopTooltip": MessageLookupByLibrary.simpleMessage("Stop listening"),
    "voiceTarget": m81,
    "voiceUnsupported": MessageLookupByLibrary.simpleMessage(
      "Speech recognition isn\'t available on this phone",
    ),
  };
}
