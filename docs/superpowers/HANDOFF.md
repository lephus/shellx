# ShellX v1.0 — Bàn giao để tiếp tục (cập nhật 2026-09-27: 6 plan đã merge; hạ tầng đã chuyển sang VPS trong code, chưa deploy)

Tài liệu này đủ để một phiên Claude mới (hoặc chính phiên cũ khi resume) tiếp tục đúng chỗ. Đọc hết trước khi làm gì.

## 1. Bối cảnh

- Sản phẩm: điều khiển terminal máy tính (macOS/Windows) từ điện thoại, qua relay chạy trên VPS riêng (Node.js + SQLite trong Docker), mã hóa đầu cuối Noise.
- Hạ tầng: `docs/superpowers/specs/2026-09-26-shellx-vps-infra-design.md` (thay các phần Cloudflare của spec v1); plan `docs/superpowers/plans/2026-09-26-shellx-vps-infra.md`; runbook `deploy/README.md`.
- Spec: `docs/superpowers/specs/2026-09-25-shellx-v1-design.md` (đã sửa nhiều lần theo các quyết định trong lúc làm).
- Kế hoạch: `docs/superpowers/plans/2026-09-25-shellx-v1-0*-*.md`; **file tổng quan + hợp đồng interface bắt buộc**: `…-00-overview.md`.
- Quy trình: superpowers `subagent-driven-development` — mỗi task: implementer (subagent) → task review → vòng sửa (tối đa 5) → ledger; cuối mỗi plan: review toàn nhánh (opus) → MỘT lượt sửa → review ngắn → merge.
- Người dùng cho phép: **tự merge nhánh plan vào `feat/shellx-v1` trên máy sau review cuối; KHÔNG push**.

## 2. Trạng thái theo kế hoạch

| # | Kế hoạch | Nhánh / worktree | Trạng thái |
|---|---|---|---|
| 06 | Web + CI + phát hành | đã merge, worktree đã xóa | ✅ Xong |
| 02 | `shellx_core` | đã merge, worktree đã xóa | ✅ Xong (253 test) |
| 01 | Relay | đã merge (bfa442b), worktree đã xóa | ✅ Xong (211 test). Ledger: `docs/superpowers/ledgers/plan01-relay.md`. Việc tiếp: merge `feat/shellx-v1` vào nhánh plan 03 (sau khi Task 9 xong) để E2E Task 15 chạy relay thật |
| 03 | `shellx_agent` + `shellx_client` + E2E | đã merge (e5aecb0), worktree đã xóa | ✅ Xong (agent 167, client 98, e2e 7 trên relay local). Ledger: `docs/superpowers/ledgers/plan03-agent-client.md` |
| 04 | Desktop (Flutter) | đã merge (25ddd75), worktree đã xóa | ✅ Xong (desktop 269, PTY integration 21 trên macOS). Windows **chưa kiểm chứng** cho tới khi chạy Windows CI (checklist trong ledger). Ledger: `docs/superpowers/ledgers/plan04-desktop.md` |
| 05 | Mobile (Flutter) | đã merge (0e9ca47), worktree đã xóa | ✅ Xong (mobile 501 test; build debug APK + iOS đã chạy). App id `com.shellx.prod`, logo mới. Ledger: `docs/superpowers/ledgers/plan05-mobile.md` |
| VPS | Chuyển hạ tầng Cloudflare → VPS | `docs/superpowers/plans/2026-09-26-shellx-vps-infra.md` | ✅ Code xong: relay chạy Node.js (265 test, cũng chạy trong bước build image), e2e 7/7 với `npm run dev`; `deploy/`, `deploy.yml`, image relay/web. **Chưa deploy** (xem mục 4) |

Ledger chi tiết (mỗi task, mọi phán quyết "Ruling", mọi lỗi nhỏ hoãn lại):
- Bản sao trong repo: `docs/superpowers/ledgers/` (plan01–06 đầy đủ; các file `.snapshot.md` là bản lúc tạm dừng).

## 3. Trạng thái và việc tiếp theo

Toàn bộ code v1.0 đã nằm trên `feat/shellx-v1` (chưa push). Kiểm chứng trên máy lúc merge plan 05: core 261, client 98, agent 167, desktop 269, mobile 501 test xanh; `flutter analyze` sạch cho mọi package/app; relay (238) và web không đổi kể từ lúc merge; e2e 7/7 lúc merge plan 03.

Việc còn lại — tất cả cần người dùng quyết/cung cấp:
1. **Không còn CI** (quyết định V5): desktop Windows chưa kiểm chứng — chạy test trên một máy Windows thật (checklist trong `ledgers/plan04-desktop.md`) trước khi phát hành.
2. **Dựng VPS và deploy lần đầu** theo `deploy/README.md` (mục 4). Push `main` là deploy.
3. **Kiểm tra thủ công trên thiết bị thật** — mobile: đăng nhập, quét QR (kể cả Android "Quét lại" cùng mã, cấp quyền camera từ Cài đặt), Face ID khi mở lại, IME tiếng Việt / phím cứng gửi trùng, dán từ gợi ý clipboard của bàn phím; desktop: đăng nhập GUI, ghép nối, banner thông báo, ⌘Q.
4. Việc gia cố nên làm sau (không chặn phát hành): một test tích hợp mobile chạy `ClientBackend` → `TerminalPageController` qua relay trong bộ nhớ của `shellx_e2e` với `SessionManager` thật; khoảng hẹp `PendingUnpairs.retry` có thể xóa một lần ghép nối lại diễn ra đúng lúc đăng nhập (xem ledger plan 05).

## 4. Việc chờ người dùng (không chặn code)

- **VPS** (runbook `deploy/README.md`): quốc gia đặt VPS đã điền là Việt Nam (2026-09-27; bộ chặn `[quốc gia]` vẫn giữ cho lần sửa sau); user deploy trong nhóm `docker`, `~/phu/shellx/data` thuộc uid 1000; tên network của nginx-proxy vào `~/phu/shellx/.env`; 4 secret `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY`, `VPS_KNOWN_HOSTS` và biến `VPS_APP_DIR` (mặc định `phu/shellx`), `VPS_SSH_PORT` (tuỳ chọn, chỉ số, mặc định `22`) — tất cả là Environment secret/variable của hai GitHub Environment `production` (dùng bởi `deploy.yml`) và `release` (dùng bởi `publish`), không phải repository secret; sau lần deploy đầu: công khai 2 package GHCR `shellx-relay`, `shellx-web` và chép (không symlink) 4 file `~/phu/shellx/nginx-proxy/*` vào `vhost.d` của nginx-proxy rồi tạo lại container ShellX — **tất cả đã xong 2026-09-28**: deploy đầu tiên (b157539) live, relay/web healthy, cert đã cấp, 4 check của README bước 6 pass. Lưu ý VPS này: container nginx-proxy tên `proxy`, network tên `nginx-proxy`, vhost.d nằm ở volume `nginx_nginx_vhosts`. Mọi lệnh trên VPS do người dùng chạy hoặc cho phép rõ ràng.
- **Chia sẻ terminal (P1) — kiểm tay còn thiếu:** bộ gõ tiếng Việt (IME), Cmd+W, giao diện thật của Cursor và Android Studio, iTerm2, VS Code, Warp.
- **Chia sẻ terminal — Windows:** kiểm tra tương tác trên máy Windows thật chưa làm (spec §12). Phải gồm: Windows Terminal thật, bộ gõ IME (Telex/VNI), đóng tab khi lệnh đang chạy, mã hóa profile PowerShell 5.1, Ctrl+Space, đổi cỡ cửa sổ conhost cổ điển. Chi tiết: `ledgers/terminal-sharing.md`, mục P2b.
- **Dọn Cloudflare** (khi nameserver đã về nhà đăng ký): xóa zone `shellx.pro` trên Cloudflare, `npx wrangler logout`, xóa secret `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`.
- **GitHub Environment `release`** (tag `desktop-v*` + nhánh `main`) với 11 secret ký — xem `release/README.md`.
- **Pháp lý**: tên pháp nhân/địa chỉ cho privacy/terms; nhờ người có chuyên môn xem lại (hiện ghi "ShellX", luật Việt Nam, 16 tuổi, log ≤ 30 ngày).
- Chính sách quyền riêng tư hứa log vận hành ≤ 30 ngày, nhưng Docker xoay vòng log theo dung lượng (10 MB × 3) nên khi ít traffic log có thể lâu hơn 30 ngày — người dùng chọn: sửa câu chữ, hoặc định kỳ tạo lại container.
- **Đã chốt (2026-09-28) — nginx-proxy log IP client ở khối redirect HTTP→HTTPS (I3):** người dùng chọn phương án 2 (công bố trong chính sách quyền riêng tư), vì VPS chạy nhiều site khác nên `DISABLE_ACCESS_LOGS` toàn proxy quá rộng. Đoạn **Địa chỉ IP** (mục 1) của `web/src/pages/privacy.md` và `web/src/pages/en/privacy.md` nay ghi rõ: yêu cầu `https://` không bị ghi access log; yêu cầu `http://` trần *có thể* được máy chủ web dùng chung ghi (kèm IP) vào nhật ký kỹ thuật trước khi chuyển hướng. Dùng "có thể" vì retention log của container proxy (ngoài `~/phu/shellx`) chưa được giới hạn — nếu sau này người dùng thêm giới hạn retention (phương án 3 bổ sung), có thể siết lại câu chữ.
- **Đã xong (2026-09-27, nhánh `fix/relay-memory-bounds`, gồm fix round 1 sau review): giới hạn bộ nhớ của relay trước lần deploy công khai đầu tiên.** Trước đây một kết nối bị kẹt giữ được khoảng 57 MB heap qua các reply ERROR và frame DATA nhỏ. Nay có các lớp: (1) hub đếm số lần gửi đang chờ trên mỗi socket, quá 1024 thì đóng 1013 như thiết bị nhận chậm, và `pong` chỉ gửi khi còn tối đa 64 lần gửi và 64 KiB đang chờ; (2) relay không trả lời khung điều khiển PING của WebSocket (`autoPong: false`); (3) mọi lần hub chủ động đóng (1013, 4001, 4002, 4003) đều ngắt hẳn sau 1 giây nếu chưa xong, các lần đóng khác sau 2 giây (`closeTimeout`); (4) snapshot lúc kết nối của chính thiết bị mới không qua kiểm tra hàng chờ, nên agent có nhiều tombstone không bị đóng 1013 mãi; (5) mỗi tài khoản tối đa 16 thiết bị online cùng lúc, thiết bị mới thứ 17 nhận 1013 `too many devices online`; (6) container relay có `mem_limit: 512m` và `memswap_limit: 512m`. Số đo cuối (probe từ các lần review, không nằm trong repo), mỗi socket kẹt: reply ERROR từ +56,5 MB xuống +0,9 MB; DATA nhỏ từ +58,7 MB xuống +0,8 MB; 300k PING điều khiển từ +58,9 MB (không bao giờ bị đóng) xuống +0,3 MB; backlog sau 4003 từ +3,5 MB giữ khoảng 30 giây xuống được giải phóng trước 1,5 giây; agent có 1100 tombstone trước bị đóng 1013 sau 1025 frame, nay nhận đủ 1100. Chi tiết: spec VPS §4.3 và `relay/README.md`. **Rủi ro còn lại:** (a) mỗi socket kẹt vẫn giữ được tới 4 MiB payload cộng khoảng 0,4 MB, nên một tài khoản có đủ 16 thiết bị kẹt giữ khoảng 70 MB; số tài khoản không giới hạn, nên trần chung duy nhất là 512 MB của container (vượt thì relay bị OOM kill rồi tự khởi động lại); (b) `ping` bị bỏ qua khi hàng chờ đầy thì mất luôn, không được trả bù, nên một backlog ngắn trên đường truyền chậm có thể làm client hết giờ nhịp tim và kết nối lại (M4, đã hoãn; kiểm trên VPS).
- **Kiểm chứng cần Docker/VPS** (danh sách đầy đủ trong `docs/superpowers/ledgers/vps-infra.md`): build hai image; diễn tập rollout/rollback thật; backup qua mount chỉ đọc và `chown`; `--force-recreate backup`; `X-Real-IP` và 429 sau nginx-proxy thật; `pong` qua đường truyền chậm (cả ngưỡng 64 KiB lẫn 64 lần gửi; một `ping` bị bỏ qua không được trả bù, M4); giới hạn bộ nhớ trong Docker: `docker inspect -f '{{.HostConfig.Memory}} {{.HostConfig.MemorySwap}}'` trên container relay phải in `536870912 536870912`, và `docker compose exec relay node -p "v8.getHeapStatistics().heap_size_limit/2**20"` cho biết trần heap của V8 trong container; `workflow_dispatch` thấy `origin/main`. Docker Desktop trên máy dev từng bị treo; cần khởi động lại trước khi chạy.
- **Ký Windows**: Azure Trusted Signing có thể không nhận nhà phát hành ở Việt Nam → phương án chứng chỉ OV.
- **Icon/thương hiệu**: mobile đã dùng logo người dùng gửi (2026-09-26); cần bản 1024×1024 hoặc SVG để icon App Store nét (thay `apps/mobile/assets/branding/*` rồi chạy `apps/mobile/tool/gen_app_icons.py`). Desktop/web chưa đổi logo.

## 5. Quy tắc làm việc đã thống nhất

- Người dùng nói tiếng Việt; trả lời bằng tiếng Việt.
- Không push, không deploy, không chạy lệnh trên VPS khi chưa hỏi.
- Mỗi phán quyết của controller ghi vào ledger dạng `Ruling: <quyết định> — <lý do> — <cái giá nếu sai>`; cuối mỗi plan liệt kê hết cho người dùng.

## 6. Mobile dựng trên base yallabb (quyết định 2026-09-25)

Người dùng: "Mobile bạn hãy lấy /Users/lehuuphu/Documents/workspace/DigitalUnicorn/flutter-base/yallabb làm base". Base là repo của team (không sửa repo đó, chỉ sao chép).

- Ruling: sao chép cây làm việc của yallabb (HEAD 2437b6f + thay đổi chưa commit trong pubspec: `signals_flutter` lấy từ pub ^6.3.0) vào `apps/mobile`, không kèm lịch sử git; đổi package `yallabb` → `shellx_mobile`, id `pro.shellx.mobile`, tên hiển thị "ShellX" — cái giá nếu sai: sao chép lại.
- Ruling: giữ kiến trúc của base — feature-first data/domain/presentation, `get_it`/`injectable`, `auto_route` (+ guard), `signals_flutter` (`Controller`, `StateSignal`, `Watch`), `intl_utils` (`S.of(context)`, locale en + vi thay cho fr), design system/`adaptive_theme`/`toastification`, widget dùng chung, validators — thay cho Riverpod/ChangeNotifier/gen-l10n của plan cũ — cái giá nếu sai: viết lại tầng trình bày.
- Ruling: bỏ phần không dùng của base — feature demo (`single`, `list`, `entry_testing`), tầng `dio`/`RestClient`/`AuthInterceptor`/`RefreshTokenHandler` (ShellX không có refresh token; REST đi qua `ShellxApi` của `shellx_core`); `SessionHolder`/`AuthStorage` được viết lại cho token + `user_id` + `device_id` + email — cái giá nếu sai: lấy lại từ base.
- Ruling: Flutter 3.41.7 / Dart ^3.11.0 như cả workspace (bỏ `.fvmrc` 3.38.2 của base); `apps/mobile` là thành viên workspace; phiên bản package phải giải được cùng `apps/desktop` (vd `flutter_secure_storage` ^10.3.4, `package_info_plus` ^9.0.1) và `test` ^1.30.0 — cái giá nếu sai: chỉnh phiên bản ở Task 1.
- Ruling: code sinh ra (injectable, auto_route, json_serializable, intl_utils, flutter_gen) được commit như base; CI mobile thêm bước kiểm tra code sinh ra còn khớp — cái giá nếu sai: một bước CI thừa.
- Ruling: font Raleway của base cho giao diện, JetBrains Mono cho terminal — cái giá nếu sai: đổi font.
- Mọi hành vi ShellX (text §12, hợp đồng overview §5, Review Focus, ba port `ShellxBackend`/`MachineSession`/`TabHandle`) giữ nguyên; chỉ đổi khung ứng dụng.

- Thiết kế UI mobile đã được người dùng duyệt ("quá tốt, làm theo design đi", 2026-09-25): `docs/superpowers/design/2026-09-25-shellx-mobile-ui.html` (artifact: https://claude.ai/artifact/PiUZitLBpKWQmkjuesTmJ7), gồm bảng màu tối mới và 5 chi tiết ngoài spec (nay đã ghi vào spec §9.2). Plan 05 phải bám theo thiết kế này.

## 7. Quyết định ngày 2026-09-26

- App mobile: bundle id iOS và applicationId/namespace Android là **`com.shellx.prod`** (thay `pro.shellx.mobile` trong plan/ledger cũ). Desktop giữ `pro.shellx.desktop`.
- Logo mobile: nguồn `apps/mobile/assets/branding/logo_shellx_{rounded,square}.png`; icon iOS (RGB, không alpha), Android adaptive (+ monochrome) và logo trong app sinh bằng `apps/mobile/tool/gen_app_icons.py`.

## 8. Hạ tầng VPS (quyết định 2026-09-26/27)

- V1–V7 (2026-09-26): bỏ Cloudflare; relay, trang web và nơi tải bản cài chạy trên VPS của người dùng (Ubuntu, Docker, `jwilder/nginx-proxy` + letsencrypt-companion); relay chuyển sang Node.js giữ nguyên giao thức; không CI, chỉ CD (`deploy.yml` khi push `main`, `release-desktop.yml` khi tag `desktop-v*`); build image relay chạy toàn bộ test relay.
- V8 (2026-09-27): mọi thứ của ShellX trên VPS nằm trong **một thư mục `~/phu/shellx`** (biến GitHub `VPS_APP_DIR`), kể cả database (`./data`, bind mount). Ngoại lệ duy nhất: các file vhost của nginx-proxy trong `vhost.d` (bản gốc ở `~/phu/shellx/nginx-proxy/`, chép — không symlink — vào đó).
- Việc còn mở: tên network của nginx-proxy. (Quốc gia đặt VPS: Việt Nam, đã điền 2026-09-27.)

## 9. Chia sẻ terminal máy tính (2026-10-01)

Từ điện thoại xem và gõ vào các cửa sổ terminal đang mở sẵn trên máy tính (mọi ứng dụng terminal, macOS và Windows).
- Spec: `specs/2026-10-01-desktop-terminal-sharing-design.md`.
- Kế hoạch P1: `plans/2026-10-01-terminal-sharing-p1-shellx-term-spike.md`.
- Kết quả và phát quyết: `ledgers/terminal-sharing.md`.

- **P1 xong:** crate Rust `term/` (`shellx-term wrap`) cho macOS, cùng khối tích hợp zsh/bash (`term/shell/`).
  - Test: 64 test trong 7 bộ (sau lượt sửa review cuối).
  - Đo khởi động: +13,2 ms, cộng khoảng 2,4 ms cho bước kiểm tra `--version`.
  - Đã kiểm trên Terminal.app thật với cả khối đầu lẫn khối cuối. Với khối cuối: PATH giống hệt, `source` bằng tay không thay shell, file `shellx-term` hỏng thì cửa sổ vẫn mở bình thường. Cursor và Android Studio kiểm bằng giả lập. Kết quả R1–R3 nằm ở spec §13.
- **Người dùng đã quyết (2026-10-01):** R2 chọn (a): chấp nhận việc Terminal.app không còn hỏi "terminate running processes?", và ghi rõ trong cửa sổ xác nhận khi bật (spec §10.1). **GO cho P2.**
- **P2a xong (2026-10-01):** `shellx-term` nối agent trên macOS (nhánh `feat/terminal-sharing-p2a`).
  - Giao thức nội bộ phía term: bắt tay HMAC hai chiều, snapshot rồi output trực tiếp, input và kích thước từ điện thoại, nối lại; không bao giờ làm chậm terminal (hàng chờ 1 MiB, ghi 1 giây, `exit` xả ≤ 200 ms).
  - Khối zsh/bash mới: gọi bằng biến môi trường với `argv[0]` của shell gốc, `probe`, dấu theo tty, `setopt login` cho zsh login, bỏ qua `source` tay (bash: giới hạn ở spec §5.2).
  - Test: 135 chạy xanh, 2 `#[ignore]`. Đo khởi động: baseline 687,4 ms, bọc 713,8 ms, **+26,4 ms** (< 50 ms).
  - Spec §5.1, §5.2, §5.4, §6.1–§6.5 đã cập nhật theo code; byte chuẩn: `term/protocol/vectors.txt` (P3 phải khớp từng byte, thứ tự khóa theo byte). Chi tiết, việc còn mở và các mục "Ghi cho P2": `ledgers/terminal-sharing.md`, mục P2a.
- **P2b (code xong, chờ CI Windows):** `shellx-term` trên Windows (ConPTY, console VT thô, khối PowerShell với danh sách đối số cho phép) và workflow `windows-check.yml` (`workflow_dispatch` hoặc push `windows-check/**`; chỉ `term/`). macOS: 157 test xanh, 2 `#[ignore]`.
  - Giới hạn: không có kiểm tra theo tty; shell bên trong thoát 222/mã âm thì rơi về shell ngoài; tích hợp PowerShell của VS Code không bọc; Ctrl+Space chưa tới shell bên trong; mỗi lần thoát chậm ~0,5 s. Việc cho P4: `+crt-static`. Chi tiết: ledger, mục P2b.
- **P3 xong (2026-10-05):** agent và giao thức, nhánh `feat/terminal-sharing-p3` (chưa gộp, chưa đẩy). Phiên `desktop` qua `DesktopSessionManager` (không có hàm tắt), `TermServer`/`TermLink`/`TerminalSharing`, `SessionRouter`, client có `listSessions(includeDesktop)`.
  - Test: core 280, agent 271, client 103, desktop 269, mobile 501, `term_link` 3, term 157 (2 `#[ignore]`); e2e trên relay cục bộ 11 xanh.
  - Còn lại cho người dùng: chạy e2e trên relay thật (`cd packages/shellx_e2e && SHELLX_E2E_RELAY=https://relay.shellx.pro dart test test/desktop_terminal_e2e_test.dart`); chạy CI Windows của job `dart` mới (đẩy `windows-check/p3` khi sẵn sàng); đọc lại spec §7.7–§7.9. Chi tiết, rulings, việc nhỏ còn mở, ghi cho P4/P5: ledger, mục P3.
- **Còn lại:**
  - **P2b:** chờ lần chạy CI Windows đầu tiên (Task 8) rồi mới đóng.
  - P4: code xong (2026-10-05), nhánh `feat/p4-desktop`: công tắc, bộ cài file cấu hình, menu và thông báo, build bundle `shellx-term`, ký. Desktop 372 test xanh, e2e macOS trong HOME tạm. Rulings, việc chờ (bật thử trên máy thật, CI Windows job `desktop`, `shellx-term uninstall` + FAQ chưa làm): ledger, mục P4.
  - P5: mobile.
  - Thứ tự ở spec §14.
- **Kiểm tay còn thiếu** (thêm vào danh sách spec §11.6): gõ bằng bộ gõ tiếng Việt (IME), Cmd+W, giao diện thật của Cursor và Android Studio, iTerm2, VS Code, Warp.
- **Windows:** kiểm tra tương tác trên máy Windows thật là việc chờ (spec §12). Trước khi kiểm xong, công tắc chỉ hiện khi đặt `SHELLX_EXPERIMENTAL=terminal-sharing`.

## 10. Thông báo đẩy (2026-10-05) — User checklist for push

Spec: `specs/2026-10-05-push-notifications-design.md`. Plan: `plans/2026-10-05-push-notifications-core.md` (N-a: relay, agent, hook) và `plans/2026-10-05-push-notifications-apps.md` (N-b: mobile, desktop, chính sách). Firebase: dự án **`shellxpro`**, tài khoản Google **phulealali@gmail.com**; app Android và iOS `com.shellx.prod` đã đăng ký, file cấu hình client đã commit (`apps/mobile/lib/firebase_options.dart`, `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`).

Việc chỉ người dùng làm được, theo thứ tự:

1. **APNs key → Firebase.** Apple Developer → Keys → tạo key có "Apple Push Notifications service (APNs)" (file `.p8`, ghi Key ID và Team ID). Firebase console `shellxpro` → Project settings → Cloud Messaging → Apple app `com.shellx.prod` → upload `.p8`. Không có bước này iPhone không nhận được gì.
2. **Service account FCM → VPS.** Firebase console → Project settings → Service accounts → Generate new private key (JSON, giữ bí mật). Đặt lên VPS đúng theo `deploy/README.md` mục "Push notifications": `~/phu/shellx/secrets/fcm.json` (chủ uid 1000, quyền 400) và dòng `FCM_SERVICE_ACCOUNT=/secrets/fcm.json` trong `~/phu/shellx/.env`. (Kiểm `push_enabled` ở bước 5: image relay đang chạy chưa có code push.)
3. **App ID `com.shellx.prod`:** Apple Developer → Identifiers → bật capability **Push Notifications**; tạo lại provisioning profile (development và App Store) rồi tải về Xcode. Project đã có `Runner/Runner.entitlements` và capability Push + Background Modes (remote-notification).
4. **Bản phát hành iOS:** `Runner.entitlements` đang để `aps-environment` = `development` (để chạy từ Xcode). Bản build App Store/TestFlight phải mang `production`: Xcode tự đổi theo distribution profile khi Archive → Distribute; nếu ký tay, kiểm tra `codesign -d --entitlements - ShellX.app` cho thấy `production`.
5. **Deploy relay:** push `main` (workflow `deploy.yml`) để relay có `push_tokens`, `PUT/DELETE /v1/devices/me/push-token`, `POST /v1/notifications`. Sau khi deploy xong: `cd ~/phu/shellx && docker compose logs relay | grep push_` phải thấy `push_enabled {"project":"shellxpro"}` (nếu thấy `push_disabled`, xem lại bước 2 rồi `docker compose up -d --force-recreate relay`). Chính sách quyền riêng tư mới (mục "Thông báo đẩy") đi cùng lần deploy này — phải lên **trước** khi phát hành app mobile có push.
6. **Cổng build trước khi phát hành:** một bản build Android (`flutter build apk` / `appbundle`) **và** một bản build iOS (Xcode Archive) phải thành công trước khi phát hành. Đã kiểm 2026-10-05: `flutter build apk --debug` thành công, `pod install` thành công (Podfile.lock đã commit); **chưa** build iOS (thiếu dung lượng đĩa, chưa ký).
7. **Nhãn quyền riêng tư của cửa hàng:** App Store Connect → App Privacy và Google Play Console → Data safety cập nhật cho push: FCM token = "Device or other IDs" (dùng cho chức năng ứng dụng, gắn với tài khoản, không theo dõi); nội dung thông báo (dòng lệnh, tên máy…) được chia sẻ với Google (FCM) và Apple (APNs) để gửi thông báo, không lưu trên máy chủ ShellX.
8. **(Tùy chọn) Giới hạn API key Firebase:** Google Cloud console của `shellxpro` → APIs & Services → Credentials: key Android chỉ cho package `com.shellx.prod` + SHA-1 chứng chỉ ký (debug và release/Play App Signing); key iOS chỉ cho bundle id `com.shellx.prod`. Key trong file cấu hình client không phải bí mật, giới hạn chỉ chống lạm dụng.
9. **Kiểm tay trên máy thật** (spec §10, §11): iPhone và Android đăng nhập, ghép nối một máy → app hỏi quyền thông báo một lần; trên máy tính chọn ngưỡng trong tray "Thông báo khi lệnh chạy lâu xong"; trong một phiên ShellX chạy `sleep 40; false` → điện thoại nhận "✗ sleep 40; false · mã 1 · 40 giây" khi app ở foreground (banner), nền và **đã đóng hẳn**; chạm vào → mở đúng máy (và tab nếu còn); `shellx notify "Build xong"` và `printf '\e]9;Xin chào\a'` → thông báo ngay; terminal máy tính được chia sẻ (sau khi bật lại chia sẻ để cài khối mới) cũng báo; Cài đặt app hiện "Đang bật"; tắt thông báo trong cài đặt điện thoại → Cài đặt app hiện "Đang tắt — Mở Cài đặt hệ thống"; đăng xuất → không còn nhận.

Lưu ý: khối tích hợp `term/shell/block.*` có hook mới, nên máy đã bật "Chia sẻ terminal" sẽ thấy "cần thiết lập lại" một lần sau khi cập nhật app desktop.

## Voice input (mobile) — việc của người dùng

- [ ] iPhone thật: chạm mic → hai hộp thoại quyền (micro, nhận dạng giọng nói) bằng tiếng Việt; nói "chạy git status gửi" trong một phiên zsh → `git status` chạy.
- [ ] iPhone: trong Claude Code, nói một câu dài rồi "gửi" → câu tới Claude Code đúng một lần, không tách dòng.
- [ ] iPhone chế độ máy bay: app không ép on-device (plugin không tự quay về cloud trên iOS), Apple tự chọn; nếu Apple nhận dạng được ngay trên máy thì vẫn chạy, nếu không thì hiện "Cần kết nối mạng…".
- [ ] Android thật (có Google app): như trên; máy chưa cài gói tiếng Việt on-device → VI vẫn được thử qua nhận dạng cloud của Google (cần mạng) và chạy; chip VI chỉ mờ + gợi ý EN khi bộ nhận dạng thật sự báo lỗi ngôn ngữ.
- [ ] Android 13+: lần chạm mic đầu không bị treo (danh sách ngôn ngữ chờ tối đa 2 s rồi dùng `vi-VN`/`en-US`).
- [ ] Từ chối quyền → dòng lỗi + "Mở Cài đặt" mở đúng trang cài đặt của ShellX.
- [ ] Đang nghe thì có cuộc gọi / khoá màn hình → dừng nghe, chữ còn nguyên, không tự gửi.
- [ ] App Store Connect / Play Console: cập nhật nhãn quyền riêng tư (Audio data — dùng cho chức năng app, không thu thập về máy chủ ShellX) nếu biểu mẫu yêu cầu.

## 11. Cửa sổ terminal trên desktop — A1 (2026-10-06)

- Spec: `docs/superpowers/specs/2026-10-06-desktop-terminal-a1-design.md`; UI: `docs/superpowers/design/2026-10-06-shellx-desktop-ui.md`; plan: `docs/superpowers/plans/2026-10-06-desktop-terminal-a1.md`.
- Trạng thái: A1 nằm trên `main` (merge từ `feat/desktop-a1` sau đợt sửa cuối, 2026-10-06). Số test lần chạy cuối (đợt sửa cuối, trước merge): `packages/shellx_agent` 386 pass; `apps/desktop` 627 pass + 1 bỏ qua (benchmark có tag). Windows **chưa thử trên máy thật**.
- Bộ nhớ: tối đa 32 tab × 10 000 dòng scrollback xterm mỗi tab (cộng ring buffer 256 KiB/phiên ở agent). xterm 4.0.0 lưu mỗi ô 16 byte (4 × uint32), nên một tab đầy ở 160 cột ≈ 10 000 × 160 × 16 B ≈ 26 MB (80 cột ≈ 13 MB); 32 tab đầy ở 160 cột ≈ 0,8 GB trong trường hợp xấu nhất. Chấp nhận cho A1 (ít ai giữ 32 tab đầy); nếu đo thật (mục thử tay 23) quá nặng thì giảm `maxLines` cho tab ẩn ở milestone sau.
- Benchmark xterm (`flutter test --run-skipped --tags benchmark test/terminal/xterm_benchmark_test.dart`, MacBook Mac16,10 / Apple M4, flutter test VM chế độ debug, lát 256 KiB, lưới 160x48; số từ commit `da98f80`):
  - `yes x2M: total 925ms, slowest slice 77ms, 6.2 MB/s (met)`
  - `cat 50 MB: total 1638ms, slowest slice 11ms, 30.5 MB/s (met)`
  - `SGR 8 MB: total 336ms, slowest slice 13ms, 23.7 MB/s (met)`
  - `TerminalFeed: 50 MiB in, 1.06 MiB written, 87 drops`
- Sửa spec v1 (`2026-09-25-shellx-v1-design.md`): D2; §3.2 (terminal trên desktop nay trong phạm vi); đăng xuất agent và 4002/401 (ngắt điện thoại, phiên vẫn chạy, chỉ Thoát mới đóng); giới hạn phiên 10 → 32 (§ giao thức, bảng lỗi, phần kiểm thử); §8.2 (Dock/thanh menu khi cửa sổ hiện, D10); §8.3 (mục tray "Mở cửa sổ terminal" ở đầu menu, tắt truy cập từ xa không đóng phiên).
- Quyền riêng tư: nội dung terminal của cửa sổ chỉ ở trong tiến trình ShellX trên máy; điện thoại vẫn nhận qua kênh mã hóa đầu cuối như cũ; không thêm loại dữ liệu mới gửi lên relay ngoài ngoại lệ thông báo đẩy N3 (nay áp dụng cả cho tab mở trên desktop: mọi phiên ShellX, dù do điện thoại hay desktop mở, đều đi qua `SessionManager` và cùng một `SessionNotifier`); khi chưa đăng nhập thì không có token, API từ chối ngay tại chỗ và không gì rời máy. Không cần sửa `web/src/pages/privacy.md` / `en/privacy.md`.

### Thử tay — macOS (máy thật)

- [ ] 1. Mở ShellX từ Finder/Launchpad: cửa sổ terminal hiện, có một tab zsh (`-l`) ở `~`, gõ được ngay; icon ShellX ở Dock, có trong ⌘Tab, thanh menu có "Quit ShellX ⌘Q".
- [ ] 2. `vim`, `htop`, `less` (phím mũi tên, Esc, màu 256/truecolor: `printf '\e[38;2;255;100;0mTRUECOLOR\e[0m\n'`), Claude Code; kéo đổi cỡ cửa sổ → chương trình vẽ lại đúng.
- [ ] 3. Bộ gõ tiếng Việt (Telex, Unikey/macOS VN): gõ "Tiếng Việt" trong zsh và trong vim, không mất/lặp ký tự. **Lặp lại sau khi chuyển qua lại giữa các tab** (⌘1/⌘2, bấm sidebar) — vẫn gõ Telex đúng ở tab vừa chọn.
- [ ] 4. ⌘T, ⌘W (tab rảnh: đóng ngay; tab đang chạy `sleep 100`: hỏi xác nhận), ⌘1…⌘9, ⌃Tab/⌃⇧Tab, chọn chữ rồi ⌘C, ⌘V (dán nhiều dòng trong vim khi bracketed paste bật), ⌘+/⌘−/⌘0.
- [ ] 5. Chuyển vùng bằng **Ctrl+F6** (sidebar ↔ terminal), ↑/↓ trong sidebar, Esc về terminal. **F6 thường phải tới được chương trình TUI** (ví dụ `htop`: F6 mở "Sort by", không bị cửa sổ nuốt).
- [ ] 6. Điện thoại: tab mở trên desktop hiện trong danh sách phiên của điện thoại ≤ 2 s; gõ cùng lúc trên cả hai, không ai bị đẩy ra; khi điện thoại gõ, dải vàng "Điện thoại đang dùng…" hiện, cỡ PTY theo điện thoại; gõ trên desktop (sau 1 s) lấy lại. Điện thoại mở phiên → tab mới có biểu tượng điện thoại, không tự chọn.
- [ ] 7. Điện thoại "Đóng" một tab mở trên desktop → chỉ tách, shell vẫn chạy trên desktop.
- [ ] 8. Nút đỏ đóng cửa sổ → ẩn, icon Dock biến mất; điện thoại vẫn dùng được; mở lại từ Dock/Finder/tray "Mở cửa sổ terminal" → tab còn nguyên, nội dung gần nhất hiện lại; vị trí/cỡ cửa sổ được nhớ (kể cả sau khi thoát và mở lại app).
- [ ] 9. **Dock và thanh menu đi theo cửa sổ:** cửa sổ hiện → icon Dock + thanh menu ShellX (có trong ⌘Tab); cửa sổ ẩn → Dock/⌘Tab không còn ShellX, chỉ còn icon tray; mở lại → trở lại như cũ, không chớp hay mất menu.
- [ ] 10. Đăng xuất (tray) → điện thoại bị ngắt, shell vẫn chạy, dải "Đăng nhập để dùng từ điện thoại" hiện; mở lại app khi chưa đăng nhập → không bật hộp thoại đăng nhập, terminal dùng được.
- [ ] 11. Tắt "Cho phép truy cập từ xa" khi có điện thoại kết nối → hỏi (câu mới), shell vẫn chạy.
- [ ] 12. **⌘Q từ menu ứng dụng** (Quit ShellX) với tab đang mở → một hộp xác nhận; đồng ý → mọi shell (cả cây tiến trình, kiểm tra `ps`) bị đóng, app thoát. ⌘Q lần hai khi hộp đang mở → vẫn chỉ một hộp. Hủy → mọi shell còn nguyên.
- [ ] 13. **Đăng xuất macOS / Khởi động lại / Tắt máy không bị ShellX chặn**, kể cả khi một tab đang chạy lệnh (`sleep 1000`): hệ thống không hiện "ShellX đã ngăn tắt máy", không có hộp xác nhận ⌘Q.
- [ ] 14. `yes` chạy 10 s rồi Ctrl+C, và `cat` một file 50 MB: UI không treo quá 1 s; ẩn cửa sổ trong lúc chạy rồi mở lại → thấy output mới nhất.
- [ ] 15. Shell thoát mã 0 (`exit`) ở tab không được chọn → tab đó tự đóng, tab đang chọn giữ nguyên; `exit 3` → dòng "[Tiến trình đã thoát, mã 3] — Enter để đóng", Enter đóng tab.
- [ ] 16. **Màn hình ngoài bị rút:** kéo cửa sổ sang màn hình ngoài, thoát app, rút màn hình, mở lại → cửa sổ hiện **ở giữa** màn hình còn lại (không nằm ngoài tầm nhìn). Cũng thử: rút màn hình khi app đang chạy rồi mở lại cửa sổ từ Dock/tray.
- [ ] 17. **Prompt đầu tiên không bị vẽ lại lúc khởi động:** mở app (và ⌘T tab mới), dòng prompt zsh đầu tiên xuất hiện đúng một lần, không bị xóa/vẽ lại bởi lần đổi cỡ ngay sau khi cửa sổ hiện.
- [ ] 18. **Cửa sổ lên trước khi đang thu nhỏ hoặc bị che:** ⌘M thu nhỏ cửa sổ (hoặc để app khác che, hoặc chuyển sang Space khác) rồi bấm tray "Ghép nối điện thoại…" → cửa sổ bung ra, lên trước, hộp QR hiện; tương tự với tray "Thoát" khi có tab (hộp xác nhận phải thấy được), "Đổi mật khẩu…", "Đăng xuất", "Đóng tất cả".
- [ ] 19. **Bấm icon Dock sau ⌘M** → cửa sổ bung ra (không chỉ kích hoạt app). Mở ShellX lần nữa từ Finder/Spotlight khi cửa sổ thu nhỏ → cũng bung ra.
- [ ] 20. **Thông báo trên điện thoại khi tắt truy cập từ xa:** điện thoại đang xem một tab → tắt "Cho phép truy cập từ xa" → điện thoại chỉ thấy mất kết nối (không báo "máy đã đóng phiên"), bật lại → điện thoại tự gắn lại vào tab, shell vẫn chạy.
- [ ] 21. **Mở app điện thoại khi đang gõ trên desktop:** đang gõ trong một tab desktop, điện thoại kết nối lại vào đúng tab đó (resume) → desktop vẫn là bên điều khiển, không có dải vàng, PTY giữ cỡ desktop; chỉ khi điện thoại gõ/đổi cỡ thì nó mới lấy quyền.
- [ ] 22. **Thanh menu macOS sau khi chuyển accessory → regular:** ẩn cửa sổ (nút đỏ), mở lại từ tray → thanh menu hiện tên ShellX và menu đầy đủ ngay (không phải bấm ra app khác rồi quay lại), ⌘Q hoạt động.
- [ ] 23. **Bộ nhớ:** 32 tab, mỗi tab `seq 1 20000` (đầy 10 000 dòng scrollback) → Activity Monitor: bộ nhớ ShellX ổn định, UI vẫn mượt; ghi lại con số vào đây.
- [ ] 24. **Quét QR từ hộp thoại:** tray "Ghép nối điện thoại…" → điện thoại quét mã trong hộp (cửa sổ 1100×720 và 640×400) → ghép thành công, hộp tự đóng.
- [ ] 25. **Menu chuột phải trong terminal:** chưa chọn chữ → "Sao chép" mờ; "Dán" dán clipboard; "Chọn tất cả" chọn cả scrollback, rồi chuột phải → "Sao chép" sao chép được. Trong `vim` có `:set mouse=a`, chuột phải đi vào vim (không hiện menu). Nút × trên tab (khi rê chuột hoặc tab đang chọn) đóng tab, hỏi nếu đang chạy lệnh. ⌥←/⌥→ ở prompt zsh nhảy theo từ.
- [ ] 26. **Phóng to / toàn màn hình được nhớ:** phóng to cửa sổ (nút xanh / double-click thanh tiêu đề), thoát, mở lại → cửa sổ mở phóng to; bỏ phóng to → về đúng cỡ thường trước đó (không phải cỡ toàn màn hình).

### Thử tay — Windows (máy thật, Windows 10 1809+ / 11)

- [ ] 1. Mở ShellX từ Start menu: cửa sổ terminal hiện với một tab PowerShell ở `%USERPROFILE%`; **có nút trên taskbar khi cửa sổ hiện, mất khi ẩn**; **title bar hệ thống tối** (dark) ngay từ khung hình đầu, không chớp trắng.
- [ ] 2. Ctrl+Shift+T / Ctrl+Shift+W / Ctrl+Alt+1…9 / Ctrl+Tab / Ctrl+Shift+Tab / Ctrl+Shift+C (có vùng chọn) / Ctrl+Shift+V / Ctrl+= / Ctrl+− / Ctrl+0; Ctrl+C trong PowerShell vẫn ngắt lệnh; Ctrl+Shift+C không có vùng chọn không làm gì sai. Chuyển vùng bằng Ctrl+F6; F6 thường tới được TUI.
- [ ] 3. **AltGr:** bàn phím có AltGr (ví dụ Đức/Pháp/Tây Ban Nha): AltGr+Q → `@`, AltGr+7 → `{`, AltGr+8 → `[`… gõ ra đúng ký tự trong PowerShell và trong vim, không bị coi là Ctrl+Alt (không kích hoạt Ctrl+Alt+1…9).
- [ ] 4. Các mục 2, 3 (bộ gõ tiếng Việt Unikey/EVKey, cả sau khi chuyển tab), 6–8, 10–11, 14–15, 17, 18 (thu nhỏ rồi dùng tray), 20–21, 23–26 của macOS (chuyển ⌘ thành Ctrl+Shift; Chọn tất cả = Ctrl+Shift+A; ⌥←/→ không áp dụng).
- [ ] 5. Alt+F4 / nút X → ẩn vào khay, shell vẫn chạy; mở lại lần hai (chạy ShellX.exe lần nữa) → cửa sổ hiện lại, không có tab thứ hai.
- [ ] 6. Tray "Thoát" với tab đang mở → hỏi; đồng ý → `Get-Process pwsh,powershell` không còn tiến trình con của ShellX. Đăng xuất / tắt máy Windows không bị ShellX chặn.
- [ ] 7. Snap layouts (Win+Z) và kéo đổi cỡ: tối thiểu 640×400, nhớ vị trí; rút màn hình ngoài rồi mở lại → cửa sổ hiện ở giữa màn hình còn lại.

## 12. Sidebar giàu thông tin — A2 (2026-10-07)

- Spec: `docs/superpowers/specs/2026-10-07-desktop-sidebar-a2-design.md`; UI: `docs/superpowers/design/2026-10-07-shellx-desktop-ui-a2.md`; plan: `docs/superpowers/plans/2026-10-07-desktop-sidebar-a2.md`.
- Trạng thái: nhánh `feat/desktop-a2`; số test agent/core/desktop: xem kiểm tra cuối khi merge.
- Hook shell (zsh/bash/pwsh) nay phát OSC 7 ở mỗi prompt; `term/shell/block.*` đổi theo (D1). Ai đã bật chia sẻ terminal chỉ có OSC 7 sau khi bật lại.
- Quyền riêng tư: thư mục và nhánh tới điện thoại (đã opt-in `desktop: true`) qua kênh mã hoá đầu cuối như mọi `SessionInfo`; relay không đọc được; cổng không gửi. Không cần sửa trang privacy.
- Agent chạy `lsof`/`ps` (macOS) hoặc `netstat`/`powershell` (Windows) mỗi 3 s **chỉ khi cửa sổ hiện**; không bao giờ chạy `git`.

### Thử tay — macOS
- [ ] 1. Tab mới: dòng thứ hai hiện `~` ngay prompt đầu; `cd ~/Documents/"Tài liệu"` → `~/Documents/Tài liệu` (đúng dấu, không `%20`).
- [ ] 2. `cd` vào repo → nhánh hiện ≤ 300 ms; `git switch -c test-a2` → nhánh mới; `git checkout HEAD~1` → SHA 7 ký tự; worktree (`git worktree add ../wt`) và submodule đúng nhánh của chính nó.
- [ ] 3. `python3 -m http.server 8000` → `:8000` ≤ 4 s; bấm mở `http://localhost:8000/` trong trình duyệt, tab không đổi; Ctrl+C → biến mất ≤ 4 s. `npm run dev` (Vite) → `:5173`. Bốn server → 3 cổng + `+1`, tooltip liệt kê đủ.
- [ ] 4. Ẩn cửa sổ (nút đỏ) → `sudo fs_usage -w -f exec | grep -E 'lsof|ps'` không còn dòng nào trong 30 s; mở lại → cổng cập nhật ngay.
- [ ] 5. 10 tab, cửa sổ hiện, để yên 1 phút → CPU ShellX trung bình ≤ 2 % (Activity Monitor); ghi số đo vào đây.
- [ ] 6. Thư mục trên ổ mạng (SMB) và một monorepo lớn → UI không khựng; nhánh hiện hoặc không, không treo.
- [ ] 7. `ssh` vào máy có tích hợp OSC 7 → thư mục và nhánh biến mất; thoát ssh → hiện lại.
- [ ] 8. ⌘⇧N → "Workspace 2" có một tab, ô tên mở sẵn; gõ "Backend" Enter → bàn phím về terminal. Double-click tên → đổi tên; menu → Xóa (Mặc định: mục mờ); tab về Mặc định, toast trung tính.
- [ ] 9. Kéo tab giữa hai workspace và trong một workspace (vạch thả hiện đúng chỗ), kéo lên tiêu đề nhóm thu gọn → 0,6 s tự mở; kéo gần mép → tự cuộn.
- [ ] 10. ⌘1…⌘9 theo thứ tự nhìn thấy (bỏ nhóm thu gọn); Ctrl+Tab cũng vậy; Ctrl+F6 vào danh sách, ↑/↓ qua tiêu đề, ←/→ thu gọn/mở, F2 đổi tên, ⌥↑/⌥↓ chuyển tab.
- [ ] 11. Thoát app, mở lại → các workspace, tên, trạng thái thu gọn còn; tab mới vào Mặc định.
- [ ] 12. Điện thoại mở phiên → tab vào Mặc định, không được chọn. Điện thoại (bản có `desktop: true`) thấy `cwd`/`branch` trong danh sách (kiểm bằng log debug của app mobile); app mobile cũ vẫn liệt kê bình thường.
- [ ] 13. VoiceOver: dòng tab đọc "…, nhánh main, thư mục ~/…, cổng 3000, tab 2 trên 3 trong Backend"; tiêu đề đọc tên, số tab, trạng thái mở/thu gọn; actions "Đổi tên tab", "Chuyển tới workspace…", "Mở cổng …" chạy được. Bật "Giảm chuyển động" → chevron không xoay.
- [ ] 14. Hostname macOS có và không có hậu tố `.local` (đổi trong Cài đặt → Chia sẻ → Tên máy cục bộ, hoặc `scutil --set HostName`): `cwd` vẫn được coi là máy cục bộ (thư mục và nhánh hiện, không bị xoá như ssh).
- [ ] 15. Kéo thả với danh sách dài (≥ 30 tab, nhiều workspace): giữ trong vùng 32 px sát mép trên/dưới → tự cuộn mượt với tốc độ **cố định 240 px/s**; thả đúng chỗ vạch hiện; thả ngoài danh sách → không đổi gì. Esc trong lúc kéo **không hỗ trợ** trong A2 (Flutter `Draggable` không huỷ bằng phím): bấm Esc không huỷ, thả ngoài danh sách để huỷ.
- [ ] 18. Đợt sửa cuối A2 (visual QA): bóng kéo là chip gọn, đục, lệch xuống-phải con trỏ, không che vạch thả/tiêu đề đích, không ra ngoài danh sách; cuộn danh sách dài → tiêu đề nhóm hiện tại dính ở trên cùng (có vạch 1 px), bấm nó vẫn thu gọn; chuột phải dòng/tiêu đề → dòng đó được tô cho tới khi menu đóng, menu "Chuyển tới" ghi tên tab; ô đổi tên cao 22, chữ không nhảy ngang khi mở; nhánh có biểu tượng nhánh; thư mục khi chật thành `…/shellx` hoặc `shell…`, không còn mảnh vô nghĩa kiểu `~/w…llx`.
- [ ] 16. Bộ gõ Telex (hoặc Unikey/VNI) trong ô tên tab và tên workspace: gõ "Dịch vụ" (dấu đang soạn) → Enter chỉ chốt khi hết soạn, không mất/lặp ký tự; Esc hủy đúng.
- [ ] 17. Click một lần chỉ chọn tab/tiêu đề (không mở ô tên); double-click mới đổi tên; click rồi kéo không kích hoạt đổi tên.

### Thử tay — Windows
- [ ] 1. PowerShell: `cd C:\Users\<bạn>\Tài liệu` → `~\Tài liệu`; ổ khác `D:\src` giữ nguyên; thư mục UNC hiện đường dẫn, không có nhánh.
- [ ] 2. `python -m http.server 8000` → `:8000` (Windows tiếng Đức/Pháp: vẫn đúng — không dựa chữ LISTENING); tiến trình `powershell` CIM chỉ chạy khi có cổng mới (Process Monitor).
- [ ] 3. Mục 2, 3, 5, 8–11, 13 (Narrator) của macOS với Ctrl+Shift+N, Ctrl+Alt+1…9, Alt+↑/↓.
- [ ] 4. Hook PowerShell phát OSC 7 trên Windows thật, cả Windows PowerShell 5.1 và pwsh 7: `cd` vào thư mục có dấu cách, tiếng Việt, `#`, `%` (ví dụ `C:\tmp\a b`, `C:\tmp\Tài liệu`, `C:\tmp\c#1`, `C:\tmp\100%`) → thư mục hiện đúng, không `%20`, không cắt ở `#`.
- [ ] 5. `WindowsPortProbe` trên Windows thật (chạy `%SystemRoot%\System32\netstat.exe` và `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe` bằng đường dẫn tuyệt đối — một `netstat.exe` giả trong thư mục làm việc hay đầu PATH không được chạy): `netstat -ano` + CIM (`Get-CimInstance Win32_Process`) cho cổng đúng theo cây tiến trình của tab; thử Windows có netstat bản địa hóa (Đức/Pháp/Việt) → vẫn đúng cổng; không có cửa sổ console nháy lên mỗi 3 s.
- [ ] 6. Narrator trên cây workspace: đọc đúng tên, số tab, mở/thu gọn, vị trí "tab n trên m"; ←/→ và F2 chạy.
- [ ] 7. Bộ gõ Telex/Unikey/EVKey trong ô tên tab và workspace; double-click để đổi tên so với click đơn để chọn (như macOS 16, 17); kéo thả danh sách dài + tự cuộn (như macOS 15).
