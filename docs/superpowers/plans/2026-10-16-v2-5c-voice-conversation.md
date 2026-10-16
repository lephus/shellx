# ShellX V2-5c — Voice conversation with the AI on the phone (phase 1) Implementation Plan

Detail level: **compact** (V2-5 plan rules, 16/10): complete code only for the state machine, the tap-only permission layers, the native keep-screen-on channel and the C37 vendor patch; elsewhere exact names, values and tests.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A waveform button in the phone's AI composer opens a hands-free voice mode inside the same conversation: listen → auto-send after ~700 ms of silence → "working…" → read the prose of the answer aloud → listen again, with a tap-only answer to every permission request and nothing running when the app leaves the screen.

**Architecture:**
- **Pure Dart first** (C36): `speakable_text.dart` (markdown → spoken chunks, §7.3–7.6), `voice_phrases.dart` (§13.2), `ai_voice_reply.dart` (which turn and which text to read, §7.1), `endpointer.dart` + `voice_timings.dart` (§6, §5.3). Table tests, fake time.
- **Device seams:** `SpeechInput` gains a `ListenProfile` and a `levels` stream (C36); new `SpeechOutput` (over `flutter_tts`, C18) and `VoiceAudio` (over `audio_session` + the app channel `shellx/voice` for keep-screen-on, C20, C23). The iOS recognizer plugin is vendored in `third_party/speech_to_text` with its recognized-words `os_log` removed (C37).
- **`AiVoiceMode`** (new controller, not an extension of `AiDictation`): the 10-state machine of §5 with every timer a `Timer` (fake_async), talking to the session only through the narrow `AiVoicePort` (8 members, no answer function — §10 layer 1).
- **After B merges:** `AiVoiceBar` replaces B's composer card at the page bottom, `AiVoiceScreen` is an in-page overlay, `ai.voice` sits in B's reserved slot right of 🎙 (B T41), `AiSessionRoute(startVoice)` (C31).

**Tech Stack:** Dart 3.11.1 / Flutter 3.41.4 (`~/fvm/versions/3.41.4/bin`); `speech_to_text` 7.4.0 (vendored, path dependency); `flutter_tts` 4.2.5 (exact; R2); `audio_session` exact version pinned at execution (R2); signals + get_it + injectable + auto_route 11.1.0 + intl_utils on mobile; `fake_async` (already a dev dependency); `shellx_design` from V2-5a (`ShellxIcons` `voice*` roles, `ShellxGlass`, `ShellxWedge`, `ShellxGradients.accent`, `ShellxSegmented`, `ShellxDurations.of`).

**Spec:** `docs/superpowers/specs/2026-10-16-v2-5c-voice-conversation-design.md` (binding, Vietnamese; C1–C37, §4 UX, §5 state machine, §6 endpointing, §7 speakable text, §8 TTS, §9 audio session, §10 permissions, §12 settings, §13 strings, §16 tests, §17 Review Focus, §18 manual checks). Also: V2-5a plan header and Tasks 1–4 (`docs/superpowers/plans/2026-10-16-v2-5a-name-and-design-system.md`), V2-5a spec §7.4 (the eight `voice*` roles), V2-5b spec T19, T34, T38, T39, T41 (`docs/superpowers/specs/2026-10-16-v2-5b-ai-assistant-design.md`). Research: `SCRATCH/v25-research/{voice-current,references}.md` (`SCRATCH` = `/private/tmp/claude-501/-Users-richard-Documents-helper-shellx/c68aea52-eaaf-4b45-9a7d-989a8fedf901/scratchpad`).

## Prerequisite and order

- Worktree `/Users/richard/Documents/helper/shellx/.claude/worktrees/v2-5c`, branch `v2-5c`, made from `shellx-v2` after V2-5a is merged (C uses `ShellxIcons` and A's widgets). **Never push.** Ledger: `docs/superpowers/ledgers/v2-5c.md` (Task 1 creates it with the rulings below; every task appends its commits and counts).
- **Tasks 1–10 do not touch B's files** and may run while B is executed (C36 steps 1–4). They add keys to `intl_{en,vi}.arb`, `app_settings.dart` and the phone Settings page, which B also extends: append-only, merge conflicts are textual only.
- **Tasks 11–13 start after V2-5b is merged** into the base (they edit B's composer card T19/T39, B's open-session composer T38, and the session page as B leaves it). Task 14 is the final verification and the manual-check hand-off.
- Code read for this plan: `shellx-v2` `91b944b` (V2-2b, V2-3, V2-4 merged); `~/.pub-cache/hosted/pub.dev/speech_to_text-7.4.0` (the recognized-words log is `darwin/speech_to_text/Sources/speech_to_text/SpeechToTextPlugin.swift:699`, `os_log("Encoded JSON result: %{PUBLIC}@", …, speechStr)` inside `handleResult`; no other iOS log carries words; Android logs words only when `debugLogging` is passed, which ShellX never does). `flutter_tts` and `audio_session` are **not** in the pub cache (R2).

## Rulings (each with "cost if wrong")

Task 1 copies these into the ledger.

- **R1 — B's plan-level names win; reconcile at execution.** Spec B names only `AiComposerCard` (T19), `AiNewSessionRoute`, `AiProjectRoute`, `AiHomeRoute`, `HomeRoute`; it does not name the open-session composer of T38, the voice slot of T41 or the page's bottom slot. This plan calls them `AiOpenComposer` (T38), the parameter `voiceSlot` (T41) and "the composer slot" of `AiSessionPage` (T39). Where the V2-5b plan (written in parallel) chose other names, Tasks 11–13 use B's names; the reconciliation is a rename in C's files only. *Cost if wrong:* a rename.
- **R2 — package pins.** `flutter_tts: 4.2.5` exactly (the spec's reference, C18). `audio_session` is not in the pub cache, so its exact version cannot be verified here: the implementer of Task 7 runs `flutter pub add audio_session` once, reads the resolved version from `pubspec.lock`, writes **that exact version** (no caret) into `apps/mobile/pubspec.yaml`, and records it in the ledger. If 4.2.5 of `flutter_tts` does not resolve on Flutter 3.41.4 / Dart 3.11, pin the newest 4.x that resolves and record why. *Cost if wrong:* a pin bump.
- **R3 — read the pinned sources before coding the adapters (C18).** Task 6 greps the resolved `flutter_tts` for `network_required` (Android `getVoices`), `autoStopSharedSession`, the Android rate mapping and every `AVAudioSession` call; Task 7 reads `audio_session`'s `interruptionEventStream`, `becomingNoisyEventStream`, `AVAudioSession().currentRoute`. Findings go in the ledger. If `network_required` is absent, Android keeps every voice but `settingsVoiceFootnote` stays (it does not claim "offline only"), and the ledger notes that the privacy page must not say "only voices without network" (spec §20). *Cost if wrong:* a cloud voice may be used on Android.
- **R4 — `SpeechErrorKind.busy`.** Android `error_busy` / `error_client` (and `error_recognizer_busy`) map to a new `SpeechErrorKind.busy` so voice mode can retry them (C8) while `other` stays the on-device → cloud switch trigger. The two existing exhaustive switches (`ai_dictation.dart`, `voice_composer.dart`/its controller) treat `busy` exactly like `other` (one added pattern each). *Cost if wrong:* two one-line edits outside C's area.
- **R5 — an injected clock.** `AiVoiceMode` and `Endpointer` read time through `VoiceClock` (`Duration elapsed()` monotonic, `DateTime wall()`); production uses a `Stopwatch` and `DateTime.now`, tests `() => async.elapsed` and `base.add(async.elapsed)`. fake_async does not fake `Stopwatch`/`DateTime.now`. *Cost if wrong:* none.
- **R6 — the session end reasons stay outside the port.** "Session closed on the desktop / unavailable / moved to another sid" (C24) is detected by the page, which already watches them, and calls `AiVoiceMode.end(VoiceEndReason.sessionClosed)`; `AiVoicePort` keeps exactly the 8 members of §10 so layer 1's test pins them. *Cost if wrong:* none.
- **R7 — native code lives in the existing entry files.** The iOS channel is a `private enum ShellxVoiceChannel` inside `ios/Runner/AppDelegate.swift` (no new Swift file → no `project.pbxproj` edit; A's Task 1 also edits `didInitializeImplicitFlutterEngine`: keep both registrations). Android: `MainActivity.configureFlutterEngine`. Both also drop keep-screen-on when the app leaves the foreground, as a safety net under the Dart release. *Cost if wrong:* none.
- **R8 — haptics through a callback.** `AiVoiceMode` takes `void Function(VoiceHaptic) haptic` (`light` when the desktop took the message, `medium` when `needsYou` starts); production maps to `HapticFeedback.lightImpact` / `mediumImpact`. *Cost if wrong:* none.
- **R9 — announcements of `needsYou` speak in `needsYou`.** The permission/question phrase (§10) is spoken while the state already reads `needsYou` (label, warn colour, no tap action), not in `speaking`, so the bar never shows "Reading…" over a request. *Cost if wrong:* a cosmetic label.
- **R10 — "the working cue" speaks in `working`.** "Đang làm." (C14) is spoken inside a `beginSpeaking`/`endSpeaking` pair while the state stays `working`; a tap during it stops the cue and opens a queued listen (C10). *Cost if wrong:* none.
- **R11 — `rev = -1` means "text still streaming".** §7.1's wait applies when a chosen `MirrorText` has `rev == -1`; if the V2-2b mirror uses another marker the implementer adapts `VoiceTurnReply.pending` only. *Cost if wrong:* a 2 s wait never taken.
- **R12 — voice mode's plain-Dart files go under `lib/features/voice/domain/`** (spec §11 table) and the AI-specific ones under `lib/features/ai/…`; `VoiceModeState` and friends live in `ai_voice_mode.dart`. *Cost if wrong:* none.

## Global Constraints

Inherited from the V2-5a plan header (verbatim; commit scope `v2-voice`), then V2-5c's own.

- **Tooling:**
  - Flutter only via `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter …`; Dart via `~/fvm/versions/3.41.4/bin/dart` (Flutter 3.41.4 / Dart 3.11.1). After a `pubspec.yaml` change: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get` at the repo root.
  - `pubspec.lock` files are git-ignored and never added.
  - After a macOS desktop build in the worktree, revert only the `COCOAPODS:` line of `apps/desktop/macos/Podfile.lock`.
  - The mobile iOS `Podfile.lock` keeps `COCOAPODS: 1.16.2`; new pod lines are committed.
  - Mobile generated code: `PATH=~/fvm/versions/3.41.4/bin:$PATH dart run intl_utils:generate` then `PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/shared/src/l10n.dart lib/shared/src/intl/messages_en.dart lib/shared/src/intl/messages_vi.dart`; routes, DI, `fonts.gen.dart`, `assets.gen.dart`: `PATH=~/fvm/versions/3.41.4/bin:$PATH dart run build_runner build --delete-conflicting-outputs` in `apps/mobile`. Desktop strings: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n` in `apps/desktop`. Generated files are committed.
  - Format only the files a task touches (`dart format <files>`; mobile page width 120 from its `analysis_options.yaml`, everything else 80).
- **Every task that changes code ends green:** each touched package's analyze clean and tests passing, run from its directory:
  - `packages/shellx_design`, `apps/desktop`, `apps/mobile`: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze` and `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test` (the mobile analyze may show only the pre-existing info above);
  - `third_party/xterm` has no tests: the two apps' suites cover it.
- **Exact values come from the spec** (hex, sizes, roles, glyphs, strings, copied verbatim in the tasks). Product naming: "Claude" or "Claude Agent", never "Claude Code", in UI strings. Vietnamese strings are the spec's, word for word.
- **Security and privacy:** ShellX never reads, stores or relays credentials; never `--hide-claude-auth`; no `SHELLX_*` variable in an agent's environment; never auto-allow a permission request, never re-apply a remembered no-approval mode. No content in logs (the font loader logs only its reason). `toString()` of every new record returns `Name(…)`, pinned by a test.
- **SF Mono licence (A32, §6.2):** never bundled, never written to disk, cached, sent or logged; no SF Mono file anywhere in the repo or in a `fonts:` declaration (`no_bundled_sf_test.dart`); Android and Windows never ask for the family.
- **App launches:**
  - The desktop app is never launched on the user's real data. Any desktop launch or integration test uses the isolated recipe (Task 1 Step 9): a throw-away worktree, bundle id `pro.shellx.desktop.itest` (or `.smoketest`), a temporary `HOME` and `CFFIXED_USER_HOME`; from Task 2 on, such a build also has its own Keychain service (R1), so it never touches the real items. Never touch the `pro.shellx.desktop` preferences domain. **No full-app launch before Task 2 is done (R1).** Never `flutter test -d macos` or `flutter run` in the worktree.
  - iOS simulator runs of a test harness are allowed (boot your own simulator and shut it down after; leave simulators others booted alone). Real devices are manual checks for the user (§12).
- **Processes:** never `pkill`/`killall`; stop only processes you started, by PID.
- **Commits:** conventional messages (`feat(v2-voice): …`, `test(v2-voice): …`, `fix(v2-voice): …`, `docs(v2-voice): …`), at least one per task, each ending with the committing model's own trailer: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` or `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. ⚠ tasks are done with opus.
- **V2-5c's own constraints (spec header, C1–C37):**
  - Worktree `.claude/worktrees/v2-5c`, branch `v2-5c`; commit there, **never push, merge or force**. V2-5 stays off `main` until the user says so (a push to `main` releases the desktop app).
  - C may change: `apps/mobile` (voice, AI page and controllers, B's composer card **only** at the waveform button and B's hook for C (T41), settings, strings, the iOS/Android files of §11, `pubspec.yaml`, tests) and the new `third_party/speech_to_text` (C37). **Never:** protocols, any `packages/*` (including `shellx_design`: the eight `voice*` roles are already in A's `ShellxIcons`), desktop, relay, `web/**`.
  - Icons only through `ShellxIcons` roles: `voiceMode`, `voiceMicOn`, `voiceMicOff`, `voiceEnd`, `voiceStopTurn`, `voiceExpand`, `voiceCollapse`, `voiceNeedsYou` (§4.8). No `Icons.` and no direct `CupertinoIcons.` in C's new or changed files (test, Task 13).
  - Monospaced UI font (SF Mono / JetBrains Mono): no fixed text widths; one-line labels end in "…" with the full text in Semantics; captions wrap (C4, §4.2–4.5); no overflow at 320 pt with text scale 1.0 and 1.3.
  - **Never answer a permission or question by voice** (C26, §10): `AiVoiceMode` sees only `AiVoicePort`; mic closed in `needsYou`; an utterance pending when a request arrives goes to the draft.
  - **Half-duplex** (C20 O1): never `SpeechInput.start` while speaking or within 300 ms after; every `AiVoiceMode` test runs with the half-duplex guard.
  - **No content in logs** (C34): no utterance, caption, spoken chunk, request title or question in any log; only error kinds. `toString()` of `SpokenChunk`, `SpokenPart`, `SpokenReply`, `SpokenText`, `TtsVoice`, `VoiceAudioEvent`, `VoiceUtterance`, `VoiceTurnReply` returns `Name(…)`, pinned by tests.
  - Voices on the device only (C18): Android only `network_required == "0"`, always `setVoice`; never read Vietnamese with an English voice (C19).
  - No background audio: no `audio` in `UIBackgroundModes`; Android adds no permission (no `BLUETOOTH_CONNECT`, `FOREGROUND_SERVICE*`, `WAKE_LOCK`); no `wakelock_plus` (C23).
  - No protocol change, no capability flag: voice mode uses only `ai.open` and `ai.prompt` (C2, C3); works with every desktop since V2-2.
  - 🎙 dictation and the terminal voice box keep "send"/"gửi" as before (V2-2b B14); C does not change them except R4's one pattern.
  - Mobile commands (from `apps/mobile`): `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze` and `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test [file]`.

## Review Focus

Spec §17, each pinned by tests in the task that owns the code.

1. **Mic and voice overlap** (a restart timer, a late `SpeechListening(true)`, a cue spoken into a listen): the phone hears itself and sends the agent's answer back. Pinned by: Task 3 `HalfDuplexGuard` enabled in **every** `ai_voice_mode_test.dart` and `ai_voice_never_answers_test.dart` test; Task 8 tests "cue during listen is impossible", "late listening(true) after cancel is ignored".
2. **Wrong end of utterance:** half a sentence sent (slow recognizer, pause mid-sentence) or never sent in noise; `M` right for iOS but not Android. Pinned by: Task 4 `endpointer_test.dart` table (700/650 ms, 1 600 ms after filler, 1 500 ms text-only in noise, 1 000 ms without levels, both `M`); manual §18 items 4–6.
3. **Some path answers a permission or opens the mic while a request waits** (recompute, a timer, the end-of-utterance/request race). Pinned by: Task 9 `ai_voice_never_answers_test.dart` (four layers, complete code), Task 13 widget test (only a panel tap calls `answerPermission`, exactly once).
4. **Lifecycle leaks:** mic open after leaving the page or going to background, screen kept on, iOS session still ducking other apps, TTS still talking after End, voice mode running under another page. Pinned by: Task 8 tests (`end` releases `cancel`, `stop`, `exit`, `keepScreenOn(false)`); Task 13 lifecycle widget tests (`inactive`, `hidden`, `TickerMode` off, sheets, 2-minute away); manual §18 items 9–12.
5. **Reading the wrong thing:** thoughts, tool output, an old turn, the user's own words; one turn read twice after reconnect or "load more"; Vietnamese read by an English voice. Pinned by: Task 2 `speakable_text_test.dart`, Task 3 `ai_voice_reply_test.dart`, Task 8 "missing Vietnamese voice" test.

## File Structure

All paths under `apps/mobile/` unless noted.

| File | Responsibility | Task |
|---|---|---|
| Create `third_party/speech_to_text/**` (copy of 7.4.0, one line removed), `third_party/speech_to_text/SHELLX_PATCHES.md`; Modify `pubspec.yaml`; Create `test/voice/vendored_speech_to_text_test.dart`; Create `docs/superpowers/ledgers/v2-5c.md` (repo root) | C37 | 1 |
| Modify `lib/features/voice/domain/voice_locale.dart`; Create `lib/features/voice/domain/{speakable_text,voice_phrases}.dart`, `test/voice/{speakable_text,voice_phrases,voice_locale_phrases}_test.dart` | spoken text, phrases | 2 |
| Create `lib/features/ai/domain/ai_voice_reply.dart`, `test/ai/ai_voice_reply_test.dart` | what to read (§7.1) | 3 |
| Create `lib/features/voice/domain/{endpointer,voice_timings,voice_clock}.dart`, `test/voice/endpointer_test.dart` | end of utterance (§6) | 4 |
| Modify `lib/features/voice/domain/speech_input.dart`, `lib/features/voice/data/speech_to_text_input.dart`, `test/support/fake_speech.dart`, the two `SpeechErrorKind` switches (R4); Create `test/voice/speech_to_text_input_profile_test.dart`, `test/support/half_duplex_guard.dart` | profiles, levels | 5 |
| Create `lib/features/voice/domain/speech_output.dart`, `lib/features/voice/data/flutter_tts_output.dart`, `test/support/fake_speech_output.dart`, `test/voice/flutter_tts_output_test.dart`; Modify `pubspec.yaml` | TTS | 6 |
| Create `lib/features/voice/domain/voice_audio.dart`, `lib/features/voice/data/audio_session_voice_audio.dart`, `test/support/fake_voice_audio.dart`, `test/voice/audio_session_voice_audio_test.dart`; Modify `ios/Runner/AppDelegate.swift`, `android/.../MainActivity.kt`, `AndroidManifest.xml`, `ios/Runner/Info.plist`, `ios/Runner/{en,vi}.lproj/InfoPlist.strings`, `pubspec.yaml`, `test/platform_config_test.dart` | audio owner, keep-screen-on, platform files | 7 |
| Create `lib/features/ai/presentation/controllers/{ai_voice_port,ai_voice_mode}.dart`, `test/support/fake_voice_port.dart`, `test/ai/ai_voice_mode_test.dart` | the state machine | 8 |
| Create `lib/features/ai/presentation/controllers/session_voice_port.dart`, `test/ai/ai_voice_never_answers_test.dart` | tap-only layers | 9 |
| Modify `lib/core/settings/app_settings.dart`, `lib/l10n/intl_{en,vi}.arb` (+ generated), the phone Settings page; Create `lib/features/settings/presentation/widgets/voice_settings_group.dart`, `voice_picker_sheet.dart`, tests | settings, strings | 10 |
| Create `lib/features/voice/presentation/widgets/voice_wave.dart`, `lib/features/ai/presentation/widgets/ai_voice_bar.dart`, tests | the bar (after B) | 11 |
| Create `lib/features/voice/presentation/widgets/voice_orb.dart`, `lib/features/ai/presentation/widgets/ai_voice_screen.dart`, tests | the overlay (after B) | 12 |
| Modify B's `AiComposerCard` / `AiOpenComposer` (voice slot), `lib/features/ai/presentation/pages/ai_session_page.dart`, `lib/core/router/app_router.dart` (+ `.gr.dart`); tests | wiring (after B) | 13 |
| Modify ledger | verification, manual checks | 14 |

---

### Task 1: ⚠ Vendor `speech_to_text` 7.4.0 and drop its recognized-words log (C37), the ledger

**Files:**
- Create: `third_party/speech_to_text/` = a copy of `~/.pub-cache/hosted/pub.dev/speech_to_text-7.4.0/` without `example/` (keep `LICENSE`, `CHANGELOG.md`, `pubspec.yaml`, `lib/`, `android/`, `darwin/`, `test/`); `third_party/speech_to_text/SHELLX_PATCHES.md`
- Modify: `third_party/speech_to_text/darwin/speech_to_text/Sources/speech_to_text/SpeechToTextPlugin.swift` (`handleResult`), `apps/mobile/pubspec.yaml` (`speech_to_text:`), root `pubspec.yaml` only if the workspace needs it (it does not list `third_party/xterm`: keep it that way)
- Create: `apps/mobile/test/voice/vendored_speech_to_text_test.dart`, `docs/superpowers/ledgers/v2-5c.md`

**Interfaces:** Consumes nothing. Produces: the app resolves `speech_to_text` from `../../third_party/speech_to_text` (same Dart API 7.4.0).

- [ ] **Step 1: Ledger.** Create `docs/superpowers/ledgers/v2-5c.md` with the rulings R1–R12 (verbatim), a "Commits" table and a "Counts" line (mobile tests before C).
- [ ] **Step 2: Failing test** `test/voice/vendored_speech_to_text_test.dart` (runs from `apps/mobile`):

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// V2-5c C37: the iOS recognizer must never write recognized words to the unified log.
void main() {
  const vendor = '../../third_party/speech_to_text';
  final swift = File('$vendor/darwin/speech_to_text/Sources/speech_to_text/SpeechToTextPlugin.swift');

  test('the app depends on the vendored copy, pinned to 7.4.0', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('speech_to_text:\n    path: ../../third_party/speech_to_text'));
    expect(File('$vendor/pubspec.yaml').readAsStringSync(), contains('\nversion: 7.4.0\n'));
  });

  test('no os_log in the plugin carries recognized text', () {
    final source = swift.readAsStringSync();
    expect(source, isNot(contains('Encoded JSON result')));
    // Every os_log call (they may span lines) must not interpolate the result JSON or a transcription.
    final calls = RegExp(r'os_log\(([\s\S]*?)\)\s*\n').allMatches(source).map((m) => m.group(1)!);
    expect(calls, isNotEmpty);
    for (final call in calls) {
      expect(call, isNot(matches(RegExp(r'speechStr|speechInfo|transcription|formattedString|recognizedWords|bestTranscription'))),
          reason: 'an os_log call carries recognized text');
    }
  });

  test('the patch is the only change to handleResult and is documented', () {
    final source = swift.readAsStringSync();
    expect(source, contains('invokeFlutter(SwiftSpeechToTextCallbackMethods.textRecognition, arguments: speechStr)'));
    expect(File('$vendor/SHELLX_PATCHES.md').readAsStringSync(), contains('C37'));
  });
}
```

- [ ] **Step 3: Run, expect FAIL** (no vendor dir): `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/voice/vendored_speech_to_text_test.dart`.
- [ ] **Step 4: Vendor and patch.** `rsync -a --exclude example ~/.pub-cache/hosted/pub.dev/speech_to_text-7.4.0/ third_party/speech_to_text/`. In `handleResult` delete exactly this line (7.4.0 line 699):

```swift
        os_log("Encoded JSON result: %{PUBLIC}@", log: pluginLog, type: .debug, speechStr)
```

so the block reads:

```swift
      if let speechStr = String(data: speechMsg, encoding: .utf8) {
        invokeFlutter(SwiftSpeechToTextCallbackMethods.textRecognition, arguments: speechStr)
      }
```

`SHELLX_PATCHES.md`: "Upstream: speech_to_text 7.4.0 (pub.dev). Patch (V2-5c C37, 2026-10-16): removed the `os_log("Encoded JSON result: …")` debug line in `handleResult` — it wrote every recognized phrase to the unified log with `%{PUBLIC}`. To upgrade: copy the new release, re-apply this patch, run `test/voice/vendored_speech_to_text_test.dart`. Android logs words only with `debugLogging: true`, which ShellX never passes." In `apps/mobile/pubspec.yaml` replace `speech_to_text: 7.4.0` with:

```yaml
  # Vendored 7.4.0 with one patch (V2-5c C37): no recognized words in the iOS log.
  # See third_party/speech_to_text/SHELLX_PATCHES.md.
  speech_to_text:
    path: ../../third_party/speech_to_text
```

Add `third_party/speech_to_text/**` to `analysis_options.yaml` excludes only if the root analyzer picks it up (it is outside `apps/mobile`; check `flutter analyze` output). Then `flutter pub get` at the repo root and `cd apps/mobile/ios && pod install` (the pod now comes from the path; keep `COCOAPODS: 1.16.2`; commit `Podfile.lock`).
- [ ] **Step 5: Run, expect PASS**; then the full mobile suite (`flutter analyze`, `flutter test`): every dictation and terminal voice test unchanged and green.
- [ ] **Step 6: Commit** `fix(v2-voice): vendor speech_to_text 7.4.0 without its recognized-words log (C37)`

---

### Task 2: Speakable text and ShellX's spoken phrases (§7.3–7.6, §13.2, §13.3)

**Files:**
- Modify: `lib/features/voice/domain/voice_locale.dart` (`enum VoiceLocale`: new fields)
- Create: `lib/features/voice/domain/speakable_text.dart`, `lib/features/voice/domain/voice_phrases.dart`
- Test: `test/voice/speakable_text_test.dart`, `test/voice/voice_phrases_test.dart`, `test/voice/voice_locale_phrases_test.dart`

**Interfaces:**
- Consumes: `markdownBlocks` fence rule from `lib/features/ai/domain/ai_text.dart` (reuse the fence detection; do not change `ai_text.dart`'s behaviour).
- Produces:
  - `VoiceLocale` new fields: `Set<String> fillers`, `Set<String> connectors`, `Set<String> moreWords`, `Set<String> stopWords`, `String ttsLanguage` (`'vi-VN'` / `'en-US'`); methods `bool endsWithPause(String normalized)`, `bool onlyFillers(String normalized)`, `bool isMore(String normalized)`, `bool isStop(String normalized)`; top-level `String normalizeUtterance(String text)` (lower case, strip `\p{P}`, collapse spaces).
  - `final class SpokenChunk { const SpokenChunk(this.text, this.lang); final String text; final VoiceLocale lang; }`, `final class SpokenPart { final List<SpokenChunk> chunks; int get length; }`, `final class SpokenReply { final List<SpokenPart> parts; bool get isEmpty; }`, `final class SpokenText { final List<SpokenChunk> chunks; }` — all `toString()` = `'SpokenChunk(…)'` etc.
  - `SpokenReply speakableReply(List<String> markdownTexts, {required VoiceLocale mode, int filesChanged = 0})`; `SpokenText speakableLine(String text, {required VoiceLocale mode, required int maxChars})` (longer than `maxChars` → `VoicePhrases.of(mode).longTitle`); `VoiceLocale chunkLanguage(String chunk, VoiceLocale previous)`.
  - `abstract final class VoicePhrases { static VoicePhraseSet of(VoiceLocale l); }` and `final class VoicePhraseSet` with members `working`, `filesChanged(int n)`, `attached(String items)`, `codeBlocks(int n)`, `tables(int n)`, `images(int n)`, `and`, `onlyAttachments(String items)`, `snippet`, `link`, `more`, `stopped`, `notFinished`, `permission(String agent, String title)`, `permissionNext(String title)`, `longTitle`, `ask(String agent, String question)`, `askNoText(String agent)`, `cancelled`, `notSent`, `sample`; `String joinItems(List<String> items)` ("a, b and c").
  - Constants `kSpokenChunkMax = 240`, `kSpokenPartMax = 600`, `kInlineCodeMax = 32`.

- [ ] **Step 1: Failing tests.**
  - `speakable_text_test.dart`: the 17 rows of spec §7.6 verbatim as a table (`(input, mode, filesChanged) → [(text, lang)…]`):
    1 ``Đã sửa **logout()** trong `src/auth.ts`.`` → [vi] "Đã sửa logout trong auth.ts." · 2 "Thêm đoạn sau:" + ```` ```dart ```` block + "Rồi chạy test." → [vi] "Thêm đoạn sau: Kèm 1 khối mã. Rồi chạy test." · 3 only a table → [vi] "Câu trả lời là 1 bảng, xem trên màn hình." · 4 "All 42 tests passed and the build is green." → [en] same · 5 ``Chạy `npm test` xong rồi.`` → [vi] "Chạy npm test xong rồi." · 6 "Xem https://github.com/x/y/pull/12 nhé." → [vi] "Xem một đường link nhé." · 7 "- Sửa auth.ts\n- Thêm test" → [vi] "Sửa auth.ts. Thêm test." · 8 "Xong ✅ → deploy lên staging" → [vi] "Xong, deploy lên staging." · 9 ``Xem [README](https://example.com/readme).`` → [vi] "Xem README." · 10 ``Sửa `apps/mobile/lib/features/voice/domain/speakable_text.dart`.`` → [vi] "Sửa speakable_text.dart." · 11 ``Thêm `await Future.delayed(const Duration(seconds: 1))` vào đầu hàm.`` → [vi] "Thêm một đoạn mã vào đầu hàm." · 12 "biến snake_case_name giữ nguyên" → [vi] same · 13 `filesChanged: 2` → first chunk [vi] "Đã đổi 2 tệp." · 14 700 chars of prose → part 1 ≤ 600 chars, part 2 the rest · 15 two adjacent code blocks then a table → one insert "Kèm 2 khối mã và 1 bảng." · 16 mode EN, "Đã sửa xong." → [vi] same · 17 empty / whitespace → no parts.
  - Plus: chunk ≤ 240 chars, a 300-char sentence cut at the last `,` or space before 240; parts never split a chunk; `~~~` fences and 4-space indented blocks count as code; `<b>x</b>` reads "x"; `<https://a.b>` reads "một đường link"; "và/hoặc" kept; `->`/`=>`/`⇒` → comma; inserted sentence takes the previous chunk's language (EN: "Plus a code block and a table."); `SpokenChunk('x', VoiceLocale.vi).toString() == 'SpokenChunk(…)'` (and the other three types).
  - `voice_phrases_test.dart`: every §13.2 row verbatim in EN and VI (the table below), including singular forms `filesChanged(1)` EN "Changed 1 file.", `codeBlocks(1)` "a code block", `tables(1)` "a table", `images(1)` "an image"; `joinItems` → "1 khối mã và 1 bảng" / "a code block and a table".
  - `voice_locale_phrases_test.dart`: the §13.3 sets verbatim; "ừm" alone → `onlyFillers`; "sửa cái lỗi thì" → `endsWithPause`; "đọc tiếp đi" → `isMore`; "no thanks" → `isStop` (EN); `normalizeUtterance('Đọc tiếp, đi!') == 'đọc tiếp đi'`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** Pipeline of `speakableReply`: (a) split each text into blocks with the `markdownBlocks` fence rule + 4-space indent + table (a `|` line followed by `|---|`) + image lines; (b) a run of adjacent dropped blocks → one counted insert (`VoicePhrases.attached(joinItems([...codeBlocks(n), tables(n), images(n)]))`), placed where the run was; (c) inline rules in the order of §7.3's table (images → links `[t](u)` → bare URLs/`<https://…>` → inline code (path → last segment; ≤ 32 chars without `/`/`\` → kept; else `snippet`) → empty `()` after a word → bold/italic/strike markers (keep `_` inside words) → emoji `\p{Extended_Pictographic}` and `✓ ✗ •` removed → arrows to `,` → headings/list items/quotes become sentences with a final `.` if missing; horizontal rule = paragraph break; HTML tags stripped); (d) sentences end at `.` `!` `?` `…` `;` `:` + space or end of line; chunks ≤ 240; (e) language per chunk: Vietnamese letters `àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ` (+ upper case) → `vi`; else ≥ 3 words of ≥ 2 Latin letters → `en`; else previous (first: `mode`); (f) only dropped blocks → one chunk `onlyAttachments(items)`; (g) `filesChanged > 0` → first chunk `filesChanged(n)` in `mode`; (h) parts: consecutive chunks with total ≤ 600. Spoken phrase tables (verbatim):

| Khoá | EN | VI |
|---|---|---|
| `working` | Working on it. | Đang làm. |
| `filesChanged(n)` | Changed {n} files. (1: Changed 1 file.) | Đã đổi {n} tệp. |
| `attached(items)` | Plus {items}. | Kèm {items}. |
| `codeBlocks(n)` | {n} code blocks (1: a code block) | {n} khối mã |
| `tables(n)` | {n} tables (1: a table) | {n} bảng |
| `images(n)` | {n} images (1: an image) | {n} ảnh |
| `and` | and | và |
| `onlyAttachments(items)` | The answer is {items}; it's on the screen. | Câu trả lời là {items}, xem trên màn hình. |
| `snippet` | a code snippet | một đoạn mã |
| `link` | a link | một đường link |
| `more` | There's more. Keep reading? | Còn nữa. Đọc tiếp không? |
| `stopped` | Stopped. | Đã dừng. |
| `notFinished` | This turn didn't finish. Check the screen. | Lượt này chưa xong. Xem trên màn hình. |
| `permission(agent, title)` | {agent} needs your permission: {title}. Tap to answer on the screen. | {agent} cần bạn cho phép: {title}. Hãy chạm để trả lời trên màn hình. |
| `permissionNext(title)` | Another request: {title}. | Thêm một yêu cầu: {title}. |
| `longTitle` | a long task, on the screen | một việc dài, xem trên màn hình |
| `ask(agent, question)` | {agent} asks: {question}. Answer on the screen. | {agent} hỏi: {question}. Hãy trả lời trên màn hình. |
| `askNoText(agent)` | {agent} asks you something. Answer on the screen. | {agent} hỏi bạn. Hãy trả lời trên màn hình. |
| `cancelled` | Cancelled. | Đã huỷ. |
| `notSent` | It may not have been sent. Check the screen. | Có thể chưa gửi được. Xem trên màn hình. |
| `sample` | Hello. This is how I'll read the AI's answers. | Xin chào. Tôi sẽ đọc câu trả lời của AI như thế này. |

`{items}` joins with `and`: "Kèm 1 khối mã và 1 bảng." / "Plus a code block and a table.". Phrases ShellX recognizes (`VoiceLocale`, compared lower case without punctuation; §13.3 verbatim):

| Nhóm | VI | EN |
|---|---|---|
| Ngập ngừng (cuối câu → 1 600 ms; cả câu chỉ có chúng → bỏ) | ừm, ờ, ơ, à, ờm, hừm | um, uh, er, erm, hmm, uhm |
| Từ nối (cuối câu → 1 600 ms) | thì, là, mà, và, với, nhưng, hay, hoặc, của, để, cho, như, kiểu, rằng | and, but, or, so, because, the, a, an, to, of, with, like, then, if, that |
| "Tiếp" (cả câu, sau "Đọc tiếp không?") | đọc tiếp, đọc tiếp đi, tiếp, tiếp đi, có, ừ, ok, được | keep reading, continue, go on, read more, more, yes, yeah, ok, okay |
| "Thôi" (cả câu, sau "Đọc tiếp không?") | thôi, không, dừng, không cần, đủ rồi | no, stop, enough, that's enough, no thanks |
| Gửi / huỷ (từ cuối, C9) | gửi / huỷ, hủy | send / cancel |

- [ ] **Step 4: Run, expect PASS**; `flutter analyze`.
- [ ] **Step 5: Commit** `feat(v2-voice): speakable text and ShellX's spoken phrases (§7.3–7.6, §13.2–13.3)`

---

### Task 3: Which turn to read and which text (§7.1)

**Files:** Create `lib/features/ai/domain/ai_voice_reply.dart`; Test `test/ai/ai_voice_reply_test.dart`.

**Interfaces:**
- Consumes: `AiMirror.items`, `MirrorText(kind, turn, rev, text)`, `MirrorTool(turn)`, `MirrorTurnEnd(turn, outcome, files)`, `MirrorHead.turn?.index` (`package:shellx_ai`).
- Produces:
  - `enum VoiceTurnOutcome { finished, cancelled, unfinished }` (`interrupted`, `failed` → `unfinished`).
  - `final class VoiceTurnReply { final int turn; final List<String> texts; final int files; final VoiceTurnOutcome outcome; final bool pending; }` (`pending` = a chosen text has `rev == -1`, R11); `toString()` `'VoiceTurnReply(…)'`.
  - `final class VoiceReplyTracker { VoiceReplyTracker.start(AiMirror? mirror, MirrorHead? head); int get baseline; List<int> takeNewTurnEnds(AiMirror mirror); }` — baseline `B` = `head.turn.index - 1` when a turn runs, else the largest `turn` among the mirror's items (0 if none); `takeNewTurnEnds` returns the `MirrorTurnEnd.turn` values `> B` in ascending order and raises `B`.
  - `VoiceTurnReply? voiceTurnReply(AiMirror mirror, int turn)` — null when no `MirrorTurnEnd` for `turn`.
- [ ] **Step 1: Failing tests** (build mirrors with the V2-2b test helpers in `test/support/`): baseline while running (`turn.index` 4 → `B` 3, the end of turn 4 is taken) and while idle (largest turn); texts are only the agent `MirrorText`s after the last `MirrorTool` of the turn, in index order; none after a tool → the last agent text of the turn; never `thought`/user texts, tools, asks, notices; "load more" adding older turns (≤ `B`) → nothing; a reconnect replaying turn 5 again → nothing; `rev == -1` → `pending: true`; `finished` with `files: 2`, `cancelled`, `interrupted`/`failed` → `unfinished`; `toString()` hides text.
- [ ] **Step 2: Run, expect FAIL. Step 3: Implement** (pure Dart; the `MirrorTextKind` value for the agent's answer is the one `ai_items.dart` renders as agent prose). **Step 4: PASS**, analyze.
- [ ] **Step 5: Commit** `feat(v2-voice): pick each finished turn's answer exactly once (§7.1)`

---

### Task 4: End-of-utterance detection and the timing table (§6, §5.3)

**Files:** Create `lib/features/voice/domain/voice_timings.dart`, `voice_clock.dart`, `endpointer.dart`; Test `test/voice/endpointer_test.dart`.

**Interfaces:**
- Consumes: `normalizeUtterance`, `VoiceLocale.endsWithPause`, `onlyFillers` (Task 2).
- Produces: `VoiceTimings` (below), `VoiceClock`, `enum LevelScale { ios, android }`, `Endpointer` (below).

`voice_timings.dart` and `voice_clock.dart` (complete):

```dart
/// V2-5c §5.3: every voice-mode timer and threshold in one place.
abstract final class VoiceTimings {
  static const endpointSilence = Duration(milliseconds: 700);
  static const endpointAfterFiller = Duration(milliseconds: 1600);
  static const endpointNoiseExtra = Duration(milliseconds: 800);
  static const endpointNoLevelExtra = Duration(milliseconds: 300);
  static const levelsAliveWindow = Duration(milliseconds: 500);
  static const floorWarmup = Duration(milliseconds: 300);
  static const floorRise = Duration(seconds: 3);
  static const tick = Duration(milliseconds: 50);
  static const finalWait = Duration(milliseconds: 600);
  static const listenDoneWait = Duration(milliseconds: 500);
  static const segmentSoft = Duration(seconds: 45);
  static const segmentQuiet = Duration(milliseconds: 250);
  static const segmentMax = Duration(seconds: 55);
  static const restartRetry = Duration(milliseconds: 500);
  static const restartRetryMax = 3;
  static const restartRetryWindow = Duration(seconds: 10);
  static const postSpeakGuard = Duration(milliseconds: 300);
  static const bluetoothSettle = Duration(milliseconds: 250);
  static const silenceBudgetIos = Duration(seconds: 30);
  static const silenceBudgetAndroid = Duration(seconds: 15);
  static const utteranceMax = Duration(seconds: 120);
  static const workingCue = Duration(milliseconds: 2500);
  static const turnTextWait = Duration(seconds: 2);
  static const linkGrace = Duration(seconds: 30);
  static const awayMax = Duration(minutes: 2);
  static const screenOnIdleMax = Duration(minutes: 10);
  static const idleLabelDelay = Duration(milliseconds: 400);
  static const startVoiceWait = Duration(seconds: 10);
  static const settle = Duration(milliseconds: 400); // the page's _kSettle (panel, Stop)
  /// Speech margin above the noise floor (§6): dBFS on iOS, `rmsdB` on Android. Tune after §18 item 6.
  static const speechMarginIos = 12.0;
  static const speechMarginAndroid = 3.0;
}
```

```dart
/// R5: fake_async fakes Timer, not Stopwatch or DateTime.now.
final class VoiceClock {
  VoiceClock(this.elapsed, this.wall);
  factory VoiceClock.system() {
    final watch = Stopwatch()..start();
    return VoiceClock(() => watch.elapsed, DateTime.now);
  }
  final Duration Function() elapsed;
  final DateTime Function() wall;
}
```

`endpointer.dart` (complete — the timing core of the state machine):

```dart
import 'dart:math' as math;

import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';
import 'package:shellx_mobile/features/voice/domain/voice_timings.dart';

enum LevelScale { ios, android }

/// V2-5c §6. Pure: the caller feeds text, levels and the clock; [shouldSend] answers rule 1–4.
final class Endpointer {
  Endpointer({required this.locale, required this.scale});

  VoiceLocale locale;
  final LevelScale scale;

  final List<String> _committed = [];
  String _partial = '';
  String _normalized = '';
  Duration? _lastWords;
  Duration? _lastVoice;
  Duration? _lastLevel;
  Duration _segmentStart = Duration.zero;
  Duration _listenStart = Duration.zero;
  double? _floor;
  Duration? _floorAt;

  double get _margin => scale == LevelScale.ios ? VoiceTimings.speechMarginIos : VoiceTimings.speechMarginAndroid;

  /// The utterance so far: committed segments + the current partial.
  String get text => [..._committed, if (_partial.isNotEmpty) _partial].join(' ').trim();
  bool get hasWords => _normalized.isNotEmpty && !locale.onlyFillers(_normalized);
  Duration? get lastWords => _lastWords;
  Duration? get lastVoice => _lastVoice;
  double? get floor => _floor;

  void beginListen(Duration now) {
    _committed.clear();
    _partial = '';
    _normalized = '';
    _lastWords = null;
    _lastVoice = null;
    _lastLevel = null;
    _listenStart = now;
    beginSegment(now);
  }

  /// A new OS listen inside the same utterance (C8): the floor is learnt again.
  void beginSegment(Duration now) {
    _segmentStart = now;
    _floor = null;
    _floorAt = null;
  }

  void onPartial(String words, Duration now) => _setPartial(words, now);

  /// The OS final of one segment: it becomes committed text.
  void onSegmentFinal(String words, Duration now) {
    _setPartial(words, now);
    if (_partial.isNotEmpty) _committed.add(_partial);
    _partial = '';
  }

  void _setPartial(String words, Duration now) {
    _partial = words.trim();
    final n = normalizeUtterance(text);
    if (n != _normalized) {
      _normalized = n;
      _lastWords = now; // punctuation or case changes alone do not count (§6)
    }
  }

  void onLevel(double x, Duration now) {
    _lastLevel = now;
    final floor = _floor;
    if (floor == null || now - _segmentStart < VoiceTimings.floorWarmup) {
      _floor = floor == null ? x : math.min(floor, x);
      _floorAt = now;
      return;
    }
    if (x < floor) {
      _floor = x;
    } else {
      final dt = (now - (_floorAt ?? now)).inMicroseconds / Duration.microsecondsPerSecond;
      final rise = VoiceTimings.floorRise.inMicroseconds / Duration.microsecondsPerSecond;
      _floor = floor + (x - floor) * (1 - math.exp(-dt / rise));
    }
    _floorAt = now;
    if (x >= floor + _margin) _lastVoice = now;
  }

  bool levelsAlive(Duration now) => _lastLevel != null && now - _lastLevel! <= VoiceTimings.levelsAliveWindow;

  Duration get _need {
    final words = _normalized.split(' ');
    return locale.endsWithPause(words.isEmpty ? '' : words.last)
        ? VoiceTimings.endpointAfterFiller
        : VoiceTimings.endpointSilence;
  }

  /// Rules 1–4 of §6.
  bool shouldSend(Duration now) {
    if (!hasWords || _lastWords == null) return false; // rule 1
    final need = _need; // rule 2
    if (levelsAlive(now)) {
      final last = _lastVoice == null || _lastWords! > _lastVoice! ? _lastWords! : _lastVoice!;
      return now - last >= need || now - _lastWords! >= need + VoiceTimings.endpointNoiseExtra; // rule 3
    }
    return now - _lastWords! >= need + VoiceTimings.endpointNoLevelExtra; // rule 4
  }

  /// Rule 7 (iOS): a soft restart at a ≥ 250 ms pause once the segment is 45 s old.
  bool shouldSoftRestart(Duration now) {
    if (now - _segmentStart < VoiceTimings.segmentSoft) return false;
    final last = [_lastWords, _lastVoice].whereType<Duration>().fold(_segmentStart, (a, b) => a > b ? a : b);
    return now - last >= VoiceTimings.segmentQuiet;
  }

  /// C29: counted from max(listen start, lastVoice, lastWords).
  bool silenceBudgetSpent(Duration now, Duration budget) {
    final last = [_listenStart, _lastWords, _lastVoice].whereType<Duration>().reduce((a, b) => a > b ? a : b);
    return !hasWords && now - last >= budget;
  }

  bool tooLong(Duration now) => hasWords && now - _listenStart >= VoiceTimings.utteranceMax;
}
```

`VoiceLocale.endsWithPause(String lastWord)` takes the last normalized word (Task 2 signature: rename the parameter to `lastWord`; it checks `fillers ∪ connectors`).

- [ ] **Step 1: Failing tests** `endpointer_test.dart` (time as plain `Duration`s, no timers): words at t=0 + levels at floor → `shouldSend` false at 650 ms, true at 700 ms; last word "thì" / "and" → false at 1 550 ms, true at 1 600 ms; noise forever (`onLevel` = floor + 20 dB every 20 ms) → true at 1 500 ms after last words (700 + 800); no levels → false at 950 ms, true at 1 000 ms; "Sửa lỗi." → "sửa lỗi" (punctuation-only change) does not reset `lastWords`; no words → never; "ừm" only → never (`hasWords` false); floor rises slowly (a step of +20 dB is ~half-absorbed after ~2 s, i.e. `1 − e^(−2/3)` ≈ 0.49) and falls at once; `speechMarginIos == 12.0`, `speechMarginAndroid == 3.0`; `shouldSoftRestart` false at 44.9 s, true at 45 s + 250 ms quiet; silence budget counts from `lastVoice` (voice at 20 s → not spent at 30 s with the iOS budget, spent at 50 s); `tooLong` at 120 s with words.
- [ ] **Step 2: FAIL. Step 3: Implement** (code above). **Step 4: PASS**, analyze.
- [ ] **Step 5: Commit** `feat(v2-voice): end-of-utterance detection from words and levels (§6)`

---

### Task 5: `SpeechInput` profiles and levels; the half-duplex guard (C8, C22, C36, R4)

**Files:** Modify `lib/features/voice/domain/speech_input.dart`, `lib/features/voice/data/speech_to_text_input.dart`, `test/support/fake_speech.dart`, the `SpeechErrorKind` switches in `ai_dictation.dart` and the terminal voice controller (R4); Create `test/support/half_duplex_guard.dart`, `test/voice/speech_to_text_input_profile_test.dart`.

**Interfaces:**
- Produces: `enum ListenProfile { dictation, conversation }`; `SpeechInput.start(String localeId, {required bool onDevice, ListenProfile profile = ListenProfile.dictation})`; `Stream<double> get levels` (broadcast; only during `conversation` listens); `SpeechErrorKind.busy`; `speechErrorKind('error_busy' | 'error_client' | 'error_recognizer_busy') == SpeechErrorKind.busy`.
- `FakeSpeechInput`: `starts` records `({String localeId, bool onDevice, ListenProfile profile})`; `void emitLevel(double x)`; `HalfDuplexGuard? guard` — `start` calls `guard?.onListenStart()`.
- `HalfDuplexGuard(Duration Function() now)`: `void onSpeakStart()`, `void onSpeakEnd()`, `void onListenStart()` → `fail('listen started while speaking or within 300 ms after')` when speaking or `now() - lastSpeakEnd < VoiceTimings.postSpeakGuard`.
- [ ] **Step 1: Failing tests** with a fake `SpeechToTextPlatform` (as the existing adapter tests do): `dictation` → `pauseFor` 2 s, `listenFor` 60 s, `partialResults`, `ListenMode.dictation`, `cancelOnError` (unchanged); `conversation` → `pauseFor` null, `listenFor` 55 s, `partialResults`, `ListenMode.dictation`, `cancelOnError`, `autoPunctuation: true`, `onSoundLevelChange` set; `initialize` passes `options: [SpeechToText.androidNoBluetooth]` (C22, for every use); `levels` emits only in `conversation`; `busy` mapping; guard test: `onListenStart` 200 ms after `onSpeakEnd` fails, 300 ms passes.
- [ ] **Step 2: FAIL. Step 3: Implement**; existing dictation/terminal tests compile unchanged (default profile). **Step 4: PASS** + full mobile suite.
- [ ] **Step 5: Commit** `feat(v2-voice): a conversation listen profile with sound levels (C8, C22)`

---

### Task 6: `SpeechOutput` over `flutter_tts` (C18, C19, §8)

**Files:** Create `lib/features/voice/domain/speech_output.dart`, `lib/features/voice/data/flutter_tts_output.dart`, `test/support/fake_speech_output.dart`, `test/voice/flutter_tts_output_test.dart`; Modify `pubspec.yaml` (`flutter_tts: 4.2.5`, R2).

**Interfaces:**
- Produces (verbatim §8):

```dart
enum SpeakResult { done, stopped, failed, noVoice }
enum TtsQuality { normal, enhanced, premium }

final class TtsVoice {
  const TtsVoice({required this.id, required this.name, required this.locale, this.quality = TtsQuality.normal});
  final String id; // iOS identifier, Android name (§12)
  final String name;
  final VoiceLocale locale;
  final TtsQuality quality;
  @override
  String toString() => 'TtsVoice(…)';
}

abstract interface class SpeechOutput {
  Future<Map<VoiceLocale, List<TtsVoice>>> voices(); // on-device voices only
  Future<void> configure({required double rate, required Map<VoiceLocale, String?> voiceIds});
  Future<SpeakResult> speak(String text, VoiceLocale lang);
  Future<void> stop();
  /// The voice [speak] would use for [lang], or null (C19).
  TtsVoice? voiceFor(VoiceLocale lang);
}
```

- `FakeSpeechOutput implements SpeechOutput`: `spoken` list of `({String text, VoiceLocale lang})`; `void finishCurrent([SpeakResult r = SpeakResult.done])`; `Map<VoiceLocale, List<TtsVoice>> available`; `int stops`; `HalfDuplexGuard? guard` (`speak` → `onSpeakStart`, completion → `onSpeakEnd`); `bool get speaking`.
- [ ] **Step 0 (R3):** `flutter pub get`; read `~/.pub-cache/hosted/pub.dev/flutter_tts-4.2.5/` (Dart, `ios/Classes/*.swift`, `android/src/**/*.kt`): confirm `network_required` in Android `getVoices`, `autoStopSharedSession`, `setSharedInstance`, the Android rate mapping (whether `0.5` = normal), every `AVAudioSession` call. Record in the ledger.
- [ ] **Step 1: Failing tests** with a fake `MethodChannel('flutter_tts')` handler: `configure` calls `awaitSpeakCompletion(true)`, Android `setQueueMode(0)`, iOS `autoStopSharedSession(false)`; rate 0.85/1.0/1.2 → `setSpeechRate(0.425 / 0.5 / 0.6)`; Android voices with `network_required: "1"` dropped; default voice: iOS highest quality (premium > enhanced > normal); Android engine default if offline else first offline; a stored id missing → default, no error; `speak` always `setVoice` before `speak` (never only `setLanguage`); no voice for the language → `SpeakResult.noVoice` without a channel call; plugin error → `failed`, log line has only the error type.
- [ ] **Step 2: FAIL. Step 3: Implement** `@LazySingleton(as: SpeechOutput) class FlutterTtsOutput`. **Step 4: PASS**, regenerate DI (`build_runner`), analyze.
- [ ] **Step 5: Commit** `feat(v2-voice): on-device text-to-speech behind SpeechOutput (C18)`

---

### Task 7: ⚠ `VoiceAudio`: the audio-session owner and native keep-screen-on (C20–C23, C33, §9)

**Files:** Create `lib/features/voice/domain/voice_audio.dart`, `lib/features/voice/data/audio_session_voice_audio.dart`, `test/support/fake_voice_audio.dart`, `test/voice/audio_session_voice_audio_test.dart`; Modify `ios/Runner/AppDelegate.swift`, `android/app/src/main/kotlin/com/shellx/prod/MainActivity.kt`, `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`, `ios/Runner/en.lproj/InfoPlist.strings`, `ios/Runner/vi.lproj/InfoPlist.strings`, `pubspec.yaml` (`audio_session` exact, R2), `test/platform_config_test.dart`.

**Interfaces:**
- Produces (§9):

```dart
enum VoiceInterruptionKind { pause, duck, unknown }

sealed class VoiceAudioEvent {
  const VoiceAudioEvent();
  @override
  String toString() => 'VoiceAudioEvent(…)';
}
final class VoiceInterrupted extends VoiceAudioEvent {
  const VoiceInterrupted({required this.begin, required this.kind});
  final bool begin;
  final VoiceInterruptionKind kind;
}
final class VoiceNoisy extends VoiceAudioEvent { const VoiceNoisy(); }

abstract interface class VoiceAudio {
  Future<void> enter();          // keepScreenOn(true) (C23)
  Future<void> beginSpeaking();  // configure + activate (O2–O4); +250 ms on iOS Bluetooth HFP output (C22)
  Future<void> endSpeaking();    // deactivate with notifyOthersOnDeactivation (iOS) / abandon focus (Android)
  Future<void> keepScreenOn(bool on);
  Future<void> exit();           // endSpeaking if active, keepScreenOn(false)
  Stream<VoiceAudioEvent> get events;
}
```

- `FakeVoiceAudio`: `calls` list of `'enter' | 'begin' | 'end' | 'exit' | 'screen:true' | 'screen:false'`; `void interrupt({bool begin = true, VoiceInterruptionKind kind = VoiceInterruptionKind.pause})`; `void noisy()`; `bool screenOn`.
- **Configuration (O3/O4, exact):** `AudioSessionConfiguration(avAudioSessionCategory: AVAudioSessionCategory.playAndRecord, avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker | AVAudioSessionCategoryOptions.allowBluetooth | AVAudioSessionCategoryOptions.allowBluetoothA2dp | AVAudioSessionCategoryOptions.duckOthers, avAudioSessionMode: AVAudioSessionMode.defaultMode, androidAudioAttributes: const AndroidAudioAttributes(contentType: AndroidAudioContentType.speech, usage: AndroidAudioUsage.assistant), androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck)`, applied **before every** `beginSpeaking` (the recognizer plugin resets the category after each listen). `endSpeaking`: `setActive(false, avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation)`. HFP check: `AVAudioSession().currentRoute` outputs contain `AVAudioSessionPort.bluetoothHfp` → `await Future.delayed(VoiceTimings.bluetoothSettle)`. Events: `interruptionEventStream` → `VoiceInterrupted(begin, kind: duck → duck, pause → pause, else unknown)`; `becomingNoisyEventStream` → `VoiceNoisy`.
- **Channel:** `MethodChannel('shellx/voice')`, method `keepScreenOn`, argument `bool`.

Swift — add to `ios/Runner/AppDelegate.swift` (complete; R7). In `didInitializeImplicitFlutterEngine`, after `GeneratedPluginRegistrant.register(...)` (and next to A's `SystemMonoFont` registration if present):

```swift
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ShellxVoice") {
      ShellxVoiceChannel.register(with: registrar)
    }
```

and at file end:

```swift
/// V2-5c C23: keeps the screen on while voice mode is open (no permission, no background mode).
/// Dart turns it off when voice mode ends; leaving the foreground turns it off too, as a safety net.
private enum ShellxVoiceChannel {
  private static var observer: NSObjectProtocol?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "shellx/voice", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "keepScreenOn":
        guard let on = call.arguments as? Bool else {
          result(FlutterError(code: "bad_args", message: "keepScreenOn takes a Bool", details: nil))
          return
        }
        DispatchQueue.main.async {
          UIApplication.shared.isIdleTimerDisabled = on
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    observer = NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
    ) { _ in
      UIApplication.shared.isIdleTimerDisabled = false
    }
  }
}
```

Kotlin — `MainActivity.kt` (complete file after the change):

```kotlin
package com.shellx.prod

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// local_auth shows BiometricPrompt, which needs a FragmentActivity.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    // V2-5c C23: keeps the screen on while voice mode is open. FLAG_KEEP_SCREEN_ON needs no permission
    // (no WAKE_LOCK) and only applies while this window is visible.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shellx/voice").setMethodCallHandler { call, result ->
            when (call.method) {
                "keepScreenOn" -> {
                    val on = call.arguments as? Boolean
                    if (on == null) {
                        result.error("bad_args", "keepScreenOn takes a Boolean", null)
                    } else {
                        runOnUiThread {
                            if (on) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                            result.success(null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // Safety net under the Dart release: leaving the foreground ends voice mode (C24).
    override fun onStop() {
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        super.onStop()
    }

    // Push notifications arrive on this channel (AndroidManifest: FCM's
    // default_notification_channel_id). Creating it again only updates its name and description,
    // so a language change shows up; the user's own channel settings are kept. minSdk is 26, so
    // channels always exist.
    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            getString(R.string.notification_channel_id),
            getString(R.string.notification_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        )
        channel.description = getString(R.string.notification_channel_description)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
}
```

- **Manifest (C33):** inside the existing `<queries>` add `<intent><action android:name="android.intent.action.TTS_SERVICE"/></intent>`; no permission added.
- **iOS usage strings (C33, §13.4 verbatim):**


| Khoá (iOS) | EN (`Info.plist`, `en.lproj`) | VI (`vi.lproj`) |
|---|---|---|
| `NSMicrophoneUsageDescription` | ShellX uses the microphone when you tap the mic to speak into your terminal or an AI session, and while voice mode is open in an AI session. It never listens in the background. | ShellX dùng micro khi bạn chạm nút mic để nói vào terminal hoặc phiên AI, và khi chế độ giọng nói đang mở trong một phiên AI. ShellX không nghe khi chạy nền. |
| `NSSpeechRecognitionUsageDescription` | ShellX turns what you say into text for your terminal or an AI session, including voice mode, using Apple's speech recognition, which may process it on your phone or on Apple's servers. | ShellX chuyển lời bạn nói thành chữ cho terminal hoặc phiên AI, kể cả ở chế độ giọng nói, bằng tính năng nhận dạng giọng nói của Apple; Apple có thể xử lý ngay trên điện thoại hoặc trên máy chủ của Apple. |

`Info.plist` (EN) and `en.lproj/InfoPlist.strings` take the EN column, `vi.lproj` the VI column; keep "ShellX" short (V2-5a A1).

- [ ] **Step 1: Failing tests.** `audio_session_voice_audio_test.dart` (fake `MethodChannel('shellx/voice')` + a fake `AudioSession` seam): `enter` → `keepScreenOn(true)`; `beginSpeaking` configures (exact options above) then activates, every time; `endSpeaking` deactivates with `notifyOthersOnDeactivation`; `exit` → end + `keepScreenOn(false)`; events mapped. `platform_config_test.dart`: both iOS strings in both languages contain "voice mode" / "chế độ giọng nói" and still the pinned phrases ("ShellX dùng micro", "your terminal or an AI session", "phiên AI", "AI session"); `UIBackgroundModes` has no `audio`; manifest has the `TTS_SERVICE` query and no `BLUETOOTH_CONNECT`, `FOREGROUND_SERVICE`, `WAKE_LOCK`; `AppDelegate.swift` and `MainActivity.kt` contain `"shellx/voice"` and `keepScreenOn`; `pubspec.yaml` has `flutter_tts: 4.2.5` and `audio_session: <exact>` (regex `audio_session: \d+\.\d+\.\d+$`).
- [ ] **Step 2: FAIL. Step 3: Implement**; `pod install` (commit `Podfile.lock`, `COCOAPODS: 1.16.2`). **Step 4: PASS**; `flutter build apk --debug` and `flutter build ios --simulator --no-codesign` compile the native code (no launch).
- [ ] **Step 5: Commit** `feat(v2-voice): one audio-session owner and native keep-screen-on (C20–C23)`

---

### Task 8: ⚠ `AiVoiceMode`: the 10-state machine and its timers (§5, C6–C15, C24–C30)

**Files:** Create `lib/features/ai/presentation/controllers/ai_voice_port.dart`, `ai_voice_mode.dart`, `test/support/fake_voice_port.dart`, `test/ai/ai_voice_mode_test.dart`.

**Interfaces:**
- Consumes: Tasks 2–7 (`Endpointer`, `VoiceTimings`, `VoiceClock`, `VoiceReplyTracker`, `voiceTurnReply`, `speakableReply`, `speakableLine`, `VoicePhrases`, `SpeechInput`/`ListenProfile`, `SpeechOutput`, `VoiceAudio`).
- Produces: `AiVoicePort` (8 members, §10 layer 1), `AiVoiceMode` with signals `state`, `pause`, `errorKind`, `sendCode`, `caption`, `level`, `muted`, `locale`, `askingMore`, `notices`, `turnStartedAt`; methods `start`, `tapOrb`, `toggleMute`, `switchLocale`, `continueReading`, `retry`, `setCovered`, `appLifecycle`, `setScreenReader`, `end`, `dispose`.

`ai_voice_port.dart` (complete):

```dart
import 'package:shellx_ai/shellx_ai.dart';
import 'package:signals/signals.dart';

/// V2-5c §10 layer 1: everything voice mode may see or do in a session. There is deliberately no way to
/// answer a permission request or a question, change config or mode, or revert: those stay on the
/// page's buttons. Adding a member here must break `ai_voice_never_answers_test.dart`.
abstract interface class AiVoicePort {
  ReadonlySignal<int> get version;
  MirrorHead? get head;
  AiMirror? get mirror;
  AiLinkState get linkState;
  bool get canSend;
  /// null when the desktop took the message, else an `AiWords.failure` code.
  Future<String?> send(String text);
  Future<String?> stopTurn();
  /// C3: an utterance that could not be sent goes into the composer (appended on a new line).
  void putInDraft(String text);
}
```

`ai_voice_mode.dart` (complete; the implementer fixes only compile-level details):

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/ai/domain/ai_voice_reply.dart';
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_voice_port.dart';
import 'package:shellx_mobile/features/voice/domain/endpointer.dart';
import 'package:shellx_mobile/features/voice/domain/speakable_text.dart';
import 'package:shellx_mobile/features/voice/domain/speech_input.dart';
import 'package:shellx_mobile/features/voice/domain/speech_output.dart';
import 'package:shellx_mobile/features/voice/domain/voice_audio.dart';
import 'package:shellx_mobile/features/voice/domain/voice_clock.dart';
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';
import 'package:shellx_mobile/features/voice/domain/voice_phrases.dart';
import 'package:shellx_mobile/features/voice/domain/voice_timings.dart';
import 'package:signals/signals.dart';

enum VoiceModeState { idle, listening, hearing, sending, working, speaking, paused, needsYou, error, ended }

enum VoicePause { muted, silence, away, interrupted, route, reconnecting, linkLost, tooLong, queueFull, cantSend, tapToTalk }

enum VoiceError { noPermission, unsupported, localeUnavailable, network, failed, sendFailed }

enum VoiceNotice { noVoiceVi, noVoiceEn, readFailed, draftKept, notSent }

enum VoiceEndReason { user, background, pageClosed, sessionClosed, awayTooLong }

enum VoiceHaptic { light, medium }

/// What [AiVoiceMode.start] needs from Settings (§12), read once per start.
final class VoiceModeConfig {
  const VoiceModeConfig({required this.locale, required this.readAloud, required this.rate, required this.voiceIds, required this.levelScale, required this.silenceBudget});
  final VoiceLocale locale;
  final bool readAloud;
  final double rate;
  final Map<VoiceLocale, String?> voiceIds;
  final LevelScale levelScale;
  final Duration silenceBudget;
}

/// What the 300 ms post-speak guard does when it ends (§5.4: the only way from speaking back to the mic).
enum _AfterGuard { recompute, listen, listenQueue }

/// One reading in the FIFO: a turn's spoken parts, or a single ShellX phrase.
final class _Reading {
  _Reading(this.parts, {this.turn});
  final List<SpokenPart> parts;
  final int? turn;
  int part = 0;
  int chunk = 0;
  bool get done => part >= parts.length;
}

/// V2-5c §5: listen → send → work → speak → listen, half-duplex, tap-only answers.
@injectable
class AiVoiceMode {
  AiVoiceMode(this._speech, this._tts, this._audio, {VoiceClock? clock, void Function(VoiceHaptic)? haptic})
      : _clock = clock ?? VoiceClock.system(),
        _haptic = haptic ?? _systemHaptic;

  final SpeechInput _speech;
  final SpeechOutput _tts;
  final VoiceAudio _audio;
  final VoiceClock _clock;
  final void Function(VoiceHaptic) _haptic;

  final state = signal(VoiceModeState.ended);
  final pause = signal<VoicePause?>(null);
  final errorKind = signal<VoiceError?>(null);
  final sendCode = signal<String?>(null);
  final caption = signal<String?>(null);
  final level = signal(0.0);
  final muted = signal(false);
  final locale = signal(VoiceLocale.vi);
  final askingMore = signal(false);
  final notices = signal<Set<VoiceNotice>>(const {});
  final idleLabel = signal(false);
  final queueMode = signal(false);

  late AiVoicePort _port;
  late VoiceModeConfig _config;
  late Endpointer _ep;
  VoiceReplyTracker? _tracker;
  String? _localeId;
  bool _onDevice = true;
  bool _cloudSwitched = false;
  final Set<VoiceLocale> _unrecognizable = {};

  // Flags of §5.1.
  bool _covered = false;
  bool _resumed = true;
  bool _screenReader = false;
  bool _userTapped = false;

  bool _preparing = false;

  // Mic bookkeeping (O1).
  bool _segmentOpen = false;
  bool _finalizing = false;
  bool _aborting = false; // events of a listen being cancelled are dropped
  bool _restarting = false; // the done of a segment we restart ourselves is not "the OS ended it"
  bool _sendInFlight = false;
  Completer<void>? _segmentDone;
  Completer<String?>? _finalWaiter;
  final List<Duration> _retries = [];

  // Speaking bookkeeping.
  final List<_Reading> _fifo = [];
  bool _audioBusy = false; // between beginSpeaking and endSpeaking + guard
  _AfterGuard _afterGuard = _AfterGuard.recompute;
  bool _screenReleased = false;
  int _speakToken = 0;
  final Set<int> _announced = {};
  int? _cueTurn;

  StreamSubscription<SpeechEvent>? _speechSub;
  StreamSubscription<double>? _levelSub;
  StreamSubscription<VoiceAudioEvent>? _audioSub;
  EffectCleanup? _portEffect;

  Timer? _tick, _guardTimer, _idleLabelTimer, _cueTimer, _linkTimer, _awayTimer, _screenTimer, _doneTimer, _textWaitTimer, _retryTimer;

  Duration get _now => _clock.elapsed();
  bool get _ended => state.peek() == VoiceModeState.ended;

  // ───────────────────────── entry ─────────────────────────

  Future<void> start(AiVoicePort port, VoiceModeConfig config) async {
    if (!_ended) return;
    _port = port;
    _config = config;
    locale.value = config.locale;
    _ep = Endpointer(locale: config.locale, scale: config.levelScale);
    muted.value = false;
    _userTapped = false;
    _announced.clear();
    _fifo.clear();
    _cloudSwitched = false; // C8: the cloud switch lasts one voice-mode session
    _unrecognizable.clear();
    _cueTurn = null;
    notices.value = const {};
    sendCode.value = null;
    _screenReleased = false;
    _to(VoiceModeState.idle);
    _speechSub = _speech.events.listen(_onSpeech);
    _levelSub = _speech.levels.listen(_onLevel);
    _audioSub = _audio.events.listen(_onAudio);
    await _audio.enter();
    _armScreenIdle();
    await _prepare();
  }

  /// idle → (error | recompute): permission, locale, TTS voices, turn baseline (§5.2 first rows).
  Future<void> _prepare() async {
    _to(VoiceModeState.idle);
    _preparing = true;
    final permission = await _speech.ensurePermission();
    if (_ended) return;
    if (permission != SpeechPermission.granted) {
      _preparing = false;
      return _fail(permission == SpeechPermission.denied ? VoiceError.noPermission : VoiceError.unsupported);
    }
    _localeId = await _speech.resolveLocale(locale.peek());
    if (_ended) return;
    if (_localeId == null) {
      _preparing = false;
      return _fail(VoiceError.localeUnavailable);
    }
    _onDevice = _speech.tryOnDeviceFirst && !_cloudSwitched;
    await _tts.configure(rate: _config.rate, voiceIds: _config.voiceIds);
    final missing = <VoiceNotice>{
      if (_config.readAloud && _tts.voiceFor(VoiceLocale.vi) == null) VoiceNotice.noVoiceVi,
      if (_config.readAloud && _tts.voiceFor(VoiceLocale.en) == null) VoiceNotice.noVoiceEn,
    };
    notices.value = {...notices.peek(), ...missing};
    _tracker ??= VoiceReplyTracker.start(_port.mirror, _port.head);
    _portEffect ??= effect(() {
      _port.version.value;
      untracked(_onPort);
    });
    _preparing = false;
    if (!_resumed) return; // C24: the first permission dialog made us inactive; `resumed` recomputes
    _recompute();
  }

  // ───────────────────────── recompute (§5.1) ─────────────────────────

  bool _hasRequest() {
    final h = _port.head;
    return h != null && (h.permission != null || h.ask != null);
  }

  void _recompute() {
    if (_ended || _preparing || state.peek() == VoiceModeState.error) return;
    if (_covered || !_resumed) return _toPause(VoicePause.away);
    if (_hasRequest()) return _enterNeedsYou();
    if (_fifo.isNotEmpty) {
      unawaited(_speakNext());
      return;
    }
    if (_port.head?.running ?? false) return _toWorking();
    if (_port.linkState != AiLinkState.live) return _toReconnecting();
    if (_screenReader && !_userTapped) return _toPause(VoicePause.tapToTalk);
    if (muted.peek()) return _toPause(VoicePause.muted);
    if (!_port.canSend) return _toPause(_queueFull() ? VoicePause.queueFull : VoicePause.cantSend);
    unawaited(_listen());
  }

  bool _queueFull() => (_port.head?.queue.length ?? 0) >= 5;

  /// §5.4 item 7 / §10 layer 2: the single gate in front of every `SpeechInput.start`.
  bool get _micAllowed =>
      !_ended &&
      state.peek() != VoiceModeState.error &&
      state.peek() != VoiceModeState.needsYou &&
      !_hasRequest() &&
      !_audioBusy &&
      !_covered &&
      _resumed &&
      !muted.peek() &&
      (!_screenReader || _userTapped) &&
      _port.linkState == AiLinkState.live;

  // ───────────────────────── listening ─────────────────────────

  Future<void> _listen({bool queue = false}) async {
    if (!_micAllowed) return;
    queueMode.value = queue;
    _ep = Endpointer(locale: locale.peek(), scale: _config.levelScale)..beginListen(_now);
    caption.value = null;
    notices.value = notices.peek().difference(const {VoiceNotice.draftKept, VoiceNotice.notSent});
    _to(VoiceModeState.listening);
    await _startSegment();
  }

  Future<void> _startSegment() async {
    if (_segmentOpen) await _waitSegmentDone();
    if (!_micAllowed || !_isListeningState) return;
    _ep.beginSegment(_now);
    _segmentOpen = true;
    _segmentDone = Completer<void>();
    await _speech.start(_localeId!, onDevice: _onDevice, profile: ListenProfile.conversation);
    _tick?.cancel();
    _tick = Timer.periodic(VoiceTimings.tick, (_) => _onTick());
  }

  bool get _isListeningState => state.peek() == VoiceModeState.listening || state.peek() == VoiceModeState.hearing;

  Future<void> _waitSegmentDone() async {
    final done = _segmentDone;
    if (done == null || done.isCompleted) return;
    await Future.any([done.future, Future<void>.delayed(VoiceTimings.listenDoneWait)]);
    _segmentOpen = false;
  }

  /// Cancels the open listen; an utterance in progress goes to the draft when [toDraft] (C24–C26).
  /// Only listening/hearing utterances are drafted here; `sending` drafts in [_finishUtterance].
  Future<void> _abortListen({required bool toDraft}) async {
    _tick?.cancel();
    _retryTimer?.cancel();
    final text = _ep.text;
    final had = _isListeningState; // read before the first await
    if (had && toDraft && _ep.hasWords) _toDraft(text);
    _aborting = true;
    if (_segmentOpen) await _speech.cancel();
    _finalWaiter?.complete(null);
    _finalWaiter = null;
    await _waitSegmentDone();
    _aborting = false;
  }

  void _toDraft(String text) {
    _port.putInDraft(text);
    notices.value = {...notices.peek(), VoiceNotice.draftKept};
  }

  void _onSpeech(SpeechEvent event) {
    if (_ended) return;
    switch (event) {
      case SpeechListening(listening: false):
        _segmentOpen = false;
        if (!(_segmentDone?.isCompleted ?? true)) _segmentDone!.complete();
        if (_isListeningState && !_finalizing && !_aborting && !_restarting) _onSegmentEnded();
      case SpeechListening():
        break; // a late listening(true) never changes state
      case SpeechPartial(:final text):
        if (!_isListeningState || _aborting) return; // late events of an old listen are dropped (layer 2)
        _ep.onPartial(text, _now);
        _afterText();
      case SpeechFinal(:final text):
        if (_finalizing) {
          _finalWaiter?.complete(text);
          _finalWaiter = null;
          return;
        }
        if (!_isListeningState || _aborting) return;
        _ep.onSegmentFinal(text, _now);
        _afterText();
      case SpeechFailed(:final kind):
        _onSpeechFailed(kind);
    }
  }

  void _afterText() {
    caption.value = _ep.text.isEmpty ? null : _ep.text;
    if (_ep.hasWords && state.peek() == VoiceModeState.listening) _to(VoiceModeState.hearing);
  }

  void _onLevel(double x) {
    if (!_isListeningState) return;
    _ep.onLevel(x, _now);
    level.value = x;
  }

  void _onTick() {
    if (!_isListeningState) return _tick?.cancel();
    final now = _now;
    if (_ep.tooLong(now)) {
      unawaited(_abortListen(toDraft: true).then((_) => _toPause(VoicePause.tooLong)));
      return;
    }
    if (_ep.shouldSend(now)) {
      unawaited(_finishUtterance());
      return;
    }
    if (_ep.silenceBudgetSpent(now, _config.silenceBudget)) {
      unawaited(_abortListen(toDraft: false).then((_) {
        if (queueMode.peek()) {
          queueMode.value = false;
          _recompute();
        } else {
          _toPause(VoicePause.silence);
        }
      }));
      return;
    }
    if (_config.levelScale == LevelScale.ios && _ep.shouldSoftRestart(now)) {
      unawaited(_restartSegment(soft: true));
    }
  }

  /// Rule 6 / C8: the OS ended the segment on its own.
  void _onSegmentEnded() {
    if (_ep.hasWords && _ep.shouldSend(_now)) {
      unawaited(_finishUtterance());
    } else {
      unawaited(_restartSegment(soft: false));
    }
  }

  Future<void> _restartSegment({required bool soft}) async {
    _tick?.cancel(); // re-armed by _startSegment
    _restarting = true;
    if (soft && _segmentOpen) await _speech.stop(); // its final still arrives and is committed
    await _waitSegmentDone();
    _restarting = false;
    await _startSegment();
  }

  void _onSpeechFailed(SpeechErrorKind kind) {
    if (!_isListeningState || _aborting) return;
    switch (kind) {
      case SpeechErrorKind.noMatch:
        _onSegmentEnded();
      case SpeechErrorKind.busy:
        final now = _now;
        _retries.removeWhere((t) => now - t > VoiceTimings.restartRetryWindow);
        if (_retries.length >= VoiceTimings.restartRetryMax) return _failListen(VoiceError.failed);
        _retries.add(now);
        _retryTimer = Timer(VoiceTimings.restartRetry, () => unawaited(_restartSegment(soft: false)));
      case SpeechErrorKind.localeUnavailable || SpeechErrorKind.other when _onDevice && !_ep.hasWords:
        _onDevice = false; // C8: cloud once, kept for this voice-mode session
        _cloudSwitched = true;
        unawaited(_restartSegment(soft: false));
      case SpeechErrorKind.localeUnavailable:
        _unrecognizable.add(locale.peek());
        _failListen(VoiceError.localeUnavailable);
      case SpeechErrorKind.interrupted:
        unawaited(_abortListen(toDraft: true).then((_) => _toPause(VoicePause.interrupted)));
      case SpeechErrorKind.noPermission:
        _failListen(VoiceError.noPermission);
      case SpeechErrorKind.network:
        _failListen(VoiceError.network);
      case SpeechErrorKind.unsupported:
        _failListen(VoiceError.unsupported);
      case SpeechErrorKind.other:
        _failListen(VoiceError.failed);
    }
  }

  void _failListen(VoiceError e) => unawaited(_abortListen(toDraft: true).then((_) => _fail(e)));

  // ───────────────────────── sending ─────────────────────────

  /// hearing → sending: stop, wait ≤ 600 ms for the final, then C9 / C15 / C26 / send.
  Future<void> _finishUtterance() async {
    if (state.peek() != VoiceModeState.hearing) return;
    _tick?.cancel();
    _to(VoiceModeState.sending);
    _finalizing = true;
    _finalWaiter = Completer<String?>();
    await _speech.stop();
    final last = await Future.any([_finalWaiter!.future, Future<String?>.delayed(VoiceTimings.finalWait, () => null)]);
    _finalizing = false;
    _finalWaiter = null;
    if (last != null) _ep.onSegmentFinal(last, _now);
    await _waitSegmentDone();
    if (state.peek() != VoiceModeState.sending) {
      // Paused (covered, link lost) before the send: the utterance is kept, never sent (C24, C25).
      if (!_ended && _ep.hasWords) _toDraft(_ep.text);
      return;
    }
    var text = _ep.text.trim();
    final normalized = normalizeUtterance(text);
    final l = locale.peek();
    if (normalized.isEmpty || l.onlyFillers(normalized)) return _recompute();
    // Layer 3 (§10): a request arrived while the utterance was being closed → draft, never send.
    if (_hasRequest()) {
      _toDraft(text);
      return _enterNeedsYou();
    }
    if (askingMore.peek()) {
      if (l.isMore(normalized)) {
        askingMore.value = false;
        return _recompute(); // the FIFO head still holds the next part
      }
      if (l.isStop(normalized)) {
        askingMore.value = false;
        _dropCurrentReading();
        return _recompute();
      }
    }
    final words = normalized.split(' ');
    if (l.cancelWords.contains(words.last)) {
      _pushPhrase(VoicePhrases.of(l).cancelled, first: true); // C9: "Đã huỷ." then listen
      return _recompute();
    }
    if (l.sendWords.contains(words.last)) text = _dropLastWord(text);
    if (normalizeUtterance(text).isEmpty) return _recompute();
    if (askingMore.peek()) {
      askingMore.value = false;
      _dropCurrentReading(); // C15: another sentence is a message; the rest is not read
    }
    if (_hasRequest()) {
      _toDraft(text);
      return _enterNeedsYou();
    }
    _sendInFlight = true;
    final code = await _port.send(text); // exactly one call per utterance; never retried (C28)
    _sendInFlight = false;
    if (_ended) return;
    queueMode.value = false;
    if (code == null) {
      _haptic(VoiceHaptic.light);
      caption.value = text;
      return _recompute();
    }
    _toDraft(text);
    sendCode.value = code;
    if (code == 'outcome_unknown') {
      notices.value = {...notices.peek(), VoiceNotice.notSent};
      _pushPhrase(VoicePhrases.of(l).notSent, first: true);
    }
    _fail(VoiceError.sendFailed);
    if (_fifo.isNotEmpty && _config.readAloud) unawaited(_speakErrorPhrase());
  }

  /// The `notSent` phrase is spoken in `error` (no state change, mic stays closed).
  Future<void> _speakErrorPhrase() async {
    final reading = _fifo.removeAt(0);
    await _withAudio(() => _speakChunk(reading.parts.first.chunks.first));
  }

  void _pushPhrase(String text, {bool first = false}) {
    if (!_config.readAloud) return; // C31: nothing is read, not even ShellX's phrases
    first ? _fifo.insert(0, _phrase(text)) : _fifo.add(_phrase(text));
  }

  static String _dropLastWord(String text) => text.trimRight().replaceFirst(RegExp(r'\s*\S+$'), '');

  // ───────────────────────── session changes ─────────────────────────

  void _onPort() {
    if (_ended) return;
    final mirror = _port.mirror;
    if (mirror != null) {
      for (final turn in _tracker!.takeNewTurnEnds(mirror)) {
        if (askingMore.peek()) {
          askingMore.value = false; // C15: a new turn ends while asking → drop the question
          _dropCurrentReading();
        }
        _enqueueTurn(turn);
      }
    }
    final s = state.peek();
    if (_port.linkState != AiLinkState.live) {
      if (s == VoiceModeState.idle || s == VoiceModeState.listening || s == VoiceModeState.hearing) {
        unawaited(_abortListen(toDraft: true).then((_) => _toReconnecting()));
      }
      return;
    }
    _linkTimer?.cancel();
    if (s == VoiceModeState.paused && pause.peek() == VoicePause.reconnecting) return _recompute();
    if (_hasRequest()) {
      if (s == VoiceModeState.needsYou) return _announceRequest(next: true);
      if (s != VoiceModeState.paused && s != VoiceModeState.error && s != VoiceModeState.speaking) {
        return _enterNeedsYou();
      }
      return; // speaking: the loop stops after the current chunk; paused/error: recompute later
    }
    if (s == VoiceModeState.needsYou) return _recompute();
    // §5.5: a listen without words yields to a turn that started (no beep while working) or to an
    // answer waiting to be read; a listen with words (hearing) finishes its sentence first.
    if (s == VoiceModeState.listening && (_fifo.isNotEmpty || (!queueMode.peek() && (_port.head?.running ?? false)))) {
      unawaited(_abortListen(toDraft: false).then((_) => _recompute()));
      return;
    }
    if (s == VoiceModeState.working && (_fifo.isNotEmpty || !(_port.head?.running ?? false))) _recompute();
  }

  void _enqueueTurn(int turn) {
    final reply = voiceTurnReply(_port.mirror!, turn);
    if (reply == null) return;
    if (reply.pending) {
      _textWaitTimer ??= Timer(VoiceTimings.turnTextWait, () {
        _textWaitTimer = null;
        _pushReply(voiceTurnReply(_port.mirror!, turn)!);
        if (state.peek() == VoiceModeState.working) _recompute();
      });
      return;
    }
    _pushReply(reply);
  }

  void _pushReply(VoiceTurnReply reply) {
    final l = locale.peek();
    final p = VoicePhrases.of(l);
    final parts = switch (reply.outcome) {
      VoiceTurnOutcome.finished => speakableReply(reply.texts, mode: l, filesChanged: reply.files).parts,
      VoiceTurnOutcome.cancelled => _phrase(p.stopped).parts,
      VoiceTurnOutcome.unfinished => _phrase(p.notFinished).parts,
    };
    if (!_config.readAloud || parts.isEmpty) return; // C31: no reading → recompute listens at once
    _fifo.add(_Reading(parts, turn: reply.turn));
  }

  _Reading _phrase(String text) => _Reading([SpokenPart([SpokenChunk(text, locale.peek())])]);

  void _dropCurrentReading() {
    if (_fifo.isNotEmpty) _fifo.removeAt(0);
  }

  // ───────────────────────── working ─────────────────────────

  void _toWorking() {
    _to(VoiceModeState.working);
    final turn = _port.head?.turn;
    if (turn == null || _cueTurn == turn.index) return;
    _cueTimer?.cancel();
    final age = _clock.wall().difference(turn.startedAt);
    final wait = age >= VoiceTimings.workingCue ? Duration.zero : VoiceTimings.workingCue - age;
    _cueTimer = Timer(wait, () {
      if (state.peek() != VoiceModeState.working || _cueTurn == turn.index) return;
      _cueTurn = turn.index; // once per turn (C14)
      if (_config.readAloud) unawaited(_speakCue(VoicePhrases.of(locale.peek()).working));
    });
  }

  /// R10: spoken while the state stays `working`.
  Future<void> _speakCue(String text) async {
    await _withAudio(() => _speakChunk(SpokenChunk(text, locale.peek())));
    if (state.peek() == VoiceModeState.working) _recompute();
  }

  // ───────────────────────── speaking ─────────────────────────

  Future<void> _withAudio(Future<void> Function() body) async {
    await _abortListen(toDraft: true); // O1: never speak with a listen open
    _audioBusy = true;
    _guardTimer?.cancel();
    await _audio.beginSpeaking();
    try {
      await body();
    } finally {
      await _audio.endSpeaking();
      _guardTimer = Timer(VoiceTimings.postSpeakGuard, _onGuardEnd);
    }
  }

  void _onGuardEnd() {
    _audioBusy = false;
    final next = _afterGuard;
    _afterGuard = _AfterGuard.recompute;
    switch (next) {
      case _AfterGuard.listen when state.peek() == VoiceModeState.idle:
        unawaited(_listen()); // C10: tap while speaking → listen, not the next reading
      case _AfterGuard.listenQueue when state.peek() == VoiceModeState.working:
        unawaited(_listen(queue: true));
      case _:
        if (state.peek() == VoiceModeState.idle) _recompute();
    }
  }

  /// Returns false when the chunk was stopped or failed.
  Future<bool> _speakChunk(SpokenChunk chunk) async {
    if (_tts.voiceFor(chunk.lang) == null) return true; // C19: skip, never another language's voice
    final token = _speakToken;
    final result = await _tts.speak(chunk.text, chunk.lang);
    if (token != _speakToken) return false;
    if (result == SpeakResult.failed) {
      notices.value = {...notices.peek(), VoiceNotice.readFailed};
      _dropCurrentReading();
      return false;
    }
    return result != SpeakResult.stopped;
  }

  Future<void> _speakNext() async {
    if (_fifo.isEmpty) return _recompute();
    _to(VoiceModeState.speaking);
    final reading = _fifo.first;
    var more = false;
    await _withAudio(() async {
      while (!reading.done) {
        final part = reading.parts[reading.part];
        while (reading.chunk < part.chunks.length) {
          final chunk = part.chunks[reading.chunk];
          caption.value = chunk.text;
          if (!await _speakChunk(chunk)) return;
          reading.chunk++;
          if (_hasRequest() || state.peek() != VoiceModeState.speaking) return; // C26: finish this chunk only
        }
        reading
          ..part++
          ..chunk = 0;
        if (!reading.done) {
          more = true;
          await _speakChunk(SpokenChunk(VoicePhrases.of(locale.peek()).more, locale.peek()));
          return;
        }
      }
    });
    if (_ended || state.peek() != VoiceModeState.speaking) return;
    if (reading.done) _fifo.remove(reading);
    if (more) askingMore.value = true;
    _to(VoiceModeState.idle); // the 300 ms guard; its timer recomputes
  }

  /// Tap while speaking (C10): stop now, drop the rest of that reading, listen.
  Future<void> _interruptSpeaking() async {
    _speakToken++;
    _afterGuard = _AfterGuard.listen;
    _dropCurrentReading();
    askingMore.value = false;
    _to(VoiceModeState.idle);
    await _tts.stop(); // ≤ 300 ms to silence (criterion 5); _withAudio's finally arms the guard
  }

  // ───────────────────────── needsYou (§10) ─────────────────────────

  void _enterNeedsYou() {
    unawaited(_abortListen(toDraft: true)); // layer 2: mic closed first
    if (state.peek() != VoiceModeState.needsYou) _haptic(VoiceHaptic.medium);
    _to(VoiceModeState.needsYou);
    _announceRequest(next: false);
  }

  void _announceRequest({required bool next}) {
    final h = _port.head!;
    final id = h.permission?.id ?? -(h.ask!.id + 1); // asks and permissions never share a key
    if (_announced.contains(id)) return;
    _announced.add(id);
    caption.value = h.permission?.title;
    if (!_config.readAloud || _screenReader) return; // C30: the panel is a liveRegion
    final l = locale.peek();
    final p = VoicePhrases.of(l);
    final agent = h.agentName;
    final String text;
    if (h.permission != null) {
      final title = speakableLine(h.permission!.title, mode: l, maxChars: 120).chunks.map((c) => c.text).join(' ');
      text = next ? p.permissionNext(title) : p.permission(agent, title);
    } else {
      final message = _askMessage(h);
      text = message == null
          ? p.askNoText(agent)
          : p.ask(agent, speakableLine(message, mode: l, maxChars: 200).chunks.map((c) => c.text).join(' '));
    }
    unawaited(_withAudio(() => _speakChunk(SpokenChunk(text, l)))); // R9: state stays needsYou
  }

  String? _askMessage(MirrorHead h) {
    final item = h.ask?.item;
    final ask = item == null ? null : _port.mirror?.items.whereType<MirrorAsk>().where((a) => a.index == item).firstOrNull;
    return ask?.request?.message;
  }

  // ───────────────────────── pauses, errors ─────────────────────────

  void _toPause(VoicePause reason) {
    pause.value = reason;
    _to(VoiceModeState.paused);
  }

  void _toReconnecting() {
    _toPause(VoicePause.reconnecting);
    _linkTimer ??= Timer(VoiceTimings.linkGrace, () {
      _linkTimer = null;
      if (pause.peek() == VoicePause.reconnecting) _toPause(VoicePause.linkLost); // screen released
    });
  }

  void _fail(VoiceError e) {
    errorKind.value = e;
    _to(VoiceModeState.error);
  }

  void _to(VoiceModeState s) {
    final old = state.peek();
    if (old == VoiceModeState.ended && s != VoiceModeState.idle) return;
    if (s != VoiceModeState.paused) pause.value = null;
    if (s != VoiceModeState.error) errorKind.value = null;
    state.value = s;
    _idleLabelTimer?.cancel();
    idleLabel.value = false;
    if (s == VoiceModeState.idle) _idleLabelTimer = Timer(VoiceTimings.idleLabelDelay, () => idleLabel.value = true);
    _updateScreen(s);
  }

  /// C23: screen on except in `error`, `ended` and the paused reasons the spec lists (silence,
  /// interrupted, route, too long, away, link lost > 30 s, cannot send); released after 10 min without
  /// listening or speaking until the next listen or reading.
  void _updateScreen(VoiceModeState s) {
    if (s == VoiceModeState.listening || s == VoiceModeState.hearing || s == VoiceModeState.speaking) _armScreenIdle();
    final on = switch (s) {
      VoiceModeState.error || VoiceModeState.ended => false,
      VoiceModeState.paused => const {VoicePause.muted, VoicePause.tapToTalk, VoicePause.reconnecting}.contains(pause.peek()),
      _ => true,
    };
    unawaited(_audio.keepScreenOn(on && !_screenReleased));
  }

  void _armScreenIdle() {
    _screenReleased = false;
    _screenTimer?.cancel();
    _screenTimer = Timer(VoiceTimings.screenOnIdleMax, () {
      _screenReleased = true;
      unawaited(_audio.keepScreenOn(false));
    });
  }

  void _onAudio(VoiceAudioEvent e) {
    final s = state.peek();
    switch (e) {
      case VoiceInterrupted(begin: true, kind: VoiceInterruptionKind.duck):
        return; // C21
      case VoiceInterrupted(begin: true):
        if (s == VoiceModeState.speaking) {
          _speakToken++;
          unawaited(_tts.stop());
          _toPause(VoicePause.interrupted); // the reading position is kept (§5.2)
        } else if (_isListeningState) {
          unawaited(_abortListen(toDraft: true).then((_) => _toPause(VoicePause.interrupted)));
        }
      case VoiceInterrupted():
        return; // never resume on its own (C21)
      case VoiceNoisy():
        if (s == VoiceModeState.speaking) {
          _speakToken++;
          unawaited(_tts.stop());
          _toPause(VoicePause.route);
        }
    }
  }

  // ───────────────────────── user actions ─────────────────────────

  /// C10.
  void tapOrb() {
    _userTapped = true;
    switch (state.peek()) {
      case VoiceModeState.speaking:
        unawaited(_interruptSpeaking());
      case VoiceModeState.hearing:
        unawaited(_finishUtterance());
      case VoiceModeState.working:
        if (!_port.canSend) {
          caption.value = null;
          return _toPause(VoicePause.queueFull);
        }
        _cueTimer?.cancel();
        if (_audioBusy) {
          _speakToken++; // R10: the cue stops; the guard then opens the queued listen
          _afterGuard = _AfterGuard.listenQueue;
          unawaited(_tts.stop());
          return;
        }
        unawaited(_listen(queue: true));
      case VoiceModeState.paused:
        if (pause.peek() == VoicePause.muted) muted.value = false;
        _recompute();
      case VoiceModeState.error:
        retry();
      case VoiceModeState.idle || VoiceModeState.listening || VoiceModeState.sending || VoiceModeState.needsYou || VoiceModeState.ended:
        return;
    }
  }

  /// C11: a flag, not a state; dropping an utterance in progress is deliberate.
  void toggleMute() {
    if (_ended) return;
    muted.value = !muted.peek();
    if (muted.peek()) {
      if (_isListeningState) unawaited(_abortListen(toDraft: false).then((_) => _recompute()));
    } else if (state.peek() == VoiceModeState.paused) {
      _recompute();
    }
  }

  /// C12: drop the utterance (wrong language), listen again; while speaking only the next listen changes.
  Future<void> switchLocale(VoiceLocale l) async {
    if (_ended || _unrecognizable.contains(l)) return;
    locale.value = l;
    _localeId = await _speech.resolveLocale(l);
    if (_localeId == null) {
      _unrecognizable.add(l);
      return _fail(VoiceError.localeUnavailable);
    }
    if (_isListeningState) {
      await _abortListen(toDraft: false);
      _recompute();
    }
  }

  /// The "Keep reading" chip = saying "tiếp" (C15).
  void continueReading() {
    if (!askingMore.peek()) return;
    askingMore.value = false;
    unawaited(_abortListen(toDraft: false).then((_) => _recompute()));
  }

  /// "Thử lại" / "Tiếp tục" / after "Chuyển sang …" (§5.2: error → idle).
  void retry() {
    if (state.peek() != VoiceModeState.error) return;
    sendCode.value = null;
    unawaited(_prepare());
  }

  /// Sheets, dialogs, menus, another page on top, `inactive` (C24).
  void setCovered(bool covered) {
    if (_ended || covered == _covered) return;
    _covered = covered;
    if (covered) {
      _coverNow();
      _awayTimer = Timer(VoiceTimings.awayMax, () => end(VoiceEndReason.awayTooLong));
    } else {
      _awayTimer?.cancel();
      if (pause.peek() == VoicePause.away) _recompute();
    }
  }

  void _coverNow() {
    final s = state.peek();
    if (s == VoiceModeState.error) return;
    if (s == VoiceModeState.speaking) {
      _speakToken++;
      unawaited(_tts.stop()); // the chunk position stays in the FIFO head
      return _toPause(VoicePause.away);
    }
    unawaited(_abortListen(toDraft: true).then((_) => _toPause(VoicePause.away)));
  }

  void appLifecycle(AppLifecycleState s) {
    switch (s) {
      case AppLifecycleState.resumed:
        _resumed = true;
        if (!_preparing && !_covered && (state.peek() == VoiceModeState.idle || pause.peek() == VoicePause.away)) {
          _recompute(); // C24: after the first permission dialog this listens without a second tap
        }
      case AppLifecycleState.inactive:
        _resumed = false;
        // C24: not while the first permission dialog is up (we are still preparing in idle).
        if (!_preparing && !_ended) _coverNow();
      case AppLifecycleState.hidden || AppLifecycleState.paused || AppLifecycleState.detached:
        _resumed = false;
        end(VoiceEndReason.background);
    }
  }

  void setScreenReader(bool on) => _screenReader = on;

  /// Every exit path (§5.2 last rows): cancel the listen, stop TTS, release audio and screen.
  void end(VoiceEndReason reason) {
    if (_ended) return;
    final s = state.peek();
    // §4.6, C24: an utterance in progress goes to the draft (not one whose send is already in flight).
    if ((_isListeningState || (s == VoiceModeState.sending && !_sendInFlight)) && _ep.hasWords) _toDraft(_ep.text);
    for (final t in [_tick, _guardTimer, _idleLabelTimer, _cueTimer, _linkTimer, _awayTimer, _screenTimer, _doneTimer, _textWaitTimer, _retryTimer]) {
      t?.cancel();
    }
    _textWaitTimer = null;
    _linkTimer = null;
    _speakToken++;
    unawaited(_speech.cancel());
    unawaited(_tts.stop());
    unawaited(_audio.exit());
    _audioBusy = false;
    _segmentOpen = false;
    _finalizing = false;
    _fifo.clear();
    askingMore.value = false;
    queueMode.value = false;
    _covered = false;
    _portEffect?.call();
    _portEffect = null;
    _tracker = null;
    unawaited(_speechSub?.cancel());
    unawaited(_levelSub?.cancel());
    unawaited(_audioSub?.cancel());
    lastEndReason = reason;
    state.value = VoiceModeState.ended;
  }

  VoiceEndReason? lastEndReason;

  void dispose() => end(VoiceEndReason.pageClosed);

  static void _systemHaptic(VoiceHaptic h) =>
      h == VoiceHaptic.light ? HapticFeedback.lightImpact() : HapticFeedback.mediumImpact();
}
```

Notes for the implementer: (1) `_to(idle)` after speaking is the §5.2 "idle 300 ms (guard)"; the guard timer calls `_recompute` — that is the only path from speaking back to the mic. (2) `_micAllowed` is checked **again** inside `_startSegment` after every `await`, so a restart timer that fires in `needsYou` cannot open the mic. (3) `HapticFeedback` comes from `package:flutter/services.dart`. (4) Use `firstOrNull` from `package:collection`.

`FakeVoicePort implements AiVoicePort` (`test/support/fake_voice_port.dart`): settable `head`, `mirror`, `linkState`, `canSend`; `final version = signal(0)`, `void bump()` increments it; records `sent` (texts), `stopTurns`, `drafts`; `String? Function(String)? sendResult`.

- [ ] **Step 1: Failing tests** `test/ai/ai_voice_mode_test.dart`, all in `fakeAsync`, every test with a `HalfDuplexGuard` wired into `FakeSpeechInput` and `FakeSpeechOutput`, a `VoiceClock((() => async.elapsed), () => base.add(async.elapsed))`, `levelScale: ios`, `silenceBudget: 30 s` unless noted:
  1. full loop: start → `listening` (`starts.single.profile == ListenProfile.conversation`) → partial "sửa nút đăng xuất" → `hearing` → 700 ms → `stop` → final → `sent == ['sửa nút đăng xuất']` → `working` (haptic light) → mirror gets the turn end → `speaking` with `spoken.first.text` from `speakableReply` → `finishCurrent` → `idle` → 299 ms no `start` → 300 ms `listening`;
  2. "Đang làm." spoken once per turn at 2.5 s (not again at 5 s; a new turn speaks it again); entering while a turn has run 10 s → spoken at once;
  3. C10 taps per state: speaking → `tts.stops == 1` and `listening` after the guard; hearing → sent at once; listening/idle/sending/needsYou → nothing; working → `listening` with `queueMode`, utterance sent while running; paused (muted) → unmuted and listening; error → `_prepare` again;
  4. mute: answer still read, no `start` while muted, paused `muted`; unmute → listen at once; muting while hearing drops the utterance (no draft);
  5. locale switch while hearing → `cancels == 1`, no draft, next `start` uses the new id;
  6. long answer (700 chars) → part 1, then `more` phrase, `askingMore`, listen; "đọc tiếp" → part 2; "thôi" → listening, no send; another sentence → sent as message; `continueReading()`; another turn ends while asking → question dropped, new turn read;
  7. queue full (`head.queue.length == 5`, `canSend == false`) → tap in working → paused `queueFull`; turn cancelled → "Đã dừng." → listening;
  8. send failure → `drafts == [text]`, `error`/`sendFailed`, `sent.length == 1` forever (advance 5 min); `outcome_unknown` → `notSent` notice and phrase;
  9. iOS: 45 s segment + 250 ms quiet → `stop` and a new `start`, text accumulates across segments; Android (`levelScale: android`, budget 15 s): `SpeechListening(false)` mid-sentence → new `start` only after the old `done`; `busy` ×3 within 10 s → retried 500 ms apart, 4th → `error`; on-device `other` before words → one restart with `onDevice: false`, kept for later listens;
  10. silence budget: iOS 30 s, Android 15 s → paused `silence`; utterance > 120 s → `drafts`, paused `tooLong`;
  11. missing Vietnamese voice: VI chunks never `speak`, EN chunks do, notice `noVoiceVi`; no voice at all → no `speak`, loop continues;
  12. `readAloud: false` → no `speak`, listen right after the turn ends;
  13. screen reader on → after reading no `start` until `tapOrb()`;
  14. screen: `keepScreenOn(true)` on enter; false in paused/error/ended; false after 10 min working without listen or speak;
  15. late events: `SpeechPartial` after `cancel` in `needsYou`/`working` changes nothing; a late `SpeechListening(true)` never moves state;
  16. reconnecting: link drops while hearing → draft, paused `reconnecting`; live within 30 s → listening; after 30 s → `linkLost`, screen off; speaking during a drop continues;
  17. `end()` from every state → `cancel`, `tts.stop`, `audio.exit`, `keepScreenOn(false)`, no timer left (`async.pendingTimers` empty).
- [ ] **Step 2: FAIL. Step 3: Implement** (code above). **Step 4: PASS**, analyze, full suite.
- [ ] **Step 5: Commit** `feat(v2-voice): the voice-mode state machine with half-duplex and tap-only answers (§5)`

---

### Task 9: ⚠ Tap-only answers: the session port and the never-answers proof (C26, §10)

**Files:** Create `lib/features/ai/presentation/controllers/session_voice_port.dart`, `test/ai/ai_voice_never_answers_test.dart`.

**Interfaces:**
- Consumes: `AiVoicePort`, `AiVoiceMode`, `FakeVoicePort`, `FakeSpeechInput`, `FakeSpeechOutput`, `FakeVoiceAudio`, `HalfDuplexGuard` (Tasks 5–8); `AiSessionController.version`, `.head`, `.mirror`, `.linkState`, `.canSend`, `.send(String)`, `.stop()`.
- Produces: `class SessionVoicePort implements AiVoicePort` — `SessionVoicePort(AiSessionController controller, {required void Function(String text) putInDraft})`.

`session_voice_port.dart` (complete — layer 1 lives here: the controller's `answerPermission`/`answerAsk` are unreachable from voice mode):

```dart
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_session_controller.dart';
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_voice_port.dart';
import 'package:signals/signals.dart';

/// The only bridge from voice mode to a session (§10 layer 1). It forwards exactly the 8 members of
/// [AiVoicePort]; it never exposes the controller, so no answer, config, mode or revert call can be made
/// from voice mode. Answers go through the page's panel buttons, as without voice mode.
final class SessionVoicePort implements AiVoicePort {
  SessionVoicePort(this._controller, {required void Function(String text) putInDraft}) : _putInDraft = putInDraft;

  final AiSessionController _controller;
  final void Function(String text) _putInDraft;

  @override
  ReadonlySignal<int> get version => _controller.version;
  @override
  MirrorHead? get head => _controller.head;
  @override
  AiMirror? get mirror => _controller.mirror;
  @override
  AiLinkState get linkState => _controller.linkState;
  @override
  bool get canSend => _controller.canSend;
  @override
  Future<String?> send(String text) => _controller.send(text); // no images, no files (C3)
  @override
  Future<String?> stopTurn() => _controller.stop();
  @override
  void putInDraft(String text) => _putInDraft(text);
}
```

`test/ai/ai_voice_never_answers_test.dart` (complete; helpers `headWithPermission`, `headWithAsk`, `headIdle`, `mirrorOf` come from the V2-2b test support used by `ai_session_controller_test.dart` — adapt names only):

```dart
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_voice_mode.dart';
import 'package:shellx_mobile/features/voice/domain/endpointer.dart';
import 'package:shellx_mobile/features/voice/domain/speech_input.dart';
import 'package:shellx_mobile/features/voice/domain/voice_clock.dart';
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';

import '../support/ai_mirror_builders.dart'; // headIdle, headWithPermission, headWithAsk, mirrorOf
import '../support/fake_speech.dart';
import '../support/fake_speech_output.dart';
import '../support/fake_voice_audio.dart';
import '../support/fake_voice_port.dart';
import '../support/half_duplex_guard.dart';

/// V2-5c §10: a voice utterance can never answer a permission request or a question.
void main() {
  late FakeSpeechInput speech;
  late FakeSpeechOutput tts;
  late FakeVoiceAudio audio;
  late FakeVoicePort port;
  late AiVoiceMode mode;

  AiVoiceMode build(FakeAsync async) {
    final base = DateTime.utc(2026, 10, 16, 9);
    final guard = HalfDuplexGuard(() => async.elapsed);
    speech = FakeSpeechInput()..guard = guard;
    tts = FakeSpeechOutput()..guard = guard;
    audio = FakeVoiceAudio();
    port = FakeVoicePort()
      ..head = headIdle()
      ..mirror = mirrorOf(const [])
      ..linkState = AiLinkState.live
      ..canSend = true;
    return AiVoiceMode(speech, tts, audio, clock: VoiceClock(() => async.elapsed, () => base.add(async.elapsed)), haptic: (_) {});
  }

  const config = VoiceModeConfig(
    locale: VoiceLocale.vi,
    readAloud: true,
    rate: 1.0,
    voiceIds: {VoiceLocale.vi: null, VoiceLocale.en: null},
    levelScale: LevelScale.ios,
    silenceBudget: Duration(seconds: 30),
  );

  void finishSpeaking(FakeAsync async) {
    for (var i = 0; i < 20 && tts.speaking; i++) {
      tts.finishCurrent();
      async.flushMicrotasks();
    }
    async.elapse(const Duration(milliseconds: 300));
  }

  group('layer 1 — structure', () {
    test('AiVoicePort has exactly the 8 members of §10', () {
      final source = File('lib/features/ai/presentation/controllers/ai_voice_port.dart').readAsStringSync();
      final members = RegExp(r'^\s+(?:[\w<>?]+\s+)+(?:get\s+)?(\w+)(?:\(|;)', multiLine: true)
          .allMatches(source)
          .map((m) => m.group(1))
          .toSet();
      expect(members, {'version', 'head', 'mirror', 'linkState', 'canSend', 'send', 'stopTurn', 'putInDraft'});
    });

    test('no voice file names an answer call', () {
      final files = [
        ...Directory('lib/features/voice').listSync(recursive: true).whereType<File>(),
        ...Directory('lib/features/ai').listSync(recursive: true).whereType<File>().where(
              (f) => RegExp(r'(ai_voice_[a-z_]+|session_voice_port)\.dart$').hasMatch(f.path),
            ),
      ];
      expect(files, isNotEmpty);
      for (final f in files) {
        final s = f.readAsStringSync();
        for (final banned in ['answerPermission', 'answerAsk', 'ai.answer', 'setConfig', 'setMode', 'revert(']) {
          expect(s.contains(banned), isFalse, reason: '${f.path} mentions $banned');
        }
      }
    });
  });

  group('layer 2 — the mic stays closed while a request waits', () {
    for (final words in ['cho phép', 'allow', 'đồng ý', 'yes', 'có', 'luôn cho phép']) {
      test('saying "$words" with a permission pending sends nothing and answers nothing', () {
        fakeAsync((async) {
          mode = build(async);
          port.head = headWithPermission(id: 7, title: 'Sửa src/main.ts');
          mode.start(port, config);
          async.flushMicrotasks();
          expect(mode.state.value, VoiceModeState.needsYou);
          finishSpeaking(async); // the announcement
          final startsBefore = speech.starts.length;
          speech
            ..emit(SpeechPartial(words))
            ..emit(SpeechFinal(words))
            ..emit(const SpeechListening(false));
          async.elapse(const Duration(seconds: 5));
          expect(port.sent, isEmpty);
          expect(port.drafts, isEmpty);
          expect(speech.starts.length, startsBefore);
          expect(mode.state.value, VoiceModeState.needsYou);
        });
      });
    }

    test('no path opens the mic in needsYou: tap, unmute, uncover, link back, resume, every timer', () {
      fakeAsync((async) {
        mode = build(async);
        port.head = headWithAsk(id: 3, message: 'Chọn nhánh nào?');
        mode.start(port, config);
        async.flushMicrotasks();
        finishSpeaking(async);
        final before = speech.starts.length;
        mode.tapOrb();
        mode
          ..toggleMute()
          ..toggleMute();
        mode
          ..setCovered(true)
          ..setCovered(false);
        port.linkState = AiLinkState.reconnecting;
        port.bump();
        port.linkState = AiLinkState.live;
        port.bump();
        mode
          ..appLifecycle(AppLifecycleState.inactive)
          ..appLifecycle(AppLifecycleState.resumed);
        mode.continueReading();
        async.elapse(const Duration(minutes: 11)); // every timer of §5.3 fires
        expect(speech.starts.length, before);
        expect(port.sent, isEmpty);
        expect(mode.state.value, VoiceModeState.needsYou);
      });
    });

    test('a request arriving while listening closes the mic and drafts the words', () {
      fakeAsync((async) {
        mode = build(async);
        mode.start(port, config);
        async.flushMicrotasks();
        expect(mode.state.value, VoiceModeState.listening);
        speech.emit(const SpeechPartial('sửa giúp tôi'));
        port.head = headWithPermission(id: 9, title: 'Chạy npm test');
        port.bump();
        async.flushMicrotasks();
        expect(speech.cancels, 1);
        expect(port.drafts, ['sửa giúp tôi']);
        expect(mode.state.value, VoiceModeState.needsYou);
        speech.emit(const SpeechFinal('cho phép')); // late event of the old listen
        async.elapse(const Duration(seconds: 3));
        expect(port.sent, isEmpty);
      });
    });

    test('when the request is answered on screen, listening resumes', () {
      fakeAsync((async) {
        mode = build(async);
        port.head = headWithPermission(id: 7, title: 'Sửa src/main.ts');
        mode.start(port, config);
        async.flushMicrotasks();
        finishSpeaking(async);
        final before = speech.starts.length;
        port.head = headIdle(); // answered by a tap on the panel (or on the desktop, or expired)
        port.bump();
        async.elapse(const Duration(milliseconds: 400));
        expect(speech.starts.length, before + 1);
        expect(mode.state.value, VoiceModeState.listening);
      });
    });
  });

  group('layer 3 — the end-of-utterance / request race', () {
    test('a request arriving between end of utterance and send keeps the words in the draft', () {
      fakeAsync((async) {
        mode = build(async);
        mode.start(port, config);
        async.flushMicrotasks();
        speech.emit(const SpeechPartial('đồng ý sửa tệp đó'));
        async.elapse(const Duration(milliseconds: 1000)); // endpoint → sending, waiting for the final
        expect(mode.state.value, VoiceModeState.sending);
        port.head = headWithPermission(id: 11, title: 'Sửa auth.ts');
        port.bump();
        speech.emit(const SpeechFinal('đồng ý sửa tệp đó'));
        async.elapse(const Duration(seconds: 2));
        expect(port.sent, isEmpty);
        expect(port.drafts, ['đồng ý sửa tệp đó']);
        expect(mode.state.value, VoiceModeState.needsYou);
      });
    });
  });

  test('every request id is announced once, also after a pause', () {
    fakeAsync((async) {
      mode = build(async);
      port.head = headWithPermission(id: 7, title: 'Sửa src/main.ts');
      mode.start(port, config);
      async.flushMicrotasks();
      finishSpeaking(async);
      mode
        ..setCovered(true)
        ..setCovered(false);
      async.elapse(const Duration(seconds: 1));
      expect(tts.spoken.where((s) => s.text.contains('cho phép')).length, 1);
      expect(tts.spoken.single.text, 'Claude cần bạn cho phép: Sửa main.ts. Hãy chạm để trả lời trên màn hình.');
    });
  });
}
```

Notes: `headWithPermission`'s agent name is "Claude"; `speakableLine('Sửa src/main.ts')` reads "Sửa main.ts" (path rule), hence the expected phrase. Layer 4 (a widget test: only a panel tap calls `answerPermission`, exactly once) belongs to Task 13. Commands: `flutter test test/ai/ai_voice_never_answers_test.dart`, analyze, full suite.
- [ ] **Step 1:** write the test; **Step 2:** FAIL (no `SessionVoicePort`); **Step 3:** add the port; fix any state-machine path the test exposes **in `ai_voice_mode.dart`, never by weakening the test**; **Step 4:** PASS.
- [ ] **Step 5: Commit** `test(v2-voice): prove a voice utterance can never answer a permission request (§10)`

---

### Task 10: Settings group "Giọng nói" and every string (C31, C32, §12, §13.1)

**Files:** Modify `lib/core/settings/app_settings.dart` (`AppSettings`), `lib/l10n/intl_en.arb`, `lib/l10n/intl_vi.arb` (+ generated `lib/shared/src/{l10n,intl/messages_en,intl/messages_vi}.dart`), the phone Settings page (`lib/features/settings/presentation/pages/settings_page.dart`, after the "Terminal" group); Create `lib/features/settings/presentation/widgets/voice_settings_group.dart`, `voice_picker_sheet.dart`; Test `test/core/settings/app_settings_voice_test.dart`, `test/features/settings/voice_settings_group_test.dart`.

**Interfaces:**
- Produces on `AppSettings`: keys `voiceReadKey = 'settings_voice_read'` (default `true`), `voiceTtsViKey = 'settings_voice_tts_vi'` (empty = phone default), `voiceTtsEnKey = 'settings_voice_tts_en'`, `voiceRateKey = 'settings_voice_rate'` (`1.0`; allowed `0.85` / `1.0` / `1.2`), `voiceStartNewKey = 'settings_voice_start_new'` (`false`); signals `voiceRead`, `voiceTtsVi`, `voiceTtsEn`, `voiceRate`, `voiceStartNew`; setters `setVoiceRead(bool)`, `setVoiceTts(VoiceLocale, String?)`, `setVoiceRate(double)`, `setVoiceStartNew(bool)` — write the store first, then the signal (as `setBiometricLock`); `VoiceModeConfig voiceModeConfig({required TargetPlatform platform})` (locale from `settings_voice_locale`, `levelScale`/`silenceBudget` by platform: iOS 30 s, Android 15 s).
- Voice id stored: iOS `identifier`, Android `name` (§12).
- **Rows (§12):** Language VI│EN (`ShellxSegmented<VoiceLocale>`, shared with terminal and 🎙) · Read answers aloud (+ hint) · Vietnamese voice → picker ("Phone default" + on-device voices with "Enhanced"/"Premium" on iOS; none → "None on this phone" + "How to add a voice") · English voice · Reading speed Slow│Normal│Fast · Listen (reads `VoicePhrases.of(locale).sample` through `VoiceAudio` + `SpeechOutput`) · Start new AI sessions in voice mode · footnote.
- [ ] **Step 1: Failing tests:** keys and defaults; write-then-signal order; `settings_voice_locale` still shared (the terminal reads the new value); picker lists voices, shows "Máy chưa có" when none, falls back to default when the stored voice vanished; every row has its EN/VI label (both locales); no overflow at 320 pt and text scale 1.3.
- [ ] **Step 2: FAIL. Step 3: Implement**; ARB keys (verbatim; `{agent}`, `{language}` placeholders as `String`), then `dart run intl_utils:generate` + format the three generated files. **Step 4: PASS**, analyze.
- [ ] **Step 5: Commit** `feat(v2-voice): voice settings and voice-mode strings (§12, §13.1)`

ARB keys (spec §13.1 verbatim; reuse `retry`, `openSettings`, `aiStop`, `aiAskTitle`, `voiceLanguageVi`/`En`, `voiceNoPermission`, `voiceUnsupported`, `voiceLocaleUnavailableVi`/`En`, `voiceNetwork`, `voiceFailed`, `AiWords.failure`/`state`; `{language}` in the two how-to lines = `voiceLanguageVi`/`voiceLanguageEn`):

| Khoá | EN | VI |
|---|---|---|
| `voiceModeStart` | Talk with {agent} | Nói chuyện với {agent} |
| `voiceModeMute` / `voiceModeUnmute` | Turn off mic / Turn on mic | Tắt mic / Bật mic |
| `voiceModeEnd` | End | Kết thúc |
| `voiceModeExpand` / `voiceModeCollapse` | Full screen / Back to the conversation | Toàn màn hình / Về hội thoại |
| `voiceModeLanguage` | Language | Ngôn ngữ |
| `voiceModeContinue` | Keep reading | Đọc tiếp |
| `voiceModeResume` | Continue | Tiếp tục |
| `voiceModeSwitchTo` | Switch to {language} | Chuyển sang {language} |
| `voiceModePreparing` | Getting ready… | Đang chuẩn bị… |
| `voiceModeListening` | Listening… | Đang nghe… |
| `voiceModeListeningQueue` | This message will wait in the queue. | Tin này sẽ chờ trong hàng đợi. |
| `voiceModeHearingHint` | Pause to send · tap to send now | Ngừng nói để gửi · chạm để gửi ngay |
| `voiceModeSending` | Sending… | Đang gửi… |
| `voiceModeQueued` | Queued | Đã xếp hàng |
| `voiceModeWorking` | {agent} is working… | {agent} đang làm… |
| `voiceModeSpeaking` | Reading the answer… | Đang đọc câu trả lời… |
| `voiceModeMore` | Keep reading? | Đọc tiếp? |
| `voiceModeMuted` | Mic off | Đã tắt mic |
| `voiceModePausedSilence` | Nothing heard for a while — tap to talk. | Một lúc không nghe thấy gì — chạm để nói. |
| `voiceModePausedAway` | Paused | Đã tạm dừng |
| `voiceModePausedInterrupted` | Paused by the phone — tap to continue | Điện thoại đã tạm dừng âm thanh — chạm để tiếp tục |
| `voiceModePausedRoute` | Headphones disconnected — tap to continue | Tai nghe đã ngắt — chạm để tiếp tục |
| `voiceModeReconnecting` | Reconnecting… | Đang kết nối lại… |
| `voiceModeLinkLost` | Not connected — tap to try again | Mất kết nối — chạm để thử lại |
| `voiceModeTooLong` | That was long — it's in the text field for you to check. | Câu nói dài quá — đã để trong ô nhập để bạn xem lại. |
| `voiceModeQueueFull` | The queue is full (5 messages). | Hàng đợi đã đủ 5 tin. |
| `voiceModeNeedsPermission` | {agent} needs your permission | {agent} cần bạn cho phép |
| `voiceModeTapOnly` | Tap a button above — voice can't answer this. | Chạm một nút ở trên — không trả lời bằng giọng nói được. |
| `voiceModeAnswerOnScreen` | Answer on the screen — tap or type. | Trả lời trên màn hình — chạm hoặc gõ. |
| `voiceModeTapToTalk` | Double-tap to talk | Chạm hai lần để nói |
| `voiceModeNotSent` | It may not have been sent. What you said is in the text field. | Có thể chưa gửi được. Lời bạn nói đã nằm trong ô nhập. |
| `voiceModeDraftKept` | What you said is in the text field. | Lời bạn nói đã nằm trong ô nhập. |
| `voiceModeNoVoiceVi` | This phone has no Vietnamese reading voice. Vietnamese answers show as text only. | Máy chưa có giọng đọc tiếng Việt. Câu trả lời tiếng Việt chỉ hiện chữ. |
| `voiceModeNoVoiceEn` | This phone has no English reading voice. English answers show as text only. | Máy chưa có giọng đọc tiếng Anh. Câu trả lời tiếng Anh chỉ hiện chữ. |
| `voiceModeHowToAddVoice` | How to add a voice | Cách thêm giọng đọc |
| `voiceModeAddVoiceIos` | On iPhone: Settings › Accessibility › Spoken Content › Voices › {language}, then download a voice. Open ShellX again afterwards. | Trên iPhone: Cài đặt › Trợ năng › Nội dung được đọc › Giọng nói › {language}, rồi tải một giọng. Sau đó mở lại ShellX. |
| `voiceModeAddVoiceAndroid` | On Android: Settings › Accessibility › Text-to-speech output › the engine's settings › Install voice data › {language}. | Trên Android: Cài đặt › Trợ năng › Chuyển văn bản sang lời nói › cài đặt của công cụ › Cài đặt dữ liệu giọng nói › {language}. |
| `voiceModeOpenAccessibility` | Open Accessibility settings | Mở cài đặt Trợ năng |
| `voiceModeReadFailed` | Couldn't read the answer aloud. | Không đọc được câu trả lời. |
| `voiceModeCantListen` | Can't listen | Không nghe được |
| `voiceModeSendFailedTitle` | Not sent | Chưa gửi được |
| `voiceModeStarted` | Voice mode on. Double-tap the voice control to talk. | Đã bật chế độ giọng nói. Chạm hai lần vào nút giọng nói để nói. |
| `voiceModeEnded` | Voice mode ended | Đã tắt chế độ giọng nói |
| `voiceModeEndedBackground` | Voice mode ended when ShellX left the screen. | Chế độ giọng nói đã tắt vì ShellX rời màn hình. |
| `voiceModeOrbListening` | Listening. Tap to send now. | Đang nghe. Chạm để gửi ngay. |
| `voiceModeOrbSpeaking` | Reading. Tap to stop and talk. | Đang đọc. Chạm để dừng và nói. |
| `voiceModeOrbWorking` | {agent} is working. Tap to say the next message. | {agent} đang làm. Chạm để nói tin tiếp theo. |
| `voiceModeOrbPaused` | Paused. Tap to talk. | Đã tạm dừng. Chạm để nói. |
| `voiceModeYou` | You | Bạn |
| `settingsVoiceGroup` | Voice | Giọng nói |
| `settingsVoiceLanguage` | Language | Ngôn ngữ |
| `settingsVoiceRead` | Read answers aloud | Đọc to câu trả lời |
| `settingsVoiceReadHint` | In voice mode, the AI's answers are read on this phone. | Ở chế độ giọng nói, câu trả lời của AI được đọc ngay trên điện thoại. |
| `settingsVoiceVoiceVi` / `settingsVoiceVoiceEn` | Vietnamese voice / English voice | Giọng đọc tiếng Việt / Giọng đọc tiếng Anh |
| `settingsVoicePhoneDefault` | Phone default | Mặc định của máy |
| `settingsVoiceNoVoice` | None on this phone | Máy chưa có |
| `settingsVoiceQualityEnhanced` / `Premium` | Enhanced / Premium | Nâng cao / Cao cấp |
| `settingsVoiceRate` | Reading speed | Tốc độ đọc |
| `settingsVoiceRateSlow` / `Normal` / `Fast` | Slow / Normal / Fast | Chậm / Vừa / Nhanh |
| `settingsVoiceTry` | Listen | Nghe thử |
| `settingsVoiceStartNew` | Start new AI sessions in voice mode | Mở phiên AI mới bằng giọng nói |
| `settingsVoiceFootnote` | Speech is turned into text by the phone's speech recognition (Apple or Google, possibly on their servers). Answers are read aloud on this phone. ShellX never stores audio. | Lời nói được chuyển thành chữ bằng nhận dạng giọng nói của điện thoại (Apple hoặc Google, có thể trên máy chủ của họ). Câu trả lời được đọc ngay trên điện thoại. ShellX không lưu âm thanh. |

---

### Task 11: The voice bar (after B) (C4, §4.2, §4.4–4.7)

**Files:** Create `lib/features/voice/presentation/widgets/voice_wave.dart`, `lib/features/ai/presentation/widgets/ai_voice_bar.dart`; Test `test/features/ai/ai_voice_bar_test.dart`, `test/features/voice/voice_wave_test.dart`.

**Interfaces:**
- Consumes: `AiVoiceMode` signals (Task 8); `ShellxGlass(blur: false)` (A Task 4), `ShellxIcons.voiceMicOn/voiceMicOff/voiceExpand/voiceStopTurn/voiceEnd/voiceNeedsYou`, A's tokens (`ShellxPalette.warn`, `.error`, `textSecondary`, `ShellxGradients.accent`, `ShellxDurations.of`).
- Produces: `class AiVoiceBar extends StatelessWidget { const AiVoiceBar({required AiVoiceMode mode, required String agent, required bool turnRunning, required Duration? turnElapsed, required VoidCallback onStopTurn, required VoidCallback onExpand, required VoidCallback onEnd, required VoidCallback onHowToAddVoice, required VoidCallback onOpenSettings}); }`; `class VoiceWave extends StatelessWidget { const VoiceWave({required VoiceModeState state, required double level, required bool muted, required VoidCallback onTap}); }` (a `CustomPainter`; continuous animation only in `listening`, `hearing`, `working`, `speaking`; `MediaQuery.disableAnimations` → 3 static steps, ≤ 4 changes/s).
- Layout (§4.2): row 1 `Expanded` one-line label with "…" + language chip 44 pt ("VI"/"EN") + `voiceExpand` 44 pt; row 2 caption ≤ 2 lines keeping the end ("…" first) or reason ≤ 3 lines or a `Wrap` of text buttons (`voiceModeContinue`, `openSettings`, `retry`, `voiceModeSwitchTo`, `voiceModeResume`, `voiceModeHowToAddVoice`); row 3 fixed: mic 44 · wave (flex) · Stop slot 44 (always reserved; the button appears 400 ms after a turn starts) · End 44. Icons only; tooltip + Semantics label; mic `Semantics(toggled)`.
- Labels per state (§4.4 table): idle `voiceModePreparing` (only when `idleLabel`), listening `voiceModeListening` (+ row 2 `voiceModeHearingHint`, queue: `voiceModeListeningQueue`), hearing caption, sending `voiceModeSending` (queue: `voiceModeQueued`), working `voiceModeWorking` + `m:ss` + latest tool title (`AiWords.toolTitle`), speaking `voiceModeSpeaking` (asking: `voiceModeMore`), paused short label `voiceModeMuted` / `voiceModeReconnecting` / `voiceModeTapToTalk` / `voiceModePausedAway` and reason row (`voiceModePausedSilence`, `voiceModePausedInterrupted`, `voiceModePausedRoute`, `voiceModeLinkLost`, `voiceModeTooLong`, `voiceModeQueueFull` or `AiWords.state`, plus `voiceModeDraftKept`), needsYou `voiceNeedsYou` icon + `voiceModeNeedsPermission` / `voiceModeTapOnly` (ask: `aiAskTitle` / `voiceModeAnswerOnScreen`), error `voiceModeCantListen` or `voiceModeSendFailedTitle` + the error line (§15) + button. Announcements (§4.7) via `SemanticsService.announce`, never while the mic is open.
- [ ] **Step 1: Failing widget tests:** each of the 10 states shows its EN label; Stop slot reserved (the End button's x is equal with and without a running turn); needsYou bar has no button that answers; 320 pt × text scale 1.0 and 1.3: no overflow, row-1 label is one line with "…" and full Semantics label, a long Vietnamese caption wraps to 2 lines ending with the latest words, a long reason ≤ 3 lines, text buttons wrap; every button ≥ 44 pt with a Semantics label; `find.byIcon(ShellxIcons.voiceEnd)` etc.; reduced motion → no ticking animation (`tester.binding.hasScheduledFrame` false after settle).
- [ ] **Step 2: FAIL. Step 3: Implement. Step 4: PASS**, analyze.
- [ ] **Step 5: Commit** `feat(v2-voice): the voice bar with its waveform (C4, §4.2)`

---

### Task 12: The full-screen orb overlay (after B) (C5, §4.3)

**Files:** Create `lib/features/voice/presentation/widgets/voice_orb.dart`, `lib/features/ai/presentation/widgets/ai_voice_screen.dart`; Test `test/features/ai/ai_voice_screen_test.dart`.

**Interfaces:**
- Consumes: Task 11's inputs; `ShellxWedge` (top right), `ShellxGradients.accent` (orb), `ShellxGlass` (blurred: solid page background behind, A29), `ShellxSegmented<VoiceLocale>` (VI│EN), `ShellxIcons.voiceCollapse`.
- Produces: `class AiVoiceScreen extends StatelessWidget { const AiVoiceScreen({required AiVoiceMode mode, required String title, required String agent, required Widget? requestPanel, required VoidCallback onCollapse, required VoidCallback onEnd, required VoidCallback onStopTurn}); }`; `class VoiceOrb extends StatelessWidget { const VoiceOrb({required VoiceModeState state, required double level, required bool muted, required VoidCallback onTap}); }` (listening breathes 2 s, hearing scales 1.0–1.15, working gradient rotates 8 s/turn, speaking pulses ~4 Hz; paused grey; needsYou `warn`; error `error`).
- Layout: `[voiceCollapse] title · agent` top; orb; state label; captions both sides (speaker name on its own line in secondary text, words ≤ 4 lines each keeping the end, scrollable at large text); bottom row Mic · VI│EN · Stop · End with labels under (≤ 2 lines). Request panel on a glass card in the lower half with the orb shrunk above. Orb semantics `voiceModeOrbListening` / `Speaking` / `Working` / `Paused`. Android Back → `onCollapse` (`PopScope`).
- [ ] **Step 1: Failing widget tests:** opens and collapses (Back too) without ending the mode; tap orb = `tapOrb`; request panel present → orb shrinks, one panel only; no overflow at 320 pt × 1.3; reduced motion static; icons via roles.
- [ ] **Step 2: FAIL. Step 3: Implement. Step 4: PASS**, analyze.
- [ ] **Step 5: Commit** `feat(v2-voice): the full-screen orb overlay (C5, §4.3)`

---

### Task 13: Wire voice mode into B's composer and the session page (after B) (C2, C3, C24, C31, B T38/T39/T41)

**Files:** Modify B's `AiComposerCard` (the `voiceSlot` right of 🎙, R1), B's `AiOpenComposer` (T38), `lib/features/ai/presentation/pages/ai_session_page.dart` (`_AiSessionPageState`), `lib/core/router/app_router.dart` (+ `app_router.gr.dart` via build_runner); Test `test/features/ai/ai_session_page_voice_mode_test.dart`, `test/features/ai/ai_open_composer_voice_test.dart`, `test/features/ai/voice_icons_guard_test.dart`.

**Interfaces:**
- Consumes: B's composer slot names (R1), `AiVoiceMode`, `SessionVoicePort`, `AiVoiceBar`, `AiVoiceScreen`, `AppSettings.voiceModeConfig`, `voiceStartNew`.
- Produces: `AiSessionRoute(…, {bool startVoice = false})`; page fields `AiVoiceMode? _voice`, `final _voiceMade = signal(false)` (F43 pattern, like `_dictationMade`), `bool _voiceFull`; methods `_startVoice()`, `_endVoice(VoiceEndReason)`, `_putInDraft(String)` (empty field → set; else newline + append; keeps images).
- **Entry (C2):** `ai.voice` button (`ShellxIcons.voiceMode`, tooltip/Semantics `voiceModeStart` "Talk with {agent}") enabled when link live **and** (`head.canSend` or a turn runs); tapping while 🎙 dictates → `_dictation.stop()` first (words stay). Open composer: empty field → `ai.open {agent, folder}` without text; with text → exactly B's Send; on `sid` push `AiSessionRoute(startVoice: true)`; failure → text kept, `AiWords.failure`, no retry. Send with `voiceStartNew` on → `startVoice: true`.
- **startVoice (C31):** once the header exists and the link is live for the first time (≤ `VoiceTimings.startVoiceWait` 10 s; else nothing), start voice mode.
- **Page (C4, C24):** voice on → keyboard closes, `AiVoiceBar` replaces the composer slot (dock panels stay above); overlay inside the page `Stack`; `TickerMode.of(context)` false → `setCovered(true)`; the page's own sheets/dialogs/menus (config sheet, history, ⋯, "Xem đủ") wrap their `show…` in `setCovered(true)`/`(false)`; `didChangeAppLifecycleState` → `appLifecycle`; `MediaQuery.accessibleNavigationOf` → `setScreenReader`; session `gone`/`desktop_closed`/`unavailable`/sid change → `end(sessionClosed)` + toast `voiceModeEnded`; `dispose` → `dispose()`; coming back after `background` → toast `voiceModeEndedBackground`, composer with its draft intact.
- [ ] **Step 1: Failing widget tests** (`test/support/app_harness.dart`): button sits right of 🎙 in both composers, enabled/disabled per C2; open composer empty → `ai.open` without text then the session page with `startVoice`, with text → like Send; 🎙 still dictation and still needs "gửi"; bar replaces the composer, draft and images intact after End; `inactive` → paused → `resumed` → listening; `hidden` → ended, everything released (`cancel`, `stop`, `exit`, screen false); push a page (TickerMode off) → paused, 2 min → ended; open config sheet → paused, close → listening; first permission dialog (`permissionGate`) does not pause and listens right after; session `gone` → ended. **Layer 4:** with a pending permission in voice mode, only tapping a panel button calls `answerPermission` (fake controller counts = 1, after the 400 ms settle); the bar has no answer button; emitting `SpeechFinal('cho phép')` calls nothing. **Icon guard:** grep every file C created or changed (§11 list) for `Icons.` and `CupertinoIcons.` → none.
- [ ] **Step 2: FAIL. Step 3: Implement**; `dart run build_runner build --delete-conflicting-outputs`. **Step 4: PASS**, full suite.
- [ ] **Step 5: Commit** `feat(v2-voice): open voice mode from the composer and run it in the session page (C2, C24, C31)`

---

### Task 14: Final verification, ledger and the manual checks (§16, §18)

**Files:** Modify `docs/superpowers/ledgers/v2-5c.md`.

- [ ] **Step 1:** From `apps/mobile`: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze` (only the pre-existing info) and `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test` — all green; record counts (before/after). `flutter build apk --debug` and `flutter build ios --simulator --no-codesign` succeed.
- [ ] **Step 2:** Self-check against spec §16: every listed test exists (fakes, endpointer, speakable, reply, state machine, never-answers ×4 layers, lifecycle, UI, monospace, icons, `SpeechToTextInput`, settings, platform files, `toString`). Grep `lib/` for `debugPrint(`/`log(` in C's files: only error kinds.
- [ ] **Step 3:** Ledger: commits, counts, R2 resolved versions, R3 source findings, open items (privacy page `web/**` after the user's go-ahead, §14; store privacy labels, GOLIVE S-04).
- [ ] **Step 4: Hand the manual checks to the user** (⚠ needs a person, a real iPhone (iOS 17/18, + 26 if available), a Pixel and a Samsung, a Mac running ShellX; each item in Vietnamese and English), spec §18 verbatim:

1. **Lần đầu:** chưa cấp quyền → chạm sóng âm → hai hộp xin quyền iOS / một hộp Android → nghe luôn, không phải chạm lần hai.
2. **Vòng rảnh tay** trong phòng yên, máy cầm tay, loa ngoài: 5 lượt liền tiếng Việt, rồi 5 lượt tiếng Anh. Ghi thời gian từ từ cuối tới bong bóng tin (≤ 1,5 s) và từ hết lượt tới tiếng đọc đầu tiên.
3. **Tai nghe:** AirPods trên iPhone (micro AirPods, có mất chữ đầu khi đọc không), tai nghe Bluetooth trên Android (micro điện thoại, tiếng ra tai nghe), tai nghe có dây.
4. **Ngừng để nghĩ:** "Sửa giúp tôi cái lỗi… ừm… ở trang đăng nhập" — không bị cắt sau "ừm"; "…thì" chờ lâu hơn.
5. **Ồn:** quán cà phê hoặc TV bật: có gửi được không, có tự gửi câu của TV không; ghi lại để chỉnh `M`.
6. **Ngưỡng mức âm:** ghi giá trị `F` và mức khi nói (bản debug in số, không in chữ) trên ba máy, chỉnh `M` nếu cần.
7. **Câu trả lời dài** (> 600 ký tự, có khối mã, bảng, link, đường dẫn): nghe phần 1, "Còn nữa. Đọc tiếp không?", trả lời "đọc tiếp", "thôi", và một câu khác; chất lượng đọc định danh tiếng Anh trong câu Việt.
8. **Xin quyền:** agent ở "Hỏi trước", nhờ sửa một tệp: lời báo được đọc, bảng hiện, nói "cho phép" to vào máy → không có gì xảy ra; chạm "Cho phép" → agent làm tiếp, câu trả lời được đọc.
9. **Ngắt:** gọi tới khi đang nghe và khi đang đọc (từ chối trên banner, và nghe máy); Siri; báo thức.
10. **Ra nền, khoá máy, quay lại:** micro tắt (chấm cam iOS / biểu tượng Android tắt), nhạc của app khác hết bị làm nhỏ, ô nhập còn nháp.
11. **Bị che:** mở "Xem đủ", menu ⋯, sheet chế độ/model của thẻ ô nhập; quay lại tiếp tục; để quá 2 phút → tắt.
12. **Màn hình sáng:** máy để khoá tự động 30 s: không khoá khi đang dùng; lượt chạy 12 phút → màn hình được thả, máy tự khoá, thông báo "Xong lượt" tới.
13. **Tiếng bíp Android:** đếm số tiếng bíp trong một lượt hội thoại và trong 15 s im lặng.
14. **Thiếu giọng tiếng Việt:** xoá/tắt giọng Việt trên một máy: dòng báo, hướng dẫn, "Mở cài đặt Trợ năng" (Android); câu Anh vẫn được đọc.
15. **Nhạc:** mở Spotify/YouTube Music rồi bật chế độ: nhạc nhỏ khi đọc, trở lại khi xong; khi nghe thì tuỳ máy (ghi lại).
16. **VoiceOver / TalkBack:** chạm hai lần để nói; micro không nghe tiếng của trình đọc màn hình; bảng xin quyền được báo. **Giảm chuyển động:** không hoạt hình liên tục.
17. **Chế độ máy bay:** iPhone có nhận dạng tiếng Việt trên máy không (ghi lại); Android báo lỗi mạng đúng.
18. **Pin, nhiệt:** 10 phút chế độ giọng nói liên tục: ghi % pin và nhiệt độ cảm nhận.
19. **🎙 và terminal:** đọc chính tả vẫn cần "gửi", không bị ảnh hưởng.
20. **Phông và biểu tượng:** iPhone (SF Mono của hệ thống, qua cách nạp của A; dự phòng JetBrains Mono) và Android (JetBrains Mono): phụ đề tiếng Việt dài, dấu chồng (ặ, ẫ, ở) không bị cắt, nhãn dài cắt "…" gọn, cỡ chữ hệ thống lớn nhất mà app hỗ trợ; tám biểu tượng Cupertino rõ nghĩa ở cả sáng và tối.

- [ ] **Step 5: Commit** `docs(v2-voice): V2-5c ledger — verification, counts and the manual checks`

---

## Self-review

- **Spec coverage:** C1 (Tasks 5–8), C2 (13), C3 (8, 9, 13), C4 (11), C5 (12), C6 (8, 11), C7 (4), C8 (5, 8), C9 (2, 8), C10 (8), C11 (8), C12 (8, 10), C13 (3), C14 (8), C15 (2, 8), C16 (2), C17 (2), C18 (6), C19 (6, 8, 10), C20–C22 (7), C23 (7, 8), C24 (8, 13), C25 (8), C26 (8, 9, 13), C27 (8, 11), C28 (8), C29 (4, 8), C30 (8, 11, 12), C31 (10, 13), C32 (2), C33 (7), C34 (all `toString` tests; Task 14 grep), C35 (8: only C9/C15 words are interpreted), C36 (order), C37 (1).
- **Types:** `AiVoicePort` 8 members (Tasks 8, 9); `SpeechInput.start(..., profile:)` (5) used by `AiVoiceMode._startSegment` (8); `SpeechOutput.voiceFor` (6) used by `_speakChunk` (8); `VoiceAudio.beginSpeaking/endSpeaking/enter/exit/keepScreenOn/events` (7, 8); `VoiceReplyTracker.start/takeNewTurnEnds`, `voiceTurnReply` (3, 8); `Endpointer` API (4, 8); `VoicePhrases.of(l).…` (2, 8, 9).
- **Review Focus:** each of the five lines has its test in Tasks 3, 4, 8, 9, 13.
