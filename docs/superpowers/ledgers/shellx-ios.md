# Sổ quyết định ShellX iOS

Sổ ghi quyết định cho dự án app iOS và ShellX Link. Các task sau ghi tiếp vào đây.

## Giấy phép (2026-10-22)

- `cmux-tui/Cargo.toml:60` ghi `license = "MIT"`, nhưng không có file LICENSE nào trong thư mục đó. `LICENSE` ở gốc repo (Manaflow GPL) nói cmux-tui theo "license that this file or their own notices state", tức là đang **mơ hồ**, phải hỏi Manaflow trước khi dựa vào nó.
- `ghostty/LICENSE` là MIT.
- `shellx-core` là GPL-3.0-or-later. Tác giả: Phu.le và "Richard". Không thấy code chép từ Manaflow. Người dùng phải xác nhận "Richard" là ai trước khi nhúng `shellx-core` vào app App Store.
- `shellx-link/` là gói MIT riêng, không phụ thuộc và không chép code từ `ios/`, `Packages/iOS/`, `Packages/Shared/`, `cmux-tui/`. Ranh giới được kiểm bằng `scripts/shellx/check-link-license.sh` (chạy trong `PackageBoundaryTests`).

## D-iOS-0 (2026-10-22): phiên riêng cho ShellX Link

ShellX Link dùng phiên Noise riêng trên `link_slot`. Lý do:

- `Service` là enum đóng (`cmux-remote-protocol/src/rpc.rs:120`), không thêm dịch vụ mới được mà không đổi giao thức cmux.
- Đăng ký lần hai trên cùng slot sẽ thay daemon đang chạy (`cmux-relay/src/relay.rs:684-730`).

## Spike P1 (2026-10-22): đo local

`shellx-link-probe` (`shellx-link/Sources/shellx-link-probe/main.swift`) đóng vai điện thoại: `keygen`, `snapshot`, `watch`, `approve`, `bench`. Nó nhận invite từ file (hoặc `-` là stdin), không bao giờ nhận trên dòng lệnh, và không in ticket, khoá riêng hay nội dung invite.

Môi trường, tất cả trên một Mac, loopback:

- Relay Node (`relay/`, đủ 7 migration, có `0007_link_slot.sql`) ở `127.0.0.1:8787`, DB tạm ngoài repo, `RELAY_V2_URL=ws://127.0.0.1:18790/v1/relay`.
- `cmux-relay serve` ở `127.0.0.1:18790`. Hai bên dùng chung một `CMUX_RELAY_HMAC_SECRET` sinh ngẫu nhiên, không ghi ra đâu.
- App tag `link` (build trên `cebb5e30f4`), chạy với `SHELLX_REMOTE_MACHINES=1`, `SHELLX_API_BASE=http://127.0.0.1:8787`, `CMUX_SOCKET_MODE=allowAll`. App tự đăng nhập qua `SHELLX_DEV_EMAIL`/`SHELLX_DEV_PASSWORD` vào một tài khoản dùng một lần, chỉ có trên relay local.

Các bước:

```bash
shellx-link-probe keygen --out phone.key            # in public key b64
CMUX_TAG=link scripts/cmux-debug-cli.sh rpc shellx.link.debug_invite \
  '{"client_key_b64":"<public key>"}' > invite.json # file 0600
shellx-link-probe watch --invite invite.json --key phone.key --seconds 600
shellx-link-probe approve <request_id> --invite invite.json --key phone.key
shellx-link-probe bench --count 50 --invite invite.json --key phone.key \
  --socket /tmp/shellx-debug-link.sock
```

### Claude Code thật

Claude Code 2.1.308 chạy trong app `link`, trong một repo git dùng một lần dưới `/private/tmp`, với `--permission-mode default`. Yêu cầu là chạy `git status && touch spike-ok.txt`. Log của `watch`:

```
[+  0.018s] connected: circuit 14.1 ms, noise + hello/welcome 2.6 ms
[+  0.019s] snapshot revision=1 pending=0
[+ 34.697s] changed revision=2 added=1 resolved=[]
    pending EB082790-7EB2-4101-8755-4BCF125516B4 kind=permission agent=claude tool=Bash workspace="link-spike-claude" preview={"command":"toknix run -- 'git status && touch spike-ok.txt'","description":"Show working tree status, then create spike-ok.txt"}
[+ 52.279s] changed revision=3 added=0 resolved=["EB082790-7EB2-4101-8755-4BCF125516B4"]
```

`approve`, rồi gửi lại và gửi một id lạ:

```
reply EB082790-… mode=once outcome=delivered rtt=15.6 ms
reply EB082790-… mode=deny outcome=already_handled rtt=1.2 ms
reply never-seen-id mode=once outcome=unknown rtt=1.2 ms
```

Màn hình Claude sau `approve`: `⎿ Allowed by PermissionRequest hook`, `git status` in `nothing to commit, working tree clean`, và `spike-ok.txt` được tạo. Lệnh trong preview là lệnh đã qua PreToolUse hook của người dùng (`toknix run -- …`), tức là đúng lệnh sẽ chạy.

### Bench 50 yêu cầu

Probe tự gửi hook giả: một `feed.push` blocking `PermissionRequest` từ `claude`, giống payload `shellx hooks feed --source claude`, vào socket của app. Probe chờ thẻ trong `agent.changed`, trả `agent.reply` `once`, rồi kiểm tra hook giả nhận đúng `{"status":"resolved","decision":{"mode":"once"}}`. Mọi mốc thời gian đo trên một đồng hồ, trong một tiến trình. Hook giả không gửi `workspace_id`, `surface_id` hay `_ppid`, nên thẻ bench không gắn với workspace hay tiến trình nào. Vì vậy dòng "hook gửi → probe thấy `agent.changed`" dưới đây (con số "Mac đổi → client") chưa gồm bước tìm workspace của thẻ, và độ trễ của thẻ Claude thật ở trên không được đo.

| Đo (ms) | Lần 1 p50 / p95 / max | Lần 2 p50 / p95 / max |
| --- | --- | --- |
| hook gửi → probe thấy `agent.changed` | 10.1 / 12.9 / 14.3 | 10.6 / 13.1 / 14.6 |
| `agent.reply` → `agent.reply.result` (round trip) | 2.8 / 3.6 / 9.6 | 2.7 / 3.6 / 3.9 |
| gửi `agent.reply` → hook nhận quyết định | 2.8 / 5.1 / 8.1 | 2.9 / 5.7 / 7.2 |

Cả hai lần đều 50/50 ok, không có khoảng hở `revision`, hook nhận đúng `resolved/once` cả 50 lần. Mở phiên: circuit 8.7–20.8 ms, Noise + `hello`/`welcome` 2.6–4.5 ms.

Một phiên `watch` mở lúc đầu vẫn sống sau hơn 6 phút. Theo log mint ticket của relay, trong thời gian đó host đăng ký lại ít nhất ba lần (khoảng 120 s một lần), và connect ticket của phiên cũng đã hết hạn 120 s. Phiên vẫn nhận đủ 202 `agent.changed`: 2 cho thẻ Claude và 200 cho hai lần bench. Cùng lúc đó còn một `watch` khác và phiên bench chạy song song.

## D-iOS-1 (2026-10-22): kết luận spike P1

**Local: đạt cả hai mục tiêu.** WAN: **chưa đo**. Migration 0007 và vé `lane:"link"` đã lên `relay.shellx.pro` ngày 2026-10-22 (`527ea81e22`, workflow Deploy xanh, `/v1/version` 200, `/v2/relay/tickets` 401 khi chưa đăng nhập). Nhưng relay2 (`cmux-relay`) chưa bật trên VPS: `GET /v2/relay` vẫn do relay Node trả 404, và biến `RELAY2_ENABLED` chưa đặt. Người dùng quyết định ngày 2026-10-22: đóng P1 với số đo local, bật relay2 rồi đo WAN ở bước đầu của P2. Chỉ khi đo WAN mới chốt được D-iOS-1.

- Bấm Cho phép → hook nhận quyết định: p95 5.1 ms và 5.7 ms, mục tiêu < 500 ms.
- Trạng thái đổi trên Mac → client: p95 12.9 ms và 13.1 ms, mục tiêu < 1 s. Đây là thẻ bench, chưa gồm bước tìm workspace (xem Bench 50 yêu cầu).
- Đo trên loopback nên các số trên chỉ là phần chi phí phần mềm: Noise, JSON, hop main actor, socket. Trên WAN, đường trả lời phải đi thêm một lượt điện thoại → relay → Mac, còn thay đổi trạng thái đi thêm một lượt theo chiều ngược lại. Với 4G, mỗi lượt thường vài chục tới vài trăm ms, nên dự kiến vẫn đạt, nhưng chưa đo.
- Round trip qua relay chỉ khoảng 3 ms, trong khi hook → `agent.changed` mất khoảng 10 ms. Vậy phần lớn thời gian nằm trên Mac, trước khi frame rời Mac (ingest Feed, hop main actor, `ShellXLinkFeedSource`). Đây là suy luận, chưa đo từng chặng.

Vấn đề gặp phải:

- Mỗi lần build lại, app `link` có chữ ký ad-hoc mới. Shell zsh trong app bị treo ở `hashdir` → `open()` trên `~/Documents/developer/flutter/bin`, một mục PATH từ `~/.zshrc`. Nhiều khả năng là app đang chờ người dùng bấm hộp thoại quyền truy cập Documents của macOS. Cách vòng: mở workspace bằng `workspace.create` với `initial_command`, vì zsh login không tương tác không đọc `.zshrc`. Lỗi này không thuộc ShellX Link, nhưng sẽ chặn người dogfood bản tag.
- Thẻ bench có `workspace_title = "Bash"`, tức tên tool, vì phiên hook giả không gắn với workspace nào và `ShellXLinkFeedSource` lùi về `item.title`. Thẻ Claude thật có đúng tên workspace `link-spike-claude`.
- Invite debug dùng connect ticket 120 s, và `cmux-relay` cho dùng lại ticket trong hạn (không chống phát lại). Mỗi lệnh probe phải mở phiên mới, nên cần invite mới sau 2 phút. Điện thoại thật cần tự xin ticket (thiết bị loại `mobile` trên relay v2), không dùng socket debug của Mac.
- Khoá host và danh sách client tin cậy nằm chung ở `~/Library/Application Support/ShellX/link/` cho mọi bundle id (nỗi lo đã ghi ở Task 7). Spike đã xoá thư mục này sau khi chạy, vì trước đó nó chưa có.
- Chưa đo trên điện thoại thật và mạng di động. Probe chạy trên chính Mac.

P2 cần đổi trong `PROTOCOL.md`:

- `revision`: mục 4 ghi "tăng ít nhất 1", nhưng client lại MUST resync khi không đúng +1. Phải ghi host MUST tăng đúng 1 cho mỗi `agent.changed` (host hiện đã làm vậy). **Đã ghi ở P1** (lượt sửa cuối), kèm luật client bỏ qua thay đổi có `revision` không lớn hơn revision hiện tại.
- `delivered` nghĩa là có một hook đang chờ đã nhận quyết định này. Thẻ không có hook chờ (ví dụ khôi phục từ log Feed) trả `already_handled`. Phải ghi rõ điều này ở mục 5. **Đã ghi ở P1** (lượt sửa cuối). Thẻ đó giờ còn bị đánh dấu hết hạn, nên rời khỏi tập đang chờ.
- Thêm MUST: host trả `agent.reply.result` cho cùng một `request_id` theo đúng thứ tự `agent.reply` đến (nợ từ Task 5). **Đã ghi ở P1** (lượt sửa cuối).
- Trả lời `question` và `exit_plan`: `agent.reply` hiện chỉ có `mode` của permission. P2 cần trường hoặc message riêng cho `selections` và cho mode `exit_plan` kèm `feedback`. Cũng phải quyết có đưa mode `bypass` của Mac vào hay không.
- Thêm mục ghép cặp và tin cậy: điện thoại lấy host key qua ghép cặp (QR) và tự xin connect ticket từ relay v2, thay cho `shellx.link.debug_invite`. Ghi rõ static key của điện thoại được tin từ lúc nào.
- Thêm mục kết nối lại: phiên sống qua hạn ticket và qua lần host đăng ký lại (đã thấy trong spike). Khi gặp `slot-offline` thì thử lại. Sau khi nối lại thì gửi `hello` rồi `agent.snapshot.get`. Trả lời đã `timedOut` có thể gửi lại vì idempotent. Cũng nên ghi nhịp `ping` và ngưỡng idle (hiện 20 s và 45 s, chỉ nằm trong code), vì iOS treo app khi chạy nền.
- `workspace_title`: ghi host gửi gì khi không tìm ra workspace, ví dụ tên thư mục `cwd`, không phải tên tool.

## Mang sang P2 (2026-10-22)

P1 đóng với số đo local. Review cuối toàn nhánh (`3726d592f6..db317f4efd`) không có lỗi Critical. Hai lỗi Important đã sửa trong lượt sửa cuối:
- thẻ không còn hook nào chờ: Mac cho hết hạn, điện thoại nhận `already_handled`;
- CI chạy test `shellx-link`, có kiểm tra license (`.github/workflows/shellx-link.yml`).

Còn lại, theo thứ tự:

Bước đầu P2:
- Bật relay2 trên VPS theo `deploy/README.md` mục "Relay v2". Gồm: source tarball của commit pin, `CMUX_RELAY_HMAC_SECRET` trong `.env` (làm tay, không qua chat), timeout nginx 330 s, build relay2, `COMPOSE_PROFILES=relay2`, biến `RELAY2_ENABLED=true`. Sau đó chạy lại bench qua WAN (4G) để chốt D-iOS-1.

Bắt buộc trước khi bật `remoteMachines` hoặc phát hành:
- Khoá host và danh sách client tin cậy: lưu riêng theo bundle id và theo tài khoản, hoặc dùng Keychain. Hiện mọi bản build dùng chung `~/Library/Application Support/ShellX/link/`, và `debug_invite` ghi thêm vào danh sách mà bản Release sẽ tin.
- Bắt buộc `wss` (từ chối `ws`/`http` trừ loopback) trước khi app iOS phát hành.
- Điện thoại không có `shellx-core`, nên phải tự kiểm tra slot trong vé như `ShellXLinkTicket` trên Mac.

Giao thức (bản sửa `PROTOCOL.md` của P2), ngoài các mục ở trên:
- Correlation id do client chọn cho `agent.reply` / `agent.reply.result`. Nó bỏ được bộ đếm `lateReplyResults`, hiện đếm sai khi waiter mới hơn bị huỷ hoặc khi gửi lỗi. Nó cũng bỏ được ràng buộc thứ tự theo `request_id`.
- Quy tắc mở rộng cho các enum đóng `mode`, `outcome` và `kind`. Hiện một `agent.reply` không giải mã được bị trả `bad_request` không kèm `request_id`, nên điện thoại phải chờ đủ 10 s.
- Kết nối lại:
  - host xin vé trước và đăng ký lại theo kiểu make-before-break, vì khoảng trống mỗi 120 s trên WAN có thể tới 0.5–1 s;
  - client thử lại khi gặp `slot-offline`;
  - lỗi đăng ký sau lần đầu hiện bị nuốt và thử lại mãi, không log, nên cần có mã lỗi và điểm dừng.

Nhỏ, làm khi đụng tới:
- `TerminalController` `feed.*.reply` vẫn trả `delivered:true` khi không hook nào nhận. Dùng giá trị Bool mới của `deliverReply`.
- Thẻ khôi phục từ log mà không hook nào còn chờ được: cân nhắc cho hết hạn ngay lúc khởi động. Việc này đổi hành vi Feed của Mac.
- Key store:
  - nhánh `EEXIST` giữa hai tiến trình chưa có test;
  - `link(2)` không có đường lùi;
  - lỗi io lúc nạp khoá dừng host cả phiên.
- Test helper của relay integration (tearDown không có timeout và vài chỗ khác); các test có khoảng thời gian sát.
- Swift 6.0: CI biên dịch bằng Xcode 26 (Swift 6.2), nên chưa lần nào biên dịch bằng 6.0. Review đọc tay không thấy cú pháp 6.1+.
- Spec §9 còn câu cũ về việc thay `cmux-tui`, dù việc này đã quyết trong `3f424d82c4`.
