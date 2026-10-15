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

  static String m1(agent) => "Message ${agent}…";

  static String m2(percent) => "Context ${percent}%";

  static String m3(count) => "${count} lines in all; the middle is on the computer";

  static String m4(n) => "${Intl.plural(n, one: '1 image', other: '${n} images')}";

  static String m5(part, parts) => "Loading ${part}/${parts}";

  static String m6(count) => "${Intl.plural(count, one: '+1 more file', other: '+${count} more files')}";

  static String m7(agent) => "${agent} doesn\'t take images.";

  static String m8(agent, code) => "${agent} stopped unexpectedly (exit ${code}).";

  static String m9(agent) => "${agent} sent output ShellX cannot read and was stopped.";

  static String m10(agent) => "${agent} needs you to sign in, on the computer.";

  static String m11(agent) => "${agent} was not found on the computer.";

  static String m12(agent, version) => "${agent} needs Node.js ${version} or newer on the computer.";

  static String m13(agent) => "${agent} is not installed on the computer.";

  static String m14(agent) => "${agent} could not start.";

  static String m15(reason) => "Undo is off for this project (${reason}).";

  static String m16(reason) => "Undo is off for this turn (${reason}).";

  static String m17(count) => "${count} more waiting";

  static String m18(agent) => "${agent} asks:";

  static String m19(done, total) => "Plan · ${done}/${total}";

  static String m20(reason) => "The computer did not take it (${reason}).";

  static String m21(agent, state) => "${agent} · ${state}";

  static String m22(max) => "Too long to send from the phone (${max} KB at most).";

  static String m23(target) => "Create ${target}";

  static String m24(target) => "Delete ${target}";

  static String m25(target) => "Edit ${target}";

  static String m26(target) => "Run ${target}";

  static String m27(target) => "Fetch ${target}";

  static String m28(target) => "Rename ${target}";

  static String m29(target) => "Read ${target}";

  static String m30(time) => "running · ${time}";

  static String m31(target) => "Search ${target}";

  static String m32(n) => "Turn ${n} failed";

  static String m33(count) => "${Intl.plural(count, one: '1 file changed', other: '${count} files changed')}";

  static String m34(n) => "Turn ${n} interrupted";

  static String m35(n, time) => "Stopped turn ${n} · ${time}";

  static String m36(n, time) => "Turn ${n} · ${time}";

  static String m37(option) => "You chose: ${option}";

  static String m38(email) => "Deletes the account ${email} with all its devices and pairings.";

  static String m39(site) => "Install ShellX on your computer (macOS or Windows) from ${site}.";

  static String m40(menu) => "Click the ShellX icon, choose ${menu}, then scan the code.";

  static String m41(reason) => "Couldn\'t start the shell: ${reason}";

  static String m42(code) => "Something went wrong (${code}).";

  static String m43(day, month, time) => "${month}/${day}, ${time}";

  static String m44(count) => "${Intl.plural(count, one: '1 minute ago', other: '${count} minutes ago')}";

  static String m45(time) => "today, ${time}";

  static String m46(time) => "yesterday, ${time}";

  static String m47(method) => "Unlock with ${method}";

  static String m48(when) => "Last online: ${when}";

  static String m49(count) => "${Intl.plural(count, one: '1 tab', other: '${count} tabs')}";

  static String m50(tabs, unseen) =>
      "${Intl.plural(tabs, one: '1 tab', other: '${tabs} tabs')} · ${unseen} with new output";

  static String m51(name) => "${name} now trusts this phone. From now on, just tap the computer to open a terminal.";

  static String m52(count) =>
      "${Intl.plural(count, one: '1 more character needed.', other: '${count} more characters needed.')}";

  static String m53(count) =>
      "${Intl.plural(count, one: '1 character too many.', other: '${count} characters too many.')}";

  static String m54(name) => "${name} · done";

  static String m55(name) => "${name} · waiting";

  static String m56(name) => "${name} · needs your answer";

  static String m57(name) => "${name} · running";

  static String m58(when) => "opened ${when}";

  static String m59(count) =>
      "${Intl.plural(count, one: 'This computer has 1 session', other: 'This computer has ${count} sessions')}";

  static String m60(number) => "Option ${number}";

  static String m61(menu) =>
      "macOS: click the ShellX icon in the menu bar. Windows: click the icon in the system tray. Choose ${menu}";

  static String m62(code) =>
      "The last command exited with code ${code}. The output above can still be read and copied.";

  static String m63(method) => "Lock with ${method}";

  static String m64(name) => "Unpair ${name}? You\'ll need to scan a QR code again to use this computer.";

  static String m65(version, build) => "ShellX ${version} (${build})";

  static String m66(terms, privacy) => "By creating an account you agree to the ${terms} and the ${privacy}.";

  static String m67(length) => "Password must be at least ${length} characters.";

  static String m68(length) => "Must be at most ${length} characters.";

  static String m69(length) => "Must be at least ${length} characters.";

  static String m70(lines) => "Showing the last ${lines} lines";

  static String m71(target) => "To: ${target}";

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
    "aiBusy": MessageLookupByLibrary.simpleMessage(
      "Too many requests at once. Wait a moment, then try again.",
    ),
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
    "aiComposerHint": m1,
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
    "aiContext": m2,
    "aiCreated": MessageLookupByLibrary.simpleMessage("new file"),
    "aiCutLines": m3,
    "aiCutText": MessageLookupByLibrary.simpleMessage(
      "The rest of this message is on the computer.",
    ),
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
    "aiImagesCount": m4,
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
    "aiLoadingParts": m5,
    "aiModeAcceptEdits": MessageLookupByLibrary.simpleMessage("Edit files"),
    "aiModeAuto": MessageLookupByLibrary.simpleMessage("Auto"),
    "aiModeBypass": MessageLookupByLibrary.simpleMessage("Bypass permissions"),
    "aiModeDefault": MessageLookupByLibrary.simpleMessage("Ask first"),
    "aiModePlan": MessageLookupByLibrary.simpleMessage("Plan"),
    "aiMoreDiffs": m6,
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
    "aiNoImages": m7,
    "aiNoOutput": MessageLookupByLibrary.simpleMessage("No output"),
    "aiNoticeCannotResume": MessageLookupByLibrary.simpleMessage(
      "This agent cannot reopen the old session; a new one was started.",
    ),
    "aiNoticeExited": m8,
    "aiNoticeFolderMissing": MessageLookupByLibrary.simpleMessage(
      "The session\'s folder is gone. Choose one on the computer.",
    ),
    "aiNoticeInvalid": m9,
    "aiNoticeLogin": m10,
    "aiNoticeMissing": m11,
    "aiNoticeNode": m12,
    "aiNoticeNotInstalled": m13,
    "aiNoticeOther": MessageLookupByLibrary.simpleMessage(
      "A notice from the computer.",
    ),
    "aiNoticeStartFailed": m14,
    "aiNoticeUndoOff": MessageLookupByLibrary.simpleMessage(
      "Undo is off for this project.",
    ),
    "aiNoticeUndoOffReason": m15,
    "aiNoticeUndoOffTurn": m16,
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
    "aiPermMore": m17,
    "aiPermOnComputer": MessageLookupByLibrary.simpleMessage(
      "Answer this request on the computer.",
    ),
    "aiPermOption": MessageLookupByLibrary.simpleMessage("Option"),
    "aiPermRejectAlways": MessageLookupByLibrary.simpleMessage("Always reject"),
    "aiPermRejectOnce": MessageLookupByLibrary.simpleMessage("Reject"),
    "aiPermTitle": m18,
    "aiPickFailed": MessageLookupByLibrary.simpleMessage(
      "Couldn\'t open the photos. Check ShellX\'s access in Settings.",
    ),
    "aiPlan": m19,
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
    "aiRequestFailed": m20,
    "aiRowSubtitle": m21,
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
    "aiThought": MessageLookupByLibrary.simpleMessage("Thinking"),
    "aiTooLong": m22,
    "aiToolAwaiting": MessageLookupByLibrary.simpleMessage("waiting for you"),
    "aiToolCreate": m23,
    "aiToolDelete": m24,
    "aiToolDone": MessageLookupByLibrary.simpleMessage("done"),
    "aiToolEdit": m25,
    "aiToolExecute": m26,
    "aiToolFailed": MessageLookupByLibrary.simpleMessage("error"),
    "aiToolFetch": m27,
    "aiToolMove": m28,
    "aiToolPending": MessageLookupByLibrary.simpleMessage("waiting"),
    "aiToolRead": m29,
    "aiToolRejected": MessageLookupByLibrary.simpleMessage("rejected"),
    "aiToolRunningFor": m30,
    "aiToolSearch": m31,
    "aiToolStopped": MessageLookupByLibrary.simpleMessage("stopped"),
    "aiToolSwitchMode": MessageLookupByLibrary.simpleMessage("Switch mode"),
    "aiTurnFailed": m32,
    "aiTurnFiles": m33,
    "aiTurnInterrupted": m34,
    "aiTurnStopped": m35,
    "aiTurnSummary": m36,
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
    "aiYouChose": m37,
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
    "deleteAccountLoseAccount": m38,
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
    "emptyStep1": m39,
    "emptyStep2": MessageLookupByLibrary.simpleMessage(
      "Sign in with this same account.",
    ),
    "emptyStep3": m40,
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
    "errorSpawnFailed": m41,
    "errorTimeout": MessageLookupByLibrary.simpleMessage(
      "The computer didn\'t respond. Please try again.",
    ),
    "errorUnknown": m42,
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
    "lastSeenDate": m43,
    "lastSeenJustNow": MessageLookupByLibrary.simpleMessage("just now"),
    "lastSeenMinutes": m44,
    "lastSeenToday": m45,
    "lastSeenUnknown": MessageLookupByLibrary.simpleMessage("unknown"),
    "lastSeenYesterday": m46,
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
    "lockUnlockWith": m47,
    "loginButton": MessageLookupByLibrary.simpleMessage("Sign in"),
    "loginSubtitle": MessageLookupByLibrary.simpleMessage(
      "Use the same account as ShellX on your computer.",
    ),
    "loginTitle": MessageLookupByLibrary.simpleMessage("Sign in"),
    "machineLastOnline": m48,
    "machineLastUsed": MessageLookupByLibrary.simpleMessage("Last used"),
    "machineNewOutput": MessageLookupByLibrary.simpleMessage("New output"),
    "machineNotPaired": MessageLookupByLibrary.simpleMessage("Not paired"),
    "machineOffline": MessageLookupByLibrary.simpleMessage(
      "This computer is offline.",
    ),
    "machineOnline": MessageLookupByLibrary.simpleMessage("Online"),
    "machineTabs": m49,
    "machineTabsActivity": m50,
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
    "pairingSucceededBody": m51,
    "passwordHide": MessageLookupByLibrary.simpleMessage("Hide password"),
    "passwordHint": MessageLookupByLibrary.simpleMessage("Password"),
    "passwordLabel": MessageLookupByLibrary.simpleMessage("Password"),
    "passwordMissing": m52,
    "passwordRule": MessageLookupByLibrary.simpleMessage(
      "8 to 128 characters.",
    ),
    "passwordShow": MessageLookupByLibrary.simpleMessage("Show password"),
    "passwordTooLong": m53,
    "pickerAgentDone": m54,
    "pickerAgentIdle": m55,
    "pickerAgentNeedsInput": m56,
    "pickerAgentRunning": m57,
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
    "pickerStarted": m58,
    "pickerSubtitle": MessageLookupByLibrary.simpleMessage(
      "Reopen a session to continue where you left off, or start a new one.",
    ),
    "pickerTitle": m59,
    "privacyLink": MessageLookupByLibrary.simpleMessage("Privacy Policy"),
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
    "replyKeyOption": m60,
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
    "scannerCardBody": m61,
    "scannerCardTitle": MessageLookupByLibrary.simpleMessage(
      "The code is on your computer",
    ),
    "scannerPairing": MessageLookupByLibrary.simpleMessage("Pairing…"),
    "scannerTitle": MessageLookupByLibrary.simpleMessage("Scan pairing code"),
    "sessionEnded": MessageLookupByLibrary.simpleMessage("Session ended"),
    "sessionExitedBody": m62,
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
    "settingsLockWith": m63,
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
    "settingsUnpairConfirm": m64,
    "settingsUnpairFailed": MessageLookupByLibrary.simpleMessage(
      "Couldn\'t unpair yet.",
    ),
    "settingsVersion": m65,
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
    "termsNotice": m66,
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
    "validationPasswordMinLength": m67,
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
    "validationTextMaxLength": m68,
    "validationTextMinLength": m69,
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
    "viewAsTextTruncated": m70,
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
    "voiceTarget": m71,
    "voiceUnsupported": MessageLookupByLibrary.simpleMessage(
      "Speech recognition isn\'t available on this phone",
    ),
  };
}
