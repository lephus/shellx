# Mobile: trạng thái agent tức thời + thanh trả lời nhanh (2026-10-13)

## Mục tiêu

Khi một agent (Claude Code, Codex, Gemini CLI, OpenCode) trên desktop cần người dùng, tab tương ứng trên điện thoại biết ngay ("chờ bạn") và người dùng trả lời bằng một chạm, không phải gõ trong terminal.

Đã có: push FCM khi agent chuyển `needs_input`/`done` (A12 D10, qua `LocalSessions.notify`); chạm push mở đúng tab (`pendingSelect`); chip agent trong bộ chọn phiên (A12 D22, chỉ qua `session.list`, không cập nhật, không có ở tab đang mở).

Thiếu: trạng thái sống trên tab đang mở; thao tác trả lời theo ngữ cảnh.

## Quyết định

- D1 — Kênh: message mới qua relay (không poll, không đoán từ màn hình).
- D2 — Mặt trả lời: tab terminal + thanh nút nhanh, chỉ hiện khi tab đang `needs_input`.

## 1. Giao thức (`packages/shellx_core`)

- `agent.state {id: int, agent: string, state: string}` — desktop → điện thoại. `agent`: tên wire của `AgentKind` (`claude|codex|gemini|opencode`) hoặc `""`. `state`: `running|needs_input|idle|done` hoặc `""` (không còn agent nhìn thấy được). Cùng tên với `agentStateWire`.
- `session.attached` thêm `agent?`, `agent_state?` (chỉ ghi khi có; vắng → null).
- Tương thích: decoder mảng bỏ qua `t` lạ (điện thoại cũ); desktop cũ không gửi → điện thoại mới hành xử như hôm nay.
- Spec v1 §6.4 ghi thêm hai mục trên.

## 2. Desktop

- `SessionManager` (`shellx_agent`) và `DesktopSessionManager`: `publishAgentState(sessionId, agent, state)` gửi `agent.state` tới mọi điện thoại **đang gắn** phiên đó; bỏ qua nếu bằng giá trị đã gửi cho phiên đó. Lúc gắn, `session.attached` điền `agent`/`agent_state` từ `agentOf` (đã có).
- `agent_controller.dart`: lắng nghe `AgentStatusNotifier`; khi trạng thái nhìn thấy được (`agentStateVisible`) của pane thuộc một phiên chia sẻ đổi, gọi `publishAgentState`. Không đổi cách phát hiện, push hay luật thông báo.

## 3. Client và mobile

- `shellx_client`: `ClientTab` phát `TabAgent(agent, state)` từ `agent.state` và từ `session.attached` (khi có trường).
- `TerminalTabController`: signal `agentState` (`AgentWireState?`).
- Chấm trạng thái ở thanh tab và danh sách máy: `running` chấm trung tính, `needs_input` màu cảnh báo, còn lại ẩn.
- `AgentReplyBar` thay `extra_keys_bar` khi tab đang xem ở `needs_input`: `1` `2` `3` `y` `n` `Enter` `Esc` `↑` `↓` + nút ô soạn/giọng nói + nút `⌨` (về bàn phím phụ thường cho tới lần `needs_input` kế tiếp). Mỗi nút gửi đúng một phím qua đường `input` hiện có (`\r`, `\x1b`, `\x1b[A`, `\x1b[B`, chữ số/chữ cái). Rời `needs_input` → trả lại `extra_keys_bar`.
- l10n vi + en cho nhãn/semantics.

## 4. Biên

- Mất kết nối/gắn lại: `session.attached` đồng bộ lại.
- Pane SSH trên desktop: không có hook → không có trạng thái (như nay).
- Nhiều điện thoại: tất cả nhận.
- Bấm nhầm: một phím, như gõ tay.

## 5. Test

- Codec round-trip `agent.state`, `session.attached` có/không trường mới; mảng có `agent.state` vẫn đọc được bằng decoder (bỏ qua `t` lạ đã có test).
- Desktop/agent: chỉ phiên đang gắn nhận; không gửi trùng; `session.attached` mang trạng thái.
- Client: `TabAgent` từ cả hai nguồn.
- Mobile: thanh hiện/ẩn theo trạng thái; từng nút gửi đúng byte; nút `⌨`; chấm trạng thái.

## Ngoài phạm vi

Nút trả lời trên thông báo lock screen, nhận diện lựa chọn của menu từ màn hình, màn tổng quan agent nhiều máy.
