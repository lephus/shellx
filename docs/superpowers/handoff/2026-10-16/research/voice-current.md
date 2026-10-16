# Voice on `v2-2b`: as built, and what is missing for a ChatGPT-style voice mode

Researched 2026-10-16, read-only. Worktree `/Users/richard/Documents/helper/shellx/.claude/worktrees/v2-2b`, branch `v2-2b`, HEAD `640141b` when read (tree clean). The voice code was last changed by `6cd7108` and `03fc266` (AI composer mic and its fix round, 2026-10-16) and, for the terminal's voice composer, by `cba537e` (2026-10-08). Nothing was built, run or tested. Test counts are grep counts of `test(` / `testWidgets(` calls.

Path shorthand:
- `M/` = `apps/mobile/`
- `PLUGIN/` = `~/.pub-cache/hosted/pub.dev/speech_to_text-7.4.0/` (read to be exact about what the engine does)
- `SDD/` = `/Users/richard/Documents/helper/shellx/.superpowers/sdd/2026-10-15-v2-2b-phone-ai-more/` (`progress.md` = the ledger, `handoff-14-19.md` = the hand-off)
- every other path is relative to the worktree root.

"(derived)" marks a statement taken from reading code or plugin source, not from a device. Section 11 lists them all.

---

## 0. Summary

- **What exists is push-to-talk dictation, not a conversation.** Tap the mic, say one utterance, the words appear in a text field, then tap Send or end the utterance with the keyword "gửi" (Vietnamese) / "send" (English). Vietnamese and English only. Mobile only.
- **One engine adapter, two controllers.** `SpeechToTextInput` wraps `speech_to_text` 7.4.0 (Apple `SFSpeechRecognizer` on iOS, Android `SpeechRecognizer`). The terminal's `VoiceComposerController` (V1, 2026-10-06) and the AI composer's `AiDictation` (V2-2b B14, task 19) are near-copies of one state machine on top of it (ledger ruling F42 accepted the duplication).
- **No spoken output anywhere** (no TTS package, no native TTS code). **No voice input on the desktop.**
- **The chosen engine is the main obstacle.** Its own README says it targets "commands and short phrases, not continuous spoken conversion or always on listening" (`PLUGIN/README.md:9-10`, `:347-352`). Hands-free turns, barge-in and echo cancellation cannot be built on it as it is. The seam for replacing it exists (`SpeechInput`, `M/lib/features/voice/domain/speech_input.dart:58-80`).
- **Verification is thin where it matters.** About 118 voice tests, all against a fake recognizer. The real adapter class `SpeechToTextInput` has no test at all (only three pure helper functions are tested), and every on-device check, including the first-tap permission behaviour, is still a pending manual check.
- **A product rule bounds voice-driven agent work:** V2-2 decision D13, "the phone has no path to answer [a permission request] without a tap" (`docs/superpowers/specs/2026-10-14-v2-2-phone-ai-design.md:100`, repeated in `docs/superpowers/specs/2026-10-15-v2-2b-phone-ai-more-design.md:180`).

---

## 1. Code map

| Piece | File | Role |
|---|---|---|
| Engine seam | `M/lib/features/voice/domain/speech_input.dart:3-80` | `SpeechInput` interface; `SpeechPermission`, `SpeechErrorKind`; events `SpeechPartial`, `SpeechFinal`, `SpeechFailed`, `SpeechListening` |
| Languages | `M/lib/features/voice/domain/voice_locale.dart:3-26` | `VoiceLocale.vi` (`vi-VN`, send `gửi`, cancel `huỷ`/`hủy`) and `en` (`en-US`, `send`, `cancel`) |
| Keyword parser | `M/lib/features/voice/domain/voice_command_parser.dart:37-52` | pure function; last-word keyword of a final result |
| Engine adapter | `M/lib/features/voice/data/speech_to_text_input.dart:56-152` | `@LazySingleton(as: SpeechInput)`: one shared instance (`M/lib/core/dependency/dependency.config.dart:99`) |
| Terminal controller | `M/lib/features/voice/presentation/controllers/voice_composer_controller.dart:21-297` | `@injectable`; owns its own text field and the per-terminal draft |
| Terminal UI | `M/lib/features/voice/presentation/widgets/voice_composer.dart`, `mic_button.dart` | composer panel above the extra keys; mic cap that pulses |
| **AI controller** | `M/lib/features/ai/presentation/controllers/ai_dictation.dart:24-240` | `@injectable` factory (`dependency.config.dart:158`); drives the session page's own text field |
| AI page glue | `M/lib/features/ai/presentation/pages/ai_session_page.dart:72-82, 95-113, 151-153, 254-266, 490-503, 571-573, 579-588` | lazy creation at the first mic tap, lifecycle stops, issue line |
| AI composer UI | `M/lib/features/ai/presentation/widgets/ai_dock.dart:495-554, 630-638, 676-689` | the `ai.mic` icon button and the `note` line |
| Language setting | `M/lib/core/settings/app_settings.dart:14, 27-29, 43, 59, 69, 90-93` | key `settings_voice_locale` in the secure `KeyValueStore` |
| Strings | `M/lib/l10n/intl_en.arb:404-432, 467, 667`; `intl_vi.arb:206-234, 268, 429` | `voice*` keys, `aiMicTooltip` |
| Fake for tests | `M/test/support/fake_speech.dart:7-50` | `FakeSpeechInput` |

The path from speech to a sent message (AI page): recognizer final result -> `AiDictation._onEvent` (`ai_dictation.dart:151-156`) -> `VoiceCommandParser.parse` -> `_apply(VoiceSend)` (`:177-180`) -> `canSend()` (`ai_session_page.dart:261`) -> page `_send()` (`:151`, which calls `_dictation?.stop()` first, `:153`) -> `AiSessionController.send` (`M/lib/features/ai/presentation/controllers/ai_session_controller.dart:193-233`) -> `machine.ai.prompt(sid, text, blobs, files)` (`:226`).

---

## 2. Packages and native configuration

### 2.1 Packages
- `M/pubspec.yaml:64-65`: `speech_to_text: 7.4.0`, pinned exactly ("BSD-3-Clause. 7.5.0+ needs Dart ^3.12 / Flutter 3.44").
- Resolved in the workspace lock (`pubspec.lock:1579-1602`): `speech_to_text` 7.4.0, `speech_to_text_platform_interface` 2.5.0, `speech_to_text_windows` 1.0.1 (transitive; unused by the desktop app).
- `M/ios/Podfile.lock:93` lists the pod as `speech_to_text (7.2.0)`. That is the podspec label of the 7.4.0 package (`PLUGIN/darwin/speech_to_text.podspec:7`), not drift.
- **No other audio-related package in any pubspec** (root, `apps/desktop`, `apps/mobile`, `packages/*`): no TTS, `audio_session`, `permission_handler`, wakelock, audio player, recorder, or other STT engine. Permissions are requested by the speech plugin itself.
- Platform floors: iOS 15.0 (`M/ios/Podfile:2`); Android `minSdk = 26` (`M/android/app/build.gradle.kts:30`).

### 2.2 iOS (`M/ios/Runner/`)
- `Info.plist:42-43` `NSMicrophoneUsageDescription`: "ShellX uses the microphone when you tap the mic to speak into your terminal or an AI session."
- `Info.plist:46-47` `NSSpeechRecognitionUsageDescription`: "ShellX turns what you say into text for your terminal or an AI session using Apple's speech recognition, which may process it on your phone or on Apple's servers."
- Localized copies: `en.lproj/InfoPlist.strings:4, 6` (same text) and `vi.lproj/InfoPlist.strings:4, 6` ("ShellX dùng micro khi bạn chạm nút mic để nói vào terminal hoặc phiên AI." / "ShellX chuyển lời bạn nói thành chữ cho terminal hoặc phiên AI bằng tính năng nhận dạng giọng nói của Apple; Apple có thể xử lý ngay trên điện thoại hoặc trên máy chủ của Apple."). `CFBundleLocalizations` = en, vi (`Info.plist:17-21`).
- Commit `6cd7108` (V2-2b B15) added "or an AI session" to both strings (before: terminal only).
- `UIBackgroundModes` = `remote-notification` only (`Info.plist:48-51`): no `audio` mode. `Runner.entitlements` holds only `aps-environment`.
- Pinned by `M/test/platform_config_test.dart:102-111, 128-135`.

### 2.3 Android (`M/android/app/src/main/AndroidManifest.xml`)
- `:7-8` `<uses-permission android:name="android.permission.RECORD_AUDIO"/>` (comment: "asked at run time on the first mic tap").
- `:76-79` `<queries><intent><action android:name="android.speech.RecognitionService"/></intent></queries>` (Android 11+ package visibility for the recognizer).
- Other permissions present: `INTERNET` (`:2`), `CAMERA` (`:3`), `USE_BIOMETRIC` (`:4`), `POST_NOTIFICATIONS` (`:6`).
- **Not declared:** `BLUETOOTH*`, `FOREGROUND_SERVICE*`, `WAKE_LOCK`; no `<service>`. (The plugin README expects BLUETOOTH, BLUETOOTH_ADMIN and BLUETOOTH_CONNECT, `PLUGIN/README.md:245-258`; its own manifest is empty.)
- Pinned by `M/test/platform_config_test.dart:234-238`.

---

## 3. UX flow

### 3.1 Starting (AI composer)
1. The mic is an `IconButton` with key `ai.mic` between the text field and Stop/Send (`ai_dock.dart:676-689`). Tooltip "Speak a message" / "Nói tin nhắn" (`aiMicTooltip`). It is passed unconditionally (`ai_session_page.dart:573`), so it shows whenever the composer shows, whatever the computer offers (spec B1 does not gate it; test `ai_session_page_voice_test.dart:170`). The whole composer is hidden when the session is closed or unavailable (`ai_session_page.dart:496-498`).
2. Tap -> `_mic()` (`ai_session_page.dart:256-266`): creates `AiDictation` lazily from `getIt` (`:258`, "a page that never hears needs no recognizer"), calls `attach(text: _text, canSend: ..., onSend: ...)` (`:259-263`; `canSend` = the session can take a message **and** the field has text or there are images, `:261`), sets the `_dictationMade` signal (`:264`, see F43), then `toggle(Localizations.localeOf(context).languageCode)` (`:257, 265`).
3. `AiDictation.toggle` (`ai_dictation.dart:84-93`): if already listening it calls `_speech.stop()` (the final result still arrives and is applied); otherwise it picks the language and runs `_start()` (`:102-136`): `ensurePermission()` (the first call shows the OS prompts) -> `resolveLocale()` -> remembers the field text (`_committed`, `_shown`) -> phase `listening` -> `SpeechInput.start(localeId, onDevice: tryOnDeviceFirst)`.

### 3.2 While listening: partial results
- Each `SpeechPartial` replaces the previous one in place, after the text that was already in the field, caret at the end (`ai_dictation.dart:147-150, 215-223`). There is no separate caption area: the composer field is the caption.
- The indicator is the filled mic (`IconButton.filled(Icons.mic)`, tooltip "Stop listening" / "Dừng nghe", `ai_dock.dart:677-683`). **No pulse, no "Listening..." hint in the field, no screen-reader announcement** in the AI composer (the terminal composer has all three: `mic_button.dart:84-133`, `voice_composer.dart:69-86, 118-123`; ledger `SDD/progress.md:506`).
- The AI field stays editable while listening; typing ends the listen (F41, section 6.5).

### 3.3 Stopping, timeouts, silence
A listen ends on the first of:
1. a second tap on the mic;
2. **`pauseFor` = 2 s** and **`listenFor` = 60 s** (`speech_to_text_input.dart:106-107`; comment at `speech_input.dart:72`). The plugin implements `pauseFor` as a Dart timer on "time since the recognized text last changed" (`PLUGIN/lib/speech_to_text.dart:529-593`, updated at `:678-684`). It is text staleness, not audio voice-activity detection;
3. limits the OS imposes: Apple stops a recognition task after about one minute (quoted at `PLUGIN/README.md:501`); Android has "a system imposed pause of from one to three seconds that cannot be overridden" (`PLUGIN/lib/speech_to_text.dart:401-405`, `README.md:330-332`). 7.4.0 also passes `pauseFor` to Android as `EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS` (`PLUGIN/android/.../SpeechToTextPlugin.kt:693`, CHANGELOG 7.4.0); whether the recognizer service honours it is unverified;
4. the page: the app is not `resumed` (`ai_session_page.dart:95-101`), the session link is not live (`:102-105`), any send (`:153`), or the page is disposed (`:112`);
5. the user types in the field (cancelled at the next recognizer report, `ai_dictation.dart:140-145`);
6. an error (`_onFailed`, `:186-206`).

After a final result the phase goes idle (`:151-156`). **One utterance per tap; nothing re-arms the mic.**

Silence specifics: `error_no_match` / `error_speech_timeout` map to `SpeechErrorKind.noMatch`, which is silent (no message, `ai_dictation.dart:204`). After `stop()` the plugin waits up to its 2 s `finalTimeout` for the OS's final result and otherwise builds one from the last partial (`PLUGIN/lib/speech_to_text.dart:123, 351-352, 672-676`). So last word -> final result can take about 2 s (`pauseFor`) plus up to 2 s (derived, not measured). A `done` without a final leaves a "drained" listen that the next tap discards (`ai_dictation.dart:104-105`).

### 3.4 The send keyword (and cancel)
- Send words: `gửi` (vi), `send` (en). Cancel words: `huỷ`, `hủy` (vi), `cancel` (en) (`voice_locale.dart:4-5`). They are language-bound: "send" said while listening in Vietnamese is just text (`voice_command_parser_test.dart:32`).
- Match rule (`voice_command_parser.dart:39-51`): trailing whitespace/punctuation stripped, then the **last whitespace-delimited word of the final result**, lower-cased, must equal a keyword. "gửi email cho tôi" stays text. Partial results never trigger anything. No Unicode normalization or diacritic folding (the stored keywords are NFC); a recognizer that wrote "gui" would not send (not tested on a device).
- Effects in the AI composer (`ai_dictation.dart:170-182`):
  - send keyword: the words (without the keyword) are added to the field, then `onSend` runs only if `canSend()` (live session and text or images). Otherwise the words just stay and nothing is sent (page tests `:103`, `:192`);
  - cancel keyword: drops only what was just said, never what was typed (ruling R9, `docs/superpowers/plans/2026-10-15-v2-2b-phone-ai-more.md:59`);
  - "gửi" with an empty field and no images sends nothing (the terminal composer would send a bare Enter).
- Design rationale: the terminal voice spec's success criterion 2, "no recognition turn runs anything until the user says gửi/send or taps Send" (`docs/superpowers/specs/2026-10-06-mobile-voice-input-design.md:17`, decision V3 `:29`).

### 3.5 Language choice and where the locale comes from
- Two languages only: Vietnamese `vi-VN`, English `en-US` (`voice_locale.dart:4-5`). One language per listen; no auto-detection, no mixed-language recognition.
- Per toggle: `AppSettings.voiceLocale` if the user ever chose one, else `VoiceLocale.fromLanguageCode(Localizations.localeOf(context).languageCode)` (`ai_dictation.dart:91`; `voice_locale.dart:25`: `vi` -> Vietnamese, anything else -> English). The app's own languages are en and vi and follow the device language (`M/lib/shared/src/l10n.dart:3845-3850`, `M/lib/features/app/app.dart:65`).
- **The only place that writes the choice is the terminal composer's VI/EN control** (`voice_composer_controller.dart:110-116`, widget `voice_composer.dart:142-146, 250-297`). The AI composer has no language control and no indicator; a user who only uses AI sessions cannot change it. Its "missing language" message still says "try EN / try VI" (the terminal's words; ledger `SDD/progress.md:506`).
- Locale id resolution (`speech_to_text_input.dart:13-32, 83-95`): the plugin's `locales()` is awaited for at most 2 s (Android 13+ may never answer), then the exact `vi-VN`/`en-US` (either separator style) or any id of the same language, else the preferred id anyway.
- Android plays system start/stop beeps on every listen and "there is no supported way to disable it" (`PLUGIN/README.md:334-336`). iOS plays nothing; the plugin can play optional sound assets, ShellX ships none (`M/assets/` holds fonts, icons, images, licenses).

### 3.6 Terminal composer vs AI composer

| Aspect | Terminal (`VoiceComposer`) | AI composer (`AiDictation`) |
|---|---|---|
| Entry | `MicButton` leading the extra-keys row (`terminal_page.dart:355-376`); pulses while listening, honours reduce-motion (`mic_button.dart:84-133`) | `ai.mic` icon button; filled while listening; no pulse |
| Field | own panel above the keys, own `TextField`, read-only while listening (`voice_composer.dart:160-193`) | the session's normal field; editable while listening, typing ends the listen |
| Language control | VI/EN segmented control, disables a language the phone lacks | none |
| "huỷ" / "cancel" | clears the whole composer (`voice_composer_controller.dart:214-215`) | drops only the utterance just spoken (R9) |
| "gửi" on empty | sends a bare Enter | sends nothing |
| Hint and screen-reader | "Đang nghe... nói “gửi” để gửi", announcement | none |
| Issue message | composer line plus "Mở Cài đặt" button (`voice_composer.dart:210-233`) | one red `note` line above the field, **no Open Settings button** (`ai_dock.dart:630-638`) |
| Lifecycle | `pause()` on inactive and hide (`terminal_page.dart:75-83`) | `stop()` on any state other than resumed (`ai_session_page.dart:99`) |
| Draft | per-terminal draft (A11 D29) | the session's draft (`AiDrafts`) |

---

## 4. Recognition: on-device or server?

- **OS recognizers only.** Apple `SFSpeechRecognizer`, Android `SpeechRecognizer` (Google app or OEM service). No ShellX server, no relay involvement, no Whisper. The original spec rejected "Whisper cloud through the relay" (breaks the blind-relay principle) and on-device whisper.cpp ("heavy") (`docs/superpowers/specs/2026-10-06-mobile-voice-input-design.md:30`). Audio never reaches ShellX servers (`:99-105`; privacy page `web/src/pages/en/privacy.md:51-55`).
- **Flags set** by `SpeechToTextInput.start` (`speech_to_text_input.dart:102-112`): `localeId`, `pauseFor: 2 s`, `listenFor: 60 s`, `partialResults: true`, `onDevice: <argument>`, `listenMode: dictation`, `cancelOnError: true`.
- **Options available in 7.4.0 and not used:** `autoPunctuation` (iOS 16+, default false), `contextualPhrases` (iOS `contextualStrings`; Android 13+ `EXTRA_BIASING_STRINGS`; `PLUGIN` platform interface `speech_to_text_platform_interface.dart:118-125`), `sampleRate`, `enableHapticFeedback`, and `onSoundLevelChange` (no audio level is ever read: grep finds no use in `M/lib`).
- **`onDevice` flag:**
  - `SpeechInput.tryOnDeviceFirst` is true on **Android only** (`speech_to_text_input.dart:65-68`). The first Android listen asks `onDevice: true`; a failure before any words with `localeUnavailable` or `other` gets exactly one retry with `onDevice: false` (cloud) (`ai_dictation.dart:186-194`; same in the terminal controller `voice_composer_controller.dart:231-239`).
  - On **iOS** it is always `false`: Apple decides between phone and server. The plugin cannot fall back from on-device to cloud within one listen on iOS (spec V4). The plugin sets `requiresOnDeviceRecognition` only when `onDevice` is true (`PLUGIN/darwin/.../SpeechToTextPlugin.swift:557-559`), and `taskHint = dictation` (`:562`).
  - (derived) On Android `onDevice: true` creates `createOnDeviceSpeechRecognizer` only on API 31+ when `isOnDeviceRecognitionAvailable`; below that, or without a language pack, the default (Google) recognizer is used, with `EXTRA_PREFER_OFFLINE` (`PLUGIN/android/.../SpeechToTextPlugin.kt:623-631, 687-689`). So "on-device first" is truly on-device only on Android 12+ with the pack. The model is `LANGUAGE_MODEL_FREE_FORM` (`:672`).
- **Privacy copy:** iPhone, "Apple may process the audio on the phone or on its servers"; Android, on the phone when it can, else Google (`privacy.md:17, 51-55, 97`). Line 53 still says the mic is used "only when you tap the mic on the terminal screen"; the AI composer mic was not added to the privacy pages (V2-2b B15 changed only the iOS strings; web pages are committed in the relay worktree per R13, `SDD/progress.md:526`).

---

## 5. Spoken output

**None.** Evidence:
- no TTS or audio package in any pubspec (section 2.1);
- no `AVSpeechSynthesizer` / `TextToSpeech` code: `M/ios/Runner/AppDelegate.swift` only registers notification categories; `M/android/app/src/main/kotlin/com/shellx/prod/MainActivity.kt` only creates the notification channel;
- no "read aloud" setting or string;
- not in any spec or plan: the original voice spec's out-of-scope list (§8, `docs/superpowers/specs/2026-10-06-mobile-voice-input-design.md:150-156`) names natural-language-to-shell, voice keys (Ctrl+C, arrows, tab switching), Whisper/cloud STT, wake word and background listening, and voice on web and desktop. TTS is not even mentioned. The V2-2 spec's stop-gap for dictation was the OS keyboard's own mic (`docs/superpowers/specs/2026-10-14-v2-2-phone-ai-design.md:384`).

The only audible outputs are incidental: the terminal composer's screen-reader announcement "Đang nghe" (`voice_composer.dart:79-86`) and Android's system start/stop beeps.

---

## 6. Errors and permissions

### 6.1 Permission model
`ensurePermission()` (`speech_to_text_input.dart:70-81`): the first call runs `SpeechToText.initialize`, which shows the OS prompts (iOS: speech authorization, then microphone, in sequence, `PLUGIN/darwin/.../SpeechToTextPlugin.swift:249-255`; Android: `RECORD_AUDIO`, plus an undeclared `BLUETOOTH_CONNECT` request that cannot be granted, `PLUGIN/android/.../SpeechToTextPlugin.kt:499-511`). `_ready` is cached. Result: `granted`; `unsupported` (init failed but `hasPermission` is true: no recognizer or recognition turned off); `denied` (any other failure or exception).

### 6.2 Error mapping and what the user sees
`speechErrorKind` (`speech_to_text_input.dart:36-52`) maps Android and iOS error names to `SpeechErrorKind`. In the AI composer (`ai_dictation.dart:198-205`, page `ai_session_page.dart:579-588`):

| Kind | Message (EN) | Note |
|---|---|---|
| `noPermission` | "ShellX needs microphone and speech recognition access to take spoken commands" | no Open Settings button |
| `unsupported` | "Speech recognition isn't available on this phone" | |
| `localeUnavailable` | "This phone can't recognize Vietnamese yet — try EN" (or English/VI) | the AI composer has no language switch |
| `network` | "Speech recognition needs a network connection" | |
| `other` | "Couldn't recognize that, try again" | |
| `noMatch`, `interrupted` | nothing | silent stop |

The line is sticky: cleared only at the next listen start (`ai_dictation.dart:108`), survives edits and Send, no close button (ledger `SDD/progress.md:505`, deferred).

### 6.3 Lifecycle stops
Not `resumed` (`ai_session_page.dart:99`; a call, the notification shade, an OS prompt, lock and background all stop the listen), link not live (`:102-105`), any send (`:153`), dispose (`:112`). Edits end the listen (6.5).

### 6.4 F40, the first-tap permission finding
- **Finding** (task 19 review, `SDD/progress.md:500`, Important 1): a first-ever permission refusal was never shown. The OS prompt takes the app out of the foreground (`inactive`), the page calls `stop()`, and `_start()` returned on `_stopped` right after `ensurePermission()` (old `ai_dictation.dart:102`), before the `noPermission` issue was set. "Don't Allow" showed nothing. The terminal composer already did it in the right order (`voice_composer_controller.dart:158-170`, `_paused` checked last).
- **Ruling and fix** (F40, `SDD/progress.md:501`, `SDD/handoff-14-19.md:56`, commit `03fc266`): after `ensurePermission` and after `resolveLocale` only `_disposed` aborts; denied/unsupported/locale issues are recorded first; `_stopped` is checked once just before `_active = true` (`ai_dictation.dart:109-123`; re-review `SDD/progress.md:513`).
- **What F40 deliberately did not fix:** a *granted* answer to the first prompt still drops that first listen, because the prompt put the app `inactive` and the page called `stop()`. The user must **tap the mic a second time** after "Allow", with no visible hint (`SDD/progress.md:506, 509`; `SDD/handoff-14-19.md:106`). The terminal composer behaves the same (test `voice_composer_controller_test.dart:269`). It is a device-only behaviour, so it is a pending manual check (`SDD/task-26-manual-checks.md`, item 6).
- **Tests:** `ai_dictation_test.dart:170-211` (group "stop() while the permission prompt is up (F40)", incl. `:201` "a granted permission: nothing is said and the listen still does not start; the next tap does"); page-level `ai_session_page_voice_test.dart:220`.

### 6.5 F41, typed text survives dictation
Found in the same review (Important 2): every partial/final/"huỷ" rewrote the whole field from `_committed`, destroying text typed during a listen. Fix (`03fc266`): the dictation remembers the text it last showed (`_shown`, `ai_dictation.dart:126, 218`); a field that differs when the next event arrives was typed in, so the listen is cancelled and the event dropped (`:140-145`), and nothing from that listen (words, "gửi", "huỷ", failure) touches or sends the field. Residual (deferred): after a keystroke the mic icon stays filled until the recognizer's next report (`SDD/progress.md:514`). Tests `ai_dictation_test.dart:213-311`, `ai_session_page_voice_test.dart:300`.

### 6.6 F43, the stale `Watch`
- **Finding** (found while fixing F40, `SDD/progress.md:509-510`): the composer dock is built inside a signals_flutter `Watch`. The `AiDictation` is created lazily at the first mic tap and held in a plain nullable field, so the dock's last tracked run had read no dictation signals. In signals_flutter 6.3.1, `Watch.didUpdateWidget` re-runs the builder outside the tracking context (`recompute()`), so no dependency is recorded after a `setState`-only change. On a real device the mic would never fill while listening and a late refusal would never show. The tests' fake answers in microtasks, which hid it.
- **Fix** (`03fc266`): a page signal `_dictationMade` (declared `ai_session_page.dart:82`, set in `_mic()` `:264`, read first in `_dock` `:492`), and the voice issue read before `note:` so the dock always tracks `phase` and `issue` (`:503, 571-572`). The re-reviewer reproduced the old and new wiring in a scratch project (`SDD/progress.md:513`). Tests: `ai_session_page_voice_test.dart:243, 259`.
- **Open:** the ledger calls this a library-level hazard: 49 `Watch(` call sites in 18 files under `M/lib`, not audited (`SDD/progress.md:515`, `SDD/handoff-14-19.md:73`; a fresh grep today finds 46 matches in 18 files). The final review plan includes an audit (`SDD/progress.md:532`, item d).

### 6.7 Other open voice items at HEAD (re-checked in code)
- A listen keeps running under pages pushed over the session page: `_viewAll` pushes `AiItemRoute` without stopping the dictation (`ai_session_page.dart:609-612`); "leaves the page" means dispose only. Ledger: "likely fix before merge, cheap" (`SDD/progress.md:504`). Same for the chooser and sheets. A "gửi" heard there could still send.
- A mic tapped while the session is not live listens until the next `version` bump (the stop is an effect on `version`, `:102-105`) (`SDD/progress.md:496`).
- Two copies of the recognizer state machine (F42).
- Test gaps the review listed: English "cancel", `done` before `final`, a late `done` of an earlier listen, `localeUnavailable` then a second failure, a narrow composer with every button (`SDD/progress.md:506`).
- No on-device result is recorded anywhere: manual checks are listed (`docs/superpowers/HANDOFF.md:133-141`, `docs/superpowers/GOLIVE-v1.md:79-81, 91`, `SDD/task-26-manual-checks.md` item 6) and none is marked done.

---

## 7. Desktop

**No voice input on the desktop.** Searched `apps/desktop` (lib, tests, pubspec, macOS `Info.plist`, both entitlements files, Windows runner): no speech/voice/microphone/audio code or package, no `NSMicrophoneUsageDescription`, no `com.apple.security.device.audio-input`. Both macOS entitlements files have the sandbox off and no audio key (`apps/desktop/macos/Runner/Release.entitlements`, `DebugProfile.entitlements`). The original voice spec lists "voice on web and desktop" as out of scope (`docs/superpowers/specs/2026-10-06-mobile-voice-input-design.md:156`). Related: the V2-3/V2-4 tool webviews deny the microphone permission (`docs/superpowers/specs/2026-10-15-v2-3-tools-desktop-design.md:76` D9, `...v2-4-tools-phone-design.md:73` E12), so a tool page cannot host a voice mode either. (If voice were ever added on macOS, the hardened-runtime audio-input entitlement and usage strings would be new; that is general platform knowledge, not checked here.)

---

## 8. Tests that cover voice

All under `M/test/`. Counts are grep counts of `test(`/`testWidgets(`; I did not run anything (ledger: mobile 1441 passing at `03fc266`, `SDD/progress.md:517`).

| File | Tests | Covers |
|---|---|---|
| `features/voice/voice_command_parser_test.dart` | 12 | keyword matching per language, punctuation, case, "gửi" alone, mid-sentence, cross-language keywords |
| `features/voice/speech_to_text_input_test.dart` | 8 | **only** the pure helpers `pickLocaleId`, `localeIdOrPreferred`, `speechErrorKind` |
| `features/voice/voice_composer_controller_test.dart` | 29 | terminal controller: partials, send/cancel, permission/locale/network/no-match, cloud retry, pause, close, dispose, late `done`, iOS path |
| `features/voice/draft_test.dart` | 6 | per-terminal drafts |
| `features/ai/ai_dictation_test.dart` | 26 | AI controller: app vs saved language, on-device first, partial/final, send, English "send", cancel (R9), stop, F40 group (4), F41 group (9), dispose |
| `features/ai/ai_composer_mic_test.dart` | 3 | mic icon states, tap handed to the page, mic works when sending is impossible |
| `features/ai/ai_session_page_voice_test.dart` | 15 | on the real page with the fake: words and "gửi", not-live, lifecycle, leaving, Send while listening, refusal, F40, F41, F43 wiring |
| `features/terminal/terminal_page_test.dart` | 13 in group `voice composer` (`:1408-1648`) + 1 layout test (`:491`) | terminal UI: composer, locale chip, hints, a11y, AA contrast |
| `core/settings/app_settings_test.dart` | 2 (`:65-85`) | voice language storage |
| `platform_config_test.dart` | 3 (`:102, :128, :234`) | iOS usage strings in both languages, B15 wording, Android `RECORD_AUDIO` and the recognizer query |
| `support/fake_speech.dart` | n/a | `FakeSpeechInput`; DI-only users: `app_test.dart`, `ai_entry_test.dart`, `ai_entry_pages_test.dart`, `agent_reply_bar_test.dart`, `terminal_fixed_height_test.dart` |

Total voice-specific tests: about 118. **Not covered:** the `SpeechToTextInput` class itself (no instantiation, no plugin-channel mock), so the listen options (2 s, 60 s, dictation, `cancelOnError`) and the permission/initialize paths are unpinned; any audio behaviour; no `integration_test` directory and no E2E flows exist in `apps/mobile`.

---

## 9. What is missing compared with a ChatGPT-style voice conversation

Legend: **Change** lists the code that would have to change (existing files first, then new ones). Every voice change also ripples through: DI regeneration (`dependency.config.dart`), ARB strings plus generated `M/lib/shared/src/l10n.dart` and `intl/messages_*.dart`, `FakeSpeechInput`, `platform_config_test.dart` pins, and the privacy pages (those live under `web/` and the V2-2b rule is to commit them in the relay worktree, `SDD/progress.md:526`).

### G1. Continuous hands-free turn-taking with automatic end-of-speech detection
- **Today:** push-to-talk, one utterance per tap (3.3). End of speech is the plugin's "text unchanged for 2 s" timer plus whatever the OS does; no acoustic VAD, and ShellX never sees audio levels. Sending needs the keyword or a Send tap by design (spec V3, criterion 2). Nothing re-arms the mic after a final (`ai_dictation.dart:151-156`).
- **Missing:** a re-arm loop; a configurable/acoustic endpoint; an auto-send policy (a ruling is needed: it reverses the voice spec's criterion 2, and the plan glosses "gửi" as "the user's own word", `docs/superpowers/plans/2026-10-15-v2-2b-phone-ai-more.md:20220`); seamless restarts across the iOS ~1 min cap and Android's short silence timeout, without Android's start/stop beeps repeating (cannot be disabled, `PLUGIN/README.md:334-336`); a state machine that joins listen -> send -> agent turn -> reply -> listen.
- **Change:**
  - `M/lib/features/ai/presentation/controllers/ai_dictation.dart` (one-shot design, `:84-168`) or a new conversation controller beside it.
  - `M/lib/features/voice/domain/speech_input.dart:58-80` and `.../data/speech_to_text_input.dart:97-118`: `pauseFor`/`listenFor` are constants shared by both composers and must become arguments of `start(...)`; or a new `SpeechInput` implementation that owns capture and endpointing (the interface was written for this swap, spec V7). The README says the current engine is not for continuous use.
  - `M/lib/features/ai/presentation/pages/ai_session_page.dart:95-105, 151-153, 254-266`: the glue assumes one-shot (`_send()` stops the dictation first; any non-resumed state stops it).
  - `M/lib/features/voice/domain/voice_command_parser.dart:37-52`, `voice_locale.dart:4-5`: the keyword becomes optional or changes meaning.
  - Turn-end signal to observe: `AiSessionController.version` (`ai_session_controller.dart:122`, bumped in `_onChange` `:522`), `MirrorHead.running` (`packages/shellx_ai/lib/src/remote/mirror.dart:314`), `MirrorTurnEnd` (`mirror.dart:153`).
  - Tests: `test/support/fake_speech.dart`, `ai_dictation_test.dart`.

### G2. Spoken replies
- **Today:** none (section 5). Agent text is on the phone as `MirrorText(kind: agent)` items (`mirror.dart:22-51`), shown by `AiMarkdown` (`M/lib/features/ai/presentation/widgets/ai_markdown.dart`).
- **Missing:** a TTS engine and a `SpeechOutput` abstraction; a speaker that watches the session and decides when to speak (after the turn ends, or sentence by sentence while it streams); voice/rate/language settings; stop/pause/replay controls; the text preparation in G8.
- **Change:**
  - `M/pubspec.yaml`: a TTS package (pin it exactly like the others) or native `AVSpeechSynthesizer` / `android.speech.tts.TextToSpeech` behind a channel.
  - `M/android/app/src/main/AndroidManifest.xml:67-80`: Android 11+ package visibility may need a TTS-service `<queries>` entry (not checked; depends on the plugin).
  - New in `M/lib/features/voice/`: `domain/speech_output.dart` (mirrors `SpeechInput`), `data/` implementation (`@LazySingleton`), a controller that observes `AiSessionController` (`version`, `mirror.changed` at `mirror.dart:464`, `head`) and speaks agent text of the current turn.
  - `M/lib/features/ai/presentation/pages/ai_session_page.dart` (entry point, lifecycle), `M/lib/core/settings/app_settings.dart:12-16, 90-93` (on/off, voice, rate), ARB strings.

### G3. Barge-in (interrupt the reply by speaking)
- **Today:** nothing to interrupt, and no full-duplex capture: the plugin takes over the audio session for each listen and gives it back afterwards (`PLUGIN/darwin/.../SpeechToTextPlugin.swift:519-528, 446-466`). The nearest existing controls are tap-based: Stop (`AiSessionController.stop()`, `ai_session_controller.dart:261-274`), Force stop (`:277-280`), queue (a prompt sent while a turn runs is queued, up to 5: `ai_dock.dart:706-714`, `mirror.dart:317-321`; `unqueue` `:283-286`). Speaking "gửi" during a running turn therefore **queues** a prompt; it does not interrupt.
- **Missing:** detecting user speech while the assistant speaks; stopping the TTS within a few hundred ms; deciding what a spoken interruption does to the running agent turn (silence only, cancel via `ai.cancel`, or queue); keeping the recognizer open during playback, which needs G7.
- **Change:** the new conversation controller (G1/G2) as arbiter between `SpeechOutput.stop()`, `SpeechInput` and `AiSessionController.stop()`/`unqueue()`; `SpeechInput` must stay open during playback (it does not today); UI state "interrupted". Product decision: cancelling a running agent turn by voice is destructive; D13 covers permission answers only, but it should be ruled on.

### G4. Dedicated voice screen with an animated indicator
- **Today:** no voice route. Routes are `AiSessionRoute` and `AiItemRoute` (`M/lib/core/router/app_router.dart:27-28`). The AI indicator is a filled icon (`ai_dock.dart:677-683`); only the terminal's `MicButton` pulses (`mic_button.dart:84-133`, with reduce-motion at `:115`). No level meter: `onSoundLevelChange` (`PLUGIN/lib/speech_to_text.dart:411-414`; iOS decibels, Android values "differ") is never passed. No thinking/speaking states.
- **Change:** a new `@RoutePage` voice page plus a route entry in `app_router.dart` and regenerated `app_router.gr.dart` (the hand-off warns about renumbering, `SDD/handoff-14-19.md` "Generator renumbering"); an entry point in `AiComposer` / the page header; a level event in `speech_input.dart:25-55` and the adapter passing `onSoundLevelChange` at `speech_to_text_input.dart:102`; the animated widget (pattern: `_Pulse`); colour tokens `M/lib/core/design/app_colors.dart`; a11y announcements (pattern `voice_composer.dart:79-86`); ARB strings; widget tests with `test/support/app_harness.dart`.

### G5. Live captions
- **Today:** only the user's partials, written live into the composer field (`ai_dictation.dart:147-150, 215-223`). The agent's words appear as markdown in the timeline, item by item. Nothing is synchronized with speech.
- **Missing:** a caption surface for both speakers on the voice screen; highlighting synchronized with TTS progress; handling partials that get revised (the plugin replaces them).
- **Change:** the voice page (G4); the existing `SpeechPartial` events (`speech_input.dart:30-35`); progress callbacks from the new `SpeechOutput` (G2); the sentence splitter from G8.

### G6. Audio session handling (ducking, Bluetooth, background)
- **Today:** ShellX has **no audio-session code** (no `audio_session`, no `AVAudioSession`/`AudioManager` use in `M/ios/Runner`, `M/android/app/src/main`, `M/lib`; no wakelock). What exists is the plugin's per-listen behaviour:
  - iOS: category `playAndRecord` with `defaultToSpeaker, allowBluetooth, allowBluetoothA2DP, mixWithOthers`, mode `.default`, activated at the start of every listen; the previous category restored and the session deactivated at the end (`SpeechToTextPlugin.swift:519-528, 446-466`). So other audio is neither ducked nor paused, a Bluetooth headset mic is allowed, and nothing is held between listens.
  - Android: the system recognizer; no audio-focus request in the plugin (derived). Bluetooth headset routing works only if `BLUETOOTH_CONNECT` is granted. The plugin asks for it with `RECORD_AUDIO` (`SpeechToTextPlugin.kt:499-511`), but ShellX does not declare it (`AndroidManifest.xml:2-8`) and calls `initialize` without `androidNoBluetooth` (`speech_to_text_input.dart:74`). So it cannot be granted and the plugin sets `bluetoothDisabled` (`:501, :716-719`) (derived).
  - Background: iOS has no `audio` background mode (`Info.plist:48-51`); Android has no foreground service or `FOREGROUND_SERVICE_MICROPHONE`; every dictation stops when the app is not `resumed` (`ai_session_page.dart:97-99`; `terminal_page.dart:75-83`); no wakelock, so the screen's auto-lock ends a listen the same way. A phone call surfaces as `error_audio_error` -> `interrupted` -> silent stop (`speech_to_text_input.dart:50`, `ai_dictation.dart:204`). No route-change or interruption-ended handling.
- **Missing:** ducking or pausing other audio; deliberate routing (speaker, earpiece, Bluetooth) and route-change handling (headphones unplugged); interruption begin/end; audio that survives screen lock; a wake lock in voice mode; an Android foreground service; an iOS audio background mode.
- **Change:** a new audio-session wrapper used by `SpeechToTextInput` and the new `SpeechOutput`; `M/ios/Runner/Info.plist:48-51` (`audio`); `AndroidManifest.xml` (`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE`, `BLUETOOTH_CONNECT`, a `<service ... foregroundServiceType="microphone">`) plus the service code; the lifecycle policy in `ai_session_page.dart:95-105`; `platform_config_test.dart` pins. The AI session link must also stay live in the background (not investigated: `AiSessionController.setForeground` only stops the turn clock, `ai_session_controller.dart:174-178`). Store-review justification for background audio and a microphone foreground service is a separate cost (platform knowledge, not re-verified).

### G7. Echo cancellation
- **Today:** none, and not needed yet, because nothing plays while the mic is open. iOS mode is `.default` (`SpeechToTextPlugin.swift:527`), so no system voice processing; on Android the app cannot choose the audio source of the system `SpeechRecognizer` (the plugin's recognizer intent has no source extra, `SpeechToTextPlugin.kt:666-696`) (derived).
- **Missing:** acoustic echo cancellation and noise suppression. They become mandatory once TTS plays while the mic is open: the recognizer would transcribe the assistant. The cheap alternative is half-duplex (mic closed while speaking), which rules out barge-in.
- **Change:** half-duplex needs only the new conversation controller (close the listen before TTS, reopen after a guard delay). Full duplex needs iOS `voiceChat` mode / voice-processing I/O and Android `AudioRecord` with `VOICE_COMMUNICATION` plus `AcousticEchoCanceler`, which means an own capture and STT pipeline: a new `SpeechInput` implementation (`speech_input.dart:58-80`) or a patched plugin (precedent: `third_party/xterm` is vendored and patched). The plugin hard-codes the iOS mode.

### G8. Long and code-heavy agent replies
- **Display pipeline today** (what voice would inherit):
  - Delivery: an agent answer is one `MirrorText` item, sent in pieces of at most 32 KiB UTF-8 (`packages/shellx_ai/lib/src/remote/wire.dart:24`; `item_codec.dart:30-65`, `r = -1` until the last piece), replaced by newer revisions while it streams. Thoughts are separate items (`MirrorTextKind.thought`); tool calls, outputs and diffs are `MirrorTool` items cut to about 4 KiB at each end (`wire.dart:28, 31`, `ai_text.dart:91-98`); permissions and questions are tap-only panels (`head.permission`, `head.ask`).
  - Display caps: `AiMarkdown` lays out at most 20 000 characters and 200 blocks (`ai_markdown.dart:45-50`; `M/lib/features/ai/domain/ai_text.dart:82-89`); beyond that the hint "The rest of this message is on the computer." and a "View all"/"Xem đủ" button open the full item (up to 2 MiB, in 36 KiB slices) on `AiItemRoute` (`ai_markdown.dart:63-72`, `full_view.dart:14-18`). An older page of a long answer can arrive clipped (`MirrorText.fullLength`, `mirror.dart:37-38`).
  - Markdown: blocks split at blank lines outside code fences (`ai_text.dart:37-75`); code in JetBrains Mono on a tinted block (`ai_markdown.dart:111-117`); links http/https only (`:127-133`); images show alt text (`:126`).
  - The 20 000-character cap is a layout cap. The live `MirrorText.text` holds the whole streamed answer, so a TTS should read the mirror, not the widget.
- **For voice there is no policy at all.** Missing:
  - item selection: agent text of the current turn only, never thoughts, tool output, diffs or the user's own text;
  - markdown-to-speech: strip markup; replace or skip fenced blocks, tables, diffs, long paths and URLs ("code block, 12 lines"); read inline identifiers sensibly;
  - language per segment: replies mix Vietnamese prose with English identifiers, and TTS voices are per language;
  - length policy: a 20 000-character answer is many minutes of speech; read the first paragraph or a summary, offer "more", allow skip/pause/resume;
  - streaming policy: sentence by sentence while pieces arrive, versus after the turn ends; revisions of an item replace its text;
  - what to say when the agent stops for a permission or question (G9).
- **Change:** a new pure-Dart speakable-text module next to `markdownBlocks` / `clipForDisplay` (`ai_text.dart:47-75, 107-121`), table-tested like `ai_text` is today; the observer from G2; `AppSettings` entries (skip code, maximum length). `AiMarkdown` itself only changes if captions highlight text.

### Additional gaps a ChatGPT-style flow would hit (not on your list)
- **G9. Answering permission requests and questions by voice.** The permission and question panels (`AiPermissionPanel`, `AiAskPanel`, `ai_session_page.dart:506-535`) are tap-only by D13; the iOS/Android push buttons were built to respect it (Face ID after the app lock, one-time choices). A hands-free agent session will stall at every permission request unless D13 is revisited or the voice mode announces the request and hands off to the screen.
- **G10. Language handling.** Two languages, one per listen, no auto-detect; the AI page cannot change the language (section 3.5); no recognition biasing for developer vocabulary although `contextualPhrases` exists in 7.4.0.
- **G11. Privacy and policy text.** The privacy page says the mic is used only on the terminal screen (`web/src/pages/en/privacy.md:53`); hands-free listening, TTS and any background audio change what must be stated (and the store privacy labels, `docs/superpowers/GOLIVE-v1.md:101` S-04).
- **Wake word / always-on listening** is explicitly out of scope in the original spec (`docs/superpowers/specs/2026-10-06-mobile-voice-input-design.md:155`).

---

## 10. Seams that already exist (what a new voice mode can reuse)

- `SpeechInput` (`speech_input.dart:58-80`) and `FakeSpeechInput`: the engine swap point, with the tests already written against it.
- `AiDictation.attach(text, canSend, onSend)` (`ai_dictation.dart:73-81`): a field-agnostic way to hand heard words to the page and send through the page's own `_send()`.
- `AiSessionController`: `version` signal, `mirror.changed`, `head.running/turn/permission/ask/queue`, `send`, `stop`, `forceStop`, `unqueue`.
- `markdownBlocks` / `clipForDisplay` (`ai_text.dart:47-75, 107-121`) for splitting agent text.
- The `_dictationMade` pattern (F43) for any controller created after a `Watch` has first run.
- `AppSettings` (signals plus `KeyValueStore`) for new options; `AppLifecycleListener` already wired in the page; `AiItemRoute` as the example of a page pushed over a session.

---

## 11. Not verified or inferred

1. All platform behaviour in this report was read from code and plugin source, never observed: no device, simulator or test was run.
2. Android Bluetooth: "BLUETOOTH_CONNECT is never granted, so headset routing is off" follows from the manifest (`AndroidManifest.xml:2-8`), the plugin's request code (`SpeechToTextPlugin.kt:499-511, 716-719`) and `initialize` being called without options. Not tested.
3. "On-device first is only really on-device on Android 12+ with a language pack" follows from `SpeechToTextPlugin.kt:623-631`.
4. Latency figures (about 2 s `pauseFor` plus up to 2 s `finalTimeout`) are from plugin source; the original spec's goal of about 1 s after the user stops speaking (`...mobile-voice-input-design.md:16`) has no recorded measurement.
5. Whether Android recognizer services honour `EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS`.
6. Keyword matching depends on the recognizer returning exactly "gửi" (NFC); variants such as "gui" are unverified.
7. The first-tap two-tap behaviour (F40 residual) is the ledger's account of a device-only effect; it was not reproduced here.
8. Platform requirements for background audio, microphone foreground services, TTS package visibility and hardened-runtime audio entitlements are general platform knowledge, not re-checked against current documentation.
9. The ledger's count of 49 `Watch(` sites differs from today's grep (46); immaterial, but the audit is still open.
