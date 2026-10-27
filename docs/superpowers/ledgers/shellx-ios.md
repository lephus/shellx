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
- Tập đang chờ của ShellX Link chưa lọc theo agent. Thẻ xin quyền của Codex (đẩy lên không chờ) cũng hiện trên điện thoại, và khi điện thoại trả lời thì thẻ đó hết hạn trên Mac, dù Codex vẫn chờ ở terminal. P2: lọc theo `agent` (v1 chỉ Claude Code) hoặc ẩn thẻ không có hook chờ.
- `TerminalController` `feed.*.reply` vẫn trả `delivered:true` khi không hook nào nhận. Dùng giá trị Bool mới của `deliverReply`.
- Thẻ khôi phục từ log mà không hook nào còn chờ được: cân nhắc cho hết hạn ngay lúc khởi động. Việc này đổi hành vi Feed của Mac.
- Key store:
  - nhánh `EEXIST` giữa hai tiến trình chưa có test;
  - `link(2)` không có đường lùi;
  - lỗi io lúc nạp khoá dừng host cả phiên.
- Test helper của relay integration (tearDown không có timeout và vài chỗ khác); các test có khoảng thời gian sát.
- Swift 6.0: CI biên dịch bằng Xcode 26 (Swift 6.2), nên chưa lần nào biên dịch bằng 6.0. Review đọc tay không thấy cú pháp 6.1+.
- Spec §9 còn câu cũ về việc thay `cmux-tui`, dù việc này đã quyết trong `3f424d82c4`. **Đã sửa ở P2** (Task 11).

## P2 kết quả (2026-10-27)

`shellx-link-probe` viết lại ở Task 11. Nó đóng vai một điện thoại đã ghép cặp:
- đăng nhập tài khoản với tư cách thiết bị `mobile`;
- ghép cặp từ URI của QR;
- tự xin vé `connect` cho mỗi phiên. Bỏ hết `--invite`.

Mọi thứ probe giữ nằm trong `--state <dir>` (0700): `phone.key`, `session.json` (token) và `machines.json` (máy đã ghép cặp, kèm host key lấy từ QR), đều 0600. Mật khẩu đọc từ stdin, URI của QR đọc từ file 0600. Probe không in mật khẩu, token, vé, khoá riêng hay mã ghép cặp. Cách dùng: `shellx-link/README.md`.

`PhonePairing.pair` có thêm tham số `onRequested`: nó nhận pairing id ngay sau khi gửi yêu cầu, trước lần hỏi trạng thái đầu. Probe in id này để gọi `debug_pairing_approve`. Có test.

### Chạy trọn đường ở local

Môi trường, tất cả trên một Mac, loopback, như Spike P1 với các điểm khác sau:
- Relay Node đủ 8 migration (có `0008_phones.sql`), DB tạm ngoài repo.
- `cmux-relay serve --bind 127.0.0.1:18790 --issuer shellx-relay`. Cả hai relay dùng `CMUX_RELAY_ISSUER=shellx-relay` và chung một `CMUX_RELAY_HMAC_SECRET` ngẫu nhiên, không ghi ra đâu.
- App tag `link` build trên `e917c35dbb`, mở bằng `open -n -g --env …` với `SHELLX_REMOTE_MACHINES=1`, `SHELLX_API_BASE=http://127.0.0.1:8787`, `CMUX_SOCKET_MODE=allowAll`. Tài khoản dùng một lần chỉ có trên relay local.
- Claude Code 2.1.311 chạy trong app (`workspace.create` với `initial_command`), trong một repo git dùng một lần dưới `/private/tmp`, với `--permission-mode default`.

Các lệnh (`p` là probe, `S` là `--state phone`):

```bash
umask 077   # redirect thường tạo file 0644: probe từ chối offer.txt như vậy, và file password cũng phải 0600
$p login $S --api http://127.0.0.1:8787 --email <tài khoản dùng một lần> --password-stdin < password
CMUX_TAG=link scripts/cmux-debug-cli.sh rpc shellx.link.debug_pairing_offer '{}' > offer.txt
$p pair $S --offer-file offer.txt
CMUX_TAG=link scripts/cmux-debug-cli.sh rpc shellx.link.debug_pairing_approve '{"pairing_id":"<id probe in ra>"}'
$p watch $S --seconds 3600
$p approve <request_id> $S
$p answer <request_id> $S --select "gamma-free-text.txt"
$p plan <request_id> $S --mode manual [--feedback-file feedback.txt]
$p sessions $S
$p chat-send <session_id> $S --text-file list.txt     # "liệt kê file"
$p chat-history <session_id> $S [--limit 3 --before 131]
$p chat-stop <session_id> $S
$p watch $S --recheck --seconds 1800
$p unpair $S --machine <machine_id>
```

| Bước | Kết quả |
| --- | --- |
| 1. `login` | Đạt |
| 2. offer → `pair` | Đạt |
| 3. Đồng ý | Đạt, bằng `debug_pairing_approve`. Chưa bấm nút Đồng ý trong sheet. |
| 4. Thẻ xin quyền, câu hỏi (có câu trả lời tự do), plan | Đạt. Claude chạy tiếp sau mỗi lần trả lời. |
| 5. `sessions`: `working` → `needs_input` → `idle` | Đạt. Có hai điểm lệch, xem "Vấn đề gặp phải". |
| 6. `chat-send` "liệt kê file", rồi `chat-history` | Đạt |
| 7. `chat-stop` | Đạt |
| 8. Gỡ trong lúc `watch` chạy | Một phần. Không bấm được Gỡ trong sheet, nên thay bằng `unpair` từ điện thoại cộng với lượt đối soát grant của Mac. |

Log, đã rút gọn và bỏ bí mật:

```
# login, pair (8.3 s là lúc tôi gọi lệnh duyệt)
logged in as a mobile device: user b2aa889f-… device 99e2cf09-…
pairing request 7083f673-2015-49e7-a05c-009469a912e8 sent; allow it on the Mac (or shellx.link.debug_pairing_approve)
paired with "PhuLe’s MacBook Pro (DEV link)" after 8341.1 ms: machine d96d32bc-… slot jn70DoRL2g43uz1GG6Nvjg host key dcb86809455ec793

# watch: thẻ xin quyền
[+149.973s] changed revision=19195 added=1 resolved=[]
    pending 0C16ED4B-… kind=permission agent=claude tool=Bash workspace="link-p2-e2e" modes=[once,always,all,deny] preview={"command":"touch e2e-permission.txt",…}
reply 0C16ED4B-… kind=permission mode=once outcome=delivered rtt=21.4 ms
[+171.967s] changed revision=19196 added=0 resolved=["0C16ED4B-…"]

# câu hỏi, trả lời bằng chữ tự do (không phải một trong hai lựa chọn)
[+237.685s] changed revision=19197 added=1 resolved=[]
    pending EA67A194-… kind=question agent=claude tool=- workspace="link-p2-e2e" modes=[]
      q1 single "What should the new file be called?" options=["alpha.txt", "beta.txt"]
reply EA67A194-… kind=question selections=["gamma-free-text.txt"] outcome=delivered rtt=14.7 ms
[+300.047s] pending 56592570-… kind=permission … preview={"command":"touch gamma-free-text.txt",…}
[+334.695s] chat bf43feed-…: #71 agent/prose: gamma-free-text.txt

# plan: lần 1 kèm góp ý, Claude sửa plan rồi hỏi lại; lần 2 duyệt manual
[+372.741s] pending 074A6B2D-… kind=exit_plan modes=[ultraplan,auto_accept,manual,deny] plan="Append the line `planned` to `README.md` …"
reply 074A6B2D-… kind=exit_plan mode=manual feedback="Approved from the phone. After the edit, show the file with cat." outcome=delivered rtt=16.5 ms
[+402.114s] pending 93D30CD5-… kind=exit_plan … plan="… Then show the file w…"
reply 93D30CD5-… kind=exit_plan mode=manual outcome=delivered rtt=186.3 ms
[+457.876s] pending 503CAFAB-… kind=permission … preview={"command":"printf 'planned\\n' >> README.md && cat README.md",…}
[+482.984s] chat bf43feed-…: #152 agent/prose: I added the line "planned" to the end of `README.md`. …

# trạng thái phiên trong watch
[+146.764s] session bf43feed-… state=working
[+149.973s] session bf43feed-… state=needs_input
[+184.040s] session bf43feed-… state=idle

# chat
chat.send bf43feed-… "liệt kê file" outcome=submitted rtt=164.6 ms
[+536.643s] chat bf43feed-…: #172 agent/prose: Thư mục `/private/tmp/shellx-link-p2-e2e` có các file sau (không tính `.git`): …
chat history bf43feed-…: 6 entries, has_more=true   (… #162 user "liệt kê file", #165 tool_use ls -la, #172 agent/prose …)
chat history --limit 3 --before 131: #116, #119, #128, has_more=true
chat.send … "Write a 3000-word story about a lighthouse keeper. Do not use any tools." outcome=submitted
chat.interrupt bf43feed-… hard=false outcome=sent rtt=4.0 ms

# gỡ: watch --recheck mở lúc 21:34:54, unpair lúc 21:35:30
removed the relay grant for machine d96d32bc-…
Mac 21:35:52.762  link host dropped 1 phone(s) the relay no longer grants
[+ 57.304s] watch: session ended at 21:35:52.766 after 57.3 s (ended by the Mac or the relay)
[+ 57.329s] recheck 1 (ticket minted before the end): refused after 25.2 ms: the relay circuit closed (does the Mac trust this phone?)
[+ 57.335s] recheck 2 (new ticket): refused after 5.6 ms: the relay API answered 403 not_granted
watch (chạy lại, machines.json chép lại từ bản sao): shellx-link-probe: the relay API answered 403 not_granted
```

Màn hình Claude sau `approve` ghi `⎿ Allowed by PermissionRequest hook`, và file được tạo. Sau câu trả lời tự do, Claude tạo `gamma-free-text.txt`. Sau plan, `README.md` có thêm dòng `planned`. Sau `chat-stop`, Claude dừng trước khi viết chữ nào, và prompt quay lại ô nhập.

Ở bước gỡ, phiên `watch` kết thúc 4 ms sau dòng log của Mac. Với vé xin trước lúc gỡ, relay không trả lỗi nào, nhưng circuit bị đóng giữa handshake (`the relay circuit closed`). Nhiều khả năng Mac đã từ chối khoá của điện thoại; log của Mac không ghi lần từ chối này. Vé mới thì relay từ chối (`not_granted`). Sau đó danh sách tin cậy của Mac rỗng (`{"phones":[],"version":2}`). Phiên `watch` đầu tiên sống 1123 s, qua nhiều lần vé hết hạn và host đăng ký lại. Nó nhận đủ 200 `agent.changed` của hai lần bench, không có khoảng hở `revision`, và cũng kết thúc khi Mac gỡ điện thoại.

### Bench local, 50 yêu cầu

Cách đo như Spike P1, nhưng phiên dùng vé do probe tự xin.

| Đo (ms) | Lần 1 p50 / p95 / max | Lần 2 p50 / p95 / max |
| --- | --- | --- |
| hook gửi → probe thấy `agent.changed` | 11.2 / 14.3 / 14.7 | 8.0 / 25.9 / 76.4 |
| `agent.reply` → `agent.reply.result` (round trip) | 3.5 / 4.6 / 5.1 | 3.4 / 5.8 / 14.6 |
| gửi `agent.reply` → hook nhận quyết định | 4.1 / 5.7 / 6.7 | 3.7 / 6.6 / 14.7 |

Cả hai lần đều 50/50 ok, không có khoảng hở `revision`, và hook nhận đúng `resolved/once`. Lần 2 có vài mẫu chậm (max 76.4 ms), chưa rõ vì sao. Tôi đoán là Mac đang bận việc khác, nhưng chưa kiểm. Trong 22 lần mở phiên có ghi lại, 21 lần mất 13.9–30.3 ms và một lần 106.1 ms. Con số này gồm xin vé HTTP, mở circuit, Noise và `hello`/`welcome`.

Số P1 để đối chiếu (mục "Bench 50 yêu cầu" của Spike P1), p95 của lần 1 và lần 2:
- hook → `agent.changed`: 12.9 và 13.1 ms;
- round trip: 3.6 và 3.6 ms;
- `agent.reply` → hook: 5.1 và 5.7 ms.

Mở phiên ở P1 gồm circuit 8.7–20.8 ms cộng Noise và `hello`/`welcome` 2.6–4.5 ms, chưa có bước xin vé.

Thẻ thật đo từ watch (thời điểm thẻ hiện so với lúc trả lời) không dùng làm số đo, vì tôi trả lời bằng tay. Round trip `agent.reply` của thẻ thật là 9.8–21.4 ms, có một lần 186.3 ms (phiên đó mở mất 106.1 ms). Round trip của `chat.send` là 164–171 ms, vì Mac xoá ô nhập rồi gõ chữ vào terminal.

**WAN của P2: chờ người dùng bật relay2 và cho deploy.** Chưa chạy Step 4, nên D-iOS-1 vẫn chỉ có số local.

### Vấn đề gặp phải

- **Chưa bấm được Gỡ trong sheet.** Tiến trình của agent không có quyền Accessibility (`AXIsProcessTrusted()` = false), và không có lệnh DEBUG nào để gỡ. Vì vậy không bấm được nút, và đường `ShellXPhonePairingCoordinator.revoke` → `revoke(clientKey:)` chưa chạy thật. Bước 8 đã dùng đường khác: relay bỏ grant, rồi một lượt đối soát grant của Mac gỡ khoá và ngắt phiên, 22 s sau `unpair` (21:35:30 → 21:35:52.762). Mac không ghi log khi bắt đầu một lượt đối soát, nên không rõ lượt đó do đâu chạy. Thời điểm này trùng với nhịp 600 s tính từ lúc host khởi động (21:15:52), nhưng đó chỉ là suy luận. Cần người dùng bấm Gỡ một lần, hoặc thêm `debug_pairing_revoke`.
- **`chat.entries` thiếu lượt đầu của phiên mới.** Phiên Claude này mở sau khi điện thoại đã nối. Cả lượt đầu (prompt, `tool_use`, câu trả lời) không có push nào. Push chỉ bắt đầu từ prompt thứ hai, sau lần đọc `chat.history` đầu tiên. `chat.history` vẫn có đủ. Nghi ngờ (chưa xác minh): ở SessionStart và UserPromptSubmit của lượt đầu, `AgentChatTranscriptService` chưa tìm ra file transcript, nên chưa tạo tailer, và không thử lại cho tới prompt sau.
- **Trạng thái phiên lệch.** Sau khi điện thoại trả lời, phiên vẫn `needs_input` tới hook kế tiếp (PreToolUse hoặc Stop). Có lần lệch 12 s trong khi Claude đang chạy. Sau `chat.interrupt` (Esc), phiên vẫn `working` mãi, vì Claude Code không gọi Stop khi bị ngắt. Lần đo cuối là 252 s sau khi ngắt.
- **`exit_plan` có `feedback` nghĩa là "sửa plan theo góp ý", bất kể `mode`.** Hook trả `deny` kèm message, nên Claude viết lại plan và hỏi lại. Đây là cách Feed của Mac vốn làm (`CLI/cmux.swift`, nhánh `exit_plan`). App P3 phải coi ô góp ý là "yêu cầu sửa", không phải "duyệt kèm ghi chú". `PROTOCOL.md` nên ghi rõ điều này.
- **Bản tag dùng chung kho hook và phiên của người dùng.** Danh sách `agent.sessions` của app `link` có 5 phiên Claude thật của người dùng, kể cả phiên đang chạy task này. Revision của tập đang chờ cũng bắt đầu từ 19194. Bản phát hành chỉ có một app nên không sao. Nhưng khi dogfood bản tag, điện thoại thấy, và có thể chat vào, phiên của app khác. Probe không đụng các phiên đó.
- Thẻ bench tạo phiên giả `shellx-link-probe-…` (workspace là tên thư mục cwd). Các phiên này nằm mãi ở `needs_input` trong danh sách phiên.
- Lần đầu chạy trong một repo mới, Claude Code hỏi "trust this folder". Phải chọn bằng `send-key`. Lệnh `ls -la` bị hook PreToolUse của người dùng đổi thành `toknix run -- 'ls -la'`, nên cũng phải xin quyền.

## Mang sang P3 (2026-10-27)

Từ kế hoạch:
- Kênh `terminal`.
- Xem trước chữ đang chạy (`streamingProse`). P2 bỏ qua nó (và cả `reset` của transcript).
- App iOS lưu token và các máy đã ghép cặp, kèm host key, trong Keychain. Probe đang dùng file 0600.
- Thẻ khôi phục từ log mà không hook nào còn chờ được: cho hết hạn ngay lúc khởi động.
- Biên dịch thử bằng Swift 6.0. CI vẫn chỉ dùng Xcode 26 (Swift 6.2).

Từ lần chạy trọn đường ở trên:
- Bấm Gỡ trong sheet một lần trên Mac thật, trong lúc điện thoại đang nối.
- Push `chat.entries` cho lượt đầu của phiên mới. Trước khi sửa, app P3 nên gọi `chat.history` khi mở một phiên, và gọi lại khi trạng thái phiên đổi.
- Trạng thái phiên: chuyển sang `working` khi thẻ được trả lời, và về `idle` sau `chat.interrupt`.
- Ghi ngữ nghĩa `feedback` của `exit_plan` vào `PROTOCOL.md` và vào giao diện P3.
- WAN của P2 (Step 4 Task 11): chờ người dùng bật relay2 và cho deploy.
