# Ledger: ShellX Android parity

Spec: `docs/superpowers/specs/2026-11-07-shellx-android-app-design.md` (S3) §6 and §9. Contracts:
`docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md`. iPhone reference: `shellx-ios/` at `53792a549b`.

One row per screen or rule of S3 §6. Each row names the iPhone file the behaviour is translated from, the
Android file it goes to, the owning plan (contracts §1) and its state.

- The plan that builds a row sets its state in the same commit: `todo` → `done (<plan>)`. When Android
  behaves differently on purpose, it uses `differs (<plan>): <what and why>` instead.
- A change to `shellx-ios/` while the Android project runs adds a row to "iPhone changes since the reference"
  in the same commit. After the release, every new phone feature lands in both apps or gets a `differs` row.
- Paths: `ShellX/…` is under `shellx-ios/`, `ShellXAppCore/…` is under `shellx-ios/Packages/ShellXAppCore/Sources/`,
  `app:…` is under `shellx-android/app/src/main/kotlin/com/shellx/app/`, and `core:…` is under
  `shellx-android/core/src/main/kotlin/com/shellx/core/`.
- Mirror rule: `ShellX/<Folders>/<Name>.swift` → `app:<folders in lower case>/<Name>.kt`, and
  `ShellXAppCore/<Folder>/<Name>.swift` → `core:<folder in lower case>/<Name>.kt`. A type keeps its iPhone
  name. Contract names win over the rule. An owning plan that renames a file updates its row.

## Screens and flows (S3 §6.1)

| # | Screen or flow | iPhone | Android | Plan | State |
| --- | --- | --- | --- | --- | --- |
| 6.1-1 | Launch: logo and name | `ShellX/UI/RootView.swift` (`LaunchView`) | `app:ui/LaunchView.kt` | 3A | todo |
| 6.1-2 | Launch: the screen is chosen by the account phase | `ShellX/UI/RootView.swift` (`RootView`), `ShellXAppCore/Account/AppPhase.swift` | `app:ui/nav/ShellXNavHost.kt` (route `launch`) | 3D | todo |
| 6.1-3 | Sign-in: one "Continue with Google" button; errors for network, server, rate limit and pending wipe; "Session expired" banner after a 401 | `ShellX/UI/SignIn/SignInView.swift` | `app:ui/signin/SignInView.kt` (route `sign_in`) | 3D | todo |
| 6.1-4 | Pairing: scan the QR, paste `shellx-link://…`, or open the link from another app; confirm the Mac's name, wait for Allow, done; camera blocked; failure; the code stays in memory and nothing goes out before the user confirms | `ShellX/UI/Pairing/PairingSheet.swift`, `QRScannerView.swift`, `PairingPaste.swift`, `ShellX/Platform/CameraAccess.swift`, `ShellX/UI/Onboarding/FirstMacView.swift`, `Config/Info.plist` (`CFBundleURLTypes`), `ShellX/ShellXApp.swift` (`onOpenURL`) | `app:ui/pairing/…`, `app:platform/CameraAccess.kt`, `app:ui/onboarding/FirstMacView.kt`, intent filter `shellx-link` in `AndroidManifest.xml` (routes `first_mac`, `pairing`) | 3D | todo |
| 6.1-5 | Home: bell with the needs-you count, ＋ (new workspace, asking which Mac when there are several), Settings; groups Needs you, Running, Just finished, Workspaces (one per Mac), then "Ended · N" collapsed; pull to refresh; row actions rename and close a workspace, close an agent, "Remove from this phone" for a gone session | `ShellX/UI/Workspaces/WorkspaceListScreen.swift`, `WorkspaceListView.swift`, `WorkspaceRowView.swift`, `MachineGroupHeader.swift`, `ListNotice.swift`, `WorkspaceRenameSheet.swift`, `ShellX/UI/Home/FocusRowView.swift`, `NeedsYouBar.swift`, `EndedSessionsView.swift` | `app:ui/workspaces/…`, `app:ui/home/…` (route `home`) | 3D | todo |
| 6.1-6 | Session lists: agent sessions outside workspaces; ended sessions | `ShellX/UI/Home/SessionListScreen.swift`, `HomeRoute.swift`, `ShellX/UI/Workspaces/OtherSessionsView.swift` | `app:ui/home/SessionListScreen.kt`, `app:ui/workspaces/OtherSessionsView.kt` (route `sessions/{kind}`) | 3D | todo |
| 6.1-7 | Your Macs: set the default, unpair (asks first), remove a Mac that unpaired this phone | `ShellX/UI/Machines/MachinesView.swift`, `MachineRow.swift` | `app:ui/machines/…` (route `machines`) | 3D | todo |
| 6.1-8 | Workspace: title and git branch; menu with Rename, Close Tab (asks) and Close Workspace (asks); chip row, swipe between panes, long-press a chip to Close Tab; says when the Mac closed a pane or the workspace | `ShellX/UI/Workspaces/WorkspaceView.swift`, `WorkspaceScreen.swift`, `PaneChips.swift`, `WorkspaceFeedback.swift` | `app:ui/workspaces/WorkspaceScreen.kt` (`PaneContent(pane)`), `WorkspaceView.kt`, `PaneChips.kt`, `WorkspaceFeedback.kt` (route `workspace/{machineId}/{workspaceId}`) | 3E | todo |
| 6.1-9 | Shell pane: a real terminal | `ShellX/UI/Workspaces/ShellPanePlaceholder.swift` (until 2C) | `app:ui/workspaces/ShellPanePlaceholder.kt`, then `TerminalPane` | 3E, 3G | todo |
| 6.1-10 | Agent chat: entry kinds (text, collapsed thinking, tool step, state); load more when scrolling up; "New messages"; Stop; Force stop (asks); Close agent (asks); Remove from this phone | `ShellX/UI/Agent/AgentScreen.swift`, `AgentView.swift`, `AgentHeader.swift`, `ChatEntryRow.swift`, `NewMessagesButton.swift`, `StopButton.swift` | `app:ui/agent/…` (route `agent/{machineId}/{sessionId}`) | 3E | todo |
| 6.1-11 | Needs you: permission card (Deny, Allow, menu Always allow / All tools); question sheet (choices, "Other…" typed, answer by voice); plan sheet (Approve, other modes, Revise with required feedback, Reject) | `ShellX/UI/Pending/` (every file) | `app:ui/pending/…` (route `pending`) | 3E | todo |
| 6.1-12 | Composer: text; mic while the field is empty (hold to talk, release to send, slide left to cancel; tap mode with a screen reader); ＋ adds photos and files (at most 5, 10 MiB each); upload progress | `ShellX/UI/Composer/` (every file), `ShellX/Voice/` | `app:ui/composer/…`, `app:voice/…` | 3E | todo |
| 6.1-13 | Settings: Your Macs; Account (email, Sign out with a question, Delete account…); Appearance (System / Light / Dark); About (version, "Licenses" opens shellx.pro) | `ShellX/UI/Settings/SettingsView.swift`, `AccountSection.swift`, `AppearanceSection.swift`, `AboutSection.swift`, `ShellX/UI/Theme/AppAppearance.swift` | `app:ui/settings/…`, `app:ui/theme/AppAppearance.kt` (route `settings`) | 3D | todo |
| 6.1-14 | Settings › Voice: language picker, shown only once the mic works | `ShellX/UI/Settings/VoiceSection.swift` | `app:ui/settings/VoiceSection.kt` | 3D (section), 3E (engine) | todo |
| 6.1-15 | Update prompt: Update / Later, at launch and on every return; never in debug | `ShellX/UI/Update/UpdateAlert.swift`, `ShellXAppCore/Update/UpdatePrompt.swift`, `AppStoreRelease.swift` | `app:ui/update/UpdateAlert.kt` (Play In-App Updates, flexible flow), `core:update/UpdatePrompt.kt` | 3C (rules), 3E (UI) | todo |
| 6.1-16 | Notifications: `needs_you` (a tap opens Needs you) and `resolved` (removes the alert); none while the app is in front | `ShellX/Platform/PushAppDelegate.swift`, `ShellXAppCore/Push/PushRegistration.swift`, `PushPayload.swift` | `app:platform/…` (FCM, contracts §8) | 3E (app), 3F (relay) | todo |
| 6.1-17 | Demo without an account: a text button on sign-in and on "no Mac yet"; a fake Mac with workspaces, agents and needs-you items; a "Demo · Exit" banner; nothing goes to the network | `ShellX/Debug/DemoComposition.swift`, `DemoScript.swift` | `core:demo/DemoScript.kt`, entry points in `app:ui/signin/` and `app:ui/onboarding/` (route `demo`) | 3C (data), 3D (entry points) | todo |

## Behaviour rules (S3 §6.2)

| # | Rule | iPhone | Android | Plan | State |
| --- | --- | --- | --- | --- | --- |
| 6.2-1 | "Just finished": idle within 3 600 s of when the phone saw the session finish | `ShellXAppCore/Home/HomeFocus.swift` (`justDoneFor`) | `core:home/HomeFocus.kt` | 3C | todo |
| 6.2-2 | Finishes are detected; each session keeps its last 2 | `ShellXAppCore/Home/SessionFinishDetector.swift` | `core:home/SessionFinishDetector.kt` | 3C | todo |
| 6.2-3 | "Ended": shown for 43 200 s (12 h) after the end | `ShellXAppCore/Home/HomeFocus.swift` (`endedFor`) | `core:home/HomeFocus.kt` | 3C | todo |
| 6.2-4 | Ended rows are dismissed per Mac | `ShellXAppCore/Home/EndedDismissals.swift` | `core:home/EndedDismissals.kt` | 3C | todo |
| 6.2-5 | A gone session removed from the phone stays removed for 30 days | `ShellXAppCore/Home/GoneRemovals.swift` | `core:home/GoneRemovals.kt` | 3C | todo |
| 6.2-6 | A needs-you item belongs to the newest live session of the same Mac, workspace and agent | `ShellXAppCore/Home/HomeFocus.swift` | `core:home/HomeFocus.kt` | 3C | todo |
| 6.2-7 | The home re-sorts every 30 s | `ShellX/UI/Workspaces/WorkspaceListView.swift` | `app:ui/workspaces/WorkspaceListView.kt` | 3D | todo |
| 6.2-8 | Reconnects after 0.5, 1, 2, 4, 8 and 15 s, then every 30 s, each ±20 %; back to the start on `welcome` | `ShellXAppCore/Link/ReconnectSchedule.swift`, `MachineConnection.swift` | `core:link/ReconnectSchedule.kt`, `MachineConnection.kt` | 3C | todo |
| 6.2-9 | A revision ≤ the current one is dropped, the next one is applied, a gap forces a full resync | `ShellXAppCore/Link/RevisionGate.swift` | `core:link/RevisionGate.kt` | 3C | todo |
| 6.2-10 | After a network change, waits 300 ms for it to settle, then reconnects | `ShellXAppCore/Link/NetworkChangeFilter.swift`, `MachineHub.swift` (`networkChanged`), `ShellX/Platform/NetworkPathWatcher.swift` | `core:link/NetworkChangeFilter.kt`, `MachineHub.kt`, `app:platform/NetworkPathWatcher.kt` (`ConnectivityManager`) | 3C (rule), 3D (watcher) | todo |
| 6.2-11 | In the background: 25 s grace, then the sessions close; on return, the Macs that are not online reconnect | `ShellXAppCore/Link/MachineHub.swift` (`backgroundGrace`) | `core:link/MachineHub.kt`, `ProcessLifecycleOwner` in `app:ShellXApplication.kt` | 3C (rule), 3D (hook) | todo |
| 6.2-12 | Decisions: resent once when there is no answer, then an error; offline is an error at once and never queued; "handled elsewhere" shows for 2 s; feedback ≤ 4 096 bytes | `ShellXAppCore/Pending/DecisionCenter.swift` | `core:pending/DecisionCenter.kt` | 3C | todo |
| 6.2-13 | A chat message ≤ 16 384 bytes | `ShellXAppCore/Home/ComposerValidation.swift` | `core:home/ComposerValidation.kt` | 3C | todo |
| 6.2-14 | An answer ≤ 1 024 bytes | `ShellXAppCore/Pending/QuestionDraft.swift` | `core:pending/QuestionDraft.kt` | 3C | todo |
| 6.2-15 | Attachments: at most 5, 10 MiB each | `shellx-link/Sources/ShellXLinkCore/ShellXLink.swift` | `shellx-link/kotlin/link-core/src/main/kotlin/com/shellx/link/core/ShellXLink.kt` | 3B | todo |
| 6.2-16 | The chat copy is saved at most 500 ms after its last change | `ShellXAppCore/Agent/AgentThreadModel.swift` (`saveDelay`) | `core:agent/AgentThreadModel.kt` | 3C | todo |
| 6.2-17 | A workspace the Mac has not listed is waited for 5 s before the Mac is asked again | `ShellXAppCore/Workspaces/WorkspaceScreenModel.swift` (`patience`) | `core:workspaces/WorkspaceScreenModel.kt` | 3C | todo |
| 6.2-18 | A notice over the composer shows for 4 s | `ShellX/UI/Agent/AgentView.swift` (`noticeDuration`) | `app:ui/agent/AgentView.kt` | 3E | todo |
| 6.2-19 | "Nothing needs you" shows for 0.7 s before the page goes back | `ShellX/UI/Pending/PendingListView.swift` (`leaveDelay`) | `app:ui/pending/PendingListView.kt` | 3E | todo |
| 6.2-20 | A voice result settles after 1.5 s (regular recognizer) or 2 s (on-device recognizer) | `ShellX/Voice/LegacyTranscriber.swift` (`finalResultTimeout`), `AnalyzerTranscriber.swift` (`finalizeTimeout`) | `app:voice/…` (`SpeechRecognizer`) | 3E | todo |
| 6.2-21 | Voice capabilities are cached for 30 s | `ShellXAppCore/Voice/VoiceCapabilityCache.swift` (`defaultReuse`) | `core:voice/VoiceCapabilityCache.kt` | 3C | todo |

## Android-only differences

| # | Difference | Why | Android | Plan | State |
| --- | --- | --- | --- | --- | --- |
| A-1 | Settings › Notifications › "Notifications arriving late?": a short guide per phone maker and a button that opens the app's system settings; no `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Xiaomi, OPPO and vivo hold FCM for apps swiped away (S3 §7.4c) | `app:ui/settings/…` | 3E | todo |
| A-2 | iPhone wording replaced in 14 strings: "iPhone" → "phone", "App Store" → "Google Play", "VoiceOver" → "TalkBack", Apple's servers → the phone's speech service. Names: `first_mac_step2`, `first_mac_subtitle`, `machine_state_revoked`, `machines_unpair_message`, `pairing_error_needs_update`, `pairing_instructions`, `pairing_waiting_detail`, `settings_account_sign_out_confirm`, `settings_appearance_system`, `settings_voice_on_device`, `settings_voice_server`, `signin_error_local_wipe_pending`, `update_message`, `voice_mic_hint` | The words match the iPhone's, except for platform names (S3 §7.2) | `shellx-android/app/src/main/res/values*/strings_android.xml` | 3A | done (3A) |
| A-3 | No Apple sign-in and no password sign-in | S3 §3 | — | — | differs (S3): by design |
| A-4 | Nothing is backed up or moved to a new phone (`allowBackup="false"`, and `data_extraction_rules.xml` excludes everything) | Secrets never go into a backup (S3 §7.3) | `AndroidManifest.xml`, `res/xml/data_extraction_rules.xml` | 3A | done (3A) |
| A-5 | On Android 12 and later, a system splash (the app icon on the ShellX background) shows before the launch screen | Android always shows one | `res/values*/themes.xml` | 3A | todo |

## Test devices

| Device | Maker and model | Android (API) | Used for | S3 §7.4c test |
| --- | --- | --- | --- | --- |
| `ShellX_Dev_API_26` (emulator) | Pixel 5 profile | 8.0 (26) | lowest supported version | no |
| `ShellX_Dev_API_36` (emulator) | Pixel 5 profile | 16 (36) | newest version | no |
| The user's phone | vsmart Live | 10 (29) | camera, voice, notifications, Vietnamese keyboard | no |

## iPhone changes since the reference

| Commit | iPhone change | Android row | State |
| --- | --- | --- | --- |
