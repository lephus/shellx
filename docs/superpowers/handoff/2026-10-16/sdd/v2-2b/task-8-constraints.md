# Task 8 constraints (verbatim excerpts) — the desktop asks for pushes with answer buttons

## Spec `docs/superpowers/specs/2026-10-15-v2-2b-phone-ai-more-design.md` (binding; Vietnamese) — B6, B7, B25 (lines 80, 81, 99):

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| B6 | Relay | Thêm hai khoá tuỳ chọn vào `POST /v1/notifications`: `category` (chỉ nhận `ai_perm`) và `tag` (`^[A-Za-z0-9_.:-]{1,64}$`); sai thì 400. FCM: thêm `apns.payload.aps.category` và `android.notification.tag`; **giữ nguyên khối `notification`** (không có tin chỉ-data, không cần bảng khả năng theo máy). Relay cũ bỏ qua hai khoá. Nhánh `v2-2b-relay`, gộp khi người dùng đồng ý triển khai. | Chưa triển khai relay thì thông báo vẫn như cũ, không có nút. |
| B7 | Desktop xin đẩy kèm nút | `AiPush` có thêm `permission` (id) và hai lựa chọn: **allow** = lựa chọn `allow_once` đầu tiên **không** bật chế độ bỏ qua xin quyền; **reject** = lựa chọn `reject_once` đầu tiên. Không bao giờ `allow_always`/`reject_always` (đổi hành vi về sau, trái tinh thần D13). Thiếu một trong hai thì thông báo thường như cũ. Câu hỏi không có nút. `aiNotice` thêm `data` `perm`, `allow`, `reject` và xin `category: ai_perm`, `tag: ai-<epoch>-<pane>-<perm>`. Hàm nhận diện chế độ bỏ qua xin quyền chuyển sang `package:shellx_ai` để hub dùng. | — |
| B25 | Riêng tư | Không có nội dung mới nào rời kênh mã hoá đầu cuối ngoài: id yêu cầu (số), hai id lựa chọn, một tag (B7). Trang Quyền riêng tư nói rõ thông báo AI mang gì (tên việc dạng rõ như N3; câu hỏi chỉ "<agent> hỏi bạn"; id). Không log nội dung (D12), kể cả ảnh, đường dẫn, diff. | — |

## Spec §4.2 (line 131) and §4.3 (lines 133–143):

- Mux `ai.push`: thêm `perm`, `allow`, `reject`, `tag` (daemon cũ bỏ qua → thông báo thường).

### 4.3 Thông báo (relay, nhánh `v2-2b-relay`)

Thân `POST /v1/notifications` thêm `category?` (`ai_perm`), `tag?`. `data` thêm `perm`, `allow`, `reject` (vẫn ≤ 10 khoá cùng `kind`, `ai_session`, `agent_id`; giá trị ≤ 256 ký tự, quá thì bỏ nút). FCM:

```json
{"message": {"token": "…",
  "notification": {"title": "MacBook · Claude", "body": "Cần bạn trả lời: Sửa src/main.ts"},
  "data": {"kind": "ai", "ai_session": "k3f9za.-12", "agent_id": "…", "perm": "41", "allow": "allow", "reject": "reject"},
  "android": {"priority": "high", "notification": {"tag": "ai-k3f9za--12-41"}},
  "apns": {"payload": {"aps": {"sound": "default", "category": "ai_perm"}}}}}
```

## Spec §6 (lines 178–184), §8 B7/B6 (lines 208–209), §9 Review Focus 1 and 5 (lines 226, 230):

## 6. Riêng tư, an ninh và log

- Không có đường nào trả lời mà không có một lần chạm của người dùng (D13 giữ nguyên). Nút trên thông báo chỉ mang hai lựa chọn "một lần"; câu trả lời chỉ gửi sau khoá Face ID của app; không gửi lại sau khi mất kênh.
- Chế độ bỏ qua xin quyền không bao giờ được liệt kê hay đặt từ điện thoại (B11).
- Đường dẫn từ điện thoại (B13, B19) chỉ là đường dẫn desktop đã đưa và phải nằm trong thư mục phiên; desktop kiểm lại lúc làm.
- Ảnh chỉ nằm trong bộ nhớ desktop tới khi gửi cho agent (B12).
- Không log nội dung; `toString` của mọi tin mới trả `Tên(…)`, có test.

- **B7:** chọn đúng `allow_once` không bỏ qua quyền và `reject_once`; thiếu thì không nút; daemon cũ bỏ khoá mới.
- **B6 (relay):** test TypeScript cho `category`, `tag` hợp lệ/không; hình dạng FCM; e2e push trong `packages/shellx_e2e`.
1. **Câu trả lời trúng nhầm yêu cầu:** runtime đổi trên cùng pane (B3), thông báo cũ chạm muộn, sid của lần chạy trước (B23). Test: mọi đường đều ra `stale` hoặc mở trang, không bao giờ trả lời.
5. **Chế độ bỏ qua xin quyền lọt qua** bằng một id lạ hay qua `ai.config` gửi thẳng. Test cả danh sách và lúc đặt.

## Plan Review Focus 1 and 5 (plan lines 97, 101):

1. **An answer lands on another request** — a pane's runtime replaced (B3), a notification tapped late, a sid from before ShellX restarted (B23). Every path ends `stale` or opens a page; nothing answers another request. [Task 1: "an answer to the old runtime's request is stale; the new request stays asked", "a queued prompt of the old runtime is not the new one's either". Task 6: "a session of the previous run opens as the one session of the same agent session now", "none, or two, of the same agent session now: the machine opens". Task 20: "stale says it was answered elsewhere and sends nothing else", "an old sid gets not_found, then the page: …", "bad data sends nothing: …", "a lost channel is never retried (…)", "a cancelled unlock sends nothing, also when the app is unlocked later".]
5. **A no-approval mode slips through,** by an id nobody listed or by an `ai.config` sent directly. [Task 10: "R16: an id that only says it (yolo, clearAndBypass, danger-full-access) is never offered, nor a switch named like one", the refusal tests of `aiConfigRefusal` (`on_computer` whatever was offered), "the phone gets the choices without "Bypass permissions"; its choice reaches the agent and is remembered as the chip remembers it". Task 8: "the allow button is never an answer that turns on a mode acting without asking (Review Focus 5)".]

## Relay rule the tag must pass (Task 7, on branch v2-2b-relay): `tag` matches `^[A-Za-z0-9_.:-]{1,64}$`; `category` only `ai_perm`; data values ≤ 256 characters, ≤ 10 keys (relay adds `agent_id`).
