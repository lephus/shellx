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
| V2 | Ngôn ngữ | Mỗi lượt một ngôn ngữ, chọn VI/EN bằng nút chọn hai phần (segmented); mặc định theo ngôn ngữ app; nhớ lựa chọn |
| V3 | Đưa chữ vào terminal | Qua ô soạn thảo (composer) sửa được; chỉ gửi khi bấm Gửi hoặc nói từ khoá gửi |
| V4 | Engine | Nhận dạng của hệ điều hành (Apple Speech, Android SpeechRecognizer) qua package `speech_to_text`; Android: ưu tiên on-device, không có thì dùng nhận dạng cloud của hệ điều hành. iOS: không ép on-device (plugin không tự quay về cloud trong cùng một lượt: khi máy không nghe on-device được, nó trả lỗi nhưng vẫn chạy lượt on-device), để Apple tự chọn xử lý trên máy hay trên máy chủ. Loại bỏ: chỉ on-device tuyệt đối, Whisper cloud qua relay (phá nguyên tắc relay mù), whisper.cpp on-device (nặng) |
| V5 | Bật micro | Chạm để bật, chạm lại hoặc im lặng ~2 giây để dừng |
| V6 | Ctrl+C bằng giọng | Không làm — nhận nhầm sẽ ngắt tiến trình; phím Ctrl trên thanh phím phụ vẫn có |
| V7 | Cách triển khai | Plugin `speech_to_text` sau interface `SpeechInput`; mọi logic (từ khoá, composer, gửi) là Dart thuần, test bằng fake. Đổi sang platform channel tự viết sau này không phải sửa UI |

---

## 3. Trải nghiệm người dùng

### 3.1 Luồng

1. Nút **mic** ở đầu thanh phím phụ (`ExtraKeysBar`), biểu tượng màu nhấn để khác các phím. Luôn ở đúng chỗ đó: khi phiên không live thì mờ (40 %) và bị vô hiệu (Semantics `enabled: false`), không biến mất, để các phím sau không xê dịch. Đang nghe thì mic vẫn bấm được ("Dừng nghe") kể cả khi phiên vừa hết live.
2. Chạm lần đầu → xin quyền micro và quyền nhận dạng giọng nói.
3. Đang nghe:
   - composer trượt lên trên thanh phím phụ và bàn phím;
   - mic có hiệu ứng sóng (đứng yên khi hệ thống yêu cầu giảm chuyển động);
   - ô chữ trống thì gợi ý đổi thành "Đang nghe… nói “gửi” để gửi" (EN: "Listening… say “send” to send"), và trình đọc màn hình được báo "Đang nghe" mỗi lần bắt đầu nghe;
   - chữ hiện dần theo kết quả từng phần (partial), bằng font JetBrains Mono như terminal (gợi ý vẫn Raleway);
   - nút chọn hai phần **VI | EN** (mỗi phần ≥ 44 pt, không có dấu ✓ nên không xê dịch) để đổi ngôn ngữ;
   - Android: nghe trên máy trước; nếu lỗi trước khi nghe được chữ nào (ngôn ngữ không có trên máy / lỗi khác), thử lại một lần bằng nhận dạng cloud của hệ điều hành. iOS: một lượt, Apple tự chọn trên máy hay cloud (V4).
4. Dừng (chạm mic hoặc im lặng ~2 giây) → chữ nằm trong composer, sửa được bằng bàn phím. Chạm mic lần nữa → nói tiếp, **nối thêm** vào chữ đang có (cách bằng một dấu cách).
5. Gửi: nút **Gửi** hoặc từ khoá gửi. Composer trống lại và vẫn mở để nói tiếp. Nút **✕** đóng composer, bỏ chữ.
6. Composer gõ tay được — cũng là chỗ soạn câu dài dễ hơn gõ thẳng vào terminal. Mở composer thì bàn phím của terminal ẩn đi; chạm vào ô chữ thì bàn phím hiện lại và gõ vào composer, không vào terminal. ✕ trả focus về terminal.
7. Composer hiện tên tab đích (ví dụ "Gửi tới: zsh · MacBook", EN "To: zsh · MacBook"). Ô chữ trống thì tooltip của Gửi là "Gửi phím Enter". Đổi tab khi đang soạn: chữ giữ nguyên, gửi luôn tới tab **đang mở**.

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
| `SpeechInput` (interface) | `domain/speech_input.dart` | `Future<SpeechPermission> ensurePermission()` (`granted`, `denied`, `unsupported`); `Future<String?> resolveLocale(VoiceLocale)` → mã locale của nền tảng hoặc null khi máy không nhận dạng được; `bool tryOnDeviceFirst` (lượt đầu có xin on-device không); `start(localeId, {required bool onDevice})`; `stop()`; `cancel()`; `Stream<SpeechEvent> events` gồm `SpeechPartial(text)`, `SpeechFinal(text)`, `SpeechFailed(SpeechErrorKind)`, `SpeechListening(bool)` | không |
| `SpeechToTextInput` | `data/speech_to_text_input.dart` | Cài đặt bằng `speech_to_text`: `pauseFor: 2s`, `listenFor: 60s`, `partialResults: true`, `ListenMode.dictation`, `cancelOnError: true`, `onDevice` theo controller. `tryOnDeviceFirst`: Android `true`, iOS `false` (V4). `resolveLocale`: `locales()` chờ tối đa 2 s (Android 13+ có thể không bao giờ trả lời); hết giờ, lỗi, hoặc danh sách không có ngôn ngữ đó → dùng mã ưu tiên (`vi-VN`/`en-US`), không trả null — Android 13+ chỉ liệt kê ngôn ngữ on-device trong khi cloud vẫn có thể nhận; nếu thật sự không có, bộ nhận dạng báo `error_language_*` → `localeUnavailable`. Ánh xạ mã lỗi plugin (Android và iOS) → `SpeechErrorKind` (`noPermission`, `localeUnavailable`, `network`, `noMatch`, `interrupted`, `unsupported` — nhận dạng bị tắt trên iOS, `other`). Chỉ ghi log tên lỗi, không ghi lời nói | `speech_to_text` |
| `VoiceCommandParser` | `domain/voice_command_parser.dart` | Hàm thuần `parse(text, VoiceLocale)` → `VoiceSend(text)` / `VoiceCancel()` / `VoiceAppend(text)` theo §3.2 | không |
| `VoiceLocale` | `domain/voice_locale.dart` | enum `vi` (`vi-VN`), `en` (`en-US`), kèm từ khoá gửi/huỷ của từng ngôn ngữ | không |
| `AppSettings.voiceLocale` / `setVoiceLocale` | `lib/core/settings/app_settings.dart` | Đọc/ghi lựa chọn VI/EN; null = theo ngôn ngữ app. App giữ một đối tượng settings duy nhất, không có `VoiceLocaleStore` riêng | storage hiện có |
| `VoiceComposerController` | `presentation/controllers/voice_composer_controller.dart` | Signals `phase` (`closed`/`idle`/`listening`), `issue` (`VoiceIssue`: `noPermission`, `unsupported`, `localeUnavailable`, `network`, `failed`), `locale`, `unavailable` (phần ngôn ngữ đó bị vô hiệu; xoá khi composer mở lại từ trạng thái đóng) + `TextEditingController text`; `attach(canSend, onSubmit)`. Một lượt nghe tại một thời điểm: partial ghép lên chữ đã có; final → parser; `VoiceSend` gọi `onSubmit(text)`; lượt đầu `onDevice: tryOnDeviceFirst`, thử lại cloud chỉ sau một lượt on-device; lượt đã cạn và `done` muộn xử lý theo §5. `pause()` (app không còn active) huỷ lượt đang nghe, và nếu đang chuẩn bị (quyền, locale) thì lượt đó không bắt đầu; lần chạm mic sau nghe lại bình thường | `SpeechInput`, `AppSettings` |
| `VoiceComposer` | `presentation/widgets/voice_composer.dart` | Ô chữ nhiều dòng (JetBrains Mono), nút chọn VI/EN, Gửi, ✕, nhãn "Gửi tới:", dòng lỗi, dòng chú thích khi không gửi được (`VoiceSendBlock`: ended / detached / disconnected); báo "Đang nghe" cho trình đọc màn hình; có Semantics label | controller |
| `MicButton` | `presentation/widgets/mic_button.dart` | Nút mic dùng ở thanh phím phụ; `enabled` theo phiên live (vẫn bật khi đang nghe); có hành động chạm cho trình đọc màn hình | controller |

### 4.2 Sửa code có sẵn

- `features/terminal/presentation/widgets/extra_keys_bar.dart`: nhận thêm widget đầu hàng (leading) để chèn `MicButton`; enum `ExtraKey` không đổi (đó là các phím gửi vào terminal).
- `features/terminal/presentation/pages/terminal_page.dart`: hiện `VoiceComposer` trên thanh phím phụ khi `phase != closed`; chuyển focus giữa composer và `TerminalView`; truyền `canSend` theo trạng thái live của tab đang mở.
- `features/terminal/presentation/controllers/terminal_page_controller.dart`: thêm `submitLine(String text)` = `terminal.paste(text)` (xử lý bracketed paste như nút Dán) rồi gửi `\r` **ngoài** cặp `ESC[200~ … ESC[201~` để Enter thực thi. Text rỗng → chỉ gửi `\r`. Khi chương trình không bật bracketed paste, xuống dòng trong composer thành dấu cách (tránh chạy sớm từng dòng). Áp dụng modifier dính (Ctrl/Alt one-shot) **không** áp lên dòng gửi từ composer.
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
| Từ chối quyền (micro hoặc nhận dạng) | Dòng lỗi trong composer "Cần quyền micro và nhận dạng giọng nói để nói lệnh", bên dưới là nút **Mở Cài đặt** (cao 44 pt). Màu chữ đạt AA trên nền bàn phím. Nút mic vẫn hiện; chạm lần sau kiểm tra lại quyền |
| Ngôn ngữ đang chọn `unavailable` (bộ nhận dạng báo lỗi ngôn ngữ, hoặc iOS báo thiếu gói `error_assets_not_installed`) | Dòng lỗi "Máy chưa hỗ trợ nhận dạng tiếng Việt" (hoặc tiếng Anh) + gợi ý đổi ngôn ngữ; phần ngôn ngữ đó trong nút chọn VI|EN bị vô hiệu tới khi composer đóng rồi mở lại |
| Không on-device và mất mạng (`network`) | "Cần kết nối mạng để nhận dạng giọng nói"; chữ giữ nguyên |
| `noMatch` (không nghe được gì) | Dừng nghe, không báo lỗi to; chữ giữ nguyên |
| Phiên hết live khi đang soạn | Chữ giữ nguyên; Gửi và từ khoá gửi vô hiệu, có dòng chú thích theo lý do: phiên đã thoát / mất / lỗi (hoặc không còn tab) → "Phiên đã kết thúc — mở phiên mới để gửi"; thiết bị khác chiếm phiên hoặc máy tính ngắt điện thoại → "Phiên đã ngắt khỏi điện thoại — gắn lại để gửi"; đang kết nối lại → "Phiên chưa kết nối — gửi được khi kết nối lại" (live lại thì gửi được) |
| Đổi tab | Chữ giữ nguyên; nhãn tab đích cập nhật; gửi tới tab đang mở |
| App xuống nền, khoá màn hình (lock gate), cuộc gọi, iOS hết giới hạn ~1 phút mỗi lượt (`interrupted`) | Dừng nghe, giữ chữ, không tự bật lại |
| Rời màn terminal | Huỷ nghe; composer đóng, chữ bỏ |
| Máy không có bộ nhận dạng giọng nói, hoặc nhận dạng bị tắt (iOS `error_speech_recognizer_disabled`) | "Máy này không hỗ trợ nhận dạng giọng nói" |
| Không có phiên live | Nút mic mờ và vô hiệu tại chỗ (trừ khi đang nghe: vẫn dừng được); composer đang mở vẫn giữ |
| `done` đến mà không có kết quả cuối (final) | Không chặn mic: lượt nghe đã cạn bị huỷ ở lần chạm mic kế tiếp rồi nghe lượt mới |
| `done` muộn của lượt nghe trước | Bỏ qua cho tới khi lượt mới báo đã bắt đầu nghe (`SpeechListening(true)`, partial hoặc final), để không kết thúc nhầm lượt mới |

---

## 6. Quyền riêng tư

Đã sửa `web/src/pages/privacy.md` và `web/src/pages/en/privacy.md`:

- Mục con "Nhập lệnh bằng giọng nói" nằm trong mục 2 (mã hoá đầu cuối), không còn ở mục 4 (dữ liệu chỉ nằm trên thiết bị), vì âm thanh có thể tới Apple/Google; số mục không đổi.
- Âm thanh chỉ được ghi khi người dùng bật mic, không ghi nền.
- iPhone: dùng nhận dạng giọng nói của Apple — Apple có thể xử lý trên điện thoại hoặc trên máy chủ của Apple. Android: nhận dạng trên điện thoại khi máy làm được; nếu không, âm thanh tới dịch vụ của Google. Việc nhận dạng diễn ra trước khi mã hoá đầu cuối.
- ShellX không lưu và không gửi âm thanh tới máy chủ của ShellX; chữ đã gửi đi như phím gõ (mã hoá đầu cuối).
- Thêm một gạch đầu dòng ở Tóm tắt và một câu ở mục 7 nêu Apple/Google (nhận dạng giọng nói) là bên xử lý khi dùng giọng nói.
- Lời xin quyền iOS (`NSSpeechRecognitionUsageDescription`, vi/en) dùng cùng cách nói.
- Cập nhật nhãn quyền riêng tư của store nếu cần (ghi vào HANDOFF).

---

## 7. Kiểm thử

- **Unit `VoiceCommandParser`** (dạng bảng): "chạy test gửi" → `VoiceSend("chạy test")`; "Gửi." → `VoiceSend("")`; "gửi email cho tôi" → `VoiceAppend`; "hủy"/"huỷ" → `VoiceCancel`; "run tests, send" (EN) → `VoiceSend("run tests")`; "send" khi locale VI → `VoiceAppend`; hoa thường, dấu câu, khoảng trắng.
- **Unit `VoiceComposerController`** với `FakeSpeechInput`: partial ghép lên chữ cũ; final → parser; `VoiceSend` gọi `onSubmit` và làm trống; `VoiceCancel` xoá; mỗi `SpeechErrorKind` → đúng state; không live → không gọi `onSubmit`; nhớ locale qua `AppSettings.voiceLocale`.
- **Unit `submitLine`**: bracketed paste bật → `ESC[200~text ESC[201~` rồi `\r`; tắt → `text\r`; rỗng → `\r`; modifier one-shot không bị áp.
- **Widget**: nút mic trên thanh phím phụ, mờ và vô hiệu tại chỗ khi không live (vẫn dừng được khi đang nghe); composer hiện/đóng; "Đang nghe…" và thông báo cho trình đọc màn hình; nút chọn VI/EN (≥ 44 pt, không xê dịch); font JetBrains Mono; Gửi/✕; nhãn "Gửi tới:"; chú thích ended/detached/disconnected; màu AA của dòng lỗi và "Mở Cài đặt"; Semantics.
- **Thử tay trên máy thật** (iPhone, Android; không giả lập được micro): tiếng Việt và tiếng Anh; máy có và không có on-device; từ chối quyền; chế độ máy bay; "gửi" khi đang trong Claude Code.

---

## 8. Ngoài phạm vi

- Dịch ngôn ngữ tự nhiên → lệnh shell.
- Lệnh giọng nói cho phím (Ctrl+C, mũi tên, Tab), chuyển tab bằng giọng.
- Whisper/STT cloud của ShellX; whisper.cpp on-device.
- Wake word ("Hey ShellX"), nghe nền.
- Voice trên web và desktop.
