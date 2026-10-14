# V2-2 — Điện thoại xem và điều khiển phiên AI — Đặc tả thiết kế

- **Ngày:** 2026-10-14
- **Branch:** `shellx-v2`. Toàn bộ V2 nằm trên branch này.
- **Trạng thái:** Người dùng vắng mặt và giao: "sản phẩm hoàn chỉnh, chất lượng tốt cho app điện thoại và app desktop vào sáng mai", "trải nghiệm mượt nhất có thể". Hướng đã có trong spec V2-1 §11 (dòng V2-2). D1–D16 do người viết spec chốt, mỗi quyết định ghi cái giá nếu sai. Spec chờ người dùng xem.
- **Lộ trình V2:** V2-1 (tab AI trên desktop: V2-1a nền, V2-1b giao diện), **V2-2 (tài liệu này)**, V2-3 (tool qua URL), V2-4 (tool trên điện thoại). V2-2 chia hai phần: **V2-2a** làm tối nay (§11.1), **V2-2b** làm sau (§11.2).
- **Nền:** `shellx-v2` tại `5e04dc8`.
  - V2-2 **được phép** sửa:
    - giao thức điện thoại `packages/shellx_core/lib/src/protocol/` (chỉ thêm);
    - `packages/shellx_ai` (thư viện mới `remote.dart`, không sửa mô hình);
    - `packages/shellx_agent` (router, hub, mux, thông báo đẩy);
    - `packages/shellx_client`;
    - daemon (`daemon_main.dart`, `src/agent/session_core.dart`, `src/agent/agent_runtime.dart`);
    - app mobile;
    - một tệp mới `apps/desktop/lib/src/ai/ai_phone.dart`, thêm luồng `made` vào `AiRuntimes` và vài dòng trong `main.dart`.
  - V2-2 **không** sửa: relay, mô hình phiên của V2-1a (`AiSessionState`, `Timeline`), `AiRuntime`, giao diện tab AI của V2-1b.
- **Giữ nguyên:** spec V2-1 (D9 mô hình dùng chung, D10 xin quyền, D13 trạng thái, D20 riêng tư, D22 câu hỏi), spec "agent quick reply", spec thông báo đẩy (N3, N5, N10), spec chia sẻ terminal (§7.9: điện thoại cũ không bao giờ nhận tin nó không đọc được). Tài liệu này chỉ **thêm**.
- **Tài liệu đi kèm:** demo `docs/superpowers/design/2026-10-14-ai-pane-demo/`, kịch bản 7 "Điện thoại" (`demo.js` hàm `phone*`, `demo-data.js` `s7`). Demo ràng buộc phần trải nghiệm; màu và cỡ lấy theo token của app mobile (`context.colors`, `context.typo`).
- **Nguồn đã kiểm ngày 14/10/2026:**
  - mã nguồn ShellX (§2);
  - kế hoạch V2-1a (phần đầu và mọi khối Interfaces) và V2-1b (phần đầu, Task 3, 4, 10, 11, 17);
  - relay: `relay/src/relay.ts`, `relay/src/hub/user-hub.ts`, `relay/src/routes/notifications.ts`.
- **Đã thử trên bản sao (ngoài repo, `git archive` + `pub get --offline`):** toàn bộ mã của V2-2a trừ phần nối desktop cần V2-1b (Task 11 của plan) đã được viết và chạy: `shellx_core` 351 test, `shellx_ai` 192, `shellx_agent` 805, `shellx_client` 117, app mobile 860, app desktop 3092 (10 bỏ qua) — đều xanh. `flutter_markdown_plus 1.0.12` chạy trong app mobile trên Flutter 3.41.4.
- **Ký hiệu:**
  - "D1" không tiền tố là quyết định của tài liệu này; "V2-1 D10" là của spec V2-1.
  - **Phiên AI:** một pane AI của desktop (V2-1 D3).
  - **sid:** mã phiên AI cho điện thoại, `<epoch>.<id pane>`; epoch đổi mỗi lần app desktop chạy.
  - **Cửa sổ:** tiến trình giao diện của ShellX desktop, nơi có tab AI. **Dịch vụ nền:** daemon A5b.
  - **Hub:** `AiPhoneHub`, phần của cửa sổ nói chuyện với điện thoại.

---

## 1. Mục tiêu

Ra khỏi bàn, người dùng vẫn làm việc với phiên AI đang chạy trên máy tính từ điện thoại:
- thấy danh sách phiên AI và phiên nào đang cần mình;
- mở một phiên, đọc hội thoại (chữ, thẻ việc, diff), cập nhật trực tiếp;
- gửi tin, xếp hàng, dừng lượt;
- trả lời xin quyền và câu hỏi bằng nút lớn;
- được báo khi agent cần mình, chạm là tới đúng chỗ;
- mở phiên AI mới trong một thư mục dự án của máy tính.

Mọi nội dung chỉ đi trong kênh mã hoá đầu cuối hiện có. Điện thoại và desktop bản cũ không bị ảnh hưởng.

### Tiêu chí thành công (đo được)

1. **Danh sách.** Trên trang máy, bộ chọn phiên có nhóm "Phiên AI" đứng đầu: mỗi phiên một hàng "tiêu đề / Claude · trạng thái", phiên cần trả lời tô màu cảnh báo và có dòng "Sửa src/main.ts". Thanh trên có nút ✦ kèm số phiên đang chờ. Trạng thái đổi trên desktop thì danh sách đổi theo trong ≤ 1 s.
2. **Mở phiên nhanh.** Từ lúc chạm vào hàng tới lúc thấy hội thoại ≤ 1,5 s trên mạng thường (một vòng hỏi đáp qua relay, bản chụp ≤ 60 mục).
3. **Trực tiếp.** Agent stream chữ thì điện thoại thấy chữ chạy, trễ ≤ 300 ms so với desktop, tối đa 10 lần cập nhật mỗi giây mỗi phiên; cuộn lên đọc thì màn không nhảy.
4. **Xin quyền.** Desktop có yêu cầu xin quyền thì điện thoại hiện bảng dưới cùng với một nút lớn (cao ≥ 52 pt) cho mỗi lựa chọn, đúng thứ tự agent gửi, nhãn theo V2-1 D10. Một chạm gửi đúng một câu trả lời; nút chờ cho tới khi desktop xác nhận. Không có gì tự trả lời.
5. **Trả lời hai nơi.** Desktop và điện thoại cùng trả lời: cái tới trước thắng, nơi kia thấy "Đã được trả lời ở thiết bị khác.", không có câu trả lời nào rơi nhầm sang yêu cầu khác.
6. **Gửi tin.** Gửi được khi agent rảnh; đang chạy thì xếp hàng (tối đa 5, bỏ được từng tin); nút Dừng khi ô trống; "Dừng hẳn" khi desktop cho phép (V2-1 §1.4).
7. **Thông báo.** Agent cần trả lời mà không ai đang mở phiên đó (trên điện thoại hay đang nhìn trên desktop) thì mọi điện thoại đã ghép đôi nhận thông báo "<máy> · Claude / Cần bạn trả lời: Sửa src/main.ts" trong ≤ 5 s. Chạm vào là mở thẳng phiên đó với bảng xin quyền. App đang mở thì hiện banner trong app.
8. **Mất mạng.** Mất kết nối thì hội thoại vẫn hiện, có dải "Đang kết nối lại…", ô nhập khoá nhưng giữ chữ. Có mạng lại thì chỉ những mục đã đổi được gửi lại.
9. **Phiên mới.** "Phiên AI mới" → chọn agent đã sẵn sàng và một thư mục máy tính đưa ra → trong ≤ 3 s mở phiên mới trên điện thoại; desktop có thêm tab AI nhưng không chuyển tab đang xem.
10. **Bản cũ.** Điện thoại cũ với desktop mới: không nhận một tin `ai.*` nào, terminal như cũ. Điện thoại mới với desktop cũ: không có nhóm "Phiên AI" mà có dòng "Cập nhật ShellX trên máy tính…", không chờ vô hạn, terminal như cũ. Có test cho cả hai chiều.
11. **Cửa sổ đã thoát.** Dịch vụ nền còn chạy mà cửa sổ ShellX đã thoát: điện thoại thấy "Mở ShellX trên máy tính để dùng phiên AI.", phiên đang mở hiện "ShellX trên máy tính đã thoát…". Mở lại cửa sổ thì danh sách tự về.
12. **Không hồi quy.** Mọi test hiện có vẫn xanh.

---

## 2. Kiểm tra hiện trạng (đọc mã ngày 2026-10-14)

| Mảng | Hiện có | Hệ quả cho V2-2 |
|---|---|---|
| Tin trong kênh | `AppMessage` là map CBOR có khoá `t` (`packages/shellx_core/lib/src/protocol/messages.dart`). `t` lạ → `null` → bị bỏ qua. Một tin **đã biết** mà sai trường thì `FormatException`, và `SecureChannel.open` nói "the channel must be dropped" (`channel/secure_channel.dart`). | D3: tin `ai.*` sai thì bỏ qua, không bao giờ làm rơi kênh |
| Độ sâu CBOR | `decodeCbor` từ chối lồng quá 8 tầng (`util/cbor_values.dart`); bộ mã hoá không nhận số thực. | D3: nội dung là byte JSON, phong bì phẳng |
| Cỡ tin | Một lô niêm phong ≤ `kMaxSealedBatchBytes` = 65 493 byte. `splitIntoBatches` để một tin quá cỡ thành một lô riêng, `seal` ném lỗi, `AgentChannel._fail()` đóng kênh (`shellx_agent/lib/src/service/agent_channel.dart`). | D4: mỗi tin `ai.*` tự đủ, phần thân ≤ 48 KiB |
| Relay | Khung ≤ 64 KiB; tin WS > 1 MiB đóng socket; 500 khung/giây mỗi thiết bị; > 4 MiB chưa gửi hoặc > 1024 lần gửi chờ thì đóng socket chậm (`relay/src/relay.ts`, `hub/user-hub.ts`). | D4, D5: cửa sổ 256 KiB mỗi phiên mỗi điện thoại, ≤ 10 cập nhật/giây |
| Terminal | Cửa sổ gửi 256 KiB chưa ack mỗi phiên (`session_stream.dart`). | D5 dùng cùng cỡ |
| Router | `SessionRouter.handle` chia tin của điện thoại cho phiên shell và terminal desktop; `session.list {desktop:true}` trả `desktop_sharing`. | D1: thêm nhánh `AiMessage`; D3: thêm khoá `ai` |
| Ai giữ relay | Mặc định (dịch vụ nền tắt) cửa sổ giữ cả relay lẫn shell. Bật dịch vụ nền thì daemon giữ relay và shell, cửa sổ nối vào qua mux (`daemon_main.dart`, `mux_server.dart`, `remote_local_sessions.dart`). Tab AI luôn ở cửa sổ (V2-1). | D1: hai đường, một hub |
| Tiền lệ `agent.state` | `AgentController` nghe `agentStatusProvider` rồi gọi `publishAgentState`; chỉ chạy khi trạng thái nằm cùng tiến trình với relay. Ở chế độ dịch vụ nền "nothing is known, so no keys are sent" (`agent_controller.dart`). | D1: V2-2 không lặp lại giới hạn này, có đường mux riêng |
| Mux | Khung ≤ 64 KiB, CBOR sâu ≤ 8. Loại lạ: daemon trả `unknown_type` chỉ khi có `q`; cửa sổ bỏ qua sự kiện lạ. | D1: tin mux mới không có `q`, nên bản cũ bỏ qua êm |
| Đóng cửa sổ | Nút đóng chỉ ẩn cửa sổ (`window_host.dart`); tab AI vẫn chạy. Thoát hẳn thì agent dừng (V2-1 §6). | §7: cửa sổ ẩn vẫn phục vụ; thoát thì "đã thoát" |
| Mô hình AI | `AiSessionState` + `Timeline` thuần Dart (`packages/shellx_ai/lib/src/model`). Mục chỉ được thêm, không bị xoá; mỗi lần đổi một mục thì `rev++`; `version` tăng mỗi lần đổi; id xin quyền và id câu hỏi lấy từ một bộ đếm, không dùng lại. | D5: chỉ số mục là id; `rev` để biết đổi |
| Runtime | `AiRuntime.send/cancel/forceStop/answerPermission/answerAsk`; `start()` không chạy lại khi đang chạy (`_starting ??=`). `AiRuntimes.runtimeFor(paneId)` tạo runtime lười (V2-1b Task 10). | D2: hub gọi đúng các hàm này |
| Thông báo đẩy | `POST /v1/notifications {title, body, data}`, `data` ≤ 10 khoá `[a-z0-9_]`, giá trị ≤ 256 ký tự, relay tự thêm `agent_id`; FCM hiện `notification {title, body}`; relay không có `category`, không có tin chỉ-data. Agent gửi ≤ 6/phút mỗi máy (`notification_sender.dart`). | D11; nút trả lời trên thông báo cần sửa relay → V2-2b |
| App mobile | signals + get_it + auto_route (sinh mã), chuỗi qua `intl_utils` (`lib/l10n/intl_*.arb`), test có `FakeBackend`, `FakeMachineSession`, `routedApp`. Bộ chọn phiên: `session_picker.dart`; trang máy: `terminal_page.dart`; mở từ thông báo: `notification_opener.dart`. App vào nền thì `suspend()` relay, kênh rơi. | D10, §5 |
| Markdown trên mobile | Chưa có gói. `flutter_markdown_plus 1.0.12` (V2-1b đã ghim cho desktop) phân giải offline và chạy trong app mobile (đã thử). | D8 |

---

## 3. Nhật ký quyết định

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| D1 | Đường đi | **Trong tiến trình:** relay → `AgentService` → `SessionRouter` → `AiEndpointSlot` (của `SessionCore`, sống suốt tiến trình) → hub của cửa sổ. **Có dịch vụ nền:** relay → daemon → `SessionRouter` → slot → `MuxAiForwarder` → mux `ai.in {m, b}` → cửa sổ (`MuxAiBinding`) → hub; trả lời đi ngược bằng `ai.out {m, b}` (`b` là byte CBOR của tin). Cửa sổ báo mình phục vụ AI bằng `ai.serve`; xin gửi thông báo bằng `ai.push`. Daemon chỉ chuyển tiếp những loại tin desktop → điện thoại, và bỏ tin quá một lô. **Không có cửa sổ phục vụ:** daemon tự trả lời: danh sách `available: false`, attach → `ai.closed {reason: unavailable}`, yêu cầu → `ai.result {code: unavailable}`. Cửa sổ thoát: mọi điện thoại đang xem danh sách nhận `available: false`, mọi phiên đang mở nhận `ai.closed {reason: desktop_closed}`. Cửa sổ mở lại: daemon hỏi lại danh sách giùm mọi điện thoại đang xem. | Một bước chuyển tiếp nữa (~1 ms qua socket nội bộ). |
| D2 | Hub ở cửa sổ | `AiPhoneHub` (thuần Dart, `shellx_agent`) đọc cửa sổ qua giao diện `AiSessionSource`: danh sách phiên, agent, thư mục, `control(paneId, start)` (lấy hoặc tạo runtime), `open(agent, folder)`, `seenOnDesktop(paneId)`, ngưỡng "lệnh chạy lâu". Desktop cài `DesktopAiSource` trên danh sách tab và `AiRuntimes` của V2-1b. Không đổi `AiRuntime` hay mô hình. | Một lớp adapter ~200 dòng. |
| D3 | Giao thức và tương thích | Tin mới (§4.1): `ai.list`, `ai.list.result`, `ai.attach`, `ai.detach`, `ai.ack`, `ai.earlier`, `ai.snapshot`, `ai.update`, `ai.closed`, `ai.prompt`, `ai.answer`, `ai.cancel`, `ai.stop`, `ai.unqueue`, `ai.open`, `ai.result`. **Phong bì phẳng:** khoá `t`, `sid`, `rid`, `seq` và `body` là byte (JSON UTF-8), nên trên dây chỉ sâu 3 tầng và không có số thực. **Bỏ qua, không bao giờ làm rơi kênh:** một tin `ai.*` sai trường hoặc loại `ai.*` lạ được giải mã thành `null`. **Cờ khả năng:** `session.list.result` có thêm `ai: 1`, chỉ trả lời `session.list {desktop: true}` và chỉ khi tiến trình có endpoint AI. Điện thoại chỉ hiện AI khi thấy cờ này. Desktop không bao giờ gửi `ai.*` cho điện thoại chưa hỏi. | Một tầng giải mã JSON (rẻ). |
| D4 | Cỡ tin | Mỗi tin `ai.*` tự đủ và không chia byte: thân ≤ 48 KiB (`kAiMaxBodyBytes`), cả tin nằm trong một lô niêm phong. Chữ dài đi thành nhiều mẩu nối tiếp (`at` + `add`). Thẻ tool được cắt cho điện thoại: đầu ra giữ 4 KiB đầu và 4 KiB cuối theo dòng (bỏ mã màu); mỗi diff chỉ giữ vùng đổi và 3 dòng quanh nó, ≤ 4 KiB mỗi bên, tối đa 3 diff; input ≤ 2 KiB; form câu hỏi ≤ 16 KiB. Vẫn quá cỡ thì cắt mạnh hơn (½, ¼, ⅛); cuối cùng thành mục `big`, hiện "Quá lớn để xem trên điện thoại. Xem trên máy tính." Prompt từ điện thoại ≤ 32 KiB UTF-8. | Thẻ khổng lồ chỉ xem đủ trên máy tính. |
| D5 | Đồng bộ | **Desktop:** mỗi điện thoại mỗi phiên một `AiSubscription` nhớ đã gửi gì: `rev` theo chỉ số mục, độ dài chữ đã gửi, header đã gửi. **Bản chụp:** 60 mục cuối kèm header; "Tải thêm" lấy 60 mục trước đó mỗi lần. **Cập nhật:** chỉ mục mới hoặc có `rev` khác; chữ đang stream chỉ gửi phần nối thêm; header gửi khi đổi. **Nhịp:** ≤ 1 lần mỗi 100 ms mỗi phiên, lần đầu sau lúc rảnh đi ngay. **Cửa sổ gửi:** ≤ 256 KiB chưa ack mỗi phiên mỗi điện thoại; điện thoại ack cộng dồn, gộp ≤ 1 ack mỗi 50 ms. **Nối lại:** điện thoại gửi kèm `ai.attach` thứ mình đang giữ (`AiHave`: thế hệ, chỉ số đầu, danh sách `rev`); desktop chỉ gửi mục khác. Khác thế hệ (runtime mới), giữ quá ít, hoặc thiếu quá 120 mục mới thì gửi lại từ đầu. **Phát hiện hở:** mẩu chữ không nối tiếp, hoặc mục nằm sau cuối → điện thoại attach lại. | Một lần attach lại sau chỗ hở thì gửi lại các mục đã đổi. |
| D6 | Mục trên điện thoại | Điện thoại không dựng lại `TimelineItem` của desktop. Nó giữ **mục gương** (`MirrorText`, `MirrorTool`, `MirrorAsk`, `MirrorTurnEnd`, `MirrorNotice`, `MirrorUnknown`) trong `AiMirror` của `package:shellx_ai/remote.dart`, được dựng từ cùng một timeline: cùng loại và trạng thái, nội dung đã cắt (D4), bỏ phần chỉ desktop cần (điểm khôi phục, `rawOutput`, lệnh đăng nhập). Câu hỏi đi nguyên dạng ACP, nên điện thoại đọc bằng `ElicitationRequest.fromJson` và kiểm câu trả lời bằng cùng `accepts` như desktop. Diff trên điện thoại: dòng chung đầu và cuối là ngữ cảnh, giữa là − rồi +. | ~7 lớp nhỏ, ghim bằng test round-trip. |
| D7 | Yêu cầu từ điện thoại | Chỉ những việc người dùng bấm: gửi tin, trả lời xin quyền (`permission` + `option`), trả lời câu hỏi (`accept` + nội dung / `decline` / `cancel`), dừng, dừng hẳn, bỏ tin đang xếp hàng, mở phiên mới, tải thêm. Desktop kiểm từng cái **với thứ đang chờ lúc đó:** id xin quyền phải đang chờ và lựa chọn phải thuộc yêu cầu đó, nếu không trả `stale` hoặc `refused`; câu trả lời form phải qua `form.accepts`; "dừng hẳn" chỉ khi desktop đã cho phép; prompt rỗng hoặc quá 32 KiB bị từ chối. Mỗi yêu cầu có `rid` và đúng một `ai.result`. Mỗi điện thoại được 60 yêu cầu dồn, rồi 30 mỗi giây (không tính ack, detach); vượt thì `busy`. | — |
| D8 | Hiển thị | Màn phiên là một trang riêng (`AiSessionRoute`) chồng trên trang máy, hoặc trên danh sách máy khi mở từ thông báo; không phải một tab trong dải tab terminal. **Danh sách hội thoại:** ảo hoá bằng `CustomScrollView` có `center`, nên nội dung mới ở dưới hay trang cũ ở trên đều không đẩy chỗ đang đọc; mỗi mục khoá theo `(chỉ số, rev)`; chỉ bám đáy khi người dùng đang ở đáy, nếu không có nút "Mới nhất". **Markdown:** `flutter_markdown_plus 1.0.12` (cùng bản desktop), chia khối nên khi stream chỉ khối cuối dựng lại; không bao giờ tải ảnh (hiện chữ alt); link chỉ mở khi chạm và chỉ http/https. | Tab AI không nằm cạnh tab terminal; tới bằng nút ✦ hoặc bộ chọn. |
| D9 | Phiên mới từ điện thoại | Chỉ với agent máy tính báo sẵn sàng (chưa biết thì coi là sẵn sàng, như V2-1b) và một **thư mục do máy tính đưa ra:** gốc dự án của các workspace cục bộ, cộng thư mục của các tab AI đang mở. Điện thoại gửi khoá (`ws:<id>` hoặc `path:<thư mục>`), không bao giờ gửi đường dẫn tự gõ. Tab AI mới vào đúng workspace, **không được chọn** trên desktop, và agent chạy ngay. Cấu hình nhớ theo agent được dùng như desktop, không bao giờ áp lại "Bỏ qua mọi quyền" (V2-1a R6). | Dự án chưa thuộc workspace nào phải đặt gốc trên máy tính trước. |
| D10 | Lối vào trên điện thoại | **Bộ chọn phiên** (nút `+` và lần đầu vào máy) có nhóm "Phiên AI" đứng đầu, rồi "Phiên AI mới". **Thanh trên** của trang máy có nút ✦ kèm số phiên đang chờ; chạm mở bộ chọn. **Thông báo** mở thẳng phiên. Danh sách máy giữ nguyên. Máy có AI thì luôn hiện bộ chọn khi vào lần đầu, kể cả khi chưa có phiên terminal. | Trên danh sách máy không thấy phiên AI; thông báo bù vào. |
| D11 | Thông báo | Desktop xin đẩy khi một phiên **bắt đầu cần trả lời** (một yêu cầu xin quyền hay câu hỏi mới thành yêu cầu hiện tại), và khi **một lượt dài kết thúc** (≥ ngưỡng "lệnh chạy lâu" của A4, mặc định 30 s, không tính lượt bị dừng). **Không đẩy** khi có điện thoại đang mở phiên đó, hoặc cửa sổ đang active và pane đó đang focus. "Cần trả lời" ≤ 1 lần mỗi phiên mỗi 30 s; chung giới hạn 6/phút mỗi máy của N10. **Nội dung:** tiêu đề "<máy> · <agent>"; thân "Cần bạn trả lời: <việc>" hoặc "Xong lượt N · <thời gian>"; `data` = `{kind: ai, ai_session: <sid>}`. Tên việc đi dạng rõ qua relay/FCM như dòng lệnh của N3. Điện thoại chỉ đang xem danh sách thì vẫn nhận, và banner đẩy sẵn có hiện nó trong app. Điện thoại cũ chạm vào thì mở trang máy (không có `session_id`). Trả lời ngay trên thông báo: V2-2b (§11.2). | Hai chạm thay vì một khi điện thoại khoá. |
| D12 | Riêng tư và log | Nội dung (prompt, chữ agent, diff, đầu ra, đường dẫn) chỉ đi trong kênh mã hoá đầu cuối, ngoại lệ duy nhất là thân thông báo (D11, N3). Không log nội dung ở đâu cả: `toString()` của mọi tin `ai.*`, mục gương, header, listing, subscription và yêu cầu đẩy trả `'…'` hoặc `Tên(…)`, có test ghim. Daemon chỉ chuyển byte, không đọc thân. | — |
| D13 | Không bao giờ tự cho phép | Điện thoại không có đường nào trả lời mà không có một lần chạm, không có "nhớ lựa chọn", không gửi lại câu trả lời sau khi mất kết nối. V2-2 **không có** tin đổi chế độ hay model, nên "Bỏ qua mọi quyền" không thể bật từ điện thoại. Chế độ hiện tại chỉ hiện để đọc ("Hỏi trước", "Tự sửa tệp"…). | Muốn đổi chế độ phải làm trên máy tính. |
| D14 | Một phiên không chạy được | Tab AI chưa có thư mục, hoặc agent đã tắt/xoá trong Cài đặt: danh sách ghi "Chọn thư mục trên máy tính" / "Agent đang tắt trên máy tính"; mở ra thì thấy đúng câu đó, không có ô nhập. | — |
| D15 | Tab khôi phục chưa chạy | Điện thoại mở một tab AI vừa khôi phục mà agent chưa chạy thì agent chạy và `session/load` phát lại lịch sử, như khi người dùng nhìn tab đó trên desktop (V2-1b B11). | Một agent chạy khi người dùng chỉ nhìn trên điện thoại. |
| D16 | Sau khi desktop khởi động lại | sid có epoch nên sid cũ thành "gone": màn phiên ghi "Phiên AI này đã đóng trên máy tính.", người dùng quay lại danh sách. Listing có sẵn `acp` (id phiên của agent) để V2-2b tự nối lại đúng phiên. | Một chạm về danh sách sau khi desktop khởi động lại. |

---

## 4. Giao thức

### 4.1 Tin `ai.*`

Mọi khoá snake_case. `sid` là chuỗi; `rid` do điện thoại đặt; `seq` tăng 1 cho mỗi tin `ai.snapshot`/`ai.update` của một điện thoại một phiên; `body` là byte JSON UTF-8.

| `t` | Chiều | Trường | Ý nghĩa |
|---|---|---|---|
| `ai.list` | ĐT → DT | — | Xin danh sách và nhận mỗi lần nó đổi, tới khi kênh rơi |
| `ai.list.result` | DT → ĐT | `available`, `body` | Danh sách (§4.3); `available: false` khi không có cửa sổ phục vụ AI |
| `ai.attach` | ĐT → DT | `sid`, `body?` | Mở gương; `body` là `AiHave` |
| `ai.detach` | ĐT → DT | `sid` | Đóng gương |
| `ai.ack` | ĐT → DT | `sid`, `seq` | Đã nhận tới `seq` (cộng dồn) |
| `ai.earlier` | ĐT → DT | `sid`, `before` | Trang mục trước chỉ số `before` |
| `ai.snapshot` | DT → ĐT | `sid`, `seq`, `body` | Tin đầu sau attach |
| `ai.update` | DT → ĐT | `sid`, `seq`, `body` | Thay đổi, phần tiếp, hoặc trang cũ (`older`) |
| `ai.closed` | DT → ĐT | `sid`, `reason` | `gone`, `desktop_closed`, `unavailable` (hoặc từ mới hơn) |
| `ai.prompt` | ĐT → DT | `sid`, `rid`, `text` | Gửi hoặc xếp hàng |
| `ai.answer` | ĐT → DT | `sid`, `rid`, `permission?`+`option?` hoặc `ask?`+`action?`+`body?` | Trả lời xin quyền / câu hỏi |
| `ai.cancel` | ĐT → DT | `sid`, `rid` | Dừng lượt |
| `ai.stop` | ĐT → DT | `sid`, `rid` | Dừng hẳn |
| `ai.unqueue` | ĐT → DT | `sid`, `rid`, `queued` | Bỏ một tin đang xếp hàng |
| `ai.open` | ĐT → DT | `rid`, `agent`, `folder` | Phiên mới (khoá thư mục từ danh sách) |
| `ai.result` | DT → ĐT | `rid`, `ok`, `code?`, `sid?` | Kết quả; `code`: `stale`, `refused`, `queue_full`, `too_large`, `busy`, `not_found`, `unavailable` |

`session.list.result` có thêm `ai: 1` (D3).

### 4.2 Thân gương (`ai.snapshot`, `ai.update`)

```json
{"v": 1, "n": 245, "g": 7, "from": 185, "reset": true, "more": true,
 "head": {…}, "items": [{…}, …]}
```
- `n`: số mục trên desktop; `g`, `from`, `reset`, `more` chỉ có ở bản chụp; `older: true` đánh dấu trang cũ.
- Mục chung: `i` (chỉ số), `r` (rev), `k` (loại), `turn`.
- **Chữ** (`user`, `agent`, `thought`): `at` (vị trí bắt đầu, tính theo đơn vị UTF-16), `add` (phần chữ); `clip` là độ dài đầy đủ khi trang cũ chỉ mang phần đầu.
- **Tool** (`tool`):
  - `id`, `tk` (kind ACP), `title`, `st` (status ACP), `end` (`completed`/`failed`/`stopped`), `t0`, `t1`;
  - `perm` (`waiting`/`answered`/`cancelled`), `ans` (`kind`, `name`);
  - `loc` (≤ 5), `out` (`head`, `tail`, `lines`, `cut`);
  - `diffs` (≤ 3: `path`, `old`, `new`, `created`, `plus`, `minus`, `cut`), `more_diffs`;
  - `input` (chuỗi JSON ≤ 2 KiB, chỉ cho kind `other`).
- **Câu hỏi** (`ask`): `id`, `st` (`open`/`accepted`/`declined`/`cancelled`/`auto_declined`/`completed`), `req` (params `elicitation/create` của ACP) hoặc `big`.
- **Hết lượt** (`end`): `outcome`, `ms`, `stop`, `error`, `files`, `plus`, `minus`.
- **Thông báo** (`notice`): `n` = `{k: login|node|not_installed|missing|exited|invalid|start_failed|cannot_resume|folder_missing|undo_off, …}`, `resolved`.
- **Quá lớn** (`big`): chỉ có phần chung.

### 4.3 Danh sách

```json
{"v": 1,
 "sessions": [{"sid": "k3f9za.-12", "agent": "claude", "name": "Claude", "title": "Nút đăng xuất",
               "state": "needs_input", "cwd": "/Users/me/shop-web", "since": 1790000000000,
               "waiting": "Sửa src/main.ts", "acp": "sess_…"}],
 "agents": [{"id": "claude", "name": "Claude", "ready": true}],
 "folders": [{"key": "ws:abc", "name": "shop-web", "path": "/Users/me/shop-web"}],
 "default_agent": "claude"}
```
`state`: `running`, `needs_input`, `idle`, `starting`, `stopped`, `needs_auth`, `failed`, `no_folder`, `agent_off`. Từ lạ đọc thành `idle`.

### 4.4 `AiHave` (thân của `ai.attach`)

`{"g": 7, "from": 185, "revs": [3, 1, 12, …]}`: thế hệ, chỉ số đầu, rev của từng mục đang giữ.

### 4.5 Header (`head`)

`phase`, `title`, `agent`, `name`, `cwd`, `turn` (`n`, `t0`, `stopping`, `force`), `perm` (`id`, `item`, `title`, `options[{id, name, kind}]`, `more`), `ask` (`id`, `item`, `more`), `queue[{id, text}]`, `usage` (`used`, `size`), `plan[{text, st}]` (≤ 30), `mode` (`id`, `name`), `unavailable` (`no_folder`/`agent_off`).

### 4.6 Mux (cửa sổ ↔ dịch vụ nền)

`ai.in {m, b}` (daemon → cửa sổ), `ai.gone {m?}` (điện thoại rời; không có `m` là tất cả), `ai.out {m, b}`, `ai.serve {}`, `ai.push {kind, name, sid, detail?, turn?, ms?}` (cửa sổ → daemon). Không tin nào có `q`.

---

## 5. Giao diện điện thoại

Màu, cỡ chữ, khoảng cách theo token mobile (`context.colors`, `context.typo`). Không có hoạt ảnh lặp, trừ vòng xoay lúc đang tải.

### 5.1 Danh sách và lối vào

- **Bộ chọn phiên:**
  - tiêu đề đếm cả phiên AI;
  - nhóm "PHIÊN AI" đứng đầu. Mỗi hàng gồm: biểu tượng ✦ (màu cảnh báo khi chờ), tiêu đề (rỗng thì "Phiên AI mới"), dòng "Claude · Cần bạn trả lời" (màu cảnh báo), dòng việc đang chờ, chữ "Mở";
  - cuối nhóm là "＋ Phiên AI mới" khi có agent sẵn sàng và thư mục; nếu không thì một dòng gợi ý (§5.5).
- **Gợi ý thay cho nhóm:** desktop cũ thì "Cập nhật ShellX trên máy tính để dùng phiên AI từ điện thoại."; không có cửa sổ phục vụ thì "Mở ShellX trên máy tính để dùng phiên AI.".
- **Nút ✦ trên thanh trang máy:** chỉ hiện khi đã có danh sách. Có huy hiệu vàng đếm số phiên đang chờ; chạm mở bộ chọn.
- **Sheet "Phiên AI mới":** danh sách agent (agent chưa sẵn sàng thì mờ, ghi "cài trên máy tính"), danh sách thư mục (tên và đường dẫn), nút "Bắt đầu".

### 5.2 Màn phiên

- **Đầu trang:**
  - nút quay lại;
  - tiêu đề phiên (rỗng thì "Phiên AI mới");
  - dòng trạng thái: chấm màu, rồi "Claude · Đang chạy · 0:12 · Hỏi trước · Ngữ cảnh 16%". Đồng hồ nhảy mỗi giây chỉ khi đang có lượt.
- **Dải thông báo:**
  - mất relay: banner kết nối sẵn có;
  - không với tới máy tính (máy tắt, ShellX không chạy): "Máy tính đang offline. Hãy mở ShellX trên máy tính rồi thử lại." (chuỗi sẵn có `errorAgentOffline`), thay cho vòng xoay;
  - đang nối lại mà vẫn có nội dung: "Đang kết nối lại… nội dung có thể chưa mới nhất.";
  - phiên đã đóng: §5.5.
- **Hội thoại** (D8):
  - tin của người dùng là bong bóng bên phải;
  - chữ agent là markdown chọn chép được;
  - suy nghĩ là dòng "Suy nghĩ" gập sẵn;
  - thẻ tool: biểu tượng theo kind, một dòng chữ theo V2-1 §4.2 ("Đọc main.ts", "Sửa main.ts", "Tạo …", "Chạy npm test"…), trạng thái ("chờ", "chờ bạn", "đang chạy · 2,1 s", ✓, "bị từ chối", "đã dừng", "lỗi"). Chạm mở diff (−/+ đơn sắc, cuộn ngang), đầu ra (đầu… "N dòng; phần giữa xem trên máy tính" …cuối) hoặc input. Thẻ đang chờ quyền tự mở. Đã trả lời thì có dòng "Bạn chọn: Cho phép (Yes)";
  - câu hỏi là thẻ ghi trạng thái;
  - cuối lượt là dòng "Lượt 3 · 0:41 · 2 tệp đổi +44 −5";
  - thông báo là thẻ (§5.5);
  - mục quá lớn: "Quá lớn để xem trên điện thoại. Xem trên máy tính.";
  - phía trên cùng: "Tải thêm".
- **Dock** (từ trên xuống):
  1. kế hoạch một dòng "Kế hoạch · 2/5", chạm để mở;
  2. bảng xin quyền (§5.3), hoặc bảng câu hỏi (§5.4);
  3. hàng đợi: mỗi tin một dòng, có nút ×;
  4. ô nhập (tự giãn tới 6 dòng), nút Gửi; đang có lượt thì nút thành "Xếp hàng"; ô trống mà đang có lượt thì thành nút Dừng (■, sau khi bấm có vòng xoay); "Dừng hẳn" (đỏ) khi desktop cho phép.

### 5.3 Bảng xin quyền

- **Khung:** nền `warnSoft`, viền `warn`, dòng đầu "Claude xin quyền:", tiêu đề việc in đậm (≤ 3 dòng), "còn N yêu cầu" nếu có.
- **Nút:** mỗi lựa chọn một nút cao ≥ 52 pt. `allow_once` "Cho phép" nền chính; `allow_always` "Luôn cho phép" kèm chữ gốc của agent; `reject_*` viền đỏ. Rung nhẹ khi chạm; chờ (mờ) cho tới khi desktop xác nhận.
- **"Xem chi tiết":** cuộn tới thẻ tool (diff).
- **Trợ năng:** `Semantics(liveRegion)` đọc khi bảng hiện.

### 5.4 Bảng câu hỏi

Các trường: chuỗi, số, bật/tắt, chọn một (radio), chọn nhiều (checkbox). "Gửi câu trả lời" chỉ bấm được khi form hợp lệ; "Từ chối" luôn bấm được. Câu hỏi URL, hoặc form quá lớn: "Trả lời câu hỏi này trên máy tính.", vẫn từ chối được.

### 5.5 Câu chữ (EN / VI)

| Khoá | EN | VI |
|---|---|---|
| `aiGroup` | AI sessions | Phiên AI |
| `aiNewSession` / `aiUntitled` | New AI session | Phiên AI mới |
| `aiStateRunning` / `NeedsInput` / `Idle` / `Starting` / `Stopped` | Running / Needs your answer / Waiting / Starting / Not started | Đang chạy / Cần bạn trả lời / Đang chờ / Đang khởi động / Chưa chạy |
| `aiStateNeedsAuth` / `Failed` / `NoFolder` / `AgentOff` | Sign in on the computer / Error / Choose a folder on the computer / Agent off on the computer | Cần đăng nhập trên máy tính / Lỗi / Chọn thư mục trên máy tính / Agent đang tắt trên máy tính |
| `aiUnavailable` | Open ShellX on the computer to use AI sessions. | Mở ShellX trên máy tính để dùng phiên AI. |
| `aiUpdateDesktop` | Update ShellX on the computer to use AI sessions from your phone. | Cập nhật ShellX trên máy tính để dùng phiên AI từ điện thoại. |
| `aiComposerHint` | Message {agent}… | Nhắn cho {agent}… |
| `aiSend` / `aiQueue` / `aiStop` / `aiStopping` / `aiForceStop` | Send / Queue / Stop / Stopping… / Force stop | Gửi / Xếp hàng / Dừng / Đang dừng… / Dừng hẳn |
| `aiReconnecting` | Reconnecting… what you see may be behind. | Đang kết nối lại… nội dung có thể chưa mới nhất. |
| `aiClosedGone` / `aiClosedDesktop` | This AI session was closed on the computer. / ShellX was closed on the computer. Open it to continue. | Phiên AI này đã đóng trên máy tính. / ShellX trên máy tính đã thoát. Mở lại để tiếp tục. |
| `aiPermTitle` | {agent} asks: | {agent} xin quyền: |
| `aiPermAllowOnce` / `AllowAlways` / `RejectOnce` / `RejectAlways` | Allow / Always allow / Reject / Always reject | Cho phép / Luôn cho phép / Từ chối / Luôn từ chối |
| `aiAnsweredElsewhere` | Already answered on another device. | Đã được trả lời ở thiết bị khác. |
| `aiYouChose` | You chose: {option} | Bạn chọn: {option} |
| `aiAskOnComputer` | Answer this question on the computer. | Trả lời câu hỏi này trên máy tính. |
| `aiTurnSummary` / `aiTurnFiles` | Turn {n} · {time} / {count} files changed | Lượt {n} · {time} / {count} tệp đổi |
| `aiFromComputerOnly` | Too large for the phone. Open it on the computer. | Quá lớn để xem trên điện thoại. Xem trên máy tính. |
| `aiTooLong` | Too long to send from the phone ({max} KB at most). | Quá dài để gửi từ điện thoại (tối đa {max} KB). |
| `aiModeDefault` / `AcceptEdits` / `Plan` / `Auto` / `Bypass` | Ask first / Edit files / Plan / Auto / Bypass permissions | Hỏi trước / Tự sửa tệp / Lập kế hoạch / Tự động / Bỏ qua mọi quyền |
| Thân thông báo (desktop, `NotificationText`) | Needs your answer: {việc} / Finished turn {n} · {time} | Cần bạn trả lời: {việc} / Xong lượt {n} · {time} |

Danh sách đủ (khoảng 100 khoá) nằm trong Task 8 của plan. Chữ thẻ thông báo theo V2-1 §4.5: "Claude cần đăng nhập, trên máy tính.", "Claude dừng bất ngờ (mã thoát 1)."…

---

## 6. Riêng tư, an ninh và log

- **Ai được nói:** chỉ điện thoại đã ghép đôi và được tin (kênh IK hiện có). Kênh ghép đôi (IKpsk2) chỉ mang một tin `pair.confirm`, không tới router.
- **Ý chí người dùng:** D7, D13. Desktop kiểm mọi câu trả lời với yêu cầu đang chờ lúc đó. Điện thoại không gửi lại câu trả lời sau khi mất kết nối: yêu cầu đó thất bại và người dùng thấy trạng thái mới.
- **Nội dung:** chỉ trong kênh mã hoá đầu cuối. Thân thông báo (D11) là ngoại lệ đã có từ N3. Daemon chỉ chuyển byte.
- **Log:** không log nội dung (D12). Các dòng log mới chỉ ghi kiểu lỗi (`error.runtimeType`).
- **Giới hạn:** nhịp và cửa sổ (D5), cỡ (D4), ngân sách yêu cầu (D7). Nhờ vậy desktop không vượt 500 khung/giây của relay và không làm đầy 4 MiB của một điện thoại chậm.
- **Thư mục:** điện thoại chỉ chọn trong danh sách desktop đưa ra (D9).

---

## 7. Lỗi và biên

| Tình huống | Xử lý |
|---|---|
| Tin `ai.*` sai hoặc loại lạ | Bỏ qua (D3); kênh và terminal không bị ảnh hưởng |
| Thân không đọc được, hoặc gương có chỗ hở | Điện thoại attach lại với `AiHave` |
| Máy tính offline khi mở phiên | Dải "Máy tính đang offline…" thay cho vòng xoay; relay/máy online lại thì tự bắt tay và attach |
| Điện thoại mất mạng, app vào nền | Kênh rơi; hub quên điện thoại đó (thông báo đẩy chạy lại); gương giữ nội dung; kênh mới thì gửi lại `ai.list` và attach mọi phiên đang mở |
| Một điện thoại chậm | Cửa sổ gửi đầy thì thôi gửi; ack tới thì gửi một bản gộp các thay đổi mới nhất, không gửi lại cả hàng đợi |
| Desktop khởi động lại | Epoch mới; sid cũ thành `gone` (D16) |
| Runtime của pane đổi (chọn thư mục khác trên desktop) | Thế hệ mới; điện thoại nhận bản chụp `reset` |
| Tab AI đóng trên desktop | Điện thoại đang mở nhận `ai.closed {gone}` |
| Cửa sổ thoát, dịch vụ nền còn chạy | D1: `available: false` và `desktop_closed`; cửa sổ mở lại thì danh sách tự về |
| Desktop không có endpoint AI (bản cũ) | Không có `ai` trong `session.list.result`; điện thoại không gửi gì (nếu vẫn gửi thì bị bỏ qua và yêu cầu hết giờ, kênh vẫn còn) |
| Cửa sổ mới, daemon cũ | Daemon bỏ qua `ai.serve`/`ai.out`; điện thoại không thấy cờ `ai` (router cũ) |
| Daemon mới, cửa sổ cũ | Không có `ai.serve`; điện thoại nhận "Mở ShellX trên máy tính…" |
| Hai điện thoại cùng mở một phiên | Mỗi chiếc một subscription; trả lời tới trước thắng (D7) |
| Trả lời khi lượt vừa bị dừng | `stale` → "Đã được trả lời ở thiết bị khác." chỉ với câu trả lời; dừng muộn thì im lặng |
| Hàng đợi đã đủ 5 | `queue_full` → "Đã có 5 tin đang chờ."; chữ giữ trong ô |
| Prompt > 32 KiB | Từ chối ngay trên điện thoại; desktop cũng kiểm lại |
| Một phiên không chạy được | D14 |
| Phiên AI mới thất bại (agent, thư mục không còn) | `refused`, có toast; trang máy không đổi |

---

## 8. Kiểm thử

- **`shellx_core`:**
  - map chính xác và round-trip của mọi tin `ai.*`;
  - `toString` không lộ gì;
  - tin sai hoặc loại lạ bị bỏ qua;
  - thân lồng 40 tầng vẫn đi được;
  - thân lớn nhất vừa một lô;
  - cờ `ai`;
  - **tương thích:** bộ giải mã đóng băng tại `5e04dc8` (điện thoại cũ, desktop cũ) đọc lô có tin `ai.*` mà không lỗi, và đọc `session.list.result` có `ai` như trước.
- **`shellx_ai` remote:**
  - cắt UTF-8 và dòng; bỏ mã màu;
  - listing round-trip;
  - câu hỏi round-trip qua `ElicitationRequest.fromJson`;
  - đầu ra dài, vùng diff, tệp mới, mục quá lớn;
  - bản chụp, stream nối chữ, attach lại chỉ gửi phần đổi, thế hệ khác thì làm lại từ đầu;
  - câu trả lời dài 200 KB đi thành nhiều mẩu trong cửa sổ gửi;
  - "Tải thêm" tới mục 0; phát hiện hở; `toString`.
- **`shellx_agent`:**
  - router: cờ `ai`, chuyển tin, báo điện thoại rời;
  - slot: trả "unavailable" khi chưa có hub;
  - hub: danh sách gộp nhịp, attach khởi động agent, stream gộp ≤ 10 Hz, cửa sổ gửi/ack, phiên lạ hoặc của lần chạy khác, phiên không chạy được, tab đóng;
  - yêu cầu: prompt (rỗng, quá cỡ, hàng đợi đầy), xin quyền (sai id, sai lựa chọn, không bao giờ tự trả lời, máy thứ hai thì `stale`), câu hỏi, dừng và dừng hẳn, mở phiên, ngân sách `busy`;
  - thông báo: chỉ khi không ai đang xem, 30 s, lượt dài, round-trip `ai.push`;
  - mux: forwarder (không có cửa sổ, phục vụ, thoát, phục vụ lại), binding, máy chủ mux thật; daemon cũ bỏ qua;
  - chữ và `data` của thông báo.
- **`shellx_client` (đầu cuối qua relay giả và kênh mã hoá thật):**
  - danh sách, attach, stream, prompt, trả lời; máy thứ hai thì `stale`;
  - mất kênh rồi nối lại chỉ với phần đổi;
  - **tương thích:** điện thoại mới với desktop cũ; điện thoại cũ với desktop mới.
- **Desktop:**
  - slot của `SessionCore`;
  - (sau V2-1b) tab là danh sách; attach khởi động tab khôi phục; prompt và trả lời xin quyền tới agent giả; thông báo bị chặn khi cửa sổ đang hiện pane; phiên mới từ điện thoại vào đúng workspace và không được chọn.
- **Mobile:**
  - dòng diff, khối markdown;
  - màn phiên: hội thoại và trạng thái, ảnh markdown không tải, bảng xin quyền (thứ tự, một chạm một lần, không tự trả lời), trả lời ở máy khác, gửi/xếp hàng/dừng/lỗi, form câu hỏi, đóng và nối lại, máy tính offline (không vòng xoay), phiên không chạy được (không có ô nhập), "Tải thêm", detach khi rời;
  - lối vào: nhóm AI trong bộ chọn, gợi ý desktop cũ, phiên mới, nút ✦ có số;
  - mở từ thông báo;
  - chuỗi EN/VI cùng khoá.

---

## 9. Review Focus

1. **Một tin làm rơi kênh:** thân quá một lô, quá sâu, hoặc có số thực, làm rơi cả terminal trên cùng kênh. Ghim bằng test "largest body fits", "depth", "malformed skipped", "big stub", "oversized ai.out dropped".
2. **Câu trả lời rơi nhầm yêu cầu:** máy kia đã trả lời, hoặc yêu cầu bị huỷ rồi một yêu cầu mới tới. Ghim bằng test "must name the pending request", "answered on another device".
3. **Tự cho phép:** phải không có đường nào trả lời mà không có một lần chạm, và không có đường bật bypass. Ghim bằng test "nothing is ever answered without a tap/one" và grep ở bước cuối.
4. **Lệch gương sau khi hở hoặc nối lại.** Ghim bằng test "a missing body is found", "re-attach brings only what changed", "another generation starts over", "a lost channel resumes".
5. **Bản cũ.** Ghim bằng bộ giải mã đóng băng, test tương thích hai chiều của client, và test "an older service ignores".

---

## 10. ⚠ Kiểm tay (cần người, iPhone/Android thật và máy Mac)

- Claude thật trên desktop (V2-1b xong) với điện thoại thật qua relay thật:
  - mở phiên, stream, xin quyền, trả lời trên điện thoại;
  - desktop hiện "Bạn chọn…".
- Khoá màn hình điện thoại khi agent xin quyền:
  - thông báo tới trong ≤ 5 s;
  - chạm mở thẳng phiên;
  - trả lời được.
- Bật dịch vụ nền; thoát cửa sổ rồi mở lại.
- Tắt Wi-Fi giữa lúc stream rồi bật lại: không mất chữ, không nhảy.
- Phiên rất dài (khoảng 500 mục): mở nhanh; "Tải thêm" mượt.
- VoiceOver/TalkBack đọc bảng xin quyền.
- Gõ tiếng Việt (Telex) trong ô nhập.

---

## 11. Phạm vi

### 11.1 V2-2a — tối nay

- Mọi thứ ở §3–§8.
- Lối vào: bộ chọn phiên, nút ✦, thông báo.
- Phiên mới từ điện thoại.
- Đường dịch vụ nền.
- Test tương thích hai chiều.
- Phần desktop cần V2-1b (Task 11 của plan) chạy khi V2-1b Task 3, 10, 11, 17 đã vào `shellx-v2`. Các task còn lại làm được ngay.

### 11.2 V2-2b — sau

| Việc | Cần gì | Vì sao chưa làm tối nay |
|---|---|---|
| Trả lời xin quyền ngay trên thông báo đẩy | Relay: `/v1/notifications` nhận `category` cho iOS (`apns.aps.category`) và tin chỉ-data cho Android. App: đăng ký category và action (`flutter_local_notifications` hoặc mã native). Data mang `permission` và id các lựa chọn. Bấm action thì app mở ở nền (iOS cho khoảng 30 s), bắt tay kênh, gửi `ai.answer` khi id vẫn đang chờ; không còn chờ thì báo, không tự trả lời cái khác. | Phải triển khai relay (VPS), thêm plugin native, lo việc chạy nền và relay coi kết nối thứ hai là `replaced`. Rủi ro cao khi không có người kiểm. |
| Đổi chế độ, model từ điện thoại | Tin `ai.config` với danh sách cho phép (không bao giờ `bypassPermissions`) | D13 |
| Ảnh, tệp đính kèm, giọng nói ShellX trong ô nhập | Chia ảnh thành nhiều tin; nối `VoiceComposer` | Bàn phím hệ thống đã có đọc chính tả |
| Hoàn tác lượt, panel Thay đổi trên điện thoại | Thêm tin cho xem và hoàn tác | Thao tác phá huỷ; để trên máy tính |
| Xem đủ thẻ lớn ("Xem trên máy tính" → tải đủ) | Tin `ai.item` lấy một mục theo từng phần | Hiếm gặp |
| Lịch sử phiên (`session/list`), chọn thư mục cho tab chưa có thư mục | Tin mới | — |
| Phiên AI trên danh sách máy | Mở kênh tới mọi máy đang online | Tốn bắt tay; thông báo đã bù |
| Tự nối lại sau khi desktop khởi động lại | Dùng `acp` của listing (D16) | — |
| "Bạn · từ điện thoại" trên desktop | Thêm nguồn cho `UserItem` | Phải sửa mô hình V2-1a |

---

## 12. Rủi ro

| Rủi ro | Mức | Xử lý |
|---|---|---|
| V2-1b chưa xong tối nay: điện thoại chưa có gì để xem trên máy thật | Trung bình | Task 1–10 không phụ thuộc V2-1b và có test đầu cuối với hub thật trên trạng thái thật; Task 11 chạy khi V2-1b tới |
| Tên API V2-1b khi vào `shellx-v2` khác bản kế hoạch | Thấp–TB | Task 11 có danh sách Consumes; khác thì sửa lời gọi, ghi ledger |
| Thông báo đẩy mang tên việc dạng rõ | Thấp | Như N3; muốn kín thì đổi một chuỗi |
| Tin quá nhiều trên relay khi nhiều điện thoại mở nhiều phiên | Thấp | ≤ 10 Hz mỗi phiên mỗi điện thoại, cửa sổ 256 KiB, gộp lô 16 ms của `AgentChannel` |
| Markdown của agent rất dài làm chậm khi cuộn | Thấp | Chia khối, khối không đổi không dựng lại, danh sách ảo hoá |

---

## 13. Sửa đổi sau khi làm và review (2026-10-15, chế độ vắng mặt)

Các điểm dưới đây thay thế chữ tương ứng ở trên. Lý do và cái giá nếu sai có trong ledger `.superpowers/sdd/2026-10-14-v2-2-phone-ai/progress.md`.

- **D5, bắt kịp:** khi một điện thoại bị bỏ lại hơn 120 mục, desktop gửi bản chụp mới gồm 60 mục cuối, không gửi bù từng mục. Trong lúc agent đang khởi động, kể cả khi phát lại lịch sử bằng `session/load`, điện thoại chỉ nhận header; khi agent sẵn sàng, nó nhận bản chụp. Mở lại một phiên đã khôi phục vì thế chỉ tải 60 mục cuối.
- **D11, ai đang xem:** một điện thoại chỉ được tính là "đang mở phiên" với một yêu cầu khi nó đã ack phần thân mang yêu cầu đó. Điện thoại chưa ack sau 10 s thì không tính.
- **D11, rời đi:** nếu điện thoại rời đi (`phoneGone`) khi một yêu cầu đang chờ, và không còn ai xem, desktop đẩy ngay.
- **D11, bỏ đi khỏi bàn:** một yêu cầu chưa ai trả lời sau 60 s thì vẫn được đẩy, kể cả khi cửa sổ đang active và pane đang focus. Mỗi yêu cầu được đẩy nhiều nhất một lần.
- **D11, câu hỏi:** thông báo đẩy cho câu hỏi chỉ ghi "<agent> hỏi bạn", không chép nội dung câu hỏi. Thông báo xin quyền vẫn ghi tên việc (N3). Tin `ai.push` (§4.6) có thêm khoá `question` (tuỳ chọn); peer cũ bỏ qua khoá này.
- **D13, §4.1:** `ai.result` có thêm mã `on_computer`. Điện thoại chọn một tuỳ chọn bật chế độ không cần duyệt (ví dụ "bypass permissions") thì bị từ chối, và yêu cầu vẫn mở trên máy tính. Điện thoại chỉ ra chữ "Trả lời yêu cầu này trên máy tính".
- **D15:** khi điện thoại attach, desktop chỉ khởi động runtime chưa từng mở phiên. Điện thoại đang mở trang của một phiên chưa chạy được (agent tắt, chưa có thư mục) cũng được tính là đang attach: khi lý do đó hết (bật lại agent, chọn thư mục), phiên tự khởi động. Runtime đã dừng (kể cả dừng hẳn) không tự chạy lại, và tin đang xếp hàng của nó không tự gửi.
- **§7, khi dịch vụ nền khởi động lại:** sau `ai.closed {unavailable}`, điện thoại tự attach lại một lần khi danh sách báo phiên đó có lại.
- **§5.3, chống chạm nhầm:** bảng xin quyền và bảng câu hỏi bỏ qua chạm trong 400 ms sau khi một yêu cầu mới hiện ra (kể cả khi yêu cầu thay đổi tại chỗ). Nút Dừng thay chỗ nút Gửi cũng vậy.
