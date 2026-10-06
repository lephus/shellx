# Nhập lệnh bằng giọng nói trên mobile — Đặc tả thiết kế

- **Ngày:** 2026-10-06
- **Trạng thái:** Người dùng đã duyệt từng quyết định V1–V6 và ba phần thiết kế (luồng, kiến trúc, lỗi/test) trong brainstorming 2026-10-06.
- **Phạm vi:** chỉ app mobile (`apps/mobile`) và chính sách quyền riêng tư (`web/src/pages/privacy.md`, `web/src/pages/en/privacy.md`). Không đổi relay, agent, protocol, desktop.
- **Lộ trình chung:** đây là dự án con **B**, làm song song với nhánh desktop kiểu cmux (A1 → A2 → A4 → A3 → A5), mỗi dự án con có spec riêng.

---

## 1. Mục tiêu

Trên màn terminal của điện thoại, người dùng **nói** thay vì gõ: lời nói thành chữ trong một ô soạn thảo, sửa được, rồi gửi vào terminal kèm Enter (bấm Gửi hoặc nói "gửi"/"send"). Trường hợp chính: nhắn cho AI agent (Claude Code, Codex…) đang chạy trong terminal — agent tự hiểu ngôn ngữ tự nhiên, ShellX không dịch ra lệnh shell.

### Tiêu chí thành công

1. Trên iPhone và Android đời gần đây: nói một câu tiếng Việt rồi "gửi" → câu đó vào terminal kèm Enter trong khoảng 1 giây sau khi dứt lời.
2. Không lượt nhận dạng nào tự chạy lệnh khi người dùng chưa nói "gửi"/"send" hoặc bấm Gửi.
3. Từ chối quyền, máy thiếu ngôn ngữ, mất mạng: có thông báo rõ ràng, không mất chữ đang soạn.
4. App cũ, agent và relay không bị ảnh hưởng (chỉ dùng đường `input` có sẵn).

---

## 2. Nhật ký quyết định

| # | Chủ đề | Quyết định |
|---|---|---|
| V1 | Nghĩa của "nói để ra lệnh" | Đọc chính tả là chính + vài từ khoá điều khiển ("gửi"/"send", "huỷ"/"cancel"). Không dịch ngôn ngữ tự nhiên → lệnh shell |
| V2 | Ngôn ngữ | Mỗi lượt một ngôn ngữ, chọn VI/EN bằng chip; mặc định theo ngôn ngữ app; nhớ lựa chọn |
| V3 | Đưa chữ vào terminal | Qua ô soạn thảo (composer) sửa được; chỉ gửi khi bấm Gửi hoặc nói từ khoá gửi |
| V4 | Engine | Nhận dạng của hệ điều hành (Apple Speech, Android SpeechRecognizer) qua package `speech_to_text`; ưu tiên on-device, không có thì dùng nhận dạng cloud của hệ điều hành. Loại bỏ: chỉ on-device tuyệt đối, Whisper cloud qua relay (phá nguyên tắc relay mù), whisper.cpp on-device (nặng) |
| V5 | Bật micro | Chạm để bật, chạm lại hoặc im lặng ~2 giây để dừng |
| V6 | Ctrl+C bằng giọng | Không làm — nhận nhầm sẽ ngắt tiến trình; phím Ctrl trên thanh phím phụ vẫn có |
| V7 | Cách triển khai | Plugin `speech_to_text` sau interface `SpeechInput`; mọi logic (từ khoá, composer, gửi) là Dart thuần, test bằng fake. Đổi sang platform channel tự viết sau này không phải sửa UI |

---

## 3. Trải nghiệm người dùng

### 3.1 Luồng

1. Nút **mic** ở đầu thanh phím phụ (`ExtraKeysBar`), chỉ hiện khi phiên đang live.
2. Chạm lần đầu → xin quyền micro và quyền nhận dạng giọng nói.
3. Đang nghe:
   - composer trượt lên trên thanh phím phụ và bàn phím;
   - mic có hiệu ứng sóng;
   - chữ hiện dần theo kết quả từng phần (partial);
   - chip **VI / EN** để đổi ngôn ngữ.
4. Dừng (chạm mic hoặc im lặng ~2 giây) → chữ nằm trong composer, sửa được bằng bàn phím. Chạm mic lần nữa → nói tiếp, **nối thêm** vào chữ đang có (cách bằng một dấu cách).
5. Gửi: nút **Gửi** hoặc từ khoá gửi. Composer trống lại và vẫn mở để nói tiếp. Nút **✕** đóng composer, bỏ chữ.
6. Composer gõ tay được — cũng là chỗ soạn câu dài dễ hơn gõ thẳng vào terminal. Khi composer mở, focus và bàn phím ảo thuộc về composer, không thuộc terminal.
7. Composer hiện tên tab đích (ví dụ "→ zsh · MacBook"). Đổi tab khi đang soạn: chữ giữ nguyên, gửi luôn tới tab **đang mở**.

### 3.2 Từ khoá

Từ khoá chỉ có tác dụng khi nằm ở **cuối kết quả cuối cùng (final) của một lượt nói** và thuộc ngôn ngữ đang chọn. So khớp bỏ qua hoa thường, dấu câu và khoảng trắng ở cuối.

| Ngôn ngữ | Từ khoá | Tác dụng |
|---|---|---|
| VI | "gửi" | Bỏ từ khoá khỏi chữ của lượt nói; gửi (chữ composer + chữ lượt nói) kèm Enter |
| VI | "huỷ", "hủy" | Xoá chữ composer (cả chữ của lượt nói), không gửi gì |
| EN | "send" | Như "gửi" |
| EN | "cancel" | Như "huỷ" |

- "gửi email cho tôi" → không phải lệnh (từ khoá không ở cuối), nối như chữ thường.
- Chỉ nói "gửi" khi composer trống (hoặc chữ còn lại toàn khoảng trắng) → gửi đúng một Enter (để trả lời xác nhận của Claude Code).
- Khi phiên không live: từ khoá gửi bị bỏ qua, từ khoá vẫn được bỏ khỏi chữ, chữ giữ nguyên.

---

## 4. Kiến trúc

Chỉ trong `apps/mobile`, theo pattern sẵn có: `Controller` + `StateSignal` (signals), DI bằng get_it/injectable, thư mục `features/`.

### 4.1 Thành phần mới — `lib/features/voice/`

| Thành phần | Vị trí | Vai trò | Phụ thuộc |
|---|---|---|---|
| `SpeechInput` (interface) | `domain/speech_input.dart` | `Future<SpeechAvailability> availability(String localeId)` (`onDevice`, `cloud`, `unavailable`); `Future<SpeechPermission> ensurePermission()` (`granted`, `denied`, `permanentlyDenied`); `start(localeId, {required bool onDevice})`; `stop()`; `cancel()`; `Stream<SpeechEvent> events` gồm `SpeechPartial(text)`, `SpeechFinal(text)`, `SpeechError(SpeechErrorKind)`, `SpeechListening(bool)` | không |
| `SpeechToTextInput` | `data/speech_to_text_input.dart` | Cài đặt bằng `speech_to_text`: `pauseFor: 2s`, `partialResults: true`, `onDevice` khi `availability` trả `onDevice`. Ánh xạ mã lỗi plugin → `SpeechErrorKind` (`noPermission`, `localeUnavailable`, `network`, `noMatch`, `interrupted`, `other`) | `speech_to_text` |
| `VoiceCommandParser` | `domain/voice_command_parser.dart` | Hàm thuần `parse(text, VoiceLocale)` → `VoiceSend(text)` / `VoiceCancel()` / `VoiceAppend(text)` theo §3.2 | không |
| `VoiceLocale` | `domain/voice_locale.dart` | enum `vi` (`vi-VN`), `en` (`en-US`) | không |
| `VoiceLocaleStore` | `data/voice_locale_store.dart` | Đọc/ghi lựa chọn VI/EN bằng storage key-value sẵn có của app; mặc định theo ngôn ngữ app | storage hiện có |
| `VoiceComposerController` | `presentation/controllers/voice_composer_controller.dart` | State `VoiceComposerState { phase: closed/idle/listening, text, partial, locale, error, canSend }`. Ghép partial lên chữ đã có; final → parser; `VoiceSend` gọi callback `onSubmit(text)`; quản lý quyền và lỗi theo §5 | `SpeechInput`, `VoiceLocaleStore` |
| `VoiceComposer` | `presentation/widgets/voice_composer.dart` | Ô chữ nhiều dòng, chip VI/EN, nút mic (sóng), Gửi, ✕, nhãn tab đích, dòng lỗi; có Semantics label | controller |
| `MicButton` | `presentation/widgets/mic_button.dart` | Nút mic dùng ở thanh phím phụ | controller |

### 4.2 Sửa code có sẵn

- `features/terminal/presentation/widgets/extra_keys_bar.dart`: nhận thêm widget đầu hàng (leading) để chèn `MicButton`; enum `ExtraKey` không đổi (đó là các phím gửi vào terminal).
- `features/terminal/presentation/pages/terminal_page.dart`: hiện `VoiceComposer` trên thanh phím phụ khi `phase != closed`; chuyển focus giữa composer và `TerminalView`; truyền `canSend` theo trạng thái live của tab đang mở.
- `features/terminal/presentation/controllers/terminal_page_controller.dart`: thêm `submitLine(String text)` = `terminal.paste(text)` (xử lý bracketed paste như nút Dán) rồi gửi `\r` **ngoài** cặp `ESC[200~ … ESC[201~` để Enter thực thi. Text rỗng → chỉ gửi `\r`. Áp dụng modifier dính (Ctrl/Alt one-shot) **không** áp lên dòng gửi từ composer.
- iOS `Info.plist` + `InfoPlist.strings` (vi, en): `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`.
- Android `AndroidManifest.xml`: `RECORD_AUDIO`; `<queries><intent><action android:name="android.speech.RecognitionService"/></intent></queries>`.
- `lib/l10n/intl_vi.arb`, `intl_en.arb`: chuỗi mới (nhãn nút, tooltip, lỗi §5, tab đích).
- `pubspec.yaml`: thêm `speech_to_text` (kiểm tra phiên bản mới nhất và license khi viết plan).

### 4.3 Luồng dữ liệu

Mic → `SpeechInput` → `SpeechPartial`/`SpeechFinal` → `VoiceComposerController` → `VoiceCommandParser` → chữ composer → (gửi) `onSubmit` → `TerminalPageController.submitLine` → frame `input` có sẵn → relay → máy tính.

Âm thanh không đi qua relay hay máy chủ ShellX; chỉ chữ đã gửi đi qua đường mã hoá đầu cuối như phím gõ.

---

## 5. Lỗi và tình huống biên

| Tình huống | Hành vi |
|---|---|
| Từ chối quyền (micro hoặc nhận dạng) | Snackbar "Cần quyền micro để nói lệnh" + nút **Mở Cài đặt** (cùng mẫu với push). Nút mic vẫn hiện; chạm lần sau kiểm tra lại quyền |
| Ngôn ngữ đang chọn `unavailable` | Dòng lỗi "Máy chưa hỗ trợ nhận dạng tiếng Việt" (hoặc tiếng Anh) + gợi ý đổi ngôn ngữ; chip ngôn ngữ đó mờ |
| Không on-device và mất mạng (`network`) | "Cần kết nối mạng để nhận dạng giọng nói"; chữ giữ nguyên |
| `noMatch` (không nghe được gì) | Dừng nghe, không báo lỗi to; chữ giữ nguyên |
| Phiên hết live khi đang soạn | Chữ giữ nguyên; Gửi và từ khoá gửi vô hiệu, có dòng chú thích; live lại thì gửi được |
| Đổi tab | Chữ giữ nguyên; nhãn tab đích cập nhật; gửi tới tab đang mở |
| App xuống nền, khoá màn hình (lock gate), cuộc gọi, iOS hết giới hạn ~1 phút mỗi lượt (`interrupted`) | Dừng nghe, giữ chữ, không tự bật lại |
| Rời màn terminal | Huỷ nghe; composer đóng, chữ bỏ |

---

## 6. Quyền riêng tư

Sửa `web/src/pages/privacy.md` và `web/src/pages/en/privacy.md`, thêm mục giọng nói:

- Âm thanh chỉ được ghi khi người dùng bật mic, không ghi nền.
- Khi máy hỗ trợ, nhận dạng chạy trên máy; nếu không, âm thanh được gửi tới dịch vụ nhận dạng của Apple (iOS) hoặc Google (Android) theo chính sách của họ.
- ShellX không lưu và không gửi âm thanh tới máy chủ của ShellX; chữ đã gửi đi như phím gõ (mã hoá đầu cuối).
- Cập nhật nhãn quyền riêng tư của store nếu cần (ghi vào HANDOFF).

---

## 7. Kiểm thử

- **Unit `VoiceCommandParser`** (dạng bảng): "chạy test gửi" → `VoiceSend("chạy test")`; "Gửi." → `VoiceSend("")`; "gửi email cho tôi" → `VoiceAppend`; "hủy"/"huỷ" → `VoiceCancel`; "run tests, send" (EN) → `VoiceSend("run tests")`; "send" khi locale VI → `VoiceAppend`; hoa thường, dấu câu, khoảng trắng.
- **Unit `VoiceComposerController`** với `FakeSpeechInput`: partial ghép lên chữ cũ; final → parser; `VoiceSend` gọi `onSubmit` và làm trống; `VoiceCancel` xoá; mỗi `SpeechErrorKind` → đúng state; không live → không gọi `onSubmit`; nhớ locale qua `VoiceLocaleStore`.
- **Unit `submitLine`**: bracketed paste bật → `ESC[200~text ESC[201~` rồi `\r`; tắt → `text\r`; rỗng → `\r`; modifier one-shot không bị áp.
- **Widget**: nút mic trên thanh phím phụ, ẩn khi không live; composer hiện/đóng; chip VI/EN; Gửi/✕; nhãn tab đích; Semantics.
- **Thử tay trên máy thật** (iPhone, Android; không giả lập được micro): tiếng Việt và tiếng Anh; máy có và không có on-device; từ chối quyền; chế độ máy bay; "gửi" khi đang trong Claude Code.

---

## 8. Ngoài phạm vi

- Dịch ngôn ngữ tự nhiên → lệnh shell.
- Lệnh giọng nói cho phím (Ctrl+C, mũi tên, Tab), chuyển tab bằng giọng.
- Whisper/STT cloud của ShellX; whisper.cpp on-device.
- Wake word ("Hey ShellX"), nghe nền.
- Voice trên web và desktop.
