# V2-5c — Trò chuyện bằng giọng nói với AI trên điện thoại (pha 1) — Đặc tả thiết kế

- **Ngày:** 2026-10-16
- **Branch:** `shellx-v2`. V2-5 không lên `main` khi người dùng chưa nói (đẩy `main` là phát hành app desktop).
- **Trạng thái:** Người dùng duyệt đề xuất V2-5 ngày 16/10: "làm theo khuyến nghị, Nhưng tên app nên để tên đầy đủ". Phần C của đề xuất là nguồn của tài liệu này. Trong khung đó, C1–C36 do người viết spec chốt, mỗi quyết định ghi giá nếu sai. Người dùng xem lại khi tiện.
- **Hướng đã được duyệt (đề xuất V2-5, phần C), không mở lại:**
  1. Nút sóng âm trong ô nhập AI bật **chế độ giọng nói ngay trong hội thoại**: một thanh có quả cầu hoặc sóng âm chạy theo mức micro và mức giọng đọc, cộng một màn "quả cầu" toàn màn hình tuỳ chọn. Mọi lượt nói nằm trong cùng hội thoại.
  2. Rảnh tay: im khoảng 700 ms sau từ cuối (lâu hơn sau từ ngập ngừng) thì **tự gửi**, không cần "gửi"; từ khoá vẫn giữ cho micro đọc chính tả của ô nhập. Agent làm thì hiện "đang làm…" kèm một gợi ý ngắn. Lượt xong thì **đọc to câu trả lời**, chỉ phần văn xuôi: khối mã, diff, đầu ra tool được bỏ và tóm tắt ("kèm 2 khối code"); câu trả lời dài đọc hết phần đầu rồi hỏi "đọc tiếp?". Đọc xong thì tự nghe lại.
  3. **Ngắt lời bằng chạm** vào quả cầu. Nói chen khi máy đang đọc (barge-in) là pha 2.
  4. Phụ đề trực tiếp cho cả hai bên; Tắt mic; Kết thúc.
  5. Tiếng Việt và tiếng Anh, đổi được ngay trong chế độ giọng nói, mặc định trong Cài đặt.
  6. Xin quyền: đọc to "Claude cần bạn cho phép: …" và hiện nút lớn. **Chỉ một lần chạm trả lời; không bao giờ trả lời xin quyền bằng giọng nói.**
  7. Pha 1: bộ nhận dạng của hệ điều hành (như đọc chính tả hôm nay) và giọng đọc của hệ điều hành; máy trạng thái riêng nghe → gửi → chờ → đọc → nghe; nhận biết hết câu từ mức âm; bắt đầu lại liền mạch qua giới hạn ~1 phút của iOS; tiếng bíp của Android là cái giá đã biết; half-duplex (micro tắt khi đang đọc); một chủ phiên âm thanh; app rời màn hình thì tắt, không chạy nền.
  8. Không dùng đám mây realtime. Desktop chưa có giọng nói. Trang Quyền riêng tư (`web/**`) là việc sau, cần đồng ý triển khai; câu xin quyền trong app được sửa.
- **Phụ thuộc và thứ tự:** V2-2b, V2-3, V2-4 đã gộp vào `shellx-v2`. Spec A (`2026-10-16-v2-5a-name-and-design-system-design.md`: tên, token, phông, biểu tượng, thành phần) và spec B (`2026-10-16-v2-5b-ai-assistant-design.md`: giao diện Trợ lý AI, thẻ ô nhập, luồng phiên mới) làm trước. C làm sau B vì cùng trang AI trên điện thoại; phần không đụng tệp của B chạy song song được (C36).
- **Cập nhật của người dùng lúc 11:25 ngày 16/10 (ràng buộc, thay dòng phông và biểu tượng của A):** "tôi muốn bạn sử dụng font chữ SF Mono cho mobile và desktop app ; icon trong app thì dùng cupertino". Với C: (1) phông giao diện là SF Mono: iOS dùng SF Mono của hệ thống, nạp lúc chạy, không bao giờ đóng gói; Android dùng JetBrains Mono; trên iOS mà không nạp được SF Mono thì dự phòng là JetBrains Mono, không phải Menlo (Menlo chỉ có 88/134 chữ tiếng Việt; V2-5a A31–A33, đã chốt). Vì vậy thanh giọng nói, phụ đề và nhãn phải đọc được bằng phông đơn cách: chữ tự xuống dòng, không có chiều rộng cố định (C4, §4.2–4.5); (2) biểu tượng là `CupertinoIcons` (`cupertino_icons` ghim 1.0.9) qua bảng vai trò trung tâm của A (`ShellxIcons` trong `packages/shellx_design`); A quyết tên vai trò và glyph. C dùng tám vai trò `voice*` ở §4.8, A khai chúng trong bảng của A (V2-5a §7.4); không dùng `Icons.*` của Material.
- **Nền mã:** đọc ở worktree `v2-2b` tại `fd48288` (mã giọng nói và AI giống hệt `640141b` mà nghiên cứu `voice-current.md` đã đọc). `PLUGIN/` = `~/.pub-cache/hosted/pub.dev/speech_to_text-7.4.0/`.
- **Nguồn đã kiểm ngày 16/10/2026:** mã app mobile (giọng nói, trang và bộ điều khiển AI, cài đặt, tệp iOS/Android, test); `packages/shellx_ai/lib/src/remote/mirror.dart`; mã nguồn `speech_to_text` 7.4.0 (Dart, Swift, Kotlin), `auto_route` 11.1.0, `app_settings` 7.0.0, `wakelock_plus` 1.3.3 trong pub cache; nghiên cứu V2-5 (`voice-current.md`; `references.md` §2.9 nguyên tắc của ChatGPT voice, §3 giới hạn nền tảng, `flutter_tts`, VAD, khử vọng, bảng so sánh, ngân sách trễ, rủi ro). `flutter_tts` và `audio_session` không có trong pub cache: kế hoạch ghim bản (C18, C20). Tên glyph Cupertino ở §4.8 đã kiểm trong `CupertinoIcons` của Flutter 3.41.4 (`packages/flutter/lib/src/cupertino/icons.dart`, cần `cupertino_icons` 1.0.0+; A ghim 1.0.9).
- **Ký hiệu:** "C1" là quyết định của tài liệu này; "V2-2 D13", "V2-2b B14" là của các spec V2 trước; "V3" là của spec giọng nói 06/10. "A", "B" là hai spec V2-5a, V2-5b, gọi theo vai trò: "thẻ kính của A", "thẻ ô nhập của B"; "B T41" là quyết định T41 của spec B (spec B ngày 16/10: T34 trang phiên đè lên thanh dưới, T38 ô nhập mở phiên, T39 thẻ ô nhập của trang phiên, T41 chỗ của 🎙 và chỗ bên phải nó dành cho nút của C). **ĐT** = điện thoại.
- **V2-5c được phép sửa:** `apps/mobile`: giọng nói, trang và bộ điều khiển AI, thẻ ô nhập của B ở đúng chỗ nút sóng âm và chỗ móc B dành cho C (B T41), cài đặt, chuỗi, các tệp iOS/Android ở §11, `pubspec.yaml`, test. **Không sửa:** giao thức, mọi gói trong `packages/*` (kể cả `shellx_design`: tám vai trò `voice*` đã có trong `ShellxIcons` của A, §4.8), desktop, relay, `web/**`.
- **Đổi so với spec cũ (có lý do):**
  - Spec giọng nói 06/10, tiêu chí 2 và V3 ("không lượt nhận dạng nào chạy gì khi chưa nói 'gửi' hay bấm Gửi"): **trong chế độ giọng nói**, câu nói tự gửi khi hết câu (C7, C9). Lý do: người dùng duyệt rảnh tay. An toàn vẫn dựa vào V2-2 D13: sửa tệp, chạy lệnh vẫn cần một lần chạm cho phép. Ở 🎙 và terminal, quy tắc cũ giữ nguyên.
  - V5 của spec 06/10 (im ~2 s thì dừng) giữ cho đọc chính tả; chế độ giọng nói dùng 700 ms (C7).
  - Loại trừ wake word và nghe nền (§8 của spec 06/10) **giữ nguyên**.
  - V2-2b B14 không đổi: 🎙 vẫn là đọc chính tả, "gửi" vẫn bắt buộc ở đó. Chuyện V2-2b F40 còn để lại (cho phép lần đầu xong phải chạm micro lần hai) không xảy ra trong chế độ giọng nói (C24).

---

## 1. Mục tiêu

Người dùng nói chuyện với agent như với ChatGPT voice: chạm một lần, nói, ngừng, nghe câu trả lời, nói tiếp. Không gõ, không chạm Gửi, không cần nhìn màn hình, trừ khi agent xin phép (khi đó bắt buộc chạm). Mỗi lượt vẫn là tin bình thường trong cùng hội thoại, nên tắt chế độ giọng nói lúc nào cũng thấy đủ. Pha 1 dùng nhận dạng và giọng đọc có sẵn của điện thoại: không thêm máy chủ, không đổi giao thức, không đổi desktop.

### Tiêu chí thành công (đo được)

1. **Vào nhanh.** Chạm nút sóng âm (đã cấp quyền từ trước): thanh giọng nói hiện và đang nghe trong ≤ 1 s.
2. **Rảnh tay.** Phòng yên, nói một câu tiếng Việt rồi ngừng: bong bóng tin của bạn hiện trong hội thoại ≤ 1,5 s sau từ cuối, không cần nói "gửi"; máy tính ghi "Bạn · từ điện thoại".
3. **Nghe câu trả lời.** Lượt kết thúc: nghe tiếng đầu tiên ≤ 0,8 s (iPhone), ≤ 1,2 s (Android). Khối mã không bị đọc mà có câu "Kèm N khối mã."; câu trả lời dài hơn 600 ký tự lời đọc dừng sau phần 1 và hỏi "Còn nữa. Đọc tiếp không?".
4. **Vòng lặp.** Đọc xong thì micro mở lại ≤ 1 s. Không bao giờ nghe trong lúc đang đọc (có test).
5. **Ngắt lời.** Chạm sóng âm (hay quả cầu) khi đang đọc: im ≤ 300 ms và đang nghe.
6. **Xin quyền.** Yêu cầu được đọc to; chỉ một lần chạm trả lời; nói "cho phép", "allow", "đồng ý" không làm gì (có test và kiểm tay).
7. **Vòng đời.** App ra nền: micro, giọng đọc, màn hình sáng đều tắt ≤ 1 s; quay lại thấy ô nhập với nháp còn nguyên.
8. **Không hồi quy.** 🎙 trong ô nhập và ô giọng nói của terminal vẫn cần "gửi"; mọi test hiện có vẫn xanh.
9. **Bản cũ.** Chạy với mọi desktop có `ai.prompt` (V2-2 trở đi); không có tin mới, không có cờ khả năng mới.
10. **Riêng tư.** Không log lời nói hay câu đọc; giọng đọc chỉ chạy trên máy (C18, C34).

### Ngân sách trễ pha 1 (suy từ số có nguồn, `references.md` §2.3, §3.8)

| Chặng | Ngân sách | Ghi chú |
|---|---|---|
| Nhận biết hết câu | 0,7 s (1,6 s sau từ ngập ngừng) | OpenAI `server_vad` 500 ms, Gemini 500–800 ms |
| Kết quả cuối sau `stop()` | ≤ 0,6 s | C8 |
| Gửi tới máy tính | một vòng qua relay | như gõ tay |
| Agent làm | tuỳ lượt | không thuộc ShellX trên ĐT |
| Tiếng đọc đầu tiên | 0,1–0,3 s iPhone; 0,3–0,8 s Android (lần đầu nối bộ đọc) | khởi động bộ đọc ngay khi vào chế độ (C18) |
| Micro mở lại sau khi đọc | 0,3 s gác + 0,2–0,8 s khởi động bộ nhận dạng | C14, C8 |

---

## 2. Kiểm tra hiện trạng (đọc mã ngày 2026-10-16)

| Mảng | Hiện có | Hệ quả cho V2-5c |
|---|---|---|
| Giao diện nhận dạng | `SpeechInput`: một lượt nghe mỗi lần `start`; sự kiện `SpeechPartial`, `SpeechFinal`, `SpeechFailed`, `SpeechListening` (`apps/mobile/lib/features/voice/domain/speech_input.dart:25-80`) | C36: thêm hồ sơ nghe và luồng mức âm, giữ nguyên sự kiện |
| Bộ nối `speech_to_text` | `pauseFor` 2 s, `listenFor` 60 s viết cứng, `ListenMode.dictation`, `cancelOnError`; không đọc mức âm; `initialize` không truyền tuỳ chọn (`.../voice/data/speech_to_text_input.dart:70-81, 97-118`) | C7, C8: hồ sơ "hội thoại"; C22: `androidNoBluetooth` |
| Plugin iOS | Mỗi lượt nghe: `playAndRecord` + `defaultToSpeaker, allowBluetooth, allowBluetoothA2DP, mixWithOthers`, mode `default`, kích hoạt; cuối lượt: trả category cũ và **tắt phiên** (`PLUGIN/darwin/.../SpeechToTextPlugin.swift:518-528, 453-466`). Mức âm dBFS mỗi bộ đệm 1 024 mẫu (`:593-597, 638-654`). Ghi chữ nhận dạng vào `os_log` mức debug `%{PUBLIC}` (`:699`) | C20: chủ phiên âm thanh chỉ nắm phần đọc; C21: không làm nhỏ app khác khi nghe; §20: log của plugin |
| Plugin Android | Mức `rmsdB` của bộ nhận dạng (`PLUGIN/android/.../SpeechToTextPlugin.kt:801-812`); tự báo hết lượt sau end-of-speech (`:736-751`); `pauseFor` thành `EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS` (`:693`); xin `BLUETOOTH_CONNECT` lúc khởi tạo trừ khi có `androidNoBluetooth` (`:499-511`; `PLUGIN/lib/speech_to_text.dart:142-143`) | C7 (thang mức âm khác iOS), C8, C22 |
| Plugin Dart | Sau `stop()` chờ kết quả cuối tối đa `finalTimeout` 2 s rồi tự làm kết quả cuối từ kết quả từng phần (`PLUGIN/lib/speech_to_text.dart:123, 344-353, 670-676`) | C8: bộ điều khiển tự chờ 600 ms |
| Đọc chính tả AI | `AiDictation` một lượt mỗi chạm, từ khoá "gửi"/"huỷ", F40, F41 (`.../ai/presentation/controllers/ai_dictation.dart:84-93, 151-156, 170-182`) | C9, C36: giữ cho 🎙; chế độ giọng nói là bộ điều khiển mới |
| Trang phiên | Không `resumed` thì dừng nghe (`.../ai/presentation/pages/ai_session_page.dart:95-101`); kênh không live thì dừng (`:102-105`); `_dictationMade` cho `Watch` (F43, `:82, 264`); `_send()` dừng đọc chính tả trước (`:151-153`) | C24, C25; C36 dùng lại mẫu F43 |
| Bộ điều khiển phiên | `send(text, images, files)` (`.../ai_session_controller.dart:193-233`), `stop()` (`:261-274`), `version` (`:122`), `canSend` (`:186`); trả lời bằng `answerPermission` / `answerAsk` (`:249-258`) | C3, C27; C26: cổng của chế độ giọng nói không có hai hàm trả lời |
| Gương phiên | `MirrorText(kind, turn, rev)` (`packages/shellx_ai/lib/src/remote/mirror.dart:22-47`), `MirrorTool` (`:88-129`), `MirrorTurnEnd(outcome, files)` (`:153-177`), `MirrorHead.turn/permission/ask/queue`, `running`, `canSend` (`:254-322`) | C13: chọn câu đọc theo số lượt |
| Markdown | `markdownBlocks` (quy tắc rào mã), `clipForDisplay` (`.../ai/domain/ai_text.dart:47-75, 107-121`) | C16: module lời đọc đặt cạnh, dùng lại quy tắc rào |
| Bảng xin quyền | Mỗi lựa chọn một nút ≥ 52 pt theo thứ tự agent, chờ 400 ms khi hiện hay đổi, `liveRegion`, rung khi chạm (`.../ai/presentation/widgets/ai_dock.dart:15, 48-145, 147-220`) | C26: dùng nguyên |
| Cài đặt | `AppSettings` + `KeyValueStore` an toàn; `settings_voice_locale` dùng chung terminal và 🎙 (`apps/mobile/lib/core/settings/app_settings.dart:14, 27-29, 90-93`) | C12, C31 |
| Gói âm thanh | Không có TTS, `audio_session`, wakelock trong pubspec nào. `wakelock_plus` 1.3.3 trong pub cache đòi `package_info_plus <9.0.0`; workspace đang dùng 9.0.1 (`pubspec.lock`) | C18, C20, C23 |
| Cài đặt hệ thống | `app_settings` 7.0.0 không có đích "đọc chữ thành lời"; `accessibility` chỉ Android | C19 |
| iOS | Câu micro, nhận dạng (`ios/Runner/Info.plist:42-47`, `{en,vi}.lproj/InfoPlist.strings`), `UIBackgroundModes` chỉ `remote-notification` (`:48-51`); ghim bởi `test/platform_config_test.dart:102-135` | C33 |
| Android | `RECORD_AUDIO` (`AndroidManifest.xml:8`), query `RecognitionService` (`:76-79`); không `BLUETOOTH*`, không query bộ đọc | C22, C33 |
| Định tuyến | `auto_route` 11.1.0; `AutoRouteObserver` chỉ báo trang `AutoRoutePage`, không báo bảng dưới (`auto_route_observer.dart:104-175`) | C24: dùng `TickerMode` của trang và tự tạm dừng khi mở bảng |
| Test | `FakeSpeechInput` phát sự kiện đồng bộ (`test/support/fake_speech.dart`); `fake_async` có trong dev dependencies | §16 |

---

## 3. Nhật ký quyết định

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| C1 | Phạm vi pha 1 | Chỉ app điện thoại. Nhận dạng: bộ nhận dạng của hệ điều hành qua `speech_to_text` 7.4.0 (như đọc chính tả). Đọc: giọng đọc của hệ điều hành qua `flutter_tts`. Half-duplex: micro tắt khi đang đọc. Ngắt lời bằng chạm. Không dịch vụ đám mây nào ngoài nhận dạng của Apple/Google; không giọng nói trên desktop; không chạy nền. **Không gói VAD:** Silero (`vad`, `vad_plus`) cần đường thu âm riêng, mà micro đang thuộc bộ nhận dạng của hệ điều hành trong lúc nghe; mức âm của chính bộ nhận dạng đủ cho pha 1 (§6). | Kém mượt hơn ChatGPT: có tiếng bíp Android, chưa nói chen được. Pha 2 gỡ (§21). |
| C2 | Lối vào | Nút sóng âm `ai.voice` (vai trò `ShellxIcons.voiceMode` = `CupertinoIcons.waveform`, nút vuông bo góc của A) nằm ở **chỗ B dành ngay bên phải 🎙** trong hàng chip của thẻ ô nhập (B T41); Gửi / Xếp hàng / Dừng của B giữ nguyên. **Thẻ ô nhập của trang phiên** (B T39): bật chế độ giọng nói cho phiên đó; bấm được khi kênh live **và** (`head.canSend` hoặc có lượt chạy), không thì mờ; chữ và ảnh đang soạn ở lại ô nhập (C3). **Ô nhập mở phiên** (B T38): ô có chữ thì làm đúng như Gửi của T38 (tin đầu là chữ đó); ô trống thì gửi `ai.open {agent, folder}` không kèm chữ, với dự án và agent của chip (dạng V2-2, mọi desktop hiểu); có `sid` thì đẩy trang phiên với `startVoice: true` (C31), câu nói đầu tiên là tin đầu; lỗi thì như T38 (chữ giữ, câu theo `AiWords.failure`, không tự thử lại). **🎙 của B** trên điện thoại là đọc chính tả V2-2b B14, giữ từ khoá "gửi"; C không đổi nó (B T41). Không cần cờ khả năng: chỉ dùng `ai.open`, `ai.prompt` có từ V2-2. | Hàng chip có thêm một nút trên máy hẹp (B đã dành chỗ). |
| C3 | Một hội thoại | Mỗi câu nói là một tin bình thường: `AiSessionController.send(text)`, không ảnh, không tệp. ĐT thấy bong bóng "từ điện thoại"; máy tính ghi "Bạn · từ điện thoại" (V2-2b B24). Không đổi giao thức, không đổi desktop. Chữ và ảnh đang soạn trong ô nhập không bị đụng và không bao giờ đi theo câu nói. Câu nói không gửi được (C24, C25, C26, C28, C29) được **đưa vào ô nhập**: ô trống thì đặt vào, có chữ thì xuống dòng rồi nối. | Máy tính không phân biệt tin nói với tin gõ. |
| C4 | Thanh giọng nói | Khi chế độ giọng nói bật, **thanh giọng nói** thay chỗ thẻ ô nhập của B ở đáy trang, cùng kiểu thẻ kính của A, theo luật kính của A (V2-5a A29): nằm trên bản ghi nên `blur: false`; chữ nằm thẳng trên kính chỉ từ `textPrimary` trở lên. Các bảng của dock (kế hoạch, xin quyền, câu hỏi, hàng đợi) vẫn ở trên nó. Ba hàng: (1) nhãn trạng thái một dòng, chip ngôn ngữ (một nút ghi "VI"/"EN", chạm để đổi), nút toàn màn hình; (2) phụ đề tự xuống dòng (tối đa 2 dòng, giữ phần cuối), lý do dài (tạm dừng, lỗi, tối đa 3 dòng) hoặc các nút chữ trong một `Wrap`; (3) hàng điều khiển cố định, chỉ có biểu tượng: Tắt mic · sóng âm (chạm được, co giãn) · ô Dừng · Kết thúc (§4.2). Ô Dừng luôn giữ chỗ để không nút nào xê dịch. Phông đơn cách SF Mono rộng hơn phông thường: không chữ nào có chiều rộng cố định; nhãn một dòng thì cắt bằng "…" và nhãn trợ năng có đủ chữ. Vào chế độ thì bàn phím đóng. | Thanh cao thêm một dòng khi lý do dài hay chữ lớn. |
| C5 | Màn toàn màn hình | Nút toàn màn hình (`voiceExpand`) mở một **lớp phủ trong trang phiên** (không phải route) với quả cầu lớn, phụ đề hai bên, Tắt mic góc trái dưới, Kết thúc góc phải dưới (như bố cục cũ của ChatGPT). Dùng chung một bộ điều khiển với thanh. Nút thu về (`voiceCollapse`) hoặc nút Back của Android thu về thanh, chế độ giọng nói vẫn chạy. Kính và mảng xanh chéo của A được dùng ở đây (A cho phép ở màn giọng nói): lớp phủ có nền trang đặc che bản ghi, nên thẻ kính trên nó được làm mờ (phía sau tĩnh, V2-5a A29). Không nhớ lựa chọn: lần nào cũng bắt đầu ở thanh. | Ai thích toàn màn hình phải chạm nút đó mỗi lần. |
| C6 | Mười trạng thái | `idle`, `listening`, `hearing`, `sending`, `working`, `speaking`, `paused`, `needsYou`, `error`, `ended` (§4.4, §5). Mỗi trạng thái có hình riêng, nhãn EN/VI riêng, nghĩa riêng của cú chạm. Chữ của `idle` chỉ hiện khi `idle` kéo dài quá 400 ms, để không nháy giữa hai pha. | — |
| C7 | Hết câu | Gửi khi im **700 ms** sau từ cuối; **1 600 ms** nếu từ cuối là từ ngập ngừng hay từ nối ("ừm", "thì", "và"…). "Im" = chữ không đổi **và** mức âm dưới ngưỡng tiếng nói. Ồn mãi: chỉ dựa vào chữ, sau 1 500 ms (2 400 ms). Máy không báo mức âm: chỉ dựa vào chữ, sau 1 000 ms (1 900 ms). Cần ít nhất một từ; câu chỉ toàn từ ngập ngừng thì không gửi. Ngưỡng và cách chống báo nhầm: §6. | Ngừng giữa câu quá 0,7 s thì nửa câu đi trước; nói tiếp thành tin sau. |
| C8 | Nghe liên tục | Một câu nói có thể trải qua nhiều lượt nghe của hệ điều hành; chữ được cộng dồn. **iOS:** mỗi lượt tối đa 55 s (`listenFor`); sau 45 s thì bắt đầu lại ở chỗ ngừng ≥ 250 ms đầu tiên. **Android:** lượt tự kết thúc (im 1–3 s, giới hạn ngắn) thì bắt đầu lại ngay khi có `done` (chờ tối đa 500 ms); `error_busy` / `error_client` thì thử lại sau 500 ms, tối đa 3 lần trong 10 s, quá thì `error`. Lượt mới chỉ bắt đầu sau `done` của lượt cũ (hoặc 500 ms), để sự kiện muộn của lượt cũ không lẫn vào. Sau `stop()` chờ kết quả cuối tối đa 600 ms, không có thì dùng kết quả từng phần cuối. Android: lượt đầu xin nhận dạng trên máy; lỗi trước từ đầu tiên (`localeUnavailable`, `other`) thì chuyển nhận dạng đám mây của hệ điều hành và giữ cách đó suốt lần bật (như V4 của spec 06/10, V2-2b B14). | Vài từ nói đúng lúc bắt đầu lại có thể mất; Android kêu bíp mỗi lần. |
| C9 | Từ khoá | Không cần "gửi"/"send". Câu cuối vẫn qua `VoiceCommandParser`: "gửi"/"send" ở cuối bị bỏ khỏi chữ rồi gửi; "huỷ"/"hủy"/"cancel" ở cuối thì bỏ cả câu và đọc "Đã huỷ.". 🎙 và terminal giữ từ khoá bắt buộc. | Câu kết thúc bằng "huỷ" nói cho agent ("…lỗi thì huỷ") bị bỏ; phải nói kiểu khác. |
| C10 | Chạm sóng âm / quả cầu | `speaking`: dừng đọc ngay, phần còn lại không đọc (vẫn có trong hội thoại), nghe luôn (ngắt lời). `hearing`: gửi ngay. `listening`: không làm gì. `working`: nghe một tin **xếp hàng**. `paused`: nghe tiếp (đang tắt mic thì bật mic lại). `error`: thử lại. `idle`, `sending`, `needsYou`: không làm gì. | — |
| C11 | Tắt mic | Là cờ, không phải trạng thái. Đang tắt mic thì micro không tự mở; câu trả lời vẫn được đọc; chỗ đáng lẽ nghe thành `paused` lý do "đã tắt mic". Tắt khi đang nói dở thì bỏ câu đó (người dùng chủ ý). Bật lại thì nghe ngay nếu không có lượt chạy. Không lưu sang lần bật sau. | — |
| C12 | Ngôn ngữ | Một cài đặt cho cả ba nơi (terminal, 🎙, chế độ giọng nói): khoá có sẵn `settings_voice_locale`, mặc định theo ngôn ngữ app. Chip ngôn ngữ trong thanh (VI│EN ở toàn màn hình) ghi vào cài đặt này, như nút VI│EN của terminal hôm nay. Đổi khi đang nghe: huỷ lượt, bỏ câu đang nói dở (sai ngôn ngữ), nghe lại bằng ngôn ngữ mới. Đổi khi đang đọc: chỉ áp cho lượt nghe sau. | Đổi tạm trong chế độ giọng nói cũng đổi mặc định; đổi lại mất một chạm. |
| C13 | Đọc gì | Mỗi lượt **kết thúc sau khi chế độ giọng nói bật** được đọc đúng một lần, xác định theo số lượt (§7.1). Đọc các mục chữ của agent thuộc lượt đó **đứng sau thẻ tool cuối cùng** của lượt; không có thì mục chữ cuối của agent trong lượt. Không bao giờ đọc suy nghĩ, thẻ tool, đầu ra, diff, câu hỏi, thông báo, tin của người dùng. Lượt có đổi tệp thì đọc trước "Đã đổi N tệp.". Lượt bị dừng: "Đã dừng."; lượt lỗi hay bị ngắt: "Lượt này chưa xong. Xem trên màn hình.". | Lời giải thích giữa lượt (trước một tool) không được đọc; xem trên màn hình. |
| C14 | Khi nào đọc | **Sau khi lượt kết thúc**, không đọc theo dòng chảy. Đọc từng đoạn (≤ 240 ký tự, mỗi đoạn một lần `speak`, chờ xong mới tới đoạn sau) để phụ đề khớp và chạm dừng được ngay. Chữ của lượt còn thiếu mảnh (`rev = -1`) thì chờ tối đa 2 s rồi đọc phần đã có. **Gợi ý "đang làm":** rung nhẹ khi máy tính nhận tin; lượt đã chạy 2,5 s mà vẫn ở `working` (micro đóng) thì đọc một lần "Đang làm." (một lần mỗi lượt; vào chế độ khi lượt đã chạy lâu thì đọc ngay). Đọc xong thì chờ 300 ms rồi mới mở micro. | Câu trả lời thuần chữ được nghe chậm hơn đọc theo dòng chảy vài giây. |
| C15 | Câu trả lời dài | Chia phần ≤ 600 ký tự lời đọc (không cắt giữa một đoạn đọc). Đọc phần 1; còn nữa thì đọc "Còn nữa. Đọc tiếp không?" rồi mở micro. Câu nói ngay sau đó được so **nguyên câu**: câu "tiếp" (§13.3) thì đọc phần sau (còn nữa thì hỏi lại); câu "thôi" thì thôi đọc và nghe; câu khác thì gửi cho agent như tin thường, phần còn lại không đọc. Chip "Đọc tiếp" làm như câu "tiếp" bằng chạm. Lượt khác kết thúc trong lúc đang hỏi thì bỏ câu hỏi và đọc lượt mới. | Muốn nghe hết phải trả lời mỗi ~600 ký tự (~45 s). |
| C16 | Lời đọc từ markdown | Module Dart thuần (§7.3): bỏ khối mã (cả diff), bảng, ảnh, thẻ HTML; thay mỗi cụm bị bỏ liền nhau bằng một câu ngắn ở đúng chỗ ("Kèm 2 khối mã."); chỉ có thứ bị bỏ thì "Câu trả lời là 2 khối mã, xem trên màn hình.". Link đọc chữ của link; URL trần đọc "một đường link"; mã trong câu ≤ 32 ký tự đọc nguyên, đường dẫn đọc tên tệp, dài hơn đọc "một đoạn mã"; bỏ dấu markdown, emoji. Ví dụ "kèm 2 khối code" của đề xuất thành "Kèm 2 khối mã" vì giọng tiếng Việt đọc chữ Việt chắc hơn chữ "code". | Đổi chữ đọc là sửa một bảng câu (§13.2). |
| C17 | Trộn Việt–Anh | Ngôn ngữ của từng đoạn đọc: có chữ cái riêng của tiếng Việt → tiếng Việt; không có mà có ≥ 3 từ chữ Latinh → tiếng Anh; còn lại theo đoạn trước (đoạn đầu theo chế độ). Mỗi đoạn đọc bằng giọng của ngôn ngữ đó; từ tiếng Anh lẻ trong câu Việt do giọng Việt đọc. Lời của ShellX (gợi ý, thông báo, "Đã đổi N tệp.") theo ngôn ngữ của chế độ; câu chèn ("Kèm 2 khối mã.") theo đoạn đứng trước nó. | Định danh tiếng Anh trong câu Việt đọc lơ lớ. |
| C18 | Bộ đọc | `flutter_tts` (MIT), ghim đúng một bản như các gói khác: bản mới nhất resolve được trên Flutter 3.41.4 / Dart 3.11 (mốc nghiên cứu ngày 16/10: 4.2.5). Chỉ dùng **giọng trên máy**: iOS mọi giọng `AVSpeechSynthesisVoice`; Android chỉ giọng có `network_required` = `"0"` trong `getVoices()`, luôn `setVoice` rõ ràng (không bao giờ chỉ `setLanguage`). Giọng mặc định: iOS chất lượng cao nhất đã cài (premium > enhanced > thường); Android giọng mặc định của bộ đọc nếu không cần mạng, không thì giọng đầu tiên không cần mạng. Tốc độ: Chậm 0,85× / Vừa 1× / Nhanh 1,2× tốc độ thường (`setSpeechRate(0.5 × hệ số)` trong flutter_tts). `awaitSpeakCompletion(true)`; iOS `autoStopSharedSession(false)` (chủ phiên âm thanh tự tắt phiên, C20). Khởi động bộ đọc và lấy danh sách giọng ngay khi vào chế độ. Kế hoạch đọc mã nguồn bản ghim để xác nhận: `network_required`, `autoStopSharedSession`, hệ số tốc độ Android, mọi lệnh `AVAudioSession` mà plugin tự gọi. | Giọng chất lượng thấp hơn giọng đám mây; người dùng tự tải giọng tốt hơn trong Cài đặt máy. |
| C19 | Thiếu giọng | Máy không có giọng tiếng Việt: đoạn tiếng Việt không đọc (vẫn có trong hội thoại); thanh hiện "Máy chưa có giọng đọc tiếng Việt. Câu trả lời tiếng Việt chỉ hiện chữ." kèm "Cách thêm giọng đọc" (bảng hướng dẫn theo nền tảng; Android có nút "Mở cài đặt Trợ năng" qua `app_settings` `accessibility`; iOS không có đường dẫn sâu nên chỉ có chữ). Lời của ShellX đọc bằng tiếng Anh nếu có giọng Anh. **Không bao giờ đọc chữ Việt bằng giọng Anh.** Không có giọng nào: chỉ rung và chữ. Tương tự cho tiếng Anh. Luồng vẫn đi như đã đọc xong. | Người chưa cài giọng chỉ có phụ đề. |
| C20 | Chủ phiên âm thanh | Một chủ duy nhất `VoiceAudio` (gói `audio_session`, MIT, ghim đúng bản resolve được) quản phần **đọc**; trong lúc nghe, plugin nhận dạng tự đặt và tự trả phiên như hôm nay. Luật: **O1** không bao giờ nghe và đọc cùng lúc; **O2** trước mỗi lần đọc (câu trả lời, gợi ý, thông báo, câu hỏi "đọc tiếp"): cấu hình lại rồi kích hoạt; xong thì tắt; chỉ sau đó mới mở micro; **O3** iOS: `playAndRecord` + `defaultToSpeaker, allowBluetooth, allowBluetoothA2DP, duckOthers`, mode `default` — cùng loại với plugin để đường âm (loa, tai nghe) không đổi giữa nghe và đọc; **O4** Android: xin audio focus `gainTransientMayDuck`, `usage: assistant`, `contentType: speech` khi đọc, trả khi xong; **O5** không chỉnh gì của plugin nhận dạng. | Thêm một gói ghim. Nếu flutter_tts tự đặt category iOS thì O2 đè lại trước mỗi lần đọc. |
| C21 | App khác và bị ngắt | **Khi ShellX đọc:** âm thanh app khác nhỏ đi (iOS `duckOthers`, Android `mayDuck`) và trở lại khi đọc xong. **Khi nghe:** ShellX không tắt, không làm nhỏ nhạc (iOS: plugin trộn âm; Android: tuỳ bộ nhận dạng, nhiều máy tự dừng nhạc). **Bị ngắt** (cuộc gọi, Siri, báo thức; iOS `AVAudioSession` interruption, Android mất focus, lỗi nhận dạng `interrupted`) → `paused` "Điện thoại đã tạm dừng âm thanh — chạm để tiếp tục", không tự tiếp tục; ngắt loại "duck" (Android, ví dụ âm báo) thì bỏ qua. **Rút tai nghe khi đang đọc** (becoming noisy) → dừng đọc, `paused` "Tai nghe đã ngắt — chạm để tiếp tục" (không đọc tiếp ra loa ngoài khi người dùng không chọn); rút khi đang nghe thì không làm gì (micro chuyển sang micro của máy). | Nhạc mở lớn làm nhận dạng kém; người dùng tự dừng nhạc. |
| C22 | Bluetooth | **Không khai `BLUETOOTH_CONNECT`** (tránh hộp xin quyền "thiết bị ở gần" và cảnh tai nghe nhảy A2DP/HFP mỗi lượt). Android: `initialize(options: [androidNoBluetooth])` cho mọi nơi dùng nhận dạng: micro là micro của điện thoại, tiếng đọc ra tai nghe. iOS: giữ `allowBluetooth` của plugin (micro AirPods qua HFP), đọc cùng đường; đầu ra là Bluetooth HFP thì chờ 250 ms sau khi kích hoạt rồi mới đọc (khỏi mất chữ đầu). | Android: máy để trong túi thì micro nghe kém. |
| C23 | Màn hình sáng | Giữ màn hình sáng khi chế độ giọng nói đang bật, trừ `paused` (lý do im lặng, bị ngắt, tai nghe, quá dài, bị che, mất kênh quá 30 s, không gửi được), `error`, `ended`. Không nghe, không đọc quá 10 phút liền (lượt rất dài, chờ chạm cho phép) thì thả: máy có thể tự khoá, chế độ tắt, và thông báo đẩy "Xong lượt" / "Cần bạn trả lời" của V2-2 D11 thay chỗ. Cách làm: kênh app `shellx/voice`, iOS `UIApplication.isIdleTimerDisabled`, Android `FLAG_KEEP_SCREEN_ON`; không thêm quyền. Không dùng `wakelock_plus`: bản trong máy đòi `package_info_plus <9.0.0`. | Thêm hai hàm native nhỏ phải giữ. |
| C24 | Vòng đời | `inactive` (màn thông báo, Trung tâm điều khiển, hộp thoại hệ thống) → `paused` lý do "bị che"; `resumed` thì tự tiếp tục. Ở `idle` lúc chờ hộp xin quyền micro/nhận dạng lần đầu thì **không** tạm dừng; xong và app `resumed` thì nghe luôn (không phải chạm lần hai như V2-2b F40). Ra nền (`hidden`, `paused`, `detached`) → `ended`. Trang bị che — trang khác đè lên, biết qua `TickerMode` của trang (trang phiên nằm trên thanh dưới của B, B T34, nên không đổi tab được khi nó hiện) — hoặc trang tự mở bảng, hộp thoại, menu → `paused` "bị che"; hết che thì tiếp tục; che quá 2 phút → `ended`. Đang nói dở mà bị tạm dừng (trừ tắt mic, đổi ngôn ngữ) thì câu đó vào ô nhập. Trang đóng, phiên đóng trên máy tính (`gone`, `desktop_closed`), phiên không chạy được (`unavailable`), trang theo phiên sang sid khác (V2-2b B22) → `ended`. | Quay lại app phải chạm sóng âm lần nữa. |
| C25 | Mất kênh | Kênh không live: đang nghe thì huỷ, câu đang nói vào ô nhập; `paused` "Đang kết nối lại…"; live lại trong 30 s thì tự tiếp tục; quá 30 s thì "Mất kết nối — chạm để thử lại" và thả màn hình sáng. Đang `working` hay `speaking` thì giữ nguyên; lượt kết thúc trong lúc mất kênh vẫn được đọc khi gương có lại `MirrorTurnEnd` (theo số lượt, §7.1). | — |
| C26 | Xin quyền và câu hỏi | Có yêu cầu xin quyền hay câu hỏi chờ → `needsYou`: micro đóng và **không mở lại được bằng bất kỳ đường nào** khi còn yêu cầu; đọc xong đoạn đang đọc rồi đọc "Claude cần bạn cho phép: <việc>. Hãy chạm để trả lời trên màn hình."; bảng xin quyền của trang hiện như thường (mỗi lựa chọn một nút ≥ 52 pt theo thứ tự agent, chờ 400 ms, rung khi chạm — không thêm, không bớt lựa chọn); thanh ghi "Chạm một nút ở trên — không trả lời bằng giọng nói được.". Câu hỏi: đọc câu hỏi, trả lời bằng chạm hay gõ trong bảng câu hỏi. Ba lớp chặn (§10): cổng của chế độ giọng nói không có hàm trả lời; micro đóng; câu nói đã hết câu mà chưa gửi khi yêu cầu tới thì vào ô nhập, không gửi. | Rảnh tay vẫn phải tới chạm điện thoại cho mỗi yêu cầu (đúng ý V2-2 D13). |
| C27 | Hàng đợi, dừng lượt | `working` mà chạm sóng âm: nghe một tin, gửi thành tin xếp hàng (như gõ khi đang chạy); hàng đợi đủ 5 tin thì không nghe, phụ đề "Hàng đợi đã đủ 5 tin."; im hết ngân sách thì về `working`. Nút Dừng (`voiceStopTurn`) ở ô Dừng khi có lượt chạy (chờ 400 ms khi vừa hiện, như nút Dừng của ô nhập), gọi `stop()`; lượt kết thúc `cancelled` → "Đã dừng." → nghe. Không dừng lượt bằng lời. | — |
| C28 | Gửi lỗi | Không bao giờ tự gửi lại (V2-2 D13 với tin). Câu nói vào ô nhập; `error` với câu của `AiWords.failure`; mã `outcome_unknown` thì đọc thêm "Có thể chưa gửi được. Xem trên màn hình.". Nút "Tiếp tục" nghe lại. | — |
| C29 | Im lặng, câu quá dài | Đang nghe mà không có từ nào và không có tiếng nói: iOS 30 s, Android 15 s (mỗi lần bắt đầu lại là một tiếng bíp) → `paused` "Một lúc không nghe thấy gì — chạm để nói.". Một câu nói quá 120 s → vào ô nhập, `paused` "Câu nói dài quá — đã để trong ô nhập để bạn xem lại.". | Người nghĩ lâu phải chạm lại. |
| C30 | Trợ năng | Báo trạng thái cho trình đọc màn hình (§4.7). Trình đọc màn hình bật (`MediaQuery.accessibleNavigation`): **chạm để nói** — không tự mở micro sau khi đọc hay khi vào (tiếng của trình đọc màn hình sẽ bị nghe thành chữ); chạm hai lần vào sóng âm hay quả cầu để nói; ShellX không đọc lời báo xin quyền (bảng đã `liveRegion`). Giảm chuyển động (`MediaQuery.disableAnimations`): không có hoạt hình liên tục; mức âm hiện bằng 3 bậc, đổi tối đa 4 lần/giây. Mọi nút ≥ 44 pt, có nhãn Semantics. | Người dùng trình đọc màn hình không rảnh tay hoàn toàn. |
| C31 | Cài đặt | Nhóm "Giọng nói" trong Cài đặt (§12): Ngôn ngữ (khoá có sẵn), Đọc to câu trả lời (bật), Giọng đọc tiếng Việt, Giọng đọc tiếng Anh (mặc định của máy), Tốc độ đọc (Vừa), Nghe thử, Mở phiên AI mới bằng giọng nói (tắt). **Phiên mới bằng giọng nói:** `AiSessionRoute` thêm `startVoice` (mặc định false); trang có header và kênh live lần đầu (chờ tối đa 10 s, không được thì thôi, ô nhập như thường) thì bật chế độ giọng nói. Ô nhập mở phiên của B (T38) truyền `startVoice: true` khi mở phiên bằng nút sóng âm (C2), và khi mở bằng Gửi mà cài đặt này bật. Tắt "Đọc to câu trả lời" thì chế độ giọng nói không đọc gì (kể cả gợi ý, thông báo); chỉ rung và chữ; lượt xong thì nghe lại ngay. | Phụ thuộc ô nhập mở phiên của B truyền một tham số. |
| C32 | Lời ShellX đọc | Không qua ARB: `VoicePhrases` (Dart thuần, vi + en, §13.2), vì lời đọc theo ngôn ngữ của chế độ giọng nói chứ không theo ngôn ngữ app (`S` của intl_utils chỉ có một ngôn ngữ hiện hành, nạp ngôn ngữ khác là đổi toàn cục). Chữ trên màn hình vẫn qua ARB (§13.1). | Người dịch sửa hai chỗ. |
| C33 | Quyền hệ điều hành | iOS: sửa `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` (en, vi) cho nói thêm chế độ giọng nói (§13.4); **không** thêm `audio` vào `UIBackgroundModes`. Android: thêm `<queries><intent><action android:name="android.intent.action.TTS_SERVICE"/></intent></queries>` (Android 11+ mới thấy bộ đọc); không thêm quyền nào (`RECORD_AUDIO` có sẵn; không `BLUETOOTH_CONNECT`, `FOREGROUND_SERVICE*`, `WAKE_LOCK`). | — |
| C34 | Riêng tư, log | Âm thanh không đi qua ShellX; chỉ chữ đã nhận dạng đi như tin gõ, mã hoá đầu cuối. Không lưu âm thanh. Không log nội dung: lời nói, phụ đề, câu đọc, tiêu đề yêu cầu, câu hỏi; chỉ log loại lỗi. `toString()` của mọi kiểu mới mang chữ trả `Tên(…)`, có test. Trang Quyền riêng tư là việc sau, cần đồng ý triển khai (§14). | — |
| C35 | Lời không phải lệnh | Lời chỉ được ShellX hiểu ở hai chỗ: "gửi"/"huỷ" ở cuối câu (C9) và câu trả lời ngay sau "Đọc tiếp không?" (C15). Mọi câu khác là tin cho agent. Không trả lời xin quyền, không dừng lượt, không đổi ngôn ngữ, không tắt mic, không kết thúc bằng lời. | Rảnh tay ít hơn ChatGPT (không có "đợi đã", "đổi sang tiếng Anh"). |
| C36 | Mã nguồn, thứ tự | Bộ điều khiển mới `AiVoiceMode` (không mở rộng `AiDictation`: một bên là hội thoại, một bên là đọc chính tả; V2-2b F42 đã chấp nhận hai bản máy đọc chính tả). Phần thuần Dart (hết câu, lời đọc, chọn câu đọc) tách riêng, test bằng bảng. Trang giữ bộ điều khiển theo mẫu `_dictationMade` (V2-2b F43). Thứ tự: (1) module thuần; (2) `SpeechInput` thêm hồ sơ và mức âm, `SpeechOutput`, `VoiceAudio`, kênh `shellx/voice`; (3) `AiVoiceMode` với fake; (4) cài đặt, chuỗi, tệp nền tảng — (1)–(4) không đụng phần B thiết kế, chạy song song B được (B cũng thêm khoá vào ARB, `app_settings.dart` và trang Cài đặt điện thoại: hai bên chỉ thêm phần của mình, chỉ có xung đột gộp chữ); (5) thanh, lớp phủ toàn màn hình, nối vào trang và thẻ ô nhập sau khi B gộp; (6) kiểm tay. | Ba nơi dùng `SpeechInput` (terminal, 🎙, chế độ giọng nói). |
| C37 | Log của plugin nhận giọng | Vá plugin iOS `speech_to_text`: bỏ dòng ghi chữ nhận dạng vào `os_log` (`SpeechToTextPlugin.swift:699`, mức debug `%{PUBLIC}`). Plugin được vendor ở `third_party/speech_to_text` (như `third_party/xterm`), đúng bản đang ghim, chỉ đổi dòng log đó; `pubspec.yaml` của app trỏ `path:` tới bản vendor. Một test đọc mã nguồn bản vendor và hỏng nếu còn `os_log` mang chữ nhận dạng. Lý do: luật bắt buộc "không log nội dung"; chế độ giọng nói nghe liên tục nên lượng lời nói lọt vào log lớn hơn nhiều so với đọc chính tả. (Người điều phối thêm sau review chéo, 16/10.) | Một thư mục vendor phải cập nhật tay khi nâng plugin; pha 2 thay bộ máy thì bỏ được. |

---

## 4. Trải nghiệm

### 4.1 Lối vào

- Nút sóng âm `ai.voice` ở chỗ B dành bên phải 🎙 (B T41), trong thẻ ô nhập của trang phiên (B T39) và trong ô nhập mở phiên (B T38) (C2). Tooltip và nhãn trợ năng: "Nói chuyện với Claude".
- Chạm khi 🎙 đang đọc chính tả: dừng đọc chính tả trước (chữ đã nghe ở lại trong ô), rồi bật chế độ giọng nói.
- Lần đầu dùng micro trên máy: hộp xin quyền của hệ điều hành (iOS: nhận dạng giọng nói rồi micro). Cho phép xong là nghe luôn (C24).
- Từ ô nhập mở phiên: chạm nút sóng âm là mở phiên mới và vào chế độ giọng nói ngay (C2). Cài đặt "Mở phiên AI mới bằng giọng nói" bật: phiên mới mở bằng Gửi cũng vào chế độ giọng nói (C31).

### 4.2 Thanh giọng nói (thay thẻ ô nhập của B khi bật)

Đang nghe, đã nghe được chữ (`hearing`); phần trên thanh là trang phiên với dock như hôm nay:

```
+--------------------------------------------------+
| <  Sửa lỗi đăng xuất                       [...] |
|    o Claude · Đang chờ · shop-web · main         |
+--------------------------------------------------+
|                                    từ điện thoại |
|                   +----------------------------+ |
|                   | Sửa nút đăng xuất giúp tôi | |
|                   +----------------------------+ |
|  Đã sửa logout() trong auth.ts, test đều qua.    |
|  [ khối mã · 12 dòng ]                           |
|  Lượt 3 · 0:41 · 2 tệp đổi +44 −5                |
+--------------------------------------------------+
| Kế hoạch · 2/5                                 ^ |
+==================================================+
| Đang nghe…                          [VI]   [ ⤢ ] |
| …chạy lại test e2e rồi báo tôi kết quả, nhớ      |
| chạy cả test của trang đăng nhập                 |
|                                                  |
| [mic]     ▁▂▅▇█▇▅▂▁▂▅▂▁▂▅▇▅▂▁     [   ]    [ X ] |
+==================================================+
```

- Hàng 1: nhãn trạng thái (một dòng, cắt bằng "…") · chip ngôn ngữ (một nút 44 pt ghi ngôn ngữ đang nghe "VI"/"EN", chạm để đổi; toàn màn hình và Cài đặt dùng VI│EN hai phần) · toàn màn hình.
- Hàng 2: phụ đề tự xuống dòng, tối đa 2 dòng, giữ phần cuối ("…" ở đầu). Lúc `listening` chưa có chữ, hàng 2 là gợi ý `voiceModeHearingHint`.
- Hàng 3: tắt mic · sóng âm (co giãn, chạm được) · ô Dừng (giữ chỗ, trống khi không có lượt chạy) · Kết thúc. Nút chỉ có biểu tượng (tooltip và nhãn trợ năng), không có chữ dưới nút.
- Biểu tượng theo vai trò (§4.8): `[mic]` `voiceMicOn` / `voiceMicOff`, `[ ⤢ ]` `voiceExpand`, `[ ■ ]` `voiceStopTurn`, `[ X ]` `voiceEnd`, `(!)` `voiceNeedsYou`.

Agent đang làm (`working`):

```
+==================================================+
| Claude đang làm… · 0:18             [VI]   [ ⤢ ] |
| Chạy npm test                                    |
|                                                  |
| [mic]     ·  ·  ~~~~~~~  ·  ·     [ ■ ]    [ X ] |
+==================================================+
```

Cần cho phép (`needsYou`); bảng xin quyền của trang nằm ngay trên thanh:

```
| +----------------------------------------------+ |
| | Claude xin quyền:                            | |
| | Sửa src/main.ts                              | |
| | [               Cho phép                 ]   | |
| | [             Luôn cho phép              ]   | |
| | [               Từ chối                  ]   | |
| +----------------------------------------------+ |
+==================================================+
| (!) Claude cần bạn cho phép         [VI]   [ ⤢ ] |
| Chạm một nút ở trên — không trả lời bằng giọng   |
| nói được.                                        |
|                                                  |
| [mic]     ───────────────────     [ ■ ]    [ X ] |
+==================================================+
```

- Hàng 2 thay phụ đề bằng lý do dài (tạm dừng, lỗi; tự xuống dòng, tối đa 3 dòng) và các nút chữ khi cần: "Đọc tiếp" (C15), "Mở Cài đặt", "Thử lại", "Chuyển sang EN/VI", "Tiếp tục" (§4.4), "Cách thêm giọng đọc" (C19). Các nút chữ nằm trong một `Wrap`: thiếu chỗ thì xuống hàng, không tràn.
- **Bề rộng, với phông đơn cách SF Mono của A:** ở 320 pt (lề 16 pt mỗi bên), hàng 3 = 44 + sóng âm co giãn + 44 + 44 pt (chỉ biểu tượng, không phụ thuộc phông); hàng 1 = nhãn co giãn (`Expanded`, một dòng, "…") + chip ngôn ngữ 44 pt + 44 pt, nên nhãn còn ~200 pt (khoảng 25 ký tự đơn cách ở cỡ chữ thân của A). Không chữ nào có chiều rộng cố định; không cuộn ngang, kể cả khi cỡ chữ hệ thống 1,3×.

### 4.3 Màn toàn màn hình (lớp phủ, C5)

```
+--------------------------------------------------+
| [ ⌄ ]  Sửa lỗi đăng xuất · Claude                |
|                                        //////    |
|                                     //////       |
|                                                  |
|                   .-''''''''-.                   |
|                .'   ______   '.                  |
|               /   .'      '.   \                 |
|              |   |  QUẢ CẦU |   |                |
|               \   '.______.'   /                 |
|                '.            .'                  |
|                   '-......-'                     |
|                                                  |
|              Đang đọc câu trả lời…               |
|  Bạn                                             |
|  giờ chạy lại test e2e rồi báo tôi kết quả       |
|  Claude                                          |
|  Đã chạy 42 test, tất cả đều qua.                |
|                                                  |
|   [mic]       [ VI | EN ]       [ ■ ]     [ X ]  |
|  Tắt mic       Ngôn ngữ         Dừng    Kết thúc |
+--------------------------------------------------+
```

- Góc trên phải là mảng xanh chéo của A; quả cầu dùng gradient nhấn của A, vòng ngoài chạy theo mức âm. `[ ⌄ ]` là vai trò `voiceCollapse` (§4.8).
- Phụ đề hai bên: tên người nói ("Bạn", tên agent) ở dòng riêng, chữ phụ của A; lời ở dòng dưới, tự xuống dòng, tối đa 4 dòng mỗi bên, giữ phần cuối. Không có cột tên rộng cố định (phông đơn cách sẽ phí chỗ).
- Chữ dưới nút (chỉ ở màn này) được xuống tối đa 2 dòng khi chữ lớn.
- Chạm quả cầu = chạm sóng âm (C10). Bảng xin quyền, câu hỏi hiện trên một thẻ kính của A ở nửa dưới, quả cầu thu nhỏ lên trên; dock của trang nằm dưới lớp phủ nên không có hai bảng.
- Nút Back của Android: thu về thanh. Kết thúc ở đây = Kết thúc ở thanh.

### 4.4 Trạng thái: hình, chữ, chạm

Màu theo token của A: gradient nhấn, `warn`, `error`, chữ phụ. Chữ EN/VI ở §13.1.

| Trạng thái | Khi nào | Sóng âm (thanh) | Quả cầu (toàn màn hình) | Nhãn (khoá) | Chạm |
|---|---|---|---|---|---|
| `idle` | vào chế độ (quyền, ngôn ngữ, bộ đọc); khoảng gác giữa đọc và nghe | thanh thấp, mờ 60 % | đứng yên, mờ | `voiceModePreparing` (chỉ khi > 400 ms) | không |
| `listening` | micro mở, chưa có từ | thở chậm (chu kỳ 2 s), theo mức âm nhẹ | thở chậm | `voiceModeListening`; hàng 2: `voiceModeHearingHint` (tin xếp hàng: `voiceModeListeningQueue`) | không |
| `hearing` | có ít nhất một từ | theo mức micro (lên 80 ms, xuống 200 ms) | phình 1,0–1,15 theo mức | `voiceModeListening`; hàng 2: phụ đề | gửi ngay |
| `sending` | đã hết câu, đang chốt chữ và gửi | gom về một chấm đi lên | co 0,9, sáng lên một lần | `voiceModeSending`; tin xếp hàng: `voiceModeQueued` | không |
| `working` | agent đang làm, micro đóng | sóng quét trái → phải (1,6 s) | gradient xoay (8 s một vòng) | `voiceModeWorking` + đồng hồ lượt; phụ đề: thẻ tool mới nhất | nghe tin xếp hàng |
| `speaking` | đang đọc | nhịp tổng hợp ~4 Hz, biên độ 0,4–0,9 (nền tảng không cho mức âm của giọng đọc) | đập theo nhịp đó | `voiceModeSpeaking`; câu hỏi đọc tiếp: `voiceModeMore` | dừng đọc, nghe |
| `paused` | tắt mic, im lặng, bị che, bị ngắt, tai nghe, mất kênh, quá dài, không gửi được, chạm để nói | phẳng, màu chữ phụ; tắt mic thì có dấu `voiceMicOff` | xám, đứng yên; tắt mic thì có dấu `voiceMicOff` | hàng 1 (ngắn): `voiceModeMuted` (tắt mic), `voiceModeReconnecting` (chờ kênh ≤ 30 s), `voiceModeTapToTalk` (trình đọc màn hình), còn lại `voiceModePausedAway`; hàng 2 (lý do, xuống dòng): `voiceModePausedSilence`, `voiceModePausedInterrupted`, `voiceModePausedRoute`, `voiceModeLinkLost`, `voiceModeTooLong`, `voiceModeQueueFull` hay `AiWords.state`, thêm `voiceModeDraftKept` khi câu dở vừa vào ô nhập | nghe tiếp (đang tắt mic thì bật lại) |
| `needsYou` | có yêu cầu xin quyền hay câu hỏi chờ | phẳng, màu `warn` | màu `warn`, đứng yên | dấu `voiceNeedsYou` + `voiceModeNeedsPermission`; hàng 2: `voiceModeTapOnly`; câu hỏi: `aiAskTitle`, hàng 2: `voiceModeAnswerOnScreen` | không |
| `error` | không nghe, không gửi được nữa | phẳng, màu `error` | màu `error` | hàng 1: `voiceModeCantListen` (lỗi nhận dạng) hay `voiceModeSendFailedTitle` (gửi lỗi); hàng 2: câu lỗi (§15) + nút | thử lại |
| `ended` | đã tắt | thanh trượt xuống 200 ms, thẻ ô nhập trở lại | lớp phủ đóng | thông báo nổi khi hệ thống tắt (§15) | — |

Chỉ có hoạt hình liên tục ở `listening`, `hearing`, `working`, `speaking`; các trạng thái khác đứng yên (đỡ pin khi màn hình luôn sáng).

### 4.5 Phụ đề

- Thanh, hàng 2: `hearing` hiện câu đang nói (các đoạn đã chốt + kết quả từng phần), quá 2 dòng thì giữ phần cuối với "…" ở đầu; `sending` hiện câu đã chốt, mờ; `working` hiện tên thẻ tool mới nhất của lượt (`AiWords.toolTitle`); `speaking` hiện đoạn đang đọc; `needsYou` hiện tiêu đề việc hay câu hỏi.
- Toàn màn hình: mỗi bên một khối: tên người nói ("Bạn", tên agent) ở dòng riêng, lời ở dưới, tự xuống dòng, tối đa 4 dòng, giữ phần cuối.
- Phông là SF Mono của A (đơn cách): phụ đề luôn tự xuống dòng theo bề rộng thật, không cắt giữa từ trừ khi một từ dài hơn cả dòng (đường dẫn, URL), không có chiều rộng cố định; chiều cao dòng theo token của A để dấu tiếng Việt chồng (ặ, ẫ, ở) không bị cắt.
- Không tô từng từ đang đọc (việc sau). Đoạn không đọc được vì thiếu giọng (C19) không hiện ở phụ đề; hội thoại vẫn có đủ.
- Phụ đề không phải `liveRegion` (trình đọc màn hình không đọc lại lời của người dùng hay của agent).

### 4.6 Điều khiển

| Nút | Ở đâu | Làm gì |
|---|---|---|
| Tắt mic / Bật mic (`voiceMicOn` / `voiceMicOff`) | hàng 3 trái; toàn màn hình trái dưới | C11; `Semantics(toggled)` |
| Sóng âm / quả cầu | giữa | C10 |
| Chip ngôn ngữ "VI"/"EN" (thanh); VI│EN (toàn màn hình) | hàng 1; toàn màn hình dưới | C12; ngôn ngữ máy không nhận dạng được thì không chọn được tới khi tắt chế độ |
| Toàn màn hình / thu về (`voiceExpand` / `voiceCollapse`) | hàng 1 phải; toàn màn hình trái trên | C5 |
| Dừng (`voiceStopTurn`) | ô Dừng (chỉ khi có lượt chạy) | C27 |
| Kết thúc (`voiceEnd`) | hàng 3 phải; toàn màn hình phải dưới | `ended`; đang nói dở thì câu đó vào ô nhập |
| Đọc tiếp (nút chữ) | hàng 2 khi đang hỏi | C15 |

### 4.7 Trợ năng

- Báo (`SemanticsService.announce`, ngôn ngữ app; chỉ có tác dụng khi trình đọc màn hình bật, lúc đó chế độ là chạm để nói): vào chế độ `voiceModeStarted`; `sending` → `voiceModeSending`; `working` → `voiceModeWorking`; `paused` → nhãn lý do; `error` → câu lỗi; `ended` → `voiceModeEnded`. Không báo khi micro đang mở (tiếng báo sẽ bị nghe thành chữ). `needsYou`: bảng xin quyền đã `liveRegion`.
- Trình đọc màn hình bật: C30 (chạm để nói; `voiceModeTapToTalk`).
- Nhãn quả cầu theo trạng thái: `voiceModeOrbListening`, `voiceModeOrbSpeaking`, `voiceModeOrbWorking`, `voiceModeOrbPaused`.
- Giảm chuyển động: C30; dùng quy tắc giảm chuyển động trong token chuyển động của A.
- Chữ lớn (đã tính tới 1,3×): nhãn hàng 1 cắt "…" và nhãn trợ năng có đủ chữ; phụ đề vẫn tối đa 2 dòng ở thanh (giữ phần cuối), lý do tối đa 3 dòng; toàn màn hình cuộn được phần phụ đề.
- Rung: nhẹ khi máy tính nhận tin; vừa khi `needsYou` bắt đầu.

### 4.8 Biểu tượng (vai trò thêm vào bảng biểu tượng trung tâm của A)

Theo cập nhật 11:25: mọi biểu tượng là `CupertinoIcons`, gọi qua vai trò của `ShellxIcons` (`packages/shellx_design`), không gọi glyph trực tiếp, không dùng `Icons.*` của Material. C dùng tám vai trò sau (tiền tố `voice` để không trùng vai trò khác). A khai chúng trong bảng `ShellxIcons` của A (V2-5a §7.4), nên C không sửa `packages/shellx_design`; bảng dưới chép lại, lệch thì theo A:

| Vai trò (`ShellxIcons.…`) | Glyph | Dùng ở |
|---|---|---|
| `voiceMode` | `CupertinoIcons.waveform` | nút vào chế độ trong thẻ ô nhập của B (C2) |
| `voiceMicOn` | `CupertinoIcons.mic` | nút Tắt mic khi micro đang được phép mở |
| `voiceMicOff` | `CupertinoIcons.mic_slash` | nút Bật mic khi đã tắt; dấu trên sóng âm và quả cầu |
| `voiceEnd` | `CupertinoIcons.xmark` | Kết thúc |
| `voiceStopTurn` | `CupertinoIcons.stop_fill` | Dừng lượt |
| `voiceExpand` | `CupertinoIcons.arrow_up_left_arrow_down_right` | mở toàn màn hình |
| `voiceCollapse` | `CupertinoIcons.chevron_down` | thu về thanh |
| `voiceNeedsYou` | `CupertinoIcons.exclamationmark_triangle` | dấu ở hàng 1 khi `needsYou` |

Cả tám glyph có trong `CupertinoIcons` của Flutter 3.41.4 (A ghim `cupertino_icons` 1.0.9). Không cần glyph Material hay SVG dự phòng nào. Sóng âm và quả cầu là hình vẽ (`CustomPainter`), không phải biểu tượng.

---

## 5. Máy trạng thái (`AiVoiceMode`)

### 5.1 Trạng thái, cờ, "tính lại"

- Trạng thái: C6. Cờ: `muted` (C11), `askingMore` (đang chờ trả lời "Đọc tiếp không?"), `queueMode` (đang nghe một tin xếp hàng), `screenReader` (C30), `onDevice` (Android, C8).
- Hàng đọc: FIFO các lượt cần đọc (§7.1) và chỗ đang đọc dở (lượt, phần, đoạn).
- **Tính lại** (sau khi đọc xong, hết tạm dừng, hết `needsYou`, vào chế độ): có yêu cầu chờ → `needsYou`; còn lượt cần đọc hay đoạn đọc dở → `speaking` (từ đầu đoạn dở); có lượt chạy → `working`; `screenReader` → `paused` (chạm để nói); `muted` → `paused` (tắt mic); không gửi được (`!canSend`: hàng đợi đầy, cần đăng nhập, lỗi) → `paused` với chữ của lý do (`voiceModeQueueFull` hoặc `AiWords.state`); còn lại → `listening`.

### 5.2 Chuyển trạng thái

| Từ | Sự kiện | Tới | Việc làm |
|---|---|---|---|
| (tắt) | chạm sóng âm, hoặc `startVoice` | `idle` | dừng 🎙 nếu đang nghe; `VoiceAudio.enter` (màn hình sáng); xin quyền; chọn mã ngôn ngữ; khởi động bộ đọc, lấy giọng; lấy mốc lượt (§7.1) |
| `idle` (vào) | quyền bị từ chối / không có bộ nhận dạng / ngôn ngữ thiếu | `error` | — |
| `idle` (vào) | xong và app `resumed` | tính lại | thiếu giọng: dòng báo C19 |
| `listening` | có từ đầu tiên | `hearing` | — |
| `listening` | lượt nghe hết mà không có từ | `listening` | bắt đầu lại (C8) |
| `listening` | hết ngân sách im lặng (C29) | `paused` im lặng; `queueMode` thì `working` | thả micro |
| `hearing` | hết câu (§6) hoặc chạm | `sending` | `stop()`; chờ kết quả cuối ≤ 600 ms |
| `hearing` | lượt nghe hết trước khi hết câu | `hearing` | bắt đầu lại, cộng dồn |
| `hearing` | quá 120 s | `paused` quá dài | câu vào ô nhập |
| `sending` | chữ rỗng, hay chỉ từ ngập ngừng | `listening` | — |
| `sending` | "huỷ" ở cuối (C9) | `listening` | đọc "Đã huỷ." trước |
| `sending` | `askingMore` và câu khớp "tiếp" / "thôi" | `speaking` / tính lại | xoá `askingMore` |
| `sending` | có yêu cầu chờ (C26; xét trước mọi hàng `sending` khác, trừ chữ rỗng) | `needsYou` | câu vào ô nhập, không gửi |
| `sending` | `send` trả null | `working` | rung nhẹ; đang `askingMore` thì xoá cờ và bỏ phần chưa đọc của câu trả lời đó |
| `sending` | `send` trả mã lỗi | `error` (gửi lỗi) | câu vào ô nhập (C28) |
| `working` | yêu cầu tới | `needsYou` | — |
| `working` | có lượt kết thúc mới (§7.1) | `speaking` (có lời đọc và bật đọc) / tính lại | — |
| `working` | chạm | `listening` (`queueMode`) | — |
| `working` | lượt chạy được 2,5 s | `working` | đọc "Đang làm." một lần mỗi lượt |
| `speaking` | hết một phần, còn phần | `listening` (`askingMore`) | đọc "Còn nữa. Đọc tiếp không?" trước |
| `speaking` | hết | `idle` 300 ms (gác), rồi tính lại | `VoiceAudio.endSpeaking` |
| `speaking` | chạm | `listening` | `SpeechOutput.stop()`; bỏ phần còn lại của lượt đó |
| `speaking` | yêu cầu tới | `needsYou` | đọc xong đoạn đang đọc |
| `needsYou` | hết yêu cầu | tính lại | — |
| `needsYou` | yêu cầu khác (id khác) | `needsYou` | đọc "Thêm một yêu cầu: <việc>." (mỗi id chỉ được báo một lần, kể cả khi vào lại `needsYou` sau tạm dừng) |
| `paused` | chạm, bật mic, hết che, có kênh lại ≤ 30 s | tính lại | — |
| `error` | "Thử lại" / "Tiếp tục" / "Chuyển sang …" | `idle` | — |
| mọi trạng thái | Kết thúc, ra nền, trang đóng, phiên đóng / không chạy được / sang sid khác, che quá 2 phút | `ended` | huỷ nghe, dừng đọc, `VoiceAudio.exit`, thả màn hình |
| mọi trạng thái trừ `ended`, `error` | `inactive`, trang bị che, trang mở bảng/hộp thoại/menu | `paused` bị che | nghe: huỷ, câu dở vào ô nhập; đọc: dừng, nhớ đoạn |
| `idle`, `listening`, `hearing` | kênh không live | `paused` mất kênh | nghe: huỷ, câu dở vào ô nhập (`sending` không bị cắt: kết quả của `send` quyết định, C28) |
| `listening`, `hearing`, `speaking` | bị ngắt (C21) | `paused` bị ngắt | nghe: huỷ, câu dở vào ô nhập; đọc: dừng, nhớ đoạn |
| `speaking` | rút tai nghe | `paused` tai nghe | dừng đọc, nhớ đoạn |

### 5.3 Hẹn giờ (một lớp `VoiceTimings`, mọi hẹn giờ là `Timer` để `fake_async` điều khiển được)

| Hằng | Giá trị | Dùng cho |
|---|---|---|
| `endpointSilence` | 700 ms | hết câu thường (C7) |
| `endpointAfterFiller` | 1 600 ms | sau từ ngập ngừng, từ nối |
| `endpointNoiseExtra` | +800 ms | chỉ dựa vào chữ khi ồn |
| `endpointNoLevelExtra` | +300 ms | máy không báo mức âm |
| `levelsAliveWindow` | 500 ms | coi là "có mức âm" |
| `floorWarmup` / `floorRise` | 300 ms / 3 s | nền ồn (§6) |
| `tick` | 50 ms | nhịp kiểm hết câu khi micro mở |
| `finalWait` | 600 ms | chờ kết quả cuối sau `stop()` |
| `listenDoneWait` | 500 ms | chờ `done` của lượt cũ |
| `segmentSoft` / `segmentQuiet` / `segmentMax` | 45 s / 250 ms / 55 s | iOS bắt đầu lại |
| `restartRetry` | 500 ms, tối đa 3 lần trong 10 s | Android `error_busy`, `error_client` |
| `postSpeakGuard` | 300 ms | đọc xong → mở micro |
| `bluetoothSettle` | 250 ms | iOS đầu ra Bluetooth HFP |
| `silenceBudget` | iOS 30 s, Android 15 s | C29 |
| `utteranceMax` | 120 s | C29 |
| `workingCue` | 2,5 s | C14 |
| `turnTextWait` | 2 s | C14 |
| `linkGrace` | 30 s | C25 |
| `awayMax` | 2 phút | C24 |
| `screenOnIdleMax` | 10 phút | C23 |
| `idleLabelDelay` | 400 ms | C6 |
| `startVoiceWait` | 10 s | C31 |
| `_kSettle` (có sẵn) | 400 ms | bảng xin quyền, nút Dừng |

### 5.4 Cái gì mở lại micro

1. Đọc xong một lượt (và 300 ms gác) → tính lại.
2. Lượt kết thúc mà không có gì để đọc, hoặc đã tắt đọc to → tính lại (sau câu ngắn "Đã dừng." / "Lượt này chưa xong…" nếu có).
3. Hỏi "Đọc tiếp không?" xong → nghe câu trả lời.
4. Lượt nghe hết mà chưa xong câu, hay chưa có từ (trong ngân sách im lặng) → bắt đầu lại ngay.
5. Bật mic; chạm khi `paused`; hết bị che; có kênh lại trong 30 s → tính lại.
6. Chạm khi `working` → nghe một tin xếp hàng.
7. **Không bao giờ** mở micro khi: đang đọc hay trong 300 ms gác; `needsYou`; `muted`; `screenReader` mà người dùng chưa chạm; `error`; app không `resumed`; trang bị che.

### 5.5 Lượt xếp hàng, lượt bị dừng, mất kênh, rời màn hình

- **Xếp hàng:** tin nói khi đang có lượt chạy vào hàng đợi của máy tính (hàng đợi hiện ở dock, có ×). Lượt hiện tại kết thúc → đọc câu trả lời của nó; tin xếp hàng thành lượt mới → `working` → lượt đó kết thúc → đọc. Một lượt nghe đang mở mà chưa có từ khi một lượt bắt đầu thì huỷ (khỏi bíp khi đang làm); đã có từ thì nghe cho hết câu, câu đó thành tin xếp hàng. Ngược lại, một lượt kết thúc khi người dùng đang nói dở: nghe cho hết câu và gửi (lúc đó không còn lượt chạy nên thành lượt mới), rồi mới đọc câu trả lời của lượt vừa kết thúc (FIFO).
- **Lượt bị dừng** (■ ở thanh, Esc trên máy tính): `cancelled` → "Đã dừng." → tính lại.
- **Mất kênh:** C25.
- **Rời màn hình:** C24. Quay lại sau khi đã `ended` vì ra nền: thông báo nổi "Chế độ giọng nói đã tắt vì ShellX rời màn hình." và thẻ ô nhập với nháp còn nguyên.

---

## 6. Nhận biết hết câu (endpointing)

**Tín hiệu.**
- **Chữ:** câu nói `U` = các đoạn đã chốt (kết quả cuối của các lượt nghe trước) nối bằng dấu cách + kết quả từng phần hiện tại. So sánh trên dạng chuẩn hoá: chữ thường, bỏ dấu câu (`\p{P}`), gộp khoảng trắng. `lastWords` = lúc dạng chuẩn hoá đổi lần cuối. Chỉ đổi dấu câu, hoa thường (iOS hay sửa lại) không tính là đổi.
- **Mức âm:** luồng `levels` mới của `SpeechInput` (chỉ ở hồ sơ hội thoại). iOS: dBFS mỗi bộ đệm 1 024 mẫu (~21–23 ms). Android: `rmsdB` của bộ nhận dạng (thường 10–20 lần/giây, thang khác iOS).

**Nền ồn và tiếng nói.**
- Nền `F`: 300 ms đầu của mỗi lượt nghe lấy giá trị nhỏ nhất; sau đó mỗi mẫu `x`: `x < F` thì `F = x`; không thì `F += (x − F) × (1 − e^(−Δt / 3 s))` (lên chậm, xuống nhanh: ồn đều như quạt, điều hoà thành nền trong ~3 s; tiếng nói từng đợt thì không).
- Mẫu tiếng nói: `x ≥ F + M`, với `M` = 12 dB (iOS), 3,0 (Android `rmsdB`). `lastVoice` = lúc của mẫu tiếng nói cuối. "Có mức âm" = có mẫu trong 500 ms vừa qua.
- Hai hằng `M` nằm ở `VoiceTimings`, có test ghim, chỉnh sau kiểm tay (§18).

**Luật** (xét ở mỗi sự kiện và mỗi 50 ms khi micro mở):
1. `U` chưa có từ nào → không gửi.
2. `need` = 700 ms; 1 600 ms nếu từ cuối của `U` là từ ngập ngừng hay từ nối của ngôn ngữ đang nghe (§13.3).
3. Có mức âm: gửi khi `now − max(lastWords, lastVoice) ≥ need`; **hoặc** (ồn) khi `now − lastWords ≥ need + 800 ms`.
4. Không có mức âm: gửi khi `now − lastWords ≥ need + 300 ms`.
5. Chạm sóng âm khi `U` có từ: gửi ngay.
6. Hệ điều hành tự kết thúc lượt: luật 3/4 đúng lúc đó thì gửi; không thì bắt đầu lại và giữ `U`.
7. iOS: tuổi lượt ≥ 45 s và `now − max(lastWords, lastVoice) ≥ 250 ms` → bắt đầu lại mềm (chốt đoạn, nghe tiếp); 55 s thì `listenFor` của plugin tự dừng → bắt đầu lại.
8. Gửi xong: `stop()`, chờ kết quả cuối ≤ 600 ms, `U` = các đoạn đã chốt + kết quả cuối (không có thì kết quả từng phần cuối) → C9 → câu chỉ toàn từ ngập ngừng thì bỏ.

**Chống báo nhầm.**
- Ho, tiếng cửa, nhạc không lời → không có từ → không bao giờ gửi (luật 1). Mức âm một mình chỉ làm sóng âm động, không vào `hearing`.
- Bộ nhận dạng trả chữ chậm (máy chủ, mạng yếu) → mức âm còn báo tiếng nói → chờ (luật 3).
- Ngừng để nghĩ sau "thì", "và", "ừm" → 1 600 ms (luật 2).
- Nghe chính giọng đọc của mình → micro đóng khi đọc và thêm 300 ms gác (C14); không nói chen.
- Ồn đều → nền thích nghi; ồn thay đổi (TV, người nói chuyện) → dựa vào chữ sau 1,5 s (luật 3); chữ của TV có thể bị nhận thành câu nói (§20).
- Ngân sách im lặng (C29) đếm từ `max(lúc bắt đầu nghe, lastVoice, lastWords)`, nên người đang nói mà chưa ra chữ không bị tạm dừng.

**Hồ sơ nghe.** `SpeechInput.start(localeId, onDevice:, profile:)`:
- `dictation` (🎙, terminal): đúng tuỳ chọn hôm nay (`pauseFor` 2 s, `listenFor` 60 s, `partialResults`, `ListenMode.dictation`, `cancelOnError`).
- `conversation`: `pauseFor` không đặt (bộ điều khiển tự quyết hết câu; Android dùng im lặng mặc định của hệ thống), `listenFor` 55 s, `partialResults`, `ListenMode.dictation`, `cancelOnError`, `autoPunctuation: true` (iOS 16+), `onSoundLevelChange` → `levels`.

---

## 7. Văn bản đọc to

### 7.1 Chọn gì để đọc (`ai_voice_reply.dart`, Dart thuần)

- **Mốc lượt `B`** khi vào chế độ: có lượt chạy thì `B = head.turn.index − 1` (câu trả lời của lượt đang chạy sẽ được đọc); không thì `B` = số `turn` lớn nhất trong các mục gương đang giữ (không có thì 0).
- Gương có `MirrorTurnEnd` với `turn > B` → thêm lượt đó vào FIFO (tăng dần), `B` = số đó. "Tải thêm" chỉ mang lượt cũ (≤ `B`): bỏ qua. Nối lại sau mất kênh mang lại cùng số lượt: bỏ qua. Nhờ vậy mỗi lượt đọc đúng một lần.
- **Chữ của lượt T:** các `MirrorText(kind: agent, turn: T)` theo thứ tự chỉ số, chỉ lấy những mục đứng **sau `MirrorTool` cuối cùng** có `turn == T`; không có thì mục chữ agent cuối của T; không có mục nào thì không đọc gì.
- Mục chọn còn `rev = -1` thì chờ bản mới tối đa 2 s, rồi dùng phần đang giữ.
- Kết quả: `(texts, files, outcome)` từ `MirrorTurnEnd`: `finished` → đọc (`files > 0` thì đọc trước "Đã đổi N tệp."); `cancelled` → "Đã dừng."; `interrupted`, `failed` → "Lượt này chưa xong. Xem trên màn hình.".

### 7.2 Khi nào đọc

C14: sau khi lượt kết thúc, từng đoạn một; cắt phần theo C15. Lý do không đọc theo dòng chảy: một lượt của agent xen chữ với thẻ tool, mục chữ bị thay bằng bản mới khi đang chảy, và lời giải thích giữa lượt không phải câu trả lời.

### 7.3 Markdown → lời đọc (`speakable_text.dart`, Dart thuần)

Tách khối bằng quy tắc rào của `markdownBlocks` (`ai_text.dart:37-75`), rồi:

| Trong câu trả lời | Đọc thành |
|---|---|
| Khối mã có rào ```` ``` ```` hay `~~~` (cả `diff`), khối thụt lề 4 dấu cách | không đọc; đếm "khối mã" |
| Bảng (dòng có `\|` và dòng kẻ `\|---\|`) | không đọc; đếm "bảng" |
| Ảnh `![…](…)` | không đọc; đếm "ảnh" |
| Thẻ HTML | bỏ thẻ, đọc chữ bên trong |
| Tiêu đề `#`, mục danh sách `-` `*` `1.`, trích dẫn `>` | đọc chữ; mỗi tiêu đề, mỗi mục là một câu (thiếu dấu câu cuối thì thêm dấu chấm) |
| Đường kẻ ngang | ngắt đoạn |
| Link `[chữ](url)` | "chữ" |
| URL trần, `<https://…>` | "một đường link" |
| Mã trong câu `` `x` `` ≤ 32 ký tự, không có `/` `\` | `x` |
| `()` rỗng ngay sau một từ (`logout()`), trong mã hay trong câu | bỏ (`logout`) |
| Đường dẫn: mã trong câu có `/` hay `\`; từ trong câu có ≥ 2 dấu `/`, hoặc có `/` và đuôi tệp | tên phần cuối ("main.dart"); "và/hoặc" giữ nguyên |
| Mã trong câu > 32 ký tự | "một đoạn mã" |
| `**đậm**`, `*nghiêng*`, `_nghiêng_`, `~~gạch~~` | bỏ dấu, đọc chữ; `_` bên trong một từ (`snake_case`) giữ nguyên |
| Emoji (`\p{Extended_Pictographic}`), `✓ ✗ •` | bỏ |
| `→ ⇒ -> =>` | dấu phẩy |
| Các khối bị bỏ liền nhau | một câu chèn ở đúng chỗ: "Kèm 2 khối mã và 1 bảng." |
| Không còn chữ nào ngoài khối bị bỏ | "Câu trả lời là 2 khối mã, xem trên màn hình." |

### 7.4 Câu trả lời dài

- Câu: kết thúc ở `.` `!` `?` `…` `;` `:` + khoảng trắng, hoặc ở cuối dòng. Đoạn đọc: gộp câu tới ≤ 240 ký tự; câu dài hơn thì cắt ở `,` hoặc khoảng trắng gần nhất trước 240.
- Phần: các đoạn liền nhau tổng ≤ 600 ký tự. Phần 1 đọc ngay; mỗi phần sau theo C15.

### 7.5 Trộn tiếng Việt và tiếng Anh

- Chữ cái riêng của tiếng Việt: `àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ` (cả chữ hoa).
- Mỗi đoạn: có ít nhất một chữ cái đó → `vi`; không có mà có ≥ 3 từ gồm ≥ 2 chữ Latinh → `en`; còn lại → ngôn ngữ của đoạn trước (đoạn đầu: ngôn ngữ của chế độ).
- Ví dụ: chế độ VI, agent trả lời toàn tiếng Anh → giọng Anh đọc; câu Việt có "npm test" → giọng Việt đọc cả câu.

### 7.6 Module và bảng test mẫu

```dart
// lib/features/voice/domain/speakable_text.dart (Dart thuần, không Flutter)
SpokenReply speakableReply(List<String> markdownTexts, {required VoiceLocale mode, int filesChanged = 0});
SpokenText speakableLine(String text, {required VoiceLocale mode, required int maxChars}); // tiêu đề xin quyền, câu hỏi
// SpokenReply(parts: List<SpokenPart>), SpokenPart(chunks: List<SpokenChunk>),
// SpokenChunk(text, lang): toString() là 'SpokenChunk(…)'.
```

Bảng test tối thiểu (chế độ VI trừ khi ghi khác; đầu ra là các đoạn và ngôn ngữ):

| # | Vào | Ra |
|---|---|---|
| 1 | ``Đã sửa **logout()** trong `src/auth.ts`.`` | [vi] "Đã sửa logout trong auth.ts." |
| 2 | "Thêm đoạn sau:" + khối ```` ```dart ```` + "Rồi chạy test." | [vi] "Thêm đoạn sau: Kèm 1 khối mã. Rồi chạy test." |
| 3 | chỉ một bảng | [vi] "Câu trả lời là 1 bảng, xem trên màn hình." |
| 4 | "All 42 tests passed and the build is green." | [en] nguyên câu |
| 5 | ``Chạy `npm test` xong rồi.`` | [vi] "Chạy npm test xong rồi." |
| 6 | "Xem https://github.com/x/y/pull/12 nhé." | [vi] "Xem một đường link nhé." |
| 7 | "- Sửa auth.ts\n- Thêm test" | [vi] "Sửa auth.ts. Thêm test." |
| 8 | "Xong ✅ → deploy lên staging" | [vi] "Xong, deploy lên staging." |
| 9 | ``Xem [README](https://example.com/readme).`` | [vi] "Xem README." |
| 10 | ``Sửa `apps/mobile/lib/features/voice/domain/speakable_text.dart`.`` | [vi] "Sửa speakable_text.dart." |
| 11 | ``Thêm `await Future.delayed(const Duration(seconds: 1))` vào đầu hàm.`` | [vi] "Thêm một đoạn mã vào đầu hàm." |
| 12 | "biến snake_case_name giữ nguyên" | [vi] nguyên câu |
| 13 | `filesChanged: 2` | đoạn đầu [vi] "Đã đổi 2 tệp." |
| 14 | 700 ký tự văn xuôi | phần 1 ≤ 600 ký tự; phần 2 phần còn lại |
| 15 | hai khối mã liền nhau rồi một bảng | một câu chèn "Kèm 2 khối mã và 1 bảng." |
| 16 | chế độ EN, "Đã sửa xong." | [vi] nguyên câu (giọng Việt nếu có) |
| 17 | rỗng, hay chỉ khoảng trắng | không có phần nào |

---

## 8. Đọc to (TTS)

- **Gói:** `flutter_tts` (C18), sau giao diện `SpeechOutput`:

```dart
abstract interface class SpeechOutput {
  Future<Map<VoiceLocale, List<TtsVoice>>> voices();            // chỉ giọng trên máy
  Future<void> configure({required double rate, required Map<VoiceLocale, String?> voiceIds});
  Future<SpeakResult> speak(String text, VoiceLocale lang);     // done | stopped | failed | noVoice
  Future<void> stop();
}
```

- **Cài lúc vào:** `awaitSpeakCompletion(true)`; Android `setQueueMode(0)` (thay hàng); iOS `autoStopSharedSession(false)`; giọng theo C18 hoặc giọng người dùng chọn (§12); giọng đã chọn không còn trên máy thì dùng mặc định, không báo gì.
- **Mỗi đoạn:** chọn giọng theo ngôn ngữ của đoạn (C17), `speak`, chờ xong. Lỗi của plugin → bỏ phần còn lại của lượt, dòng báo `voiceModeReadFailed`, tính lại. Không log chữ (chỉ loại lỗi).
- **Nghe thử** (Cài đặt): đọc `VoicePhrases.sample` bằng giọng và tốc độ đang chọn, qua cùng chủ phiên âm thanh.
- **Thiếu giọng:** C19. Hướng dẫn thêm giọng: §13.1 (`voiceModeAddVoiceIos`, `voiceModeAddVoiceAndroid`); iOS có thể phải mở lại ShellX sau khi cài giọng mới (danh sách giọng chỉ đọc lúc khởi động, `references.md` §3.2).

---

## 9. Phiên âm thanh

- **Chủ:** `VoiceAudio` (C20), cài bằng `audio_session` và kênh `shellx/voice`:

```dart
abstract interface class VoiceAudio {
  Future<void> enter();             // giữ màn hình sáng (C23)
  Future<void> beginSpeaking();     // cấu hình lại + kích hoạt (O2–O4); chờ 250 ms nếu đầu ra Bluetooth HFP trên iOS (C22)
  Future<void> endSpeaking();       // tắt phiên (iOS notifyOthersOnDeactivation) / trả focus (Android)
  Future<void> keepScreenOn(bool on);
  Future<void> exit();              // endSpeaking nếu cần, thả màn hình
  Stream<VoiceAudioEvent> get events; // interrupted(begin, kind) | noisy
}
```

- **Thứ tự cứng (O1):** `AiVoiceMode` chỉ gọi `beginSpeaking` khi không có lượt nghe nào mở (đã `cancel`/`stop` và có `done`, hoặc 500 ms); chỉ gọi `SpeechInput.start` sau `endSpeaking` + 300 ms gác. Mọi lần đọc (câu trả lời, "Đang làm.", lời báo xin quyền, "Đọc tiếp không?", "Đã huỷ.") nằm giữa một cặp `beginSpeaking` / `endSpeaking`.
- **iOS:** O3. Trong lúc nghe, plugin đặt `playAndRecord` + `mixWithOthers` và cuối lượt trả category của ta rồi tắt phiên (`SpeechToTextPlugin.swift:453-466, 518-528`); vì vậy O2 cấu hình lại trước mỗi lần đọc. Không `audio` nền.
- **Android:** O4. Bộ nhận dạng của hệ thống tự lo micro và focus của nó trong lúc nghe.
- **Bị ngắt, rút tai nghe:** C21 (từ `interruptionEventStream`, `becomingNoisyEventStream` của `audio_session`, và lỗi nhận dạng `interrupted`).
- **Bluetooth:** C22. **Màn hình sáng:** C23: kênh `shellx/voice`, hàm `keepScreenOn(bool)`; iOS đăng ký trong `didInitializeImplicitFlutterEngine` (registrar `ShellxVoice`), Android trong `MainActivity.configureFlutterEngine`.

---

## 10. Xin quyền và câu hỏi

- **Vào `needsYou`** (C26): huỷ lượt nghe đang mở (câu dở vào ô nhập), đọc xong đoạn đang đọc, rung vừa, rồi (nếu bật đọc to, không có trình đọc màn hình, và id yêu cầu này chưa được báo) đọc `VoicePhrases.permission(agent, title)`; tiêu đề qua `speakableLine` (≤ 120 ký tự, dài hơn thì "một việc dài, xem trên màn hình"). Câu hỏi: `VoicePhrases.ask(agent, message)` với `ElicitationRequest.message` (≤ 200 ký tự), không có thì `askNoText`.
- **Trên màn hình:** bảng xin quyền và bảng câu hỏi của trang, y như ngoài chế độ giọng nói (thứ tự, nhãn, nút ≥ 52 pt, chờ 400 ms, chờ xác nhận của máy tính). Thanh: `voiceModeNeedsPermission` + `voiceModeTapOnly` (câu hỏi: `aiAskTitle` + `voiceModeAnswerOnScreen`). Toàn màn hình: bảng trên thẻ kính của A.
- **Ba lớp bảo đảm "không trả lời bằng giọng nói":**
  1. **Cấu trúc:** `AiVoiceMode` chỉ thấy `AiVoicePort` — `version`, `head`, `mirror`, `linkState`, `canSend`, `send(text)`, `stopTurn()`, `putInDraft(text)`. Không có `answerPermission`, `answerAsk`, `setConfig`, `setMode`, `revert`. Trả lời chỉ đi qua nút của bảng, do trang gọi như hôm nay.
  2. **Micro đóng:** ở `needsYou` không đường nào gọi `SpeechInput.start` (chạm, bật mic, hẹn giờ, hết che, có kênh lại đều chỉ "tính lại", mà tính lại ra `needsYou`). Sự kiện của lượt nghe cũ tới muộn bị bỏ.
  3. **Đua giờ:** câu đã hết câu mà đang chờ gửi khi yêu cầu tới → không gửi, vào ô nhập (`voiceModeDraftKept`).
- Hết yêu cầu (trả lời trên ĐT, trên máy tính, hay hết hạn) → tính lại.

---

## 11. Luồng dữ liệu và mã

```
 micro ─► SpeechToTextInput (hồ sơ "conversation") ─► partial/final/failed/listening + levels
                                                         │
                                                         ▼
                                   Endpointer (Dart thuần, §6) ──► hết câu
                                                         │
 AiVoicePort ◄── send(text) ── AiVoiceMode (máy trạng thái §5) ── speak(đoạn) ─► SpeechOutput (flutter_tts)
     │                               ▲            │                                   ▲
     ▼                               │            └──── begin/endSpeaking ─► VoiceAudio (audio_session + shellx/voice)
 AiSessionController.send            │
     │ ai.prompt (mã hoá đầu cuối, relay mù)       aiVoiceReply(mirror, T) ─► speakableReply(...) ─► phần/đoạn đọc
     ▼                               │                         ▲
 máy tính: agent chạy lượt ─► ai.* ─► AiMirror ─► version/head ┘
```

| Tệp (trong `apps/mobile/` trừ khi ghi khác) | Mới / sửa | Vai trò |
|---|---|---|
| `lib/features/voice/domain/speech_input.dart` | sửa | `ListenProfile {dictation, conversation}`, `start(…, profile)`, `Stream<double> levels` |
| `lib/features/voice/data/speech_to_text_input.dart` | sửa | hồ sơ hội thoại, mức âm, `androidNoBluetooth`; hồ sơ đọc chính tả giữ nguyên tuỳ chọn |
| `lib/features/voice/domain/voice_locale.dart` | sửa | từ ngập ngừng, từ nối, câu "tiếp"/"thôi", mã giọng đọc `vi-VN` / `en-US` |
| `lib/features/voice/domain/endpointer.dart` | mới | §6 |
| `lib/features/voice/domain/speakable_text.dart` | mới | §7.3–7.6 |
| `lib/features/voice/domain/voice_phrases.dart` | mới | §13.2 |
| `lib/features/voice/domain/voice_timings.dart` | mới | §5.3, hai hằng `M` |
| `lib/features/voice/domain/speech_output.dart`, `voice_audio.dart` | mới | giao diện §8, §9 |
| `lib/features/voice/data/flutter_tts_output.dart` | mới | `@LazySingleton(as: SpeechOutput)` |
| `lib/features/voice/data/audio_session_voice_audio.dart` | mới | `@LazySingleton(as: VoiceAudio)` |
| `lib/features/voice/presentation/widgets/voice_wave.dart`, `voice_orb.dart` | mới | §4.4, giảm chuyển động |
| `lib/features/ai/domain/ai_voice_reply.dart` | mới | §7.1 |
| `lib/features/ai/presentation/controllers/ai_voice_port.dart` | mới | cổng hẹp §10 |
| `lib/features/ai/presentation/controllers/ai_voice_mode.dart` | mới | §5; `@injectable` |
| `lib/features/ai/presentation/widgets/ai_voice_bar.dart`, `ai_voice_screen.dart` | mới | §4.2, §4.3 |
| thẻ ô nhập của B (T38, T39) | sửa | nút `ai.voice` ở chỗ T41 (C2) |
| `lib/features/ai/presentation/pages/ai_session_page.dart` | sửa | lối vào, đổi thanh, lớp phủ, vòng đời, `TickerMode`, tạm dừng khi mở bảng/menu, `startVoice`, `_voiceMade` (mẫu F43), `putInDraft` |
| `lib/core/router/app_router.dart` (+ `.gr.dart`) | sửa | `AiSessionRoute(startVoice)` |
| `lib/core/settings/app_settings.dart` | sửa | khoá §12 |
| `lib/features/settings/presentation/…` | sửa / mới | nhóm "Giọng nói", bảng chọn giọng |
| `lib/l10n/intl_{en,vi}.arb` (+ tệp sinh) | sửa | §13.1 |
| `ios/Runner/AppDelegate.swift` | sửa | kênh `shellx/voice` |
| `ios/Runner/Info.plist`, `{en,vi}.lproj/InfoPlist.strings` | sửa | §13.4 |
| `android/app/src/main/AndroidManifest.xml` | sửa | query `TTS_SERVICE` |
| `android/app/src/main/kotlin/com/shellx/prod/MainActivity.kt` | sửa | kênh `shellx/voice` |
| `pubspec.yaml` | sửa | `flutter_tts`, `audio_session` ghim đúng bản |
| `test/support/fake_speech.dart`; mới `fake_speech_output.dart`, `fake_voice_audio.dart`, `fake_voice_port.dart` | sửa / mới | §16 |

Giao thức, mọi gói trong `packages/*` (kể cả `shellx_design`: A đã khai tám vai trò `voice*`), desktop, relay: không đổi.

---

## 12. Cài đặt

Nhóm "Giọng nói" đặt sau nhóm "Terminal" trong trang Cài đặt (dùng thành phần của A). Lưu như mọi cài đặt khác (`KeyValueStore`; ghi trước, đổi signal sau, như `setBiometricLock`).

| Khoá | Mặc định | Dòng trong Cài đặt |
|---|---|---|
| `settings_voice_locale` (có sẵn) | theo ngôn ngữ app | Ngôn ngữ: VI│EN (`ShellxSegmented` của A; dùng chung terminal, 🎙, chế độ giọng nói) |
| `settings_voice_read` | `true` | Đọc to câu trả lời (+ dòng giải thích) |
| `settings_voice_tts_vi` | rỗng = mặc định của máy | Giọng đọc tiếng Việt → bảng chọn: "Mặc định của máy" + các giọng trên máy (tên, "Nâng cao"/"Cao cấp" trên iOS); không có thì "Máy chưa có" + "Cách thêm giọng đọc" |
| `settings_voice_tts_en` | rỗng | Giọng đọc tiếng Anh, như trên |
| `settings_voice_rate` | `1.0` (`0.85` / `1.0` / `1.2`) | Tốc độ đọc: Chậm │ Vừa │ Nhanh |
| — | — | Nghe thử |
| `settings_voice_start_new` | `false` | Mở phiên AI mới bằng giọng nói (C31) |
| — | — | Dòng chú thích riêng tư (`settingsVoiceFootnote`) |

Mã giọng lưu: iOS `identifier`; Android `name`.

---

## 13. Chuỗi (EN / VI)

### 13.1 Giao diện (ARB)

Dùng lại khoá có sẵn: `retry` (Retry / Thử lại), `openSettings` (Open Settings / Mở Cài đặt), `aiStop` (Stop / Dừng), `aiAskTitle`, `voiceLanguageVi` / `voiceLanguageEn`, `voiceNoPermission`, `voiceUnsupported`, `voiceLocaleUnavailableVi` / `En`, `voiceNetwork`, `voiceFailed`, và câu của `AiWords.failure`, `AiWords.state`.

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

`{language}` trong hai câu hướng dẫn = `voiceLanguageVi` / `voiceLanguageEn` (Vietnamese / Tiếng Việt, English / Tiếng Anh).

### 13.2 Lời ShellX đọc (`VoicePhrases`, theo ngôn ngữ của chế độ)

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

`{items}` ghép các mục khác không bằng `and`: "Kèm 1 khối mã và 1 bảng." / "Plus a code block and a table.".

### 13.3 Cụm từ ShellX nhận ra (trong `VoiceLocale`, so chữ thường, bỏ dấu câu)

| Nhóm | VI | EN |
|---|---|---|
| Ngập ngừng (cuối câu → 1 600 ms; cả câu chỉ có chúng → bỏ) | ừm, ờ, ơ, à, ờm, hừm | um, uh, er, erm, hmm, uhm |
| Từ nối (cuối câu → 1 600 ms) | thì, là, mà, và, với, nhưng, hay, hoặc, của, để, cho, như, kiểu, rằng | and, but, or, so, because, the, a, an, to, of, with, like, then, if, that |
| "Tiếp" (cả câu, sau "Đọc tiếp không?") | đọc tiếp, đọc tiếp đi, tiếp, tiếp đi, có, ừ, ok, được | keep reading, continue, go on, read more, more, yes, yeah, ok, okay |
| "Thôi" (cả câu, sau "Đọc tiếp không?") | thôi, không, dừng, không cần, đủ rồi | no, stop, enough, that's enough, no thanks |
| Gửi / huỷ (từ cuối, C9) | gửi / huỷ, hủy | send / cancel |

### 13.4 Câu xin quyền của hệ điều hành

| Khoá (iOS) | EN (`Info.plist`, `en.lproj`) | VI (`vi.lproj`) |
|---|---|---|
| `NSMicrophoneUsageDescription` | ShellX uses the microphone when you tap the mic to speak into your terminal or an AI session, and while voice mode is open in an AI session. It never listens in the background. | ShellX dùng micro khi bạn chạm nút mic để nói vào terminal hoặc phiên AI, và khi chế độ giọng nói đang mở trong một phiên AI. ShellX không nghe khi chạy nền. |
| `NSSpeechRecognitionUsageDescription` | ShellX turns what you say into text for your terminal or an AI session, including voice mode, using Apple's speech recognition, which may process it on your phone or on Apple's servers. | ShellX chuyển lời bạn nói thành chữ cho terminal hoặc phiên AI, kể cả ở chế độ giọng nói, bằng tính năng nhận dạng giọng nói của Apple; Apple có thể xử lý ngay trên điện thoại hoặc trên máy chủ của Apple. |

Hai câu giữ các cụm mà test hiện có ghim ("ShellX dùng micro", "your terminal or an AI session", "phiên AI", "AI session") và giữ chữ ngắn "ShellX" (V2-5a A1: câu văn giữ tên ngắn). Android không có câu xin quyền riêng (hộp `RECORD_AUDIO` của hệ thống).

---

## 14. Riêng tư, an ninh và log

- **Âm thanh:** tới bộ nhận dạng của Apple/Google như đọc chính tả hôm nay; không tới máy chủ ShellX, không lưu. Chỉ chữ đã nhận dạng đi tới máy tính, như tin gõ, mã hoá đầu cuối. Không nghe nền; chế độ tắt khi app rời màn hình.
- **Đọc to:** giọng đọc của chính điện thoại, chỉ giọng không cần mạng (C18): chữ không bị gửi đi đâu để đọc.
- **Xin quyền:** V2-2 D13 giữ nguyên và được ghim thêm (§10).
- **Log:** không log lời nói, phụ đề, đoạn đọc, tiêu đề yêu cầu, câu hỏi; chỉ log loại lỗi (`runtimeType`, tên lỗi của plugin như hôm nay). `toString()` của `SpokenChunk`, `SpokenPart`, `SpokenReply`, `SpokenText`, `TtsVoice`, sự kiện `VoiceAudioEvent` và bản ghi câu nói trả `Tên(…)`, có test.
- **Việc sau, cần đồng ý triển khai** (`web/**` tự triển khai từ `main`; như V2-2b, sửa trên một nhánh riêng và chỉ gộp khi người dùng đồng ý): trang Quyền riêng tư hai ngôn ngữ:
  - Tóm tắt (`web/src/pages/en/privacy.md:17`, `web/src/pages/privacy.md:17`) thành — EN: "Voice input and voice mode: when you tap the mic, or while voice mode is open in an AI session, what you say is turned into text by Apple's (iPhone) or Google's (Android, when the phone cannot do it itself) speech recognition, which may process the audio on their servers. In voice mode the AI's answers are read aloud by the phone's own text-to-speech, on the phone. ShellX does not store or receive the audio (section 2)." — VI: "Nhập lệnh và trò chuyện bằng giọng nói: khi bạn chạm nút mic, hoặc khi chế độ giọng nói đang mở trong một phiên AI, lời nói được chuyển thành chữ bằng nhận dạng giọng nói của Apple (iPhone) hoặc Google (Android, khi điện thoại không tự nhận dạng được), có thể xử lý âm thanh trên máy chủ của họ. Ở chế độ giọng nói, câu trả lời của AI được đọc to bằng giọng đọc của chính điện thoại, ngay trên điện thoại. ShellX không lưu và không nhận âm thanh (mục 2)."
  - Mục giọng nói (`:53`) thành — EN: "The mobile app uses the microphone only when you tap the mic, or while voice mode is open on screen in an AI session; it never records in the background, and voice mode stops when the app leaves the screen." — VI: "Ứng dụng di động chỉ dùng micro khi bạn chạm nút mic, hoặc khi chế độ giọng nói đang mở trên màn hình trong một phiên AI; không ghi âm nền, và chế độ giọng nói tắt khi ứng dụng rời màn hình."; thêm một ý — EN: "In voice mode, answers are read aloud by the phone's text-to-speech on the phone. ShellX uses only voices that work without a network connection, so the text is not sent anywhere to be read." — VI: "Ở chế độ giọng nói, câu trả lời được đọc to bằng giọng đọc của điện thoại, ngay trên điện thoại. ShellX chỉ dùng giọng đọc chạy không cần mạng, nên chữ không bị gửi đi đâu để đọc."
  - Mục bên thứ ba (`:97`): "When you use voice input" → "When you use voice input or voice mode"; "Khi bạn nhập lệnh bằng giọng nói" → "Khi bạn nhập lệnh bằng giọng nói hoặc dùng chế độ giọng nói".
- **Việc của người dùng trên console:** xem lại nhãn quyền riêng tư App Store và mục Data safety của Play cho dữ liệu âm thanh (GOLIVE S-04).

---

## 15. Lỗi và biên

| Tình huống | Hành vi |
|---|---|
| Từ chối quyền micro hay nhận dạng | `error`: `voiceNoPermission` + "Mở Cài đặt"; chạm lần sau kiểm lại quyền |
| Không có bộ nhận dạng, hoặc bị tắt (iOS) | `error`: `voiceUnsupported` |
| Máy không nhận dạng được ngôn ngữ đang chọn | `error`: `voiceLocaleUnavailableVi/En` + "Chuyển sang EN/VI"; ngôn ngữ đó không chọn được (chip ngôn ngữ, VI│EN) tới khi tắt chế độ |
| Mất mạng khi nhận dạng qua máy chủ | `error`: `voiceNetwork` + "Thử lại" |
| Hết lượt nhận dạng trong ngày (iOS), `error_too_many_requests` | `error`: `voiceFailed` + "Thử lại" |
| Android `error_busy` / `error_client` lúc bắt đầu lại | thử lại sau 500 ms, tối đa 3 lần trong 10 s, rồi `error`: `voiceFailed` |
| Thiếu giọng đọc | C19 |
| Bộ đọc lỗi giữa chừng | bỏ phần còn lại, `voiceModeReadFailed`, tính lại |
| Gửi lỗi | C28: không gửi lại; câu vào ô nhập; `outcome_unknown` → `voiceModeNotSent` |
| Hàng đợi đầy | không nghe; `voiceModeQueueFull` |
| Yêu cầu tới khi đang nói dở (tin xếp hàng) | huỷ nghe, câu dở vào ô nhập (`voiceModeDraftKept`), `needsYou` |
| Kênh rơi | C25 |
| Phiên đóng trên máy tính / không chạy được / sang sid khác | `ended`; thông báo nổi `voiceModeEnded`; dải của trang nói lý do như hôm nay |
| App ra nền, bấm nút nguồn | `ended`; quay lại: `voiceModeEndedBackground` |
| Màn thông báo, Trung tâm điều khiển | `paused` bị che → quay lại tự tiếp tục |
| Cuộc gọi tới (banner, chưa nghe), Siri | `paused` bị ngắt; nghe máy thì app ra nền → `ended` |
| Rút tai nghe khi đang đọc | `paused` tai nghe |
| "Xem đủ", trang khác đè lên, bảng/menu của trang | `paused` bị che; quá 2 phút → `ended` |
| Đổi ngôn ngữ khi đang nói dở | huỷ, bỏ câu dở, nghe lại |
| Câu cuối là "huỷ" | không gửi, đọc "Đã huỷ.", nghe |
| Chỉ "ừm", "à" | không gửi, nghe tiếp |
| Câu nói quá 120 s | vào ô nhập, `paused` quá dài |
| Lượt bị dừng / lỗi / bị ngắt | "Đã dừng." / "Lượt này chưa xong…" → tính lại |
| Câu trả lời chỉ có mã | "Câu trả lời là 2 khối mã, xem trên màn hình." |
| Hai lượt kết thúc liền nhau | đọc lần lượt (FIFO) |
| Trình đọc màn hình bật | chạm để nói (C30) |
| Giảm chuyển động bật | không hoạt hình liên tục (C30) |
| 🎙 đang nghe khi chạm sóng âm | dừng đọc chính tả, chữ ở lại ô, bật chế độ |
| Desktop cũ (V2-2a) | chạy được: chỉ dùng `ai.prompt` |

---

## 16. Kiểm thử

- **Fake:**
  - `FakeSpeechInput` (sửa): thêm `emitLevel(double)`, ghi `profile` của mỗi `start`.
  - `FakeSpeechOutput` (mới): ghi `(text, lang)` mỗi `speak`; test tự kết thúc từng đoạn (`finishCurrent()`), làm lỗi, đặt danh sách giọng; đếm `stop`.
  - `FakeVoiceAudio` (mới): ghi `enter/begin/end/exit/keepScreenOn`; phát `interrupted`, `noisy`.
  - `FakeVoicePort` (mới): `head`/`mirror` dựng được, `version`, `linkState`; ghi `send`, `stopTurn`, `putInDraft`; kết quả `send` đặt được.
  - **Bộ canh half-duplex** dùng chung: `FakeSpeechInput` và `FakeSpeechOutput` báo cho một bộ canh; `start` khi đang `speak` (hay trong 300 ms sau) làm test hỏng. Bật trong **mọi** test của `AiVoiceMode`.
- **Hết câu (`endpointer_test.dart`, bảng, thời gian giả):** 700 ms gửi, 650 ms chưa; từ ngập ngừng, từ nối → 1 600 ms; ồn mãi → 1 500 ms theo chữ; không có mức âm → 1 000 ms; chỉ đổi dấu câu không đặt lại; câu không từ không gửi; chỉ "ừm" bị bỏ; nền ồn lên chậm, xuống nhanh; hai hằng `M` iOS/Android; bắt đầu lại mềm iOS ở 45 s + 250 ms; ngân sách im lặng tính cả `lastVoice`.
- **Lời đọc (`speakable_text_test.dart`):** bảng §7.6 (17 dòng, mở rộng thêm khi sửa lỗi); cắt đoạn 240, phần 600; ngôn ngữ từng đoạn; câu chèn ghép và theo ngôn ngữ đoạn trước; `toString()` giấu chữ.
- **Chọn câu đọc (`ai_voice_reply_test.dart`):** mốc khi đang chạy và khi rảnh; chỉ chữ sau tool cuối; không có thì chữ cuối; không bao giờ suy nghĩ, tool, câu hỏi, thông báo, tin người dùng; "Tải thêm" và nối lại không đọc lại; `rev = -1` chờ 2 s; ba kết cục.
- **Máy trạng thái (`ai_voice_mode_test.dart`, `fake_async`):**
  - vòng đầy đủ nghe → gửi → làm → đọc → nghe; 300 ms gác; "Đang làm." ở 2,5 s đúng một lần mỗi lượt;
  - từng cú chạm của C10 ở từng trạng thái;
  - tắt mic (vẫn đọc, không nghe), bật lại; đổi ngôn ngữ khi đang nói dở;
  - câu dài: phần 1, "đọc tiếp", "thôi", câu khác thành tin, chip "Đọc tiếp", lượt mới trong lúc hỏi;
  - xếp hàng: chạm khi làm, gửi khi có lượt chạy, hàng đợi đầy; lượt bị dừng → "Đã dừng.";
  - gửi lỗi: câu vào ô nhập, không bao giờ gửi lại (đếm `send` = 1);
  - iOS bắt đầu lại ở 45/55 s, cộng dồn chữ; Android hết lượt giữa câu → bắt đầu lại sau `done`; `error_busy` thử lại 3 lần rồi `error`; Android thử trên máy rồi đám mây một lần và giữ;
  - ngân sách im lặng iOS 30 s, Android 15 s; câu 120 s → ô nhập;
  - thiếu giọng: đoạn Việt không `speak`, đoạn Anh vẫn đọc, lời ShellX đọc bằng tiếng Anh; không giọng nào: không `speak` nào;
  - tắt "Đọc to câu trả lời": không `speak` nào, nghe lại ngay sau lượt;
  - trình đọc màn hình: không tự nghe sau khi đọc;
  - màn hình sáng: giữ/thả theo C23, thả sau 10 phút không nghe không đọc.
- **Không bao giờ trả lời bằng giọng nói (`ai_voice_never_answers_test.dart`):**
  1. `AiVoicePort` chỉ có đúng các thành viên ở §10 (fake cài đặt đúng giao diện; thêm thành viên là test phải sửa); grep `lib/features/voice/` và `lib/features/ai/**/ai_voice_*.dart` không có `answerPermission`, `answerAsk`, `ai.answer`.
  2. Có yêu cầu chờ: phát `SpeechFinal` "cho phép", "allow", "đồng ý", "yes", "có" → không `send`, không trả lời; chạm, bật mic, hết che, có kênh lại, mọi hẹn giờ → không `start` nào.
  3. Đua giờ: hết câu rồi yêu cầu tới trước khi gửi → không `send`, có `putInDraft`.
  4. Widget: ở chế độ giọng nói có yêu cầu, chỉ chạm một nút của bảng mới gọi `answerPermission`, đúng một lần; thanh không có nút trả lời nào.
- **Vòng đời (widget, `test/support/app_harness.dart`):** `inactive` → tạm dừng → `resumed` tiếp tục; `hidden`/`paused` → `ended`, mọi thứ được thả (`cancel`, `stop`, `exit`, màn hình); đẩy một trang lên (`TickerMode` tắt) → tạm dừng, quá 2 phút → `ended`; mở bảng cấu hình, lịch sử, menu → tạm dừng rồi tiếp; trang đóng → `ended`; phiên `gone` → `ended`; lần đầu xin quyền (`permissionGate` của fake) không tạm dừng và nghe ngay khi xong.
- **Giao diện (widget):** nút `ai.voice` ở chỗ T41 (bên phải 🎙) của thẻ ô nhập trang phiên và ô nhập mở phiên; bấm được hay mờ theo C2; ô nhập mở phiên: ô trống → `ai.open` không chữ rồi trang phiên với `startVoice`, có chữ → như Gửi rồi `startVoice`, lỗi → chữ giữ, không thử lại; 🎙 vẫn là đọc chính tả; thanh thay thẻ ô nhập, nháp và ảnh còn nguyên khi Kết thúc; mười trạng thái ra đúng nhãn; ô Dừng giữ chỗ (không xê dịch); lớp phủ toàn màn hình mở/thu, Back của Android thu; giảm chuyển động; nhãn Semantics; nút ≥ 44 pt.
- **Phông đơn cách:** với họ phông giao diện của A, ở 320 pt và cỡ chữ 1,0× lẫn 1,3×: thanh và lớp phủ không tràn (không lỗi overflow), nhãn hàng 1 một dòng có "…", phụ đề tiếng Việt dài xuống dòng và giữ phần cuối, lý do dài tối đa 3 dòng, các nút chữ ở hàng 2 xuống hàng trong `Wrap`.
- **Biểu tượng:** các nút của thanh và lớp phủ dùng đúng vai trò `voice*` ở §4.8 (glyph do `icons_test.dart` của A ghim); grep các tệp mới và sửa của C (§11) không có `Icons.` hay `CupertinoIcons.` gọi thẳng.
- **`SpeechToTextInput`** (với `SpeechToTextPlatform` giả): hồ sơ `dictation` ra đúng tuỳ chọn hôm nay; hồ sơ `conversation` ra §6; `androidNoBluetooth` khi khởi tạo; `levels` chỉ phát ở hồ sơ hội thoại. Test cũ của 🎙 và terminal giữ nguyên, xanh.
- **Cài đặt:** khoá, mặc định, ghi trước đổi sau; `settings_voice_locale` dùng chung; bảng chọn giọng (có, không có, giọng đã chọn biến mất).
- **Tệp nền tảng (`platform_config_test.dart`):** câu iOS hai ngôn ngữ có "voice mode" / "chế độ giọng nói" và vẫn có các cụm cũ; `UIBackgroundModes` không có `audio`; manifest có query `TTS_SERVICE`, không có `BLUETOOTH_CONNECT`, `FOREGROUND_SERVICE`, `WAKE_LOCK`; kênh `shellx/voice` có ở `AppDelegate.swift` và `MainActivity.kt`; `pubspec.yaml` ghim đúng bản `flutter_tts`, `audio_session`.
- **Log và `toString`:** mọi kiểu mới mang chữ trả `Tên(…)`.

---

## 17. Review Focus

1. **Micro và giọng đọc chồng nhau** (một hẹn giờ bắt đầu lại, một `SpeechListening(true)` muộn, một lần đọc gợi ý chen vào lượt nghe): điện thoại nghe chính nó và gửi câu trả lời của agent ngược lại cho agent. Test: bộ canh half-duplex bật ở mọi test.
2. **Hết câu sai:** gửi nửa câu (bộ nhận dạng trả chữ chậm, ngừng giữa câu) hoặc không bao giờ gửi khi ồn; ngưỡng `M` hợp iOS mà không hợp Android. Test bảng thời gian giả; §18 mục 4–6.
3. **Một đường nào đó trả lời xin quyền hay mở micro khi đang có yêu cầu** (tính lại sai, hẹn giờ, đua giờ giữa hết câu và yêu cầu). Test §16 "không bao giờ trả lời".
4. **Rò vòng đời:** micro còn mở sau khi rời trang hay ra nền, màn hình sáng không thả, phiên âm thanh iOS còn làm nhỏ nhạc của app khác, bộ đọc còn nói sau Kết thúc, chế độ chạy tiếp dưới trang khác. Test vòng đời; §18 mục 9–12.
5. **Đọc sai thứ:** đọc suy nghĩ, đầu ra tool, lượt cũ, câu của chính người dùng; đọc một lượt hai lần sau khi nối lại hay "Tải thêm"; đọc chữ Việt bằng giọng Anh. Test chọn câu đọc và lời đọc.

---

## 18. ⚠ Kiểm tay (cần người, iPhone và Android thật, máy Mac chạy ShellX)

Máy: một iPhone (iOS 17 hoặc 18; thêm iOS 26 nếu có), một Pixel (Google) và một Samsung (bộ đọc Samsung). Mỗi mục thử cả tiếng Việt và tiếng Anh.

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

---

## 19. Phạm vi

**Trong V2-5c:** mọi thứ ở §3–§16.

**Ngoài V2-5c:** nói chen khi máy đang đọc và khử vọng; gói giọng nói trên máy (sherpa-onnx); bỏ tiếng bíp; đọc theo dòng chảy; tô từng từ khi đọc; nút "Đọc lại"; lệnh giọng nói ("đợi đã", "đổi sang tiếng Anh", dừng lượt); chạy nền, khoá màn hình, Live Activity; giọng nói trên desktop; đám mây realtime; thiên vị nhận dạng theo tên tệp của dự án (`contextualPhrases`); đánh dấu tin "nói" khác tin "gõ" trên máy tính; wake word; trang Quyền riêng tư (việc sau, cần đồng ý).

---

## 20. Rủi ro

| Rủi ro | Mức | Xử lý |
|---|---|---|
| Nhận nhầm lời → agent làm sai | Trung bình | Phụ đề hiện chữ trước khi gửi; "huỷ" ở cuối bỏ câu; sửa tệp, chạy lệnh vẫn cần chạm cho phép (D13); hoàn tác từ điện thoại có sẵn (V2-2b B19, B20). Chế độ "Tự sửa tệp", "Tự động" trên máy tính là lựa chọn của người dùng |
| Ồn thay đổi (TV) bị nhận thành câu nói và gửi | Trung bình | Luật 1–3 §6; Tắt mic, Kết thúc luôn ở tay; §18 mục 5 |
| Ngưỡng mức âm khác nhau theo máy (nhất là Android) | Trung bình | Nền thích nghi; hai hằng ở một chỗ, chỉnh sau §18 mục 6; vẫn có đường dự phòng theo chữ |
| Giới hạn của nhận dạng hệ điều hành (iOS giới hạn mỗi ngày, Android giới hạn ngắn, tiếng bíp) | Trung bình | C8, C29; pha 2 thay bộ máy |
| Chất lượng giọng đọc tiếng Việt chưa ai đo (`references.md` §3.2) | Trung bình | Chọn giọng tốt nhất đã cài; Cài đặt cho đổi giọng; §18 mục 2, 7 |
| `speech_to_text`, `flutter_tts`, `audio_session` giành phiên âm thanh iOS | Trung bình | Một chủ cho phần đọc, cấu hình lại trước mỗi lần đọc (C20); kế hoạch đọc mã nguồn bản ghim; §18 mục 3, 15 |
| AirPods qua HFP: tiếng đọc chất lượng cuộc gọi, có thể mất chữ đầu | Thấp–TB | Cùng đường cho nghe và đọc; chờ 250 ms (C22); §18 mục 3 |
| Bản ghim của `flutter_tts` không báo `network_required` | Thấp | Kế hoạch kiểm trong mã nguồn trước khi viết; thiếu thì không đưa câu "chỉ giọng không cần mạng" vào trang Quyền riêng tư và ghi vào bàn giao |
| Plugin iOS ghi chữ nhận dạng vào `os_log` mức debug (`SpeechToTextPlugin.swift:699`; có từ V1) | Thấp | Đã xử lý ở C37: vá plugin (vendor ở `third_party/speech_to_text`), bỏ dòng log; test nguồn giữ cho nó không quay lại |
| Màn hình luôn sáng tốn pin | Thấp–TB | Thả khi tạm dừng và sau 10 phút không nghe không đọc (C23); hoạt hình chỉ ở bốn trạng thái; §18 mục 18 |
| Phụ thuộc B (chỗ bên phải 🎙 ở T41, `startVoice` từ ô nhập mở phiên T38, trang phiên trên thanh dưới T34) | Thấp | C2, C31 nêu đúng phần cần; `TickerMode` không phụ thuộc cách B sắp route |
| Bộ nhận dạng Android tự dừng nhạc khi nghe | Thấp | Ghi nhận, không chống (C21) |
| Phông đơn cách rộng hơn: nhãn trạng thái bị cắt, phụ đề tốn dòng | Thấp–TB | Không chiều rộng cố định; nhãn một dòng có "…" và nhãn trợ năng đủ chữ; chip ngôn ngữ một nút; lý do dài xuống hàng 2 (C4, §4.2); test §16 "Phông đơn cách"; §18 mục 20 |

---

## 21. Việc sau

- **Pha 2 (giọng nói của riêng ShellX):** gói sherpa-onnx tải khi cần (~100–200 MB: Zipformer tiếng Việt, mô hình tiếng Anh, Silero VAD, giọng Piper/Supertonic), thu âm riêng nên **không còn tiếng bíp**, nhận dạng trên máy ở cả iOS và Android, tự kiểm theo máy (`references.md` §3.4, §3.8).
- **Nói chen (barge-in):** tầng tai nghe trước (không có đường âm quay lại micro), rồi loa ngoài với khử vọng (iOS voice processing, Android `VOICE_COMMUNICATION` + AEC), cổng SNR, chặn câu trùng lời vừa đọc, thời gian gác 200–800 ms (`references.md` §3.6).
- **Giọng nói trên desktop** (macOS, Windows): sau pha 2, dùng cùng bộ máy.
- **Chạy nền và màn khoá** (iOS `audio` nền, Android foreground service micro, Live Activity): cần lý do với App Store/Play.
- Đọc theo dòng chảy từng câu; tô từng từ; nút "Đọc lại" trên tin của agent.
- Thiên vị nhận dạng theo tên tệp, tên hàm của dự án (`contextualPhrases`).
- Lệnh giọng nói an toàn ("đợi đã", "đổi sang tiếng Anh").
- Trang Quyền riêng tư (§14) khi người dùng đồng ý triển khai (`web/**` tự triển khai từ `main`): người dùng chọn lúc nào, cùng đợt V2-5c lên `main` hay sớm hơn. Trong lúc chưa triển khai, app đã có câu xin quyền mới và dòng chú thích trong Cài đặt. Nhãn quyền riêng tư trên store.
- Gộp ba máy nghe (terminal, 🎙, chế độ giọng nói) dùng chung phần bắt đầu lại và trên máy/đám mây (V2-2b F42).

---

## 22. Việc người dùng quyết

Không có mục thiết kế nào chờ người dùng. Việc đồng ý triển khai trang Quyền riêng tư là việc sau của người dùng (§14, §21), không phải một quyết định thiết kế.
