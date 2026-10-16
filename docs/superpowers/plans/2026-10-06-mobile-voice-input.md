# Mobile Voice Input Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On the phone's terminal page, the user taps a mic, speaks (Vietnamese or English), sees the words in an editable composer, and sends them into the terminal with Enter by tapping Send or ending the utterance with "gửi"/"send".

**Architecture:** A new `features/voice/` module in `apps/mobile`: pure-Dart domain (`VoiceLocale`, `VoiceCommandParser`, the `SpeechInput` interface), one data adapter over the `speech_to_text` plugin, a signals `VoiceComposerController`, and two widgets (`VoiceComposer`, `MicButton`). The terminal page hosts the composer above the extra keys bar and sends lines through a new `TerminalPageController.submitLine`, which reuses the existing paste path, so relay, agent and protocol are untouched.

**Tech Stack:** Flutter 3.41 / Dart ^3.11, signals_flutter 6.3.1 (`Controller` + signals), get_it/injectable (generated `dependency.config.dart`), intl_utils ARB l10n, xterm 4.0.0, `speech_to_text` 7.4.0 (new), flutter_test + fake_async.

**Spec:** `docs/superpowers/specs/2026-10-06-mobile-voice-input-design.md`

## Global Constraints

- All work is inside `apps/mobile` plus `web/src/pages/privacy.md`, `web/src/pages/en/privacy.md`, `docs/superpowers/HANDOFF.md`. No change to `relay/`, `packages/`, `apps/desktop`, `term/`.
- Flutter: run every `flutter`/`dart` command with the 3.41 SDK on this machine: `~/fvm/versions/3.41.4/bin/flutter` (written `flutter` below). The fvm default 3.38.2 is too old for the workspace (`sdk: ^3.11.0`).
- `speech_to_text` is pinned **exactly** `7.4.0` (7.5.0+ needs Dart ^3.12 / Flutter 3.44; license BSD-3-Clause). Comment the pin in `pubspec.yaml` like the other exact pins.
- Speech recognition: the OS recognizer only; try on-device first, fall back to the OS cloud recognizer. Audio never goes through the relay or a ShellX server.
- Keywords (spec §3.2): VI send `gửi`, VI cancel `huỷ` / `hủy`; EN send `send`, EN cancel `cancel`; only the **last word of a final result**, only for the selected language; case, trailing punctuation and whitespace ignored.
- No voice keyword sends Ctrl+C or any key (spec V6).
- Silence timeout `pauseFor: 2 s`; one listen is at most 60 s (`listenFor`).
- Sending: text via `terminal.paste` (bracketed when the program enabled it), then `\r` **outside** the paste brackets; sticky Ctrl/Alt never apply to a composed line.
- UI strings in both `lib/l10n/intl_vi.arb` and `lib/l10n/intl_en.arb` (test `test/l10n_test.dart` enforces same keys), regenerate with `dart run intl_utils:generate`; regenerate DI with `dart run build_runner build --delete-conflicting-outputs`. Generated files are committed.
- Code style: match the surrounding code — doc comments on public members that say *why*, `// comment` density like `terminal_page_controller.dart`, no signal write after dispose (signals_core 6.3.1 throws).
- Commit after each task with a conventional message (`feat(mobile): …`, `test(mobile): …`, `docs: …`).

## Review Focus

1. **Multi-line composer text while bracketed paste is off** — each `\n` would become `\r` and run lines early; a reasonable person expects one line. `submitLine` joins line breaks with spaces when bracketed paste is off (test in Task 5).
2. **Sticky Ctrl armed when Send is tapped** — the composed line must arrive as typed, not as `Ctrl+<first letter>` (test in Task 5).
3. **A late recognition result after the composer closed or the page left** — must not write disposed signals or send anything (tests in Task 4).
4. **Double tap on the mic while permission/locale lookup is still running** — must start exactly one listen (test in Task 4).
5. **Keyword with capital letter or punctuation from the recognizer** ("Gửi.", "Send!", "run tests, send") — must still send, with the punctuation before the keyword trimmed (tests in Task 1).

---

## File Structure

| File | Responsibility |
|---|---|
| Create `lib/features/voice/domain/voice_locale.dart` | `VoiceLocale` enum: language code, preferred platform locale id, keyword sets |
| Create `lib/features/voice/domain/voice_command_parser.dart` | `VoiceCommand` (sealed) + `VoiceCommandParser.parse` — pure keyword logic |
| Create `lib/features/voice/domain/speech_input.dart` | `SpeechInput` interface, `SpeechEvent` (sealed), `SpeechErrorKind`, `SpeechPermission` |
| Create `lib/features/voice/data/speech_to_text_input.dart` | `SpeechToTextInput` (plugin adapter) + pure helpers `pickLocaleId`, `speechErrorKind` |
| Create `lib/features/voice/presentation/controllers/voice_composer_controller.dart` | Composer state machine, keyword application, on-device→cloud retry, submit gate |
| Create `lib/features/voice/presentation/widgets/voice_composer.dart` | Composer panel (target, VI/EN chips, text field, Send, ✕, issue line) |
| Create `lib/features/voice/presentation/widgets/mic_button.dart` | Mic key cap for the extra keys bar |
| Modify `lib/core/settings/app_settings.dart` | Remember the chosen `VoiceLocale` (replaces the spec's separate `VoiceLocaleStore`: the app keeps one settings object) |
| Modify `lib/features/terminal/presentation/controllers/terminal_page_controller.dart` | `submitLine(String)` |
| Modify `lib/features/terminal/presentation/widgets/extra_keys_bar.dart` | Optional `leading` widget |
| Modify `lib/features/terminal/presentation/pages/terminal_page.dart` | Host composer + mic, focus hand-off, lifecycle pause |
| Modify `pubspec.yaml`, `ios/Runner/Info.plist`, `ios/Runner/{vi,en}.lproj/InfoPlist.strings`, `android/app/src/main/AndroidManifest.xml` | Plugin + permissions |
| Modify `lib/l10n/intl_vi.arb`, `lib/l10n/intl_en.arb` (+ generated `lib/shared/src/**`) | Strings |
| Create `test/support/fake_speech.dart` | `FakeSpeechInput` for controller and page tests |
| Tests | `test/features/voice/*.dart`, `test/features/terminal/terminal_page_test.dart`, `test/features/terminal/submit_line_test.dart`, `test/core/settings/…`, `test/platform_config_test.dart` |

---

### Task 1: Voice locale and keyword parser

**Files:**
- Create: `apps/mobile/lib/features/voice/domain/voice_locale.dart`
- Create: `apps/mobile/lib/features/voice/domain/voice_command_parser.dart`
- Test: `apps/mobile/test/features/voice/voice_command_parser_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum VoiceLocale { vi, en }` with `String languageCode`, `String preferredLocaleId` (`'vi-VN'`, `'en-US'`), `Set<String> sendWords`, `Set<String> cancelWords`, `static VoiceLocale fromLanguageCode(String? code)` (`'vi'` → vi, anything else → en).
  - `sealed class VoiceCommand extends Equatable`; `final class VoiceAppend(String text)`, `final class VoiceSend(String text)`, `final class VoiceCancel()`.
  - `abstract final class VoiceCommandParser { static VoiceCommand parse(String heard, VoiceLocale locale); }`

- [ ] **Step 1: Write the failing test**

```dart
// apps/mobile/test/features/voice/voice_command_parser_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/voice/domain/voice_command_parser.dart';
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';

void main() {
  group('VoiceCommandParser, Vietnamese', () {
    const vi = VoiceLocale.vi;

    test('a trailing "gửi" sends the words before it', () {
      expect(VoiceCommandParser.parse('chạy test gửi', vi), const VoiceSend('chạy test'));
    });

    test('capital letter and trailing punctuation still send (review focus 5)', () {
      expect(VoiceCommandParser.parse('Chạy test. Gửi.', vi), const VoiceSend('Chạy test'));
      expect(VoiceCommandParser.parse('Gửi!', vi), const VoiceSend(''));
    });

    test('"gửi" alone sends an empty line (just Enter)', () {
      expect(VoiceCommandParser.parse('gửi', vi), const VoiceSend(''));
      expect(VoiceCommandParser.parse('  gửi  ', vi), const VoiceSend(''));
    });

    test('"gửi" that is not the last word is text', () {
      expect(VoiceCommandParser.parse('gửi email cho tôi', vi), const VoiceAppend('gửi email cho tôi'));
    });

    test('both spellings of "huỷ" cancel', () {
      expect(VoiceCommandParser.parse('xoá hết đi huỷ', vi), const VoiceCancel());
      expect(VoiceCommandParser.parse('Hủy.', vi), const VoiceCancel());
    });

    test('English keywords are text in Vietnamese', () {
      expect(VoiceCommandParser.parse('git status send', vi), const VoiceAppend('git status send'));
    });

    test('plain text is appended trimmed', () {
      expect(VoiceCommandParser.parse('  sửa bug trong auth service ', vi), const VoiceAppend('sửa bug trong auth service'));
    });

    test('empty input appends nothing', () {
      expect(VoiceCommandParser.parse('   ', vi), const VoiceAppend(''));
    });
  });

  group('VoiceCommandParser, English', () {
    const en = VoiceLocale.en;

    test('"send" after a comma sends the words before it (review focus 5)', () {
      expect(VoiceCommandParser.parse('run tests, send', en), const VoiceSend('run tests'));
      expect(VoiceCommandParser.parse('Run tests. Send.', en), const VoiceSend('Run tests'));
    });

    test('"cancel" cancels', () {
      expect(VoiceCommandParser.parse('never mind cancel', en), const VoiceCancel());
    });

    test('Vietnamese keywords are text in English', () {
      expect(VoiceCommandParser.parse('hello gửi', en), const VoiceAppend('hello gửi'));
    });
  });

  test('VoiceLocale.fromLanguageCode: vi is Vietnamese, anything else English', () {
    expect(VoiceLocale.fromLanguageCode('vi'), VoiceLocale.vi);
    expect(VoiceLocale.fromLanguageCode('en'), VoiceLocale.en);
    expect(VoiceLocale.fromLanguageCode(null), VoiceLocale.en);
    expect(VoiceLocale.vi.preferredLocaleId, 'vi-VN');
    expect(VoiceLocale.en.preferredLocaleId, 'en-US');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/voice/voice_command_parser_test.dart`
Expected: FAIL — `voice_command_parser.dart` / `voice_locale.dart` not found.

- [ ] **Step 3: Write the implementation**

```dart
// apps/mobile/lib/features/voice/domain/voice_locale.dart

/// The two languages the composer listens in (voice spec V2). The keywords belong to one language
/// each: "send" said while listening in Vietnamese is just a word.
enum VoiceLocale {
  vi(languageCode: 'vi', preferredLocaleId: 'vi-VN', sendWords: {'gửi'}, cancelWords: {'huỷ', 'hủy'}),
  en(languageCode: 'en', preferredLocaleId: 'en-US', sendWords: {'send'}, cancelWords: {'cancel'});

  const VoiceLocale({
    required this.languageCode,
    required this.preferredLocaleId,
    required this.sendWords,
    required this.cancelWords,
  });

  final String languageCode;

  /// The recognizer locale to pick when the phone offers several for [languageCode].
  final String preferredLocaleId;

  /// Lower case; compared with the lower-cased last word (spec §3.2).
  final Set<String> sendWords;
  final Set<String> cancelWords;

  /// The app is Vietnamese or English; anything that is not Vietnamese listens in English.
  static VoiceLocale fromLanguageCode(String? code) => code == 'vi' ? vi : en;
}
```

```dart
// apps/mobile/lib/features/voice/domain/voice_command_parser.dart
import 'package:equatable/equatable.dart';
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';

/// What one final recognition result asks the composer to do (spec §3.2).
sealed class VoiceCommand extends Equatable {
  const VoiceCommand();
}

/// Plain dictation: add [text] to the composer.
final class VoiceAppend extends VoiceCommand {
  const VoiceAppend(this.text);

  final String text;

  @override
  List<Object?> get props => [text];
}

/// The utterance ended with a send keyword: add [text] (without the keyword), then send.
final class VoiceSend extends VoiceCommand {
  const VoiceSend(this.text);

  final String text;

  @override
  List<Object?> get props => [text];
}

/// The utterance ended with a cancel keyword: clear the composer.
final class VoiceCancel extends VoiceCommand {
  const VoiceCancel();

  @override
  List<Object?> get props => const [];
}

abstract final class VoiceCommandParser {
  /// Punctuation and whitespace the recognizer puts after the words ("Gửi.", "send!").
  static final RegExp _trailing = RegExp(r'[\s\p{P}]+$', unicode: true);
  static final RegExp _space = RegExp(r'\s');

  /// A keyword only counts as the **last** word, so "gửi email cho tôi" stays text.
  static VoiceCommand parse(String heard, VoiceLocale locale) {
    final words = heard.trim().replaceAll(_trailing, '');
    final split = words.lastIndexOf(_space);
    final last = words.substring(split + 1).toLowerCase();
    final before = split < 0 ? '' : words.substring(0, split).replaceAll(_trailing, '');
    if (locale.sendWords.contains(last)) return VoiceSend(before);
    if (locale.cancelWords.contains(last)) return const VoiceCancel();
    return VoiceAppend(heard.trim());
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/voice/voice_command_parser_test.dart`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/voice/domain apps/mobile/test/features/voice/voice_command_parser_test.dart
git commit -m "feat(mobile): voice keyword parser — trailing gửi/send sends, huỷ/hủy/cancel clears, per language"
```

---

### Task 2: Speech input interface, plugin adapter and platform permissions

**Files:**
- Create: `apps/mobile/lib/features/voice/domain/speech_input.dart`
- Create: `apps/mobile/lib/features/voice/data/speech_to_text_input.dart`
- Create: `apps/mobile/test/support/fake_speech.dart`
- Modify: `apps/mobile/pubspec.yaml` (dependencies, after `mobile_scanner`)
- Modify: `apps/mobile/ios/Runner/Info.plist` (next to `NSCameraUsageDescription`)
- Modify: `apps/mobile/ios/Runner/vi.lproj/InfoPlist.strings`, `apps/mobile/ios/Runner/en.lproj/InfoPlist.strings`
- Modify: `apps/mobile/android/app/src/main/AndroidManifest.xml` (permissions block, `<queries>`)
- Modify: `apps/mobile/lib/core/dependency/dependency.config.dart` (generated)
- Test: `apps/mobile/test/features/voice/speech_to_text_input_test.dart`, `apps/mobile/test/platform_config_test.dart`

**Interfaces:**
- Consumes: `VoiceLocale` (Task 1).
- Produces:
  - `enum SpeechPermission { granted, denied, unsupported }`
  - `enum SpeechErrorKind { noPermission, localeUnavailable, network, noMatch, interrupted, other }`
  - `sealed class SpeechEvent`; `SpeechPartial(String text)`, `SpeechFinal(String text)`, `SpeechFailed(SpeechErrorKind kind)`, `SpeechListening(bool listening)` (named `SpeechFailed` to avoid clashing with the plugin's `SpeechRecognitionError`).
  - `abstract interface class SpeechInput { Stream<SpeechEvent> get events; Future<SpeechPermission> ensurePermission(); Future<String?> resolveLocale(VoiceLocale locale); Future<void> start(String localeId, {required bool onDevice}); Future<void> stop(); Future<void> cancel(); }`
  - `String? pickLocaleId(Iterable<String> available, VoiceLocale locale)`; `SpeechErrorKind speechErrorKind(String errorMsg)`
  - `@LazySingleton(as: SpeechInput) class SpeechToTextInput`
  - Test support: `class FakeSpeechInput implements SpeechInput` with `permission`, `localeIds` map, `starts` list of `(String localeId, bool onDevice)`, `stops`, `cancels`, `emit(SpeechEvent)`, and a `Completer`-based `permissionGate` for delaying `ensurePermission`.

- [ ] **Step 1: Add the dependency and check the plugin API**

Edit `apps/mobile/pubspec.yaml`, after `mobile_scanner: ^7.4.2`:

```yaml
  package_info_plus: ^9.0.1
  shellx_client: any
  shellx_core: any
  # Voice input (voice spec V4), BSD-3-Clause. Pinned exactly: 7.5.0+ needs Dart ^3.12 / Flutter 3.44.
  speech_to_text: 7.4.0
```

(Keep the list alphabetical: it goes after `shellx_core`.)

Run: `cd apps/mobile && flutter pub get`
Then open `~/.pub-cache/hosted/pub.dev/speech_to_text-7.4.0/lib/speech_to_text.dart` and confirm these names exist exactly: `SpeechToText.initialize({onError, onStatus, ...})`, `hasPermission`, `locales()` returning `LocaleName` with `localeId`, `listen({onResult, listenFor, pauseFor, localeId, listenOptions})`, `SpeechListenOptions({partialResults, onDevice, listenMode, cancelOnError})`, `ListenMode.dictation`, `stop()`, `cancel()`, `SpeechRecognitionResult.recognizedWords` / `.finalResult`, `SpeechRecognitionError.errorMsg`, status strings `'listening'` and `'done'`. If a name differs, adapt only `speech_to_text_input.dart` below and note it in the commit message.

- [ ] **Step 2: Write the failing tests**

```dart
// apps/mobile/test/features/voice/speech_to_text_input_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/voice/data/speech_to_text_input.dart';
import 'package:shellx_mobile/features/voice/domain/speech_input.dart';
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';

void main() {
  group('pickLocaleId', () {
    test('prefers the exact preferred locale in either separator style', () {
      expect(pickLocaleId(['en-GB', 'vi-VN', 'en-US'], VoiceLocale.vi), 'vi-VN');
      expect(pickLocaleId(['en_GB', 'en_US', 'vi_VN'], VoiceLocale.en), 'en_US');
    });

    test('falls back to any locale of the language', () {
      expect(pickLocaleId(['en-GB', 'fr-FR'], VoiceLocale.en), 'en-GB');
    });

    test('null when the phone has no locale of the language', () {
      expect(pickLocaleId(['en-US', 'fr-FR'], VoiceLocale.vi), isNull);
      expect(pickLocaleId([], VoiceLocale.en), isNull);
    });

    test('a language prefix must be the whole language ("vi" is not "vie")', () {
      expect(pickLocaleId(['vie-XX'], VoiceLocale.vi), isNull);
    });
  });

  group('speechErrorKind', () {
    test('maps the platform error names', () {
      expect(speechErrorKind('error_insufficient_permissions'), SpeechErrorKind.noPermission);
      expect(speechErrorKind('error_permission'), SpeechErrorKind.noPermission);
      expect(speechErrorKind('error_network'), SpeechErrorKind.network);
      expect(speechErrorKind('error_network_timeout'), SpeechErrorKind.network);
      expect(speechErrorKind('error_server'), SpeechErrorKind.network);
      expect(speechErrorKind('error_server_disconnected'), SpeechErrorKind.network);
      expect(speechErrorKind('error_no_match'), SpeechErrorKind.noMatch);
      expect(speechErrorKind('error_speech_timeout'), SpeechErrorKind.noMatch);
      expect(speechErrorKind('error_language_not_supported'), SpeechErrorKind.localeUnavailable);
      expect(speechErrorKind('error_language_unavailable'), SpeechErrorKind.localeUnavailable);
      expect(speechErrorKind('error_audio_error'), SpeechErrorKind.interrupted);
      expect(speechErrorKind('error_busy'), SpeechErrorKind.other);
      expect(speechErrorKind('error_listen_failed'), SpeechErrorKind.other);
      expect(speechErrorKind('something new'), SpeechErrorKind.other);
    });
  });
}
```

Add to `apps/mobile/test/platform_config_test.dart`, inside `group('iOS', ...)`:

```dart
    test('microphone and speech recognition prompts: Info.plist and both languages', () {
      final plist = readFile('ios/Runner/Info.plist');
      expect(plist, contains('<key>NSMicrophoneUsageDescription</key>'));
      expect(plist, contains('<key>NSSpeechRecognitionUsageDescription</key>'));
      for (final language in ['vi', 'en']) {
        final strings = readFile('ios/Runner/$language.lproj/InfoPlist.strings');
        expect(strings, contains('"NSMicrophoneUsageDescription" = "'), reason: language);
        expect(strings, contains('"NSSpeechRecognitionUsageDescription" = "'), reason: language);
      }
      expect(readFile('ios/Runner/vi.lproj/InfoPlist.strings'), contains('ShellX dùng micro'));
    });
```

and inside `group('Android', ...)`:

```dart
    test('voice input: RECORD_AUDIO and the speech recognition service query', () {
      final manifest = readFile('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('android.permission.RECORD_AUDIO'));
      expect(manifest, contains('<action android:name="android.speech.RecognitionService"/>'));
    });
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd apps/mobile && flutter test test/features/voice/speech_to_text_input_test.dart test/platform_config_test.dart`
Expected: FAIL — missing files and missing plist/manifest entries.

- [ ] **Step 4: Write the interface**

```dart
// apps/mobile/lib/features/voice/domain/speech_input.dart
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';

enum SpeechPermission {
  granted,

  /// The user refused the microphone or speech recognition prompt (now or earlier).
  denied,

  /// The phone has no speech recognizer at all (e.g. an Android build without one).
  unsupported,
}

enum SpeechErrorKind { noPermission, localeUnavailable, network, noMatch, interrupted, other }

/// What the recognizer reports while the composer listens (voice spec §4.1).
sealed class SpeechEvent {
  const SpeechEvent();
}

/// The words so far; replaced by the next partial or by the final result.
final class SpeechPartial extends SpeechEvent {
  const SpeechPartial(this.text);

  final String text;
}

/// The whole utterance; the listen is over once this arrives.
final class SpeechFinal extends SpeechEvent {
  const SpeechFinal(this.text);

  final String text;
}

final class SpeechFailed extends SpeechEvent {
  const SpeechFailed(this.kind);

  final SpeechErrorKind kind;
}

/// `true` when the recognizer started hearing, `false` when the listen is fully over.
final class SpeechListening extends SpeechEvent {
  const SpeechListening(this.listening);

  final bool listening;
}

/// The OS speech recognizer, behind an interface so the composer is tested without a microphone.
abstract interface class SpeechInput {
  /// Broadcast: every event of every listen.
  Stream<SpeechEvent> get events;

  /// Asks for the microphone and speech recognition permissions the first time.
  Future<SpeechPermission> ensurePermission();

  /// The recognizer's locale id for [locale], or null when the phone cannot recognize it.
  Future<String?> resolveLocale(VoiceLocale locale);

  /// One listen; it ends on its own after 2 s of silence or 60 s.
  Future<void> start(String localeId, {required bool onDevice});

  /// Ends the listen; the final result still arrives.
  Future<void> stop();

  /// Ends the listen without a final result.
  Future<void> cancel();
}
```

- [ ] **Step 5: Write the adapter**

```dart
// apps/mobile/lib/features/voice/data/speech_to_text_input.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/voice/domain/speech_input.dart';
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// [locale]'s preferred id if the phone has it, else any id of the same language; ids come as
/// `vi-VN` (iOS) or `vi_VN` (Android).
String? pickLocaleId(Iterable<String> available, VoiceLocale locale) {
  String norm(String id) => id.toLowerCase().replaceAll('_', '-');
  final preferred = norm(locale.preferredLocaleId);
  String? sameLanguage;
  for (final id in available) {
    final n = norm(id);
    if (n == preferred) return id;
    if (sameLanguage == null && (n == locale.languageCode || n.startsWith('${locale.languageCode}-'))) {
      sameLanguage = id;
    }
  }
  return sameLanguage;
}

/// The plugin reports Android `SpeechRecognizer` error names and a few iOS ones as strings.
SpeechErrorKind speechErrorKind(String errorMsg) => switch (errorMsg) {
  'error_insufficient_permissions' || 'error_permission' => SpeechErrorKind.noPermission,
  'error_network' || 'error_network_timeout' || 'error_server' || 'error_server_disconnected' =>
    SpeechErrorKind.network,
  'error_no_match' || 'error_speech_timeout' => SpeechErrorKind.noMatch,
  'error_language_not_supported' || 'error_language_unavailable' => SpeechErrorKind.localeUnavailable,
  'error_audio_error' => SpeechErrorKind.interrupted,
  _ => SpeechErrorKind.other,
};

/// [SpeechInput] over `speech_to_text` (voice spec V4, V7). Only names of errors are logged, never
/// what was said.
@LazySingleton(as: SpeechInput)
class SpeechToTextInput implements SpeechInput {
  final SpeechToText _speech = SpeechToText();
  final StreamController<SpeechEvent> _events = StreamController<SpeechEvent>.broadcast();
  bool _ready = false;

  @override
  Stream<SpeechEvent> get events => _events.stream;

  @override
  Future<SpeechPermission> ensurePermission() async {
    try {
      // The first call shows the microphone and speech recognition prompts.
      if (!_ready) _ready = await _speech.initialize(onError: _onError, onStatus: _onStatus);
      if (_ready) return SpeechPermission.granted;
      return await _speech.hasPermission ? SpeechPermission.unsupported : SpeechPermission.denied;
    } catch (error) {
      if (kDebugMode) debugPrint('SpeechToTextInput init error: ${error.runtimeType}');
      return SpeechPermission.denied;
    }
  }

  @override
  Future<String?> resolveLocale(VoiceLocale locale) async {
    try {
      final locales = await _speech.locales();
      return pickLocaleId(locales.map((l) => l.localeId), locale);
    } catch (error) {
      if (kDebugMode) debugPrint('SpeechToTextInput locales error: ${error.runtimeType}');
      return null;
    }
  }

  @override
  Future<void> start(String localeId, {required bool onDevice}) async {
    try {
      await _speech.listen(
        onResult: _onResult,
        localeId: localeId,
        pauseFor: const Duration(seconds: 2),
        listenFor: const Duration(seconds: 60),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          onDevice: onDevice,
          listenMode: ListenMode.dictation,
          cancelOnError: true,
        ),
      );
    } catch (error) {
      if (kDebugMode) debugPrint('SpeechToTextInput listen error: ${error.runtimeType}');
      _events.add(const SpeechFailed(SpeechErrorKind.other));
    }
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();

  void _onResult(SpeechRecognitionResult result) {
    _events.add(result.finalResult ? SpeechFinal(result.recognizedWords) : SpeechPartial(result.recognizedWords));
  }

  void _onError(SpeechRecognitionError error) {
    if (kDebugMode) debugPrint('SpeechToTextInput error: ${error.errorMsg}');
    _events.add(SpeechFailed(speechErrorKind(error.errorMsg)));
  }

  /// `notListening` comes before the final result; only `done` means the listen is over.
  void _onStatus(String status) {
    if (status == SpeechToText.listeningStatus) _events.add(const SpeechListening(true));
    if (status == SpeechToText.doneStatus) _events.add(const SpeechListening(false));
  }
}
```

- [ ] **Step 6: Write the test fake**

```dart
// apps/mobile/test/support/fake_speech.dart
import 'dart:async';

import 'package:shellx_mobile/features/voice/domain/speech_input.dart';
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';

/// Synchronous events; every call is recorded.
class FakeSpeechInput implements SpeechInput {
  final StreamController<SpeechEvent> _events = StreamController<SpeechEvent>.broadcast(sync: true);

  SpeechPermission permission = SpeechPermission.granted;

  /// Completes [ensurePermission] when set (to hold it open in a test).
  Completer<void>? permissionGate;

  Map<VoiceLocale, String?> localeIds = {VoiceLocale.vi: 'vi-VN', VoiceLocale.en: 'en-US'};

  final List<({String localeId, bool onDevice})> starts = [];
  int permissionCalls = 0;
  int stops = 0;
  int cancels = 0;

  @override
  Stream<SpeechEvent> get events => _events.stream;

  void emit(SpeechEvent event) => _events.add(event);

  @override
  Future<SpeechPermission> ensurePermission() async {
    permissionCalls++;
    await permissionGate?.future;
    return permission;
  }

  @override
  Future<String?> resolveLocale(VoiceLocale locale) async => localeIds[locale];

  @override
  Future<void> start(String localeId, {required bool onDevice}) async {
    starts.add((localeId: localeId, onDevice: onDevice));
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> cancel() async => cancels++;
}
```

- [ ] **Step 7: Platform permissions**

`apps/mobile/ios/Runner/Info.plist`, right after the `NSFaceIDUsageDescription` string:

```xml
	<key>NSMicrophoneUsageDescription</key>
	<string>ShellX uses the microphone when you tap the mic to speak a command into your terminal.</string>
	<key>NSSpeechRecognitionUsageDescription</key>
	<string>ShellX turns what you say into text for your terminal. When your phone can, this happens on the phone; otherwise Apple's speech recognition service is used.</string>
```

Append to `apps/mobile/ios/Runner/vi.lproj/InfoPlist.strings`:

```
"NSMicrophoneUsageDescription" = "ShellX dùng micro khi bạn chạm nút mic để nói lệnh vào terminal.";
"NSSpeechRecognitionUsageDescription" = "ShellX chuyển lời bạn nói thành chữ cho terminal. Khi máy hỗ trợ, việc này diễn ra ngay trên điện thoại; nếu không, dịch vụ nhận dạng giọng nói của Apple được dùng.";
```

Append to `apps/mobile/ios/Runner/en.lproj/InfoPlist.strings` (equal to Info.plist):

```
"NSMicrophoneUsageDescription" = "ShellX uses the microphone when you tap the mic to speak a command into your terminal.";
"NSSpeechRecognitionUsageDescription" = "ShellX turns what you say into text for your terminal. When your phone can, this happens on the phone; otherwise Apple's speech recognition service is used.";
```

`apps/mobile/android/app/src/main/AndroidManifest.xml`, after the `POST_NOTIFICATIONS` permission:

```xml
    <!-- Voice input (voice spec §4.2): asked at run time on the first mic tap. -->
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
```

and inside the existing `<queries>` element, as a new `<intent>`:

```xml
        <!-- Android 11+ package visibility: lets the app find the speech recognizer. -->
        <intent>
            <action android:name="android.speech.RecognitionService"/>
        </intent>
```

- [ ] **Step 8: Regenerate DI and run the tests**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs && flutter test test/features/voice test/platform_config_test.dart test/core/dependency_test.dart && flutter analyze`
Expected: PASS; `dependency.config.dart` now registers `SpeechInput` as a lazy singleton of `SpeechToTextInput`; analyze reports no issues.

- [ ] **Step 9: Commit**

```bash
git add apps/mobile/pubspec.yaml apps/mobile/lib/features/voice apps/mobile/lib/core/dependency/dependency.config.dart \
  apps/mobile/test/support/fake_speech.dart apps/mobile/test/features/voice apps/mobile/test/platform_config_test.dart \
  apps/mobile/ios/Runner/Info.plist apps/mobile/ios/Runner/vi.lproj/InfoPlist.strings apps/mobile/ios/Runner/en.lproj/InfoPlist.strings \
  apps/mobile/android/app/src/main/AndroidManifest.xml
git commit -m "feat(mobile): SpeechInput over speech_to_text 7.4.0 (locale pick, error names), microphone and speech recognition permissions"
```

(If `pubspec.lock` at the repo root changed and is tracked, add it too; `git status` tells.)

---

### Task 3: Remember the voice language in AppSettings

**Files:**
- Modify: `apps/mobile/lib/core/settings/app_settings.dart`
- Test: `apps/mobile/test/core/settings/app_settings_test.dart` (exists — add tests; if the file is named differently, `ls apps/mobile/test/core/settings` and add to the AppSettings test file there)

**Interfaces:**
- Consumes: `VoiceLocale` (Task 1).
- Produces: `AppSettings.voiceLocaleKey = 'settings_voice_locale'`, `ReadonlySignal<VoiceLocale?> AppSettings.voiceLocale` (null = never chosen → follow the app language), `Future<void> AppSettings.setVoiceLocale(VoiceLocale locale)`.

- [ ] **Step 1: Write the failing tests**

Add to the AppSettings test file (it already builds `AppSettings(InMemoryKeyValueStore())`; reuse its imports and add `import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';`):

```dart
  group('voice language', () {
    test('is null until chosen, then stored and loaded back', () async {
      final store = InMemoryKeyValueStore();
      final settings = AppSettings(store);
      await settings.load();
      expect(settings.voiceLocale.value, isNull);

      await settings.setVoiceLocale(VoiceLocale.en);
      expect(settings.voiceLocale.value, VoiceLocale.en);
      expect(await store.read(AppSettings.voiceLocaleKey), 'en');

      final reloaded = AppSettings(store);
      await reloaded.load();
      expect(reloaded.voiceLocale.value, VoiceLocale.en);
    });

    test('an unknown stored value counts as never chosen', () async {
      final store = InMemoryKeyValueStore();
      await store.write(AppSettings.voiceLocaleKey, 'fr');
      final settings = AppSettings(store);
      await settings.load();
      expect(settings.voiceLocale.value, isNull);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/mobile && flutter test test/core/settings`
Expected: FAIL — `voiceLocale` / `setVoiceLocale` / `voiceLocaleKey` undefined.

- [ ] **Step 3: Implement**

In `app_settings.dart` add the import `import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';` and:

```dart
  static const String voiceLocaleKey = 'settings_voice_locale';

  /// Voice spec V2: the language the composer listens in; null until the user picks one (the
  /// composer then follows the app language).
  final Signal<VoiceLocale?> _voiceLocale = signal(null);

  ReadonlySignal<VoiceLocale?> get voiceLocale => _voiceLocale;

  Future<void> setVoiceLocale(VoiceLocale locale) async {
    _voiceLocale.value = locale;
    await _store.write(voiceLocaleKey, locale.languageCode);
  }
```

In `load()`, read it with the others and set it in the `batch`:

```dart
    final bool biometricLock;
    final String? voiceCode;
    try {
      storedSize = double.tryParse(await _store.read(fontSizeKey) ?? '');
      biometricLock = await _store.read(biometricLockKey) != 'false';
      voiceCode = await _store.read(voiceLocaleKey);
    } catch (error) {
      ...unchanged...
    }
    batch(() {
      _fontSize.value = clampFontSize(storedSize ?? defaultFontSize);
      _biometricLock.value = biometricLock;
      _voiceLocale.value = VoiceLocale.values.where((l) => l.languageCode == voiceCode).firstOrNull;
    });
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/mobile && flutter test test/core/settings test/core/dependency_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/core/settings/app_settings.dart apps/mobile/test/core/settings
git commit -m "feat(mobile): AppSettings remembers the voice language (null = follow the app language)"
```

---

### Task 4: VoiceComposerController

**Files:**
- Create: `apps/mobile/lib/features/voice/presentation/controllers/voice_composer_controller.dart`
- Modify: `apps/mobile/lib/core/dependency/dependency.config.dart` (generated)
- Test: `apps/mobile/test/features/voice/voice_composer_controller_test.dart`

**Interfaces:**
- Consumes: `SpeechInput`, `SpeechEvent`s, `SpeechPermission`, `SpeechErrorKind` (Task 2); `VoiceLocale`, `VoiceCommandParser`, `VoiceCommand` (Task 1); `AppSettings.voiceLocale` / `setVoiceLocale` (Task 3); `FakeSpeechInput` (Task 2).
- Produces:
  - `enum VoicePhase { closed, idle, listening }`
  - `enum VoiceIssue { noPermission, unsupported, localeUnavailable, network, failed }`
  - `@injectable class VoiceComposerController extends Controller` with:
    - `final TextEditingController text`
    - `ReadonlySignal<VoicePhase> phase`, `ReadonlySignal<VoiceIssue?> issue`, `ReadonlySignal<VoiceLocale> locale`, `ReadonlySignal<Set<VoiceLocale>> unavailable`
    - `void attach({required bool Function() canSend, required void Function(String line) onSubmit})`
    - `Future<void> toggleMic(String appLanguageCode)` — closed/idle → open and listen; listening → stop
    - `Future<void> setLocale(VoiceLocale locale)`
    - `void sendNow()` — the Send button
    - `void pause()` — app inactive: cancel the listen, keep the text
    - `void close()` — ✕: cancel, clear, closed
    - `void dispose()`

- [ ] **Step 1: Write the failing tests**

```dart
// apps/mobile/test/features/voice/voice_composer_controller_test.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/voice/domain/speech_input.dart';
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';
import 'package:shellx_mobile/features/voice/presentation/controllers/voice_composer_controller.dart';

import '../../support/fake_popup_handler.dart';
import '../../support/fake_speech.dart';

void main() {
  late FakeSpeechInput speech;
  late AppSettings settings;
  late VoiceComposerController voice;
  late List<String> sent;
  late bool live;

  setUp(() async {
    getIt.registerSingleton<PopupHandler>(FakePopupHandler());
    speech = FakeSpeechInput();
    settings = AppSettings(InMemoryKeyValueStore());
    await settings.load();
    voice = VoiceComposerController(speech, settings);
    sent = [];
    live = true;
    voice.attach(canSend: () => live, onSubmit: sent.add);
  });

  tearDown(() async {
    voice.dispose();
    await getIt.reset();
  });

  Future<void> listen({String app = 'vi'}) async {
    await voice.toggleMic(app);
    speech.emit(const SpeechListening(true));
  }

  test('first tap opens, listens in the app language, on-device first', () async {
    await listen();
    expect(voice.phase.value, VoicePhase.listening);
    expect(voice.locale.value, VoiceLocale.vi);
    expect(speech.starts.single, (localeId: 'vi-VN', onDevice: true));
  });

  test('a chosen language wins over the app language', () async {
    await settings.setVoiceLocale(VoiceLocale.en);
    await listen(app: 'vi');
    expect(speech.starts.single.localeId, 'en-US');
  });

  test('partials show after the text already there; the final replaces them', () async {
    voice.text.text = 'cd app';
    await listen();
    speech.emit(const SpeechPartial('và chạy'));
    expect(voice.text.text, 'cd app và chạy');
    speech.emit(const SpeechPartial('và chạy test'));
    expect(voice.text.text, 'cd app và chạy test');
    speech.emit(const SpeechFinal('và chạy test'));
    speech.emit(const SpeechListening(false));
    expect(voice.text.text, 'cd app và chạy test');
    expect(voice.phase.value, VoicePhase.idle);
    expect(sent, isEmpty);
  });

  test('a trailing "gửi" sends the whole composer and clears it', () async {
    voice.text.text = 'sửa bug';
    await listen();
    speech.emit(const SpeechFinal('trong auth gửi'));
    expect(sent, ['sửa bug trong auth']);
    expect(voice.text.text, isEmpty);
    expect(voice.phase.value, isNot(VoicePhase.closed));
  });

  test('"gửi" alone on an empty composer sends an empty line', () async {
    await listen();
    speech.emit(const SpeechFinal('gửi'));
    expect(sent, ['']);
  });

  test('"huỷ" clears without sending', () async {
    voice.text.text = 'rm -rf build';
    await listen();
    speech.emit(const SpeechFinal('thôi huỷ'));
    expect(sent, isEmpty);
    expect(voice.text.text, isEmpty);
  });

  test('not live: "gửi" keeps the text (keyword dropped) and sends nothing', () async {
    live = false;
    await listen();
    speech.emit(const SpeechFinal('chạy test gửi'));
    expect(sent, isEmpty);
    expect(voice.text.text, 'chạy test');
  });

  test('a final that arrives after done still applies', () async {
    await listen();
    speech.emit(const SpeechListening(false));
    speech.emit(const SpeechFinal('git status gửi'));
    expect(sent, ['git status']);
  });

  test('tap while listening stops (the final result still comes)', () async {
    await listen();
    await voice.toggleMic('vi');
    expect(speech.stops, 1);
    expect(speech.starts, hasLength(1));
  });

  test('double tap while permission is pending starts one listen (review focus 4)', () async {
    speech.permissionGate = Completer<void>();
    final first = voice.toggleMic('vi');
    final second = voice.toggleMic('vi');
    speech.permissionGate!.complete();
    await Future.wait([first, second]);
    expect(speech.permissionCalls, 1);
    expect(speech.starts, hasLength(1));
  });

  test('permission refused: open, idle, noPermission, no listen', () async {
    speech.permission = SpeechPermission.denied;
    await voice.toggleMic('vi');
    expect(voice.phase.value, VoicePhase.idle);
    expect(voice.issue.value, VoiceIssue.noPermission);
    expect(speech.starts, isEmpty);
  });

  test('no recognizer on the phone: unsupported', () async {
    speech.permission = SpeechPermission.unsupported;
    await voice.toggleMic('vi');
    expect(voice.issue.value, VoiceIssue.unsupported);
  });

  test('language missing on the phone: localeUnavailable and the chip is marked', () async {
    speech.localeIds = {VoiceLocale.vi: null, VoiceLocale.en: 'en-US'};
    await voice.toggleMic('vi');
    expect(voice.issue.value, VoiceIssue.localeUnavailable);
    expect(voice.unavailable.value, {VoiceLocale.vi});
    expect(speech.starts, isEmpty);
  });

  test('on-device failure before any words retries once with the cloud recognizer', () async {
    await listen();
    speech.emit(const SpeechFailed(SpeechErrorKind.localeUnavailable));
    expect(speech.starts, [(localeId: 'vi-VN', onDevice: true), (localeId: 'vi-VN', onDevice: false)]);
    expect(voice.phase.value, VoicePhase.listening);
    expect(voice.issue.value, isNull);
    speech.emit(const SpeechFailed(SpeechErrorKind.localeUnavailable));
    expect(speech.starts, hasLength(2));
    expect(voice.issue.value, VoiceIssue.localeUnavailable);
    expect(voice.phase.value, VoicePhase.idle);
  });

  test('network error keeps the text and says so', () async {
    voice.text.text = 'giữ lại';
    await listen();
    speech.emit(const SpeechPartial('chữ'));
    speech.emit(const SpeechFailed(SpeechErrorKind.network));
    expect(voice.issue.value, VoiceIssue.network);
    expect(voice.text.text, 'giữ lại chữ');
    expect(voice.phase.value, VoicePhase.idle);
  });

  test('no match is quiet', () async {
    await listen();
    speech.emit(const SpeechFailed(SpeechErrorKind.noMatch));
    expect(voice.issue.value, isNull);
    expect(voice.phase.value, VoicePhase.idle);
  });

  test('switching language while listening cancels and remembers the choice', () async {
    await listen();
    await voice.setLocale(VoiceLocale.en);
    expect(speech.cancels, 1);
    expect(voice.phase.value, VoicePhase.idle);
    expect(settings.voiceLocale.value, VoiceLocale.en);
    await voice.toggleMic('vi');
    expect(speech.starts.last.localeId, 'en-US');
  });

  test('Send button sends the trimmed text, gated on live', () async {
    voice.text.text = '  git log  \n';
    live = false;
    voice.sendNow();
    expect(sent, isEmpty);
    live = true;
    voice.sendNow();
    expect(sent, ['git log']);
    expect(voice.text.text, isEmpty);
  });

  test('pause cancels the listen and keeps what was heard; later results are ignored', () async {
    await listen();
    speech.emit(const SpeechPartial('nửa câu'));
    voice.pause();
    expect(speech.cancels, 1);
    expect(voice.phase.value, VoicePhase.idle);
    speech.emit(const SpeechFinal('nửa câu gửi'));
    expect(sent, isEmpty);
    expect(voice.text.text, 'nửa câu');
  });

  test('close clears and ignores late results (review focus 3)', () async {
    await listen();
    voice.close();
    expect(voice.phase.value, VoicePhase.closed);
    expect(voice.text.text, isEmpty);
    speech.emit(const SpeechFinal('muộn gửi'));
    expect(sent, isEmpty);
  });

  test('results after dispose write nothing and send nothing (review focus 3)', () async {
    await listen();
    voice.dispose();
    expect(speech.cancels, 1);
    speech.emit(const SpeechFinal('muộn gửi'));
    expect(sent, isEmpty);
    // tearDown disposes again: dispose must be idempotent.
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/mobile && flutter test test/features/voice/voice_composer_controller_test.dart`
Expected: FAIL — `voice_composer_controller.dart` not found.

- [ ] **Step 3: Implement**

```dart
// apps/mobile/lib/features/voice/presentation/controllers/voice_composer_controller.dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/voice/domain/speech_input.dart';
import 'package:shellx_mobile/features/voice/domain/voice_command_parser.dart';
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';

enum VoicePhase { closed, idle, listening }

/// What the composer's issue line says (voice spec §5); `noMatch` and interruptions say nothing.
enum VoiceIssue { noPermission, unsupported, localeUnavailable, network, failed }

/// The voice composer of the terminal page (voice spec §3, §4.1): what was heard lands in [text],
/// where it can be edited; a trailing send keyword or the Send button hands the line to the page.
///
/// One listen at a time. A listen is "active" from [SpeechInput.start] until its final result, an
/// error, [pause], [close] or [dispose]; partials and the final result of anything else are
/// ignored, so a late result never reaches a closed composer or a page that left.
@injectable
class VoiceComposerController extends Controller {
  VoiceComposerController(this._speech, this._settings) {
    _events = _speech.events.listen(_onEvent);
  }

  final SpeechInput _speech;
  final AppSettings _settings;
  late final StreamSubscription<SpeechEvent> _events;

  final TextEditingController text = TextEditingController();
  final Signal<VoicePhase> _phase = signal(VoicePhase.closed);
  final Signal<VoiceIssue?> _issue = signal(null);
  final Signal<VoiceLocale> _locale = signal(VoiceLocale.vi);
  final Signal<Set<VoiceLocale>> _unavailable = signal(const {});

  bool Function() _canSend = () => false;
  void Function(String line) _onSubmit = (_) {};

  /// The composer text when the listen started; partials are shown after it.
  String _committed = '';
  String? _localeId;
  bool _active = false;
  bool _starting = false;
  bool _onDeviceAttempt = false;
  bool _heard = false;
  bool _disposed = false;

  ReadonlySignal<VoicePhase> get phase => _phase;
  ReadonlySignal<VoiceIssue?> get issue => _issue;
  ReadonlySignal<VoiceLocale> get locale => _locale;
  ReadonlySignal<Set<VoiceLocale>> get unavailable => _unavailable;

  /// [canSend]: the active tab is live. [onSubmit]: sends one line with Enter.
  void attach({required bool Function() canSend, required void Function(String line) onSubmit}) {
    _canSend = canSend;
    _onSubmit = onSubmit;
  }

  /// The mic: opens the composer and listens; while listening, stops (the final result still
  /// comes and is applied).
  Future<void> toggleMic(String appLanguageCode) async {
    if (_disposed) return;
    if (_phase.peek() == VoicePhase.listening) {
      await _speech.stop();
      return;
    }
    if (_phase.peek() == VoicePhase.closed) {
      _locale.value = _settings.voiceLocale.peek() ?? VoiceLocale.fromLanguageCode(appLanguageCode);
      _phase.value = VoicePhase.idle;
    }
    await _startListening();
  }

  Future<void> setLocale(VoiceLocale locale) async {
    if (_disposed) return;
    if (_active) _cancelListen();
    _locale.value = locale;
    _issue.value = null;
    await _settings.setVoiceLocale(locale);
  }

  /// The Send button: the text as edited, without surrounding blank space (a trailing newline
  /// would be a second Enter).
  void sendNow() {
    if (_disposed || !_canSend()) return;
    if (_active) _cancelListen();
    final line = text.text.trim();
    text.clear();
    _committed = '';
    _onSubmit(line);
  }

  /// The app went inactive (call, lock, background): stop hearing, keep what is shown.
  void pause() {
    if (_disposed || !_active) return;
    _cancelListen();
  }

  /// ✕: nothing is sent; the next mic tap opens an empty composer.
  void close() {
    if (_disposed) return;
    if (_active) _cancelListen();
    text.clear();
    _committed = '';
    _issue.value = null;
    _phase.value = VoicePhase.closed;
  }

  Future<void> _startListening() async {
    if (_starting || _active) return;
    _starting = true;
    try {
      _issue.value = null;
      final permission = await _speech.ensurePermission();
      if (_disposed || _phase.peek() == VoicePhase.closed) return;
      if (permission != SpeechPermission.granted) {
        _issue.value = permission == SpeechPermission.denied ? VoiceIssue.noPermission : VoiceIssue.unsupported;
        return;
      }
      final locale = _locale.peek();
      final localeId = await _speech.resolveLocale(locale);
      if (_disposed || _phase.peek() == VoicePhase.closed) return;
      if (localeId == null) {
        _markUnavailable(locale);
        return;
      }
      _localeId = localeId;
      _committed = text.text.trim();
      _heard = false;
      _onDeviceAttempt = true;
      _active = true;
      _phase.value = VoicePhase.listening;
      await _speech.start(localeId, onDevice: true);
    } finally {
      _starting = false;
    }
  }

  void _onEvent(SpeechEvent event) {
    if (_disposed || !_active) return;
    switch (event) {
      case SpeechPartial(:final text):
        _heard = true;
        _show(_join(_committed, text));
      case SpeechFinal(:final text):
        _heard = true;
        _active = false;
        _phase.value = VoicePhase.idle;
        _apply(VoiceCommandParser.parse(text, _locale.peek()));
      case SpeechFailed(:final kind):
        _onFailed(kind);
      case SpeechListening(:final listening):
        // `done` may come before the final result: keep the listen active for it.
        if (!listening) _phase.value = VoicePhase.idle;
    }
  }

  void _apply(VoiceCommand command) {
    switch (command) {
      case VoiceAppend(:final text):
        _show(_join(_committed, text));
      case VoiceCancel():
        text.clear();
      case VoiceSend(:final text):
        final line = _join(_committed, text);
        if (_canSend()) {
          this.text.clear();
          _onSubmit(line);
        } else {
          _show(line);
        }
    }
    _committed = text.text;
  }

  /// Spec V4: on-device first; a phone that cannot do it on the device fails before any words, and
  /// gets one more try with the OS cloud recognizer.
  void _onFailed(SpeechErrorKind kind) {
    final retry = _onDeviceAttempt && !_heard && (kind == SpeechErrorKind.localeUnavailable || kind == SpeechErrorKind.other);
    if (retry) {
      _onDeviceAttempt = false;
      unawaited(_speech.start(_localeId!, onDevice: false));
      return;
    }
    _active = false;
    _phase.value = VoicePhase.idle;
    _committed = text.text;
    switch (kind) {
      case SpeechErrorKind.noPermission:
        _issue.value = VoiceIssue.noPermission;
      case SpeechErrorKind.localeUnavailable:
        _markUnavailable(_locale.peek());
      case SpeechErrorKind.network:
        _issue.value = VoiceIssue.network;
      case SpeechErrorKind.other:
        _issue.value = VoiceIssue.failed;
      case SpeechErrorKind.noMatch || SpeechErrorKind.interrupted:
        break;
    }
  }

  void _markUnavailable(VoiceLocale locale) {
    _unavailable.value = {..._unavailable.peek(), locale};
    _issue.value = VoiceIssue.localeUnavailable;
  }

  void _cancelListen() {
    _active = false;
    unawaited(_speech.cancel());
    _committed = text.text;
    _phase.value = VoicePhase.idle;
  }

  void _show(String value) {
    text.value = TextEditingValue(text: value, selection: TextSelection.collapsed(offset: value.length));
  }

  static String _join(String before, String after) =>
      [before.trim(), after.trim()].where((part) => part.isNotEmpty).join(' ');

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_active) {
      _active = false;
      unawaited(_speech.cancel());
    }
    unawaited(_events.cancel());
    text.dispose();
    _phase.dispose();
    _issue.dispose();
    _locale.dispose();
    _unavailable.dispose();
  }
}
```

Note for `pause` test: `pause` keeps `'nửa câu'` because `_cancelListen` commits the shown text; the later `SpeechFinal` is dropped by `!_active`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/mobile && flutter test test/features/voice/voice_composer_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Regenerate DI, analyze, commit**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs && flutter analyze`
Expected: no issues; `dependency.config.dart` has a factory for `VoiceComposerController`.

```bash
git add apps/mobile/lib/features/voice/presentation/controllers apps/mobile/lib/core/dependency/dependency.config.dart apps/mobile/test/features/voice/voice_composer_controller_test.dart
git commit -m "feat(mobile): VoiceComposerController — partials, keywords, on-device then cloud, permission/locale/network issues, late results ignored"
```

---

### Task 5: `TerminalPageController.submitLine`

**Files:**
- Modify: `apps/mobile/lib/features/terminal/presentation/controllers/terminal_page_controller.dart` (after `paste`)
- Test: `apps/mobile/test/features/terminal/submit_line_test.dart`

**Interfaces:**
- Consumes: `TerminalWorkspace.activeTab`, `ShellxTerminal.paste`, `Terminal.bracketedPasteMode`, `Terminal.onOutput` (existing).
- Produces: `void TerminalPageController.submitLine(String line)`.

- [ ] **Step 1: Write the failing tests**

The test reuses the fakes of `terminal_page_test.dart` (`FakeBackend`, `FakeSessionHolder`, `WorkspaceRegistry`, `pinned`, `agentA`, `FakeTabHandle.emit`, `TabOutput`) but drives the controller without a widget.

```dart
// apps/mobile/test/features/terminal/submit_line_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_page_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';
import 'package:shellx_mobile/features/terminal/presentation/terminal_metrics.dart';

import '../../support/fake_popup_handler.dart';
import '../../support/fakes.dart';

void main() {
  late FakeBackend backend;
  late FakeMachineSession machine;
  late WorkspaceRegistry registry;
  late TerminalPageController controller;

  setUp(() async {
    getIt.registerSingleton<PopupHandler>(FakePopupHandler());
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    final session = FakeSessionHolder(backend);
    registry = WorkspaceRegistry(session.backend);
    controller = TerminalPageController(agentA, registry, session, AppSettings(InMemoryKeyValueStore()));
    await controller.prepare();
    await controller.openNew(fallbackGrid);
  });

  tearDown(() async {
    controller.dispose();
    registry.dispose();
    await getIt.reset();
  });

  List<String> inputs() => [for (final input in machine.inputs) utf8.decode(input.data)];

  test('plain mode: the text, then Enter', () {
    controller.submitLine('git status');
    expect(inputs().join(), 'git status\r');
  });

  test('bracketed paste: Enter goes after the closing bracket', () {
    machine.handles.single.emit(const TabOutput('\x1b[?2004h'));
    controller.submitLine('sửa bug trong auth');
    expect(inputs().join(), '\x1b[200~sửa bug trong auth\x1b[201~\r');
  });

  test('an empty line is just Enter', () {
    controller.submitLine('');
    expect(inputs().join(), '\r');
  });

  test('plain mode joins line breaks with spaces so nothing runs early (review focus 1)', () {
    controller.submitLine('echo 1\necho 2\r\necho 3');
    expect(inputs().join(), 'echo 1 echo 2 echo 3\r');
  });

  test('bracketed paste keeps line breaks (as CR, like Paste)', () {
    machine.handles.single.emit(const TabOutput('\x1b[?2004h'));
    controller.submitLine('a\nb');
    expect(inputs().join(), '\x1b[200~a\rb\x1b[201~\r');
  });

  test('a sticky Ctrl is not applied to the line (review focus 2)', () {
    registry.forMachine(agentA).extraKeys.tapModifier(ExtraKey.ctrl);
    controller.submitLine('ls');
    expect(inputs().join(), 'ls\r');
  });
}
```

If `FakeMachineSession` exposes inputs or handles under other names than in `terminal_page_test.dart` (`machine.inputs`, `machine.handles.single.emit`), use the names that file uses — they are the same fakes.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/mobile && flutter test test/features/terminal/submit_line_test.dart`
Expected: FAIL — `submitLine` is not defined.

- [ ] **Step 3: Implement**

In `terminal_page_controller.dart`, after `paste`:

```dart
  static final RegExp _lineBreaks = RegExp(r'[\r\n]+');

  /// A line from the voice composer (voice spec §4.2), then Enter. The text goes the way of Paste
  /// (bracketed when the program enabled it, control characters stripped, sticky modifiers never
  /// applied); Enter is sent after it, outside the paste brackets, so it runs the line. Without
  /// bracketed paste a line break would itself be Enter, so line breaks become spaces.
  void submitLine(String line) {
    if (_closed) return;
    final terminal = workspace.activeTab.peek()?.terminal.peek();
    if (terminal == null) return;
    final text = terminal.bracketedPasteMode ? line : line.replaceAll(_lineBreaks, ' ');
    if (text.isNotEmpty) terminal.paste(text);
    terminal.onOutput?.call('\r');
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/mobile && flutter test test/features/terminal/submit_line_test.dart test/features/terminal`
Expected: PASS (new and existing terminal tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/terminal/presentation/controllers/terminal_page_controller.dart apps/mobile/test/features/terminal/submit_line_test.dart
git commit -m "feat(mobile): TerminalPageController.submitLine — paste path then Enter outside the brackets; plain mode joins line breaks"
```

---

### Task 6: Composer UI on the terminal page

**Files:**
- Create: `apps/mobile/lib/features/voice/presentation/widgets/mic_button.dart`
- Create: `apps/mobile/lib/features/voice/presentation/widgets/voice_composer.dart`
- Modify: `apps/mobile/lib/features/terminal/presentation/widgets/extra_keys_bar.dart`
- Modify: `apps/mobile/lib/features/terminal/presentation/pages/terminal_page.dart`
- Modify: `apps/mobile/lib/l10n/intl_vi.arb`, `apps/mobile/lib/l10n/intl_en.arb`, generated `apps/mobile/lib/shared/src/**`
- Test: `apps/mobile/test/features/terminal/terminal_page_test.dart` (setUp + new tests), `apps/mobile/test/features/terminal/extra_keys_bar_test.dart`

**Interfaces:**
- Consumes: `VoiceComposerController` and its signals/methods (Task 4), `submitLine` (Task 5), `FakeSpeechInput` (Task 2), `ExternalLinks.openAppSettingsOrToast` (existing), `TerminalTabController.title` / `isLive` (existing).
- Produces: `ExtraKeysBar({..., Widget? leading})`; `MicButton({required VoiceComposerController controller, required VoidCallback onTap})` with key `ValueKey('voice-mic')`; `VoiceComposer({required VoiceComposerController controller, required String? target, required bool canSend, required VoidCallback onOpenSettings})` with keys `voice-text`, `voice-send`, `voice-close`, `voice-locale-vi`, `voice-locale-en`, `voice-issue`.

- [ ] **Step 1: Add the strings**

Add to `apps/mobile/lib/l10n/intl_vi.arb` (before the closing `}`, after `deleteAccountButton`; mind the comma):

```json
  "voiceMicTooltip": "Nói lệnh",
  "voiceStopTooltip": "Dừng nghe",
  "voiceHint": "Nói hoặc gõ… nói “gửi” để gửi",
  "voiceSend": "Gửi",
  "voiceClose": "Đóng",
  "voiceTarget": "→ {target}",
  "@voiceTarget": {
    "placeholders": {
      "target": {
        "type": "String"
      }
    }
  },
  "voiceLanguageVi": "Tiếng Việt",
  "voiceLanguageEn": "Tiếng Anh",
  "voiceNoPermission": "Cần quyền micro và nhận dạng giọng nói để nói lệnh",
  "voiceUnsupported": "Máy này không hỗ trợ nhận dạng giọng nói",
  "voiceLocaleUnavailableVi": "Máy chưa hỗ trợ nhận dạng tiếng Việt — thử EN",
  "voiceLocaleUnavailableEn": "Máy chưa hỗ trợ nhận dạng tiếng Anh — thử VI",
  "voiceNetwork": "Cần kết nối mạng để nhận dạng giọng nói",
  "voiceFailed": "Không nhận dạng được, hãy thử lại",
  "voiceNotLive": "Phiên chưa kết nối — gửi được khi kết nối lại"
```

Add to `apps/mobile/lib/l10n/intl_en.arb` in the same place:

```json
  "voiceMicTooltip": "Speak a command",
  "voiceStopTooltip": "Stop listening",
  "voiceHint": "Speak or type… say “send” to send",
  "voiceSend": "Send",
  "voiceClose": "Close",
  "voiceTarget": "→ {target}",
  "@voiceTarget": {
    "placeholders": {
      "target": {
        "type": "String"
      }
    }
  },
  "voiceLanguageVi": "Vietnamese",
  "voiceLanguageEn": "English",
  "voiceNoPermission": "ShellX needs microphone and speech recognition access to take spoken commands",
  "voiceUnsupported": "Speech recognition isn't available on this phone",
  "voiceLocaleUnavailableVi": "This phone can't recognize Vietnamese yet — try EN",
  "voiceLocaleUnavailableEn": "This phone can't recognize English yet — try VI",
  "voiceNetwork": "Speech recognition needs a network connection",
  "voiceFailed": "Couldn't recognize that, try again",
  "voiceNotLive": "The session isn't connected — you can send once it reconnects"
```

The "Mở Cài đặt" button reuses the existing `openSettings` key.

Run: `cd apps/mobile && dart run intl_utils:generate && flutter test test/l10n_test.dart`
Expected: PASS.

- [ ] **Step 2: Write the failing tests**

In `test/features/terminal/extra_keys_bar_test.dart`, add:

```dart
  testWidgets('a leading widget sits before Esc', (tester) async {
    await tester.pumpWidget(
      localized(
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ExtraKeysBar(
              controller: keys,
              onKey: (key) => keys.sendKey(key, terminal),
              onPaste: () {},
              leading: const SizedBox(key: ValueKey('lead'), width: 40, height: 40),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('lead'))).dx,
      lessThan(tester.getTopLeft(find.text('Esc')).dx),
    );
  });
```

In `test/features/terminal/terminal_page_test.dart`:
- add imports `package:shellx_mobile/features/voice/domain/speech_input.dart`, `package:shellx_mobile/features/voice/presentation/controllers/voice_composer_controller.dart`, `../../support/fake_speech.dart`, `../../support/fake_links.dart`;
- add `late FakeSpeechInput speech;` and in `setUp`, after `final settings = ...`, extend the `getIt` cascade:

```dart
    speech = FakeSpeechInput();
    getIt
      ..registerFactory<VoiceComposerController>(() => VoiceComposerController(speech, settings))
      ..registerSingleton<ExternalLinks>(FakeExternalLinks());
```

(check `FakeExternalLinks`'s constructor in `test/support/fake_links.dart`);
- add the tests. The mic pulses forever while listening, so these tests disable animations (as a user with "reduce motion" would) to let `pumpAndSettle` finish:

```dart
  group('voice composer', () {
    Finder mic() => find.byKey(const ValueKey('voice-mic'));

    /// [open] with "reduce motion" on: the listening pulse then stands still.
    Future<void> openQuiet(WidgetTester tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await open(tester);
    }

    testWidgets('the mic opens the composer, which shows the target tab and listens in Vietnamese', (tester) async {
      await openQuiet(tester);
      expect(find.byKey(const ValueKey('voice-text')), findsNothing);
      await tester.tap(mic());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('voice-text')), findsOneWidget);
      expect(find.textContaining('→ '), findsOneWidget);
      expect(find.textContaining('MacBook-Pro'), findsWidgets);
      expect(speech.starts.single.localeId, 'vi-VN');
    });

    testWidgets('speaking then "gửi" sends the line with Enter to the active session', (tester) async {
      await openQuiet(tester);
      await tester.tap(mic());
      await tester.pumpAndSettle();
      speech.emit(const SpeechPartial('git'));
      await tester.pump();
      expect(find.text('git'), findsOneWidget);
      speech.emit(const SpeechFinal('git status gửi'));
      await tester.pump();
      expect(lastInput(), '\r');
      expect(utf8.decode(machine.inputs[machine.inputs.length - 2].data), 'git status');
    });

    testWidgets('typed text goes with the Send button; ✕ closes and gives focus back', (tester) async {
      await openQuiet(tester);
      await tester.tap(mic());
      await tester.pumpAndSettle();
      speech.emit(const SpeechListening(false));
      await tester.enterText(find.byKey(const ValueKey('voice-text')), 'ls -la');
      await tester.tap(find.byKey(const ValueKey('voice-send')));
      await tester.pump();
      expect(lastInput(), '\r');
      await tester.tap(find.byKey(const ValueKey('voice-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('voice-text')), findsNothing);
    });

    testWidgets('refused permission shows the issue with Mở Cài đặt', (tester) async {
      speech.permission = SpeechPermission.denied;
      await openQuiet(tester);
      await tester.tap(mic());
      await tester.pumpAndSettle();
      expect(find.text('Cần quyền micro và nhận dạng giọng nói để nói lệnh'), findsOneWidget);
      expect(find.text('Mở Cài đặt'), findsOneWidget);
    });

    testWidgets('the EN chip switches the language for the next listen', (tester) async {
      await openQuiet(tester);
      await tester.tap(mic());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('voice-locale-en')));
      await tester.pump();
      await tester.tap(mic());
      await tester.pumpAndSettle();
      expect(speech.starts.last.localeId, 'en-US');
    });

    testWidgets('an ended session hides the mic and disables Send, keeping the text', (tester) async {
      await openQuiet(tester);
      await tester.tap(mic());
      await tester.pumpAndSettle();
      speech.emit(const SpeechFinal('giữ chữ này'));
      machine.handles.single.emit(const TabExited(0));
      await tester.pumpAndSettle();
      expect(mic(), findsNothing);
      expect(find.text('giữ chữ này'), findsOneWidget);
      expect(find.text('Phiên chưa kết nối — gửi được khi kết nối lại'), findsOneWidget);
      final send = tester.widget<IconButton>(find.byKey(const ValueKey('voice-send')));
      expect(send.onPressed, isNull);
    });
  });
```

If `TabExited`'s constructor differs, use it the way existing tests in this file end a session (search for `TabExited(`).

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd apps/mobile && flutter test test/features/terminal`
Expected: FAIL — no `leading` parameter, no `voice-mic`.

- [ ] **Step 4: `ExtraKeysBar.leading`**

In `extra_keys_bar.dart`:

```dart
  const ExtraKeysBar({
    super.key,
    required this.controller,
    required this.onKey,
    required this.onPaste,
    this.leading,
  });

  ...

  /// Before the keys (the voice mic, voice spec §4.2); not an [ExtraKey]: it sends nothing itself.
  final Widget? leading;
```

and in `build`, first child of the `ListView`:

```dart
        children: [
          ?leading,
          for (final key in ExtraKey.values)
```

(`?leading` is Dart 3.8+ null-aware element syntax; the workspace SDK is ^3.11.)

- [ ] **Step 5: `MicButton`**

```dart
// apps/mobile/lib/features/voice/presentation/widgets/mic_button.dart
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/voice/presentation/controllers/voice_composer_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// The mic cap at the start of the extra keys row; filled and pulsing while listening.
class MicButton extends StatelessWidget {
  const MicButton({super.key, required this.controller, required this.onTap});

  final VoiceComposerController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Watch((context) {
      final listening = controller.phase.value == VoicePhase.listening;
      final strings = S.of(context);
      return Semantics(
        button: true,
        label: listening ? strings.voiceStopTooltip : strings.voiceMicTooltip,
        child: GestureDetector(
          key: const ValueKey('voice-mic'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              constraints: const BoxConstraints(minWidth: 46),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: listening ? colors.primary : colors.keyboardKey,
                borderRadius: BorderRadius.circular(9),
                boxShadow: const [BoxShadow(color: Color(0x47000000), offset: Offset(0, 1))],
              ),
              child: _Pulse(
                active: listening,
                child: Icon(
                  listening ? Icons.mic : Icons.mic_none,
                  size: 20,
                  color: listening ? colors.onPrimary : colors.keyboardInk,
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// Grows and shrinks the icon while [active]; still when the platform asks for less motion.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
    lowerBound: 0.85,
    upperBound: 1.15,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Pulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final animate = widget.active && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_animation.isAnimating) {
      _animation.repeat(reverse: true);
    } else if (!animate) {
      _animation
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(scale: _animation, child: widget.child);
}
```

Note: the pulse repeats while listening and never settles; the page tests use `openQuiet` (Step 2), and `_PulseState._sync` keeps it still under "reduce motion".

- [ ] **Step 6: `VoiceComposer`**

```dart
// apps/mobile/lib/features/voice/presentation/widgets/voice_composer.dart
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';
import 'package:shellx_mobile/features/voice/presentation/controllers/voice_composer_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// The panel above the extra keys while voice input is open (voice spec §3.1): where the line
/// goes, the language, the editable text, Send and ✕, and the issue line (§5).
class VoiceComposer extends StatelessWidget {
  const VoiceComposer({
    super.key,
    required this.controller,
    required this.target,
    required this.canSend,
    required this.onOpenSettings,
  });

  final VoiceComposerController controller;

  /// "zsh · MacBook"; null without a tab.
  final String? target;
  final bool canSend;
  final VoidCallback onOpenSettings;

  String? _issueText(S strings, VoiceIssue? issue, VoiceLocale locale) => switch (issue) {
    null => null,
    VoiceIssue.noPermission => strings.voiceNoPermission,
    VoiceIssue.unsupported => strings.voiceUnsupported,
    VoiceIssue.localeUnavailable =>
      locale == VoiceLocale.vi ? strings.voiceLocaleUnavailableVi : strings.voiceLocaleUnavailableEn,
    VoiceIssue.network => strings.voiceNetwork,
    VoiceIssue.failed => strings.voiceFailed,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = S.of(context);
    return Watch((context) {
      final listening = controller.phase.value == VoicePhase.listening;
      final locale = controller.locale.value;
      final unavailable = controller.unavailable.value;
      final issue = controller.issue.value;
      final issueText = _issueText(strings, issue, locale);
      return Container(
        color: context.colors.keyboardBackground,
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    target == null ? '' : strings.voiceTarget(target!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.typo.paragraph.copyWith(color: colors.keyboardInk),
                  ),
                ),
                for (final option in VoiceLocale.values)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: ChoiceChip(
                      key: ValueKey('voice-locale-${option.languageCode}'),
                      label: Text(
                        option.languageCode.toUpperCase(),
                        semanticsLabel: option == VoiceLocale.vi ? strings.voiceLanguageVi : strings.voiceLanguageEn,
                      ),
                      selected: option == locale,
                      onSelected: unavailable.contains(option) ? null : (_) => controller.setLocale(option),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                IconButton(
                  key: const ValueKey('voice-close'),
                  tooltip: strings.voiceClose,
                  icon: Icon(Icons.close, color: colors.keyboardInk),
                  onPressed: controller.close,
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('voice-text'),
                    controller: controller.text,
                    readOnly: listening,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: strings.voiceHint,
                      isDense: true,
                      filled: true,
                      fillColor: colors.keyboardKey,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('voice-send'),
                  tooltip: strings.voiceSend,
                  icon: Icon(Icons.send, color: canSend ? colors.primary : colors.keyboardInk.withValues(alpha: 0.4)),
                  onPressed: canSend ? controller.sendNow : null,
                ),
              ],
            ),
            if (issueText != null)
              Row(
                key: const ValueKey('voice-issue'),
                children: [
                  Expanded(child: Text(issueText, style: context.typo.paragraph.copyWith(color: colors.error))),
                  if (issue == VoiceIssue.noPermission)
                    TextButton(onPressed: onOpenSettings, child: Text(strings.openSettings)),
                ],
              ),
            if (!canSend)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(strings.voiceNotLive, style: context.typo.paragraph.copyWith(color: colors.keyboardInk)),
              ),
          ],
        ),
      );
    });
  }
}
```

If `context.colors` has no `error` (check `lib/core/design/app_colors.dart`), use the error/red colour that file defines (e.g. `colors.danger`); if `context.typo.paragraph` is named differently, use the style `ExtraKeysBar` uses for Paste (`context.typo.paragraph`).

- [ ] **Step 7: Wire the page**

In `terminal_page.dart` add imports:

```dart
import 'package:shellx_mobile/features/voice/presentation/controllers/voice_composer_controller.dart';
import 'package:shellx_mobile/features/voice/presentation/widgets/mic_button.dart';
import 'package:shellx_mobile/features/voice/presentation/widgets/voice_composer.dart';
```

State fields (after `_controller`):

```dart
  /// Voice spec §3.1: the composer of this page; a line goes to whichever tab is active.
  late final VoiceComposerController _voice;
  late final AppLifecycleListener _lifecycle;
  late final void Function() _stopVoicePhase;
```

`initState`, after `_stopExit = ...` (creating the controller is cheap: the recognizer is only
initialised on the first mic tap):

```dart
    _voice = getIt<VoiceComposerController>()..attach(canSend: _activeTabLive, onSubmit: _controller.submitLine);
    // A call, the lock screen or the app switcher stops the listen; the text stays (spec §5).
    _lifecycle = AppLifecycleListener(onInactive: _voice.pause, onHide: _voice.pause);
    // Spec §3.1: while the composer is open the keyboard types into it, not into the terminal.
    var wasOpen = false;
    _stopVoicePhase = _voice.phase.subscribe((phase) {
      final open = phase != VoicePhase.closed;
      if (open && !wasOpen) _terminalFocus.unfocus();
      if (!open && wasOpen && mounted) _terminalFocus.requestFocus();
      wasOpen = open;
    });
```

`dispose`, before `_controller.dispose()` (leaving the page cancels the listen and drops the text,
spec §5):

```dart
    _stopVoicePhase();
    _lifecycle.dispose();
    _voice.dispose();
```

Helper in the state class:

```dart
  bool _activeTabLive() =>
      !_controller.closing.peek() && (_controller.workspace.activeTab.peek()?.isLive.peek() ?? false);
```

In `_body`, replace the bottom `Container(... ExtraKeysBar ...)` with:

```dart
        Watch((context) {
          if (_voice.phase.value == VoicePhase.closed) return const SizedBox.shrink();
          final tab = workspace.activeTab.value;
          return VoiceComposer(
            controller: _voice,
            target: tab == null ? null : '${tab.title.value} · ${widget.machineName}',
            canSend: tab?.isLive.value ?? false,
            onOpenSettings: () => unawaited(getIt<ExternalLinks>().openAppSettingsOrToast()),
          );
        }),
        Container(
          color: context.colors.keyboardBackground,
          child: SafeArea(
            top: false,
            child: ExtraKeysBar(
              controller: workspace.extraKeys,
              onKey: _controller.sendKey,
              onPaste: _paste,
              leading: Watch(
                (context) => (workspace.activeTab.value?.isLive.value ?? false)
                    ? MicButton(
                        controller: _voice,
                        onTap: () => _voice.toggleMic(Localizations.localeOf(context).languageCode),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
```

Both `Watch`es are inside `_body`, which [build] replaces once the page is closing, so they never
read a disposed workspace.

- [ ] **Step 8: Run the tests**

Run: `cd apps/mobile && flutter test test/features/terminal test/features/voice test/l10n_test.dart && flutter analyze`
Expected: PASS; no analyzer issues.

- [ ] **Step 9: Run the whole mobile suite**

Run: `cd apps/mobile && flutter test`
Expected: PASS (every test, including the existing `terminal_page_test.dart` cases).

- [ ] **Step 10: Commit**

```bash
git add apps/mobile/lib apps/mobile/test
git commit -m "feat(mobile): voice composer on the terminal page — mic in the extra keys, VI/EN chips, Send/✕, issues with Mở Cài đặt, focus hand-off, pause on inactive"
```

---

### Task 7: Privacy policy, spec sync and manual test checklist

**Files:**
- Modify: `web/src/pages/privacy.md`, `web/src/pages/en/privacy.md`
- Modify: `docs/superpowers/specs/2026-10-06-mobile-voice-input-design.md`
- Modify: `docs/superpowers/HANDOFF.md`

**Interfaces:** none (docs).

- [ ] **Step 1: Privacy policy (vi)**

In `web/src/pages/privacy.md`: set `updated: "<today's date>"` in the front matter, and at the end of section `## 4. Dữ liệu chỉ nằm trên thiết bị của bạn` add:

```markdown
### Nhập lệnh bằng giọng nói

- Ứng dụng di động chỉ dùng micro khi bạn chạm nút mic trên màn terminal; không ghi âm nền.
- Khi điện thoại hỗ trợ, lời nói được chuyển thành chữ ngay trên điện thoại. Nếu không, âm thanh được gửi tới dịch vụ nhận dạng giọng nói của Apple (iOS) hoặc Google (Android) và được xử lý theo chính sách của họ.
- ShellX không lưu âm thanh và không gửi âm thanh tới máy chủ của ShellX. Chữ bạn gửi đi vào terminal như phím gõ, được mã hóa đầu cuối (mục 2).
- Lựa chọn ngôn ngữ nhận dạng (tiếng Việt/tiếng Anh) được lưu trên điện thoại.
```

- [ ] **Step 2: Privacy policy (en)**

In `web/src/pages/en/privacy.md`: same `updated`, and at the end of `## 4. Data that stays on your devices`:

```markdown
### Voice input

- The mobile app uses the microphone only when you tap the mic on the terminal screen; it never records in the background.
- When your phone supports it, speech is turned into text on the phone. Otherwise the audio is sent to Apple's (iOS) or Google's (Android) speech recognition service and handled under their policies.
- ShellX does not store audio and does not send audio to ShellX servers. The text you send goes to the terminal like typed keys, end-to-end encrypted (section 2).
- Your recognition language choice (Vietnamese/English) is stored on the phone.
```

Run: `cd web && npm run build`
Expected: build succeeds.

- [ ] **Step 3: Sync the spec with what was built**

In `docs/superpowers/specs/2026-10-06-mobile-voice-input-design.md` §4.1:
- `VoiceLocaleStore` row → "`AppSettings.voiceLocale` / `setVoiceLocale` (`lib/core/settings/app_settings.dart`) — the app keeps one settings object".
- `SpeechInput` row → `ensurePermission()` returns `granted`, `denied`, `unsupported`; `availability(locale)` is `resolveLocale(locale)` → platform locale id or null; events `SpeechPartial`, `SpeechFinal`, `SpeechFailed`, `SpeechListening`.
- Add under §3.1 point 3: "Nghe trên máy trước; nếu lỗi trước khi nghe được chữ nào (ngôn ngữ không có trên máy / lỗi khác), thử lại một lần bằng nhận dạng cloud của hệ điều hành."
- Add to §5: "Máy không có bộ nhận dạng giọng nói → 'Máy này không hỗ trợ nhận dạng giọng nói'"; "Không có phiên live: nút mic ẩn, composer đang mở vẫn giữ".
- Add to §4.2 `submitLine`: "Khi chương trình không bật bracketed paste, xuống dòng trong composer thành dấu cách (tránh chạy sớm từng dòng)."

- [ ] **Step 4: HANDOFF checklist**

Append to `docs/superpowers/HANDOFF.md` a section:

```markdown
## Voice input (mobile) — việc của người dùng

- [ ] iPhone thật: chạm mic → hai hộp thoại quyền (micro, nhận dạng giọng nói) bằng tiếng Việt; nói "chạy git status gửi" trong một phiên zsh → `git status` chạy.
- [ ] iPhone: trong Claude Code, nói một câu dài rồi "gửi" → câu tới Claude Code đúng một lần, không tách dòng.
- [ ] iPhone chế độ máy bay: nếu máy nghe được tiếng Việt on-device thì vẫn chạy; nếu không, hiện "Cần kết nối mạng…".
- [ ] Android thật (có Google app): như trên; máy chưa cài gói tiếng Việt → chip VI mờ + gợi ý EN.
- [ ] Từ chối quyền → dòng lỗi + "Mở Cài đặt" mở đúng trang cài đặt của ShellX.
- [ ] Đang nghe thì có cuộc gọi / khoá màn hình → dừng nghe, chữ còn nguyên, không tự gửi.
- [ ] App Store Connect / Play Console: cập nhật nhãn quyền riêng tư (Audio data — dùng cho chức năng app, không thu thập về máy chủ ShellX) nếu biểu mẫu yêu cầu.
```

- [ ] **Step 5: Commit**

```bash
git add web/src/pages/privacy.md web/src/pages/en/privacy.md docs/superpowers/specs/2026-10-06-mobile-voice-input-design.md docs/superpowers/HANDOFF.md
git commit -m "docs: privacy (vi, en) voice input section; voice spec synced with the build; HANDOFF device checklist"
```

---

## Final verification

- [ ] `cd apps/mobile && flutter analyze && flutter test` — all green.
- [ ] `cd web && npm run build` — succeeds.
- [ ] `git status` clean; `git log --oneline` shows the seven task commits.
- [ ] Manual device checks are listed in HANDOFF (cannot be run here: no microphone in tests).
