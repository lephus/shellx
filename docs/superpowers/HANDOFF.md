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

## 13. Thông báo kiểu cmux — A4 (2026-10-07)

- Spec: `docs/superpowers/specs/2026-10-07-desktop-notifications-a4-design.md`; UI: `docs/superpowers/design/2026-10-07-shellx-desktop-ui-a4.md`; plan: `docs/superpowers/plans/2026-10-07-desktop-notifications-a4.md`.
- Trạng thái: nhánh `feat/desktop-a4`; số test agent/desktop: xem kiểm tra cuối khi merge.
- Push sang điện thoại không đổi (N8); OSC 99 và BEL chỉ ở máy tính. Chữ thông báo không bao giờ vào log, cài đặt hay đĩa (N9).

Thử tay trên macOS 14/15 và Windows 10/11 thật (CI không có):

### Thử tay — macOS
- [ ] 1. Tab B không chọn: `printf '\e]9;Build xong\a'` → badge 1 + dòng "Build xong" ≤ 200 ms; Dock hiện 1.
- [ ] 2. `printf '\e]777;notify;CI;Đã xanh\a'`, `shellx notify xong`, `printf '\e]99;;Xin chào\e\\'`, OSC 99 hai mảnh (`i=1:d=0` rồi `i=1:p=body`), `e=1` base64 tiếng Việt.
- [ ] 3. Claude Code với `preferredNotifChannel` = `kitty`, `iterm2`, `terminal_bell`: tab của nó có badge khi chờ trả lời.
- [ ] 4. `printf '\a'` liên tục 10 s → tối đa 2 chuông; gõ Tab-completion sai trong tab đang xem → không có gì.
- [ ] 5. Ngưỡng 10 s: `sleep 11; false` trong tab không chọn → "✗ … · mã 1 · 11 giây"; Tắt → không.
- [ ] 6. Chọn tab có badge, rời trước 1 s → còn; ở lại 1 s → mất; vòng sáng quanh terminal khi cửa sổ ở sau app khác rồi focus lại; giảm chuyển động (Cài đặt hệ thống) → vòng tĩnh.
- [ ] 7. ⌘⇧I / Ctrl+Shift+I: bảng, ↑/↓/Enter nhảy tới tab trong workspace thu gọn; ⌘⇧U lần lượt các tab chưa đọc; hết → toast.
- [ ] 8. Cửa sổ ở sau app khác / thu nhỏ / ở Space khác: thông báo hệ thống tới; bấm trong Notification Center → cửa sổ lên trước (đúng Space, hết thu nhỏ), đúng tab (workspace thu gọn tự mở), badge của tab mất ngay, gõ được ngay; vòng lặp 20 OSC 9 → 2 thông báo; đọc tab → thông báo biến khỏi Notification Center. Đóng tab rồi bấm thông báo cũ của nó → chỉ đưa cửa sổ lên.
- [ ] 9. Focus: cửa sổ trước + tab đang xem → không badge, không thông báo; thu nhỏ cửa sổ (⌘M) rồi gửi OSC 9 vào tab đang chọn → có badge và thông báo; chuyển Space khác → cũng vậy.
- [ ] 10. Tray → Thông báo: tắt "Thông báo trên máy tính" → không còn thông báo hệ thống (badge vẫn); tắt "Chỉ khi…" → tab không chọn khi cửa sổ đang trước cũng thông báo; còn sau khi khởi động lại; dùng được khi **chưa đăng nhập**.
- [ ] 11. Dock badge trên macOS 14+: khi app đã được cấp quyền thông báo có "Badges" (Cài đặt hệ thống → Thông báo → ShellX) → số hiện trên icon Dock, `99+` khi quá 99, mất khi đọc hết; tắt "Badges" → không hiện, không lỗi. Ghi lại ở đây có cần quyền badge riêng không.
- [ ] 12. Ẩn cửa sổ (nút đỏ) rồi hiện lại → Dock badge vẫn đúng số (icon Dock trở lại trước, badge sau).
- [ ] 13. Điện thoại đã ghép: OSC 9/777 và lệnh chạy lâu vẫn push như trước; OSC 99 và BEL không push.
- [ ] 14. VoiceOver: dòng tab đọc "N thông báo chưa đọc, mới nhất: …"; cửa sổ đang trước, thông báo tới tab khác → đọc "Thông báo mới từ {tab}: {chữ}" một lần (OSC 9 dồn dập trong 3 s chỉ đọc cái đầu); tab đang xem hoặc cửa sổ ở sau → không đọc. Mở bảng ⌘⇧I → "Thông báo, N mục".
- [ ] 15. Focus/Không làm phiền bật → không lỗi, badge/vòng vẫn chạy.

### Thử tay — Windows
- [ ] 1. `flutter build windows` thành công (CMake bật `/W4 /WX`: mọi cảnh báo trong `windows/runner/flutter_window.cpp` là lỗi).
- [ ] 2. Mục 1–7, 10, 13, 15 của macOS với Ctrl+Shift+I, Ctrl+Shift+U.
- [ ] 3. Chấm accent trên nút taskbar khi có chưa đọc (Narrator đọc mô tả "N thông báo chưa đọc"); gỡ khi đọc hết; Explorer khởi động lại (`taskkill /f /im explorer.exe` rồi chạy lại) → chấm trở lại khi còn chưa đọc.
- [ ] 4. Nút taskbar nháy khi có thông báo mới lúc app khác đang ở trước (và lúc cửa sổ thu nhỏ); không nháy khi cửa sổ đang focus.
- [ ] 5. Toast trong Action Center: bấm → cửa sổ lên trước, đúng tab, badge mất, gõ được ngay; đọc tab → toast biến khỏi Action Center; tab đã đóng → chỉ đưa cửa sổ lên.
- [ ] 6. Narrator: dòng tab đọc "N thông báo chưa đọc, mới nhất: …"; thông báo tới tab khác khi cửa sổ đang trước được đọc một lần.

## 14. Chia pane — A3 (2026-10-07)

- Spec: `docs/superpowers/specs/2026-10-07-desktop-splits-a3-design.md`. Không đổi giao thức, không đổi điện thoại: mỗi pane là một phiên; điện thoại mở phiên luôn thành tab mới.

Thử tay trên **macOS và Windows thật** (CI không có; spec §6):

- [ ] ⌘D / Ctrl+Shift+D trong `~/work/shellx` (zsh, bash, PowerShell có hook) → pane mới bên phải, `pwd` đúng thư mục; ⌘⇧D / Ctrl+Shift+Alt+D → bên dưới. Thử trong một git worktree (cwd là thư mục worktree, không phải repo gốc). Shell không hook (fish, cmd) → home.
- [ ] Thư mục trên ổ mạng chậm/không phản hồi (`/Volumes/nas`, ổ ánh xạ) → pane mới ở home trong ≤ 0,3 s, không treo; UNC trên Windows → home.
- [ ] `vim`, `htop`, Claude Code trong hai pane cạnh nhau: `tput cols` mỗi pane đúng cỡ của nó; kéo đường chia → cả hai vẽ lại đúng; nháy đúp đường chia → 50/50.
- [ ] ⌘⌥mũi tên / Ctrl+Alt+mũi tên chuyển focus đúng theo hình (chữ T, lưới 2×2); máy Windows có driver Intel cũ: kiểm Ctrl+Alt+mũi tên không xoay màn hình (nếu có, ghi lại).
- [ ] Bàn phím Đức/Ba Lan trên Windows: AltGr+Shift+D, AltGr+mũi tên vẫn gõ ký tự vào shell, không chia/không chuyển pane.
- [ ] ⌘⇧↩ phóng to/bỏ; pane ẩn vẫn chạy (`ping` vẫn chạy khi quay lại); ⌘⌃= cân bằng ba cột; ⌘⌃mũi tên dời đường chia; không pane nào < 20 cột.
- [ ] ⌘W đóng pane đang focus, focus về pane dùng gần nhất; pane đang chạy `sleep 100` → hỏi "Lệnh đang chạy trong pane này…"; × dòng sidebar đóng cả tab, hỏi "2 pane đang chạy lệnh…".
- [ ] `exit` (0) trong một pane → pane biến mất; `exit 3` → dòng thoát, Enter đóng đúng pane đó.
- [ ] Điện thoại: mỗi pane là một phiên trong danh sách; gõ trên điện thoại vào pane 2 → dải driver chỉ ở pane 2; điện thoại mở phiên → tab mới.
- [ ] Thông báo: pane không focus `printf '\e]9;xong\a'` → badge dòng, vòng chỉ quanh pane đó; bấm pane đó, chờ 1 s → tắt; ⌘⇧U focus đúng pane.
- [ ] VoiceOver / Narrator: đọc "Pane 2 trên 3 — vim" khi chuyển focus bằng phím; đọc khi chia/đóng/phóng to; đường chia là thanh trượt tăng/giảm được.
- [ ] Windows, màn hình 125 % (và 150 %): đường chia 1 px sắc nét, không nhoè hay lệch nửa điểm ảnh. Đã biết: gốc vùng terminal x = 221 không nằm trên lưới điểm ảnh vật lý ở 1,25×; các cạnh chia đã làm tròn theo điểm ảnh thiết bị, nhưng cần nhìn bằng mắt ở 1,25× và ghi lại nếu đường chia mờ.
- [ ] Tab một pane trông giống hệt trước A3 (so ảnh chụp với bản A4); test tự động: `apps/desktop/test/ui/one_pane_parity_test.dart`.

## 15. Khôi phục phiên — A5a (2026-10-07)

Spec `specs/2026-10-07-desktop-restore-a5a-design.md`, UI `design/2026-10-07-shellx-desktop-ui-a5.md`, plan `plans/2026-10-07-desktop-restore-a5a.md`. Shell **không** sống qua thoát (A5b mới làm); A5a mở shell mới ở thư mục cũ và vẽ lại nội dung cũ trên vạch "— Phiên được khôi phục · … —".

Riêng tư: `restore/` (macOS `~/Library/Application Support/pro.shellx.desktop/restore`, Windows `%LOCALAPPDATA%\ShellX\restore`) chứa nội dung terminal (có thể có bí mật): 0700/0600, loại khỏi Time Machine, không bao giờ rời máy; tắt/xoá ở tray → Terminal; gỡ cài đặt Windows xoá thư mục. Trang chính sách §4 đã cập nhật (vi/en).

Đo (spec tiêu chí 10, đo không chặn): từ `apps/desktop`, `flutter test --run-skipped --tags benchmark test/restore/restore_benchmark_test.dart` (phải có `--run-skipped`: `dart_test.yaml` bỏ qua thẻ `benchmark`). Apple M4, 2026-10-07: mã hoá 32 pane × 2.000 dòng ~85 ms + ghi ~37 ms = **~120 ms** (≤ 500 ms); ghi bố cục 32 tab ~6 ms (≤ 20 ms).

### Thử tay — macOS
- [ ] ⌘Q / mở lại: workspace, tab, tên, cây pane, tỉ lệ, phóng to, pane focus, tab chọn; không có tab thừa
- [ ] `seq 1 5000` → 3001…5000 + vạch + prompt mới; `ls --color` giữ màu; `history` không có rác
- [ ] vim mở lúc thoát → nội dung trước vim được lưu, không có màn hình vim
- [ ] `kill -9` → dải "đóng bất thường"; Esc/Đóng; F6 tới được; Tab từ dải → terminal, Shift+Tab → sidebar
- [ ] VoiceOver: dải được đọc **một lần** khi hiện (lịch sự, không ngắt lời); nút Đóng đọc "Đóng thông báo khôi phục"
- [ ] Khởi động lại máy không thoát app (menu Apple → Restart) → khôi phục đủ, không có dải
- [ ] Đăng xuất (Log Out) khi ShellX mở → mở lại: khôi phục đủ, không có dải
- [ ] Đăng xuất bị huỷ (một app khác từ chối thoát): nhiều khả năng ShellX đã thoát (đã trả lời đồng ý). Nếu ShellX vẫn chạy: sau ~10 s việc lưu chạy lại; `kill -9` lúc đó → lần mở sau có dải
- [ ] Ẩn cửa sổ (đóng cửa sổ, app vẫn ở tray) → `restore/layout.json` đổi giờ sửa ngay (`ls -l`), không đợi 60 s
- [ ] cwd bị xoá / ổ mạng ngắt / thư mục SMB → home, không chờ
- [ ] Tray → Terminal → bỏ chọn → `restore/scrollback` rỗng ngay; "Xóa nội dung đã lưu" mờ
- [ ] `ls -l` quyền 700/600; `tmutil isexcluded` → Excluded
- [ ] Điện thoại: phiên được khôi phục **không** có nội dung cũ
- [ ] Đo: chạy lệnh benchmark ở trên trên máy thật, ghi số (mốc: ~120 ms trên M4; tiêu chí < 500 ms)

### Thử tay — Windows
- [ ] `flutter build windows` thành công (`/W4 /WX`). C++ của A5a **chưa từng được biên dịch**: kênh `pro.shellx.desktop/app`, `flutter::MethodResultFunctions`, `MsgWaitForMultipleObjects`/`GetTickCount64`, `ENDSESSION_CLOSEAPP` trong `windows/runner/flutter_window.cpp`
- [ ] Như macOS (trừ Time Machine, VoiceOver, Log Out): Thoát ở tray, `seq`/màu, vim, `End task` trong Task Manager → dải, cwd mất/UNC → home, công tắc tray, điện thoại
- [ ] Start → Restart khi ShellX mở → mở lại: khôi phục đủ, nội dung có (cũ nhất 60 s), không có dải
- [ ] Huỷ tắt máy (Notepad có chữ chưa lưu → Cancel): việc lưu chạy lại (`exitCancelled`); `End task` sau đó → lần mở sau có dải. Rồi tắt máy lại (hỏi → huỷ → hỏi lại) → lần mở sau **không** có dải
- [ ] Restart Manager (một trình cài đặt/công cụ gọi `RmShutdown` lên ShellX.exe): ShellX lưu rồi tự thoát, **không** hỏi xác nhận; lần mở sau không có dải
- [ ] Cập nhật khi ShellX đang chạy (update while running → no strip on next launch): chạy bản cài mới → bản cài ghi `%APPDATA%\pro.shellx\ShellX\quit.signal`, ShellX lưu rồi tự thoát (không hỏi) trong ≤ 8 s, rồi mới cài; lần mở sau khôi phục đủ, **không** có dải. `taskkill /F` chỉ còn là đường lùi khi ShellX không thoát kịp (khi đó có dải)
- [ ] `icacls "%LOCALAPPDATA%\ShellX\restore"` → chỉ tài khoản của bạn (cùng SYSTEM/Administrators thừa hưởng), không có Users/Everyone
- [ ] Không có LOCALAPPDATA (`set LOCALAPPDATA=` trong cmd rồi chạy ShellX.exe từ đó): app khởi động bình thường, không lưu/không khôi phục gì, không lỗi
- [ ] Ẩn cửa sổ → `layout.json` đổi giờ sửa ngay
- [ ] Narrator: dải có thể bị đọc **hai lần** (vùng live + `sendAnnouncement`). Ghi lại; nếu đọc hai lần thì bỏ một trong hai
- [ ] Màn hình 125 % (mang từ A3 §14): đường chia 1 px sắc nét; gốc vùng terminal x = 221 không nằm trên lưới điểm ảnh vật lý ở 1,25× — nhìn bằng mắt, cả khi dải khôi phục đang hiện
- [ ] Gỡ cài đặt xoá `%LOCALAPPDATA%\ShellX\restore`

## 16. Dòng lệnh shellx — A7 (2026-10-07)

Spec `specs/2026-10-07-desktop-cli-a7-design.md`, plan `plans/2026-10-07-desktop-cli-a7.md`. Lệnh `shellx` (bản chép của `shellx-term`) ở macOS `~/Library/Application Support/ShellX/cli/shellx`, Windows `%LOCALAPPDATA%\ShellX\cli\shellx.exe`; mỗi shell ShellX mở có nó đầu `PATH` cùng `SHELLX_SOCKET` và `SHELLX_CLI_TOKEN` (token mỗi lần chạy, không bao giờ ghi log; hai biến này chỉ có khi host đã chạy — host khởi động trước khi có phiên shell nào, và biến thừa hưởng từ một ShellX khác bị bỏ). Host trong tiến trình cửa sổ: macOS `~/Library/Application Support/pro.shellx.desktop/mux/` (`endpoint`, `mux.sock`, `mux.lock`), Windows `%LOCALAPPDATA%\ShellX\mux\` + pipe. Tray → **Dòng lệnh** (sau "Thông báo"): ☑ điều khiển bằng dòng lệnh, ☐ "Cho phép terminal khác", cài/gỡ lệnh cho mọi terminal, sao chép lệnh cài skill.

Mặc định chỉ shell ShellX điều khiển được (có `SHELLX_CLI_TOKEN`); terminal khác chỉ được `notify` không kèm pane (và `api.version`) cho tới khi tick "Cho phép terminal khác" — đây là rào chặn nhầm lẫn, không phải ranh giới bảo mật với mã độc cùng tài khoản (đọc được secret của endpoint). Lệnh trình duyệt (`shellx browser …`) chờ A6: hiện thoát 7 "this ShellX has no browser panes yet". Daemon A5b chưa có: host chạy trong tiến trình cửa sổ; khi A5b vào, mục này đổi số và daemon nhận token, `mux.lock` và đường `role: cli` (xem ledger "A5b obligation").

Test tự động: `packages/shellx_e2e/test/cli_e2e_test.dart` (binary `shellx` thật ↔ `CliHost` thật qua Unix socket, cửa sổ giả lập vì `UiCommandHandler` cần Flutter; `notify` từ một shell thật tới `SessionManager` thật), `apps/desktop/test/cli/cli_binary_test.dart` (binary thật ↔ `CliService` với `UiCommandHandler` thật; cần `shellx-term` đã build, không có thì bỏ qua và nói lý do). Đo (D40, đo không chặn): từ `apps/desktop`, `flutter test --run-skipped --tags benchmark test/cli/cli_benchmark_test.dart`. Apple M4, 2026-10-07: `ui.ls` 32 tab trung vị ~0,36 ms (≤ 5 ms); `ui.pane.read` 10.000 dòng (6 trang) ~20 ms (≤ 100 ms); cả lệnh `shellx ls` (bản debug, gồm khởi động tiến trình) ~3 ms; `shellx read --lines 10000` trọn vẹn ~70 ms.

Mỗi dòng ⚠ dưới đây ghi đạt/không đạt kèm ngày và máy vào ledger (`ledgers/a1-desktop-terminal.md`, mục A7 — execution). **Danh sách này chặn phát hành (release), không chặn merge** (ruling cuối A7, như A1–A5a): A7 merge sau đợt sửa cuối và review lại; không phát hành bản nào có A7 khi còn dòng chưa đạt. **Các dòng Windows là chặn phát hành** (Windows chưa từng chạy).

### Thử tay — macOS (Task 9)
- [ ] `flutter run -d macos`, trong một tab ShellX: `command -v shellx` → `…/ShellX/cli/shellx`; `echo $SHELLX_PANE_ID $SHELLX_TAB_ID $SHELLX_SOCKET` có giá trị; `echo ${#SHELLX_CLI_TOKEN}` → 64
- [ ] `ls -l ~/Library/Application\ Support/pro.shellx.desktop/mux/` → socket `srw-------`, endpoint `-rw-------`; `ls -ld` thư mục → `drwx------`
- [ ] Tray → "Dòng lệnh" có bốn mục; bỏ chọn "Cho phép điều khiển…" → `shellx ls` trong tab ShellX thoát 6 ngay (không cần mở lại kết nối)
- [ ] Terminal.app (không phải shell ShellX), sau khi cài lệnh cho mọi terminal: `shellx ls` → thoát 6 với gợi ý "Allow other terminals"; tick "Cho phép terminal khác" → chạy được; bỏ tick → bị từ chối ngay (cả `shellx events --follow` đang chạy bị đóng)
- [ ] "Cài lệnh shellx cho mọi terminal…": `/usr/local/bin` ghi được → không hỏi; không ghi được → hộp mật khẩu hệ thống, Huỷ → không đổi gì, không có thông báo; thành công → toast nhắc bật "Cho phép terminal khác"; "Gỡ…" chỉ gỡ link của ShellX (một `shellx` khác ở đó → toast lỗi kèm đường dẫn, không đụng vào)
- [ ] Shell đăng nhập không có `/usr/local/bin` trong PATH (thử: `SHELL=/bin/bash` với `~/.bash_profile` đặt `PATH=/usr/bin:/bin`): cài xong → toast ghi đúng dòng `export PATH="/usr/local/bin:$PATH"` và tệp cần thêm
- [ ] Bấm "Cài…" hai lần khi hộp mật khẩu đang mở → chỉ một hộp
- [ ] `shellx-term uninstall` xoá `ShellX/cli` và link `/usr/local/bin/shellx` nếu nó trỏ vào đó (cần quyền root → in lệnh `sudo rm …`)
- [ ] Chip "Agent" trên dòng tab và đầu pane đích 10 s sau mỗi lệnh; VoiceOver đọc "An agent is controlling …" tối đa một lần mỗi phút

### Thử tay — Windows (Task 9) — chặn phát hành
- [ ] `where shellx` trong tab ShellX; Tray → "Cài…" rồi một cửa sổ Windows Terminal **mới** tìm thấy `shellx` (`HKCU\Environment\Path` có `%LOCALAPPDATA%\ShellX\cli` đúng một lần, kiểu `REG_EXPAND_SZ`); "Gỡ…" bỏ nó
- [ ] Gỡ cài đặt xoá `cli\` và mục Path đó

### ⚠ Thử tay — macOS: tiêu chí spec (Task 11)
- [ ] Tiêu chí 1–8 và 10 nguyên văn trong một tab ShellX: `command -v shellx`, `echo $SHELLX_PANE_ID $SHELLX_TAB_ID`, `shellx --version` ≤ 50 ms; `shellx ls` / `shellx ls --json | jq .`; `p=$(shellx split --right --cmd "python3 -m http.server 8000")` → hai pane trong ≤ 1 s, bàn phím vẫn ở pane cũ, `shellx wait $p --match 'Serving HTTP' --timeout 10` thoát 0, `shellx read $p --lines 20` in log (phần `browser` của tiêu chí 3 chờ A6); `shellx send $p --text $'echo a\necho b' --enter` chạy như dán, chữ có `ESC[201~` không thoát chế độ dán; `wait --idle` (zsh có hook), `wait --exit` in mã thoát, hết giờ → 5; `shellx events --follow` in một dòng JSON mỗi lần mở/đóng tab, chia/đóng pane, đổi tiêu đề/cwd, thông báo, Ctrl+C dừng sạch; tắt công tắc → `shellx send` thoát 6, `shellx notify` vẫn chạy; `shellx help`, `shellx help <lệnh>`
- [ ] `shellx notify "Build xong"` trong pane → badge/dòng thông báo A4 của tab đó **và** push điện thoại; trong Terminal.app (không chia sẻ) → thông báo hệ thống ShellX + mục "Dòng lệnh" trong bảng thông báo (không cần tick "Cho phép terminal khác")
- [ ] Chip "Agent" 10 s; VoiceOver đọc "An agent is controlling …" đúng một lần
- [ ] Shell sống sót từ lần chạy ShellX trước (ví dụ `tmux` mở trong tab ShellX, thoát rồi mở lại ShellX, `tmux attach`): `shellx ls` → thoát 6 "This shell belongs to an earlier ShellX launch; open a new tab"; quá hai terminal ngoài (chưa tick) kết nối cùng lúc → cái thứ ba thoát 1 `busy`
- [ ] Quyền: tài khoản macOS khác `shellx ls` (với `SHELLX_ENDPOINT` trỏ vào endpoint của bạn hoặc `--socket`) → thoát 3
- [ ] `shellx events --follow > /dev/null` chạy tiếp (không tự thoát) tới khi ShellX đóng luồng (thoát 3); `shellx events --follow | head -1` thoát ≤ ~1 s sau dòng đầu dù không còn sự kiện
- [ ] Hiệu năng (D40): `time shellx ls` ≤ 50 ms với ShellX đang rảnh (bản release trong app); `shellx read p… --lines 10000` nhanh (thời gian phía cửa sổ ≤ 100 ms — benchmark ở trên)

### ⚠ Thử tay — Windows (Task 11; Windows chưa từng chạy, chỉ biên dịch/clippy chéo) — chặn phát hành
- [ ] Các lệnh trên trong PowerShell và cmd ở một tab ShellX (`where shellx`); Setup đè lên ShellX đang chạy thay được `shellx.exe` (bản cũ đổi tên `.old-<n>`); Narrator đọc dấu Agent
- [ ] Pipe: `apps/desktop/test/mux/windows_pipe_transport_test.dart` (testOn windows: khứ hồi, listen lần hai thất bại, connect tới không ai nghe thất bại nhanh, DACL đúng một ACE của bạn) chạy xanh; `[System.IO.Directory]::GetAccessControl('\\.\pipe\shellx-mux-…')` chỉ có tài khoản của bạn
- [ ] Client Rust: mở pipe với SQOS mức identification, thử lại khi `PIPE_BUSY`, bắt tay trên luồng phụ (hết giờ → thoát 3; luồng phụ kẹt trong `ReadFile` tới khi CLI thoát — residual chấp nhận); listener chết / đóng có thứ tự
- [ ] Back-pressure (ruling cuối W1): isolate ghi của pipe báo từng khối đã ghi xong, nên `pendingBytes`/`drained` và giới hạn D24 (1000 sự kiện), D32 (256 KiB chưa đọc, 64 yêu cầu chờ) có hiệu lực trên Windows — chạy test "A7 final W1" trong `windows_pipe_transport_test.dart` (client thô không đọc → `pendingBytes` > 64 KiB; đóng nó → `drained`); thử `shellx events --follow` đọc chậm (ví dụ `| more` để yên) → ShellX không phình bộ nhớ, có `overflow{dropped}` khi đọc lại; ghi số
- [ ] `shellx events --follow | Select-Object -First 1` chỉ kết thúc ở sự kiện kế tiếp (Windows không theo dõi stdout — residual)
- [ ] Đăng ký PATH (`HKCU\Environment\Path` `REG_EXPAND_SZ`, `WM_SETTINGCHANGE`) và Pascal của Inno (`RemoveCliFromUserPath`, `ChangesEnvironment`) — mới chỉ phân tích tĩnh trên macOS

### ⚠ Thử tay — completion và agent thật
- [ ] zsh thật: `source <(shellx completions zsh)` (hoặc `~/.zfunc/_shellx`), Tab gợi ý lệnh, cờ và id pane sống (`p…`/`t…`); bash `source <(shellx completions bash)`; pwsh `shellx completions pwsh | Out-String | Invoke-Expression` (pwsh chưa từng chạy, chỉ sinh script)
- [ ] Claude Code: `shellx skills install --claude`, khởi động lại Claude Code, nhờ nó "chạy dev server trong một pane ShellX cạnh bạn, chờ nó sẵn sàng, đọc log rồi báo tôi" → dùng `shellx split --cmd`, `wait --match`, `read`, `notify`, không cướp focus (phần trình duyệt chờ A6); chạy lại install sau khi sửa `SKILL.md` → hỏi trước khi ghi đè
- [ ] Codex: `shellx skills install --codex` ghi vào `~/.agents/skills/shellx/` (theo tài liệu Codex 2026-10-07) và cả `~/.codex/skills/shellx/` khi có `~/.codex` (ruling cuối M7); Codex thấy skill

### ⚠ Linux (chưa thử: không có máy/target Linux)
- [ ] `controlling_tty` qua `/proc/self/stat` (D23 đường 2 khi `$SHELLX_TERM` là terminal này) và đường POLLERR khi người đọc stdout bỏ đi (`events --follow | head -1`) mới chỉ viết, chưa biên dịch cho Linux. ShellX desktop chưa phát hành Linux; ghi lại nếu có máy để thử

## 17. Cấu hình, phím tắt, bảng lệnh — A9 (2026-10-07)

Spec `specs/2026-10-07-desktop-config-a9-design.md`, plan `plans/2026-10-07-desktop-config-a9.md`. (Plan gọi mục này §18; thực tế là §17 vì A6 chưa merge — ghi trong ledger.)

**File ở đâu (D3/D4).** File ShellX, cú pháp Ghostty (`key = value`, `#` là chú thích): macOS/Linux `$XDG_CONFIG_HOME/shellx/config` hoặc `~/.config/shellx/config`; Windows `%APPDATA%\ShellX\config` (`XDG_CONFIG_HOME` tuyệt đối thắng cả trên Windows). Theme của bạn: thư mục `themes/` cạnh file đó. App chỉ ghi file này ở hai chỗ: tạo từ mẫu khi bấm "Mở file cấu hình" (mọi dòng là chú thích) và khối do trình sửa phím tắt quản lý (bên dưới); không bao giờ tự ghi gì khác. Mặc định ShellX đọc thêm file Ghostty của bạn (`~/.config/ghostty/config[.ghostty]`, macOS `~/Library/Application Support/com.mitchellh.ghostty/config[.ghostty]`) cho font, cỡ, theme, màu, con trỏ, option-as-alt; có thông báo một lần khi lần đầu dùng; `ghostty-config = false` tắt. Dòng của ShellX luôn thắng dòng của Ghostty. File tối đa 256 KiB, include (`config-file`) sâu 4, tối đa 64 file; BOM, CRLF, UTF-16 có BOM đều đọc được.

**Bảng khoá (spec §3.1).** `font-family` (lặp), `font-size` 9–28, `font-weight` (`light|regular`, mặc định `light` = JetBrains Mono **Light**; `regular` = như trước; chỉ áp cho font đóng gói; `font-thicken = true` của Ghostty cũng được đọc là `regular`), `theme` (tên | đường dẫn | `light:A,dark:B`), `background`, `foreground`, `cursor-color`, `selection-background`, `palette = N=#hex` (0–15), `cursor-style`, `scrollback-limit` 1000–100000 (pane mới), `window-padding-x/y` 0–64, `macos-option-as-alt` (`false|true|left|right`), `confirm-close-surface` (`true|false|always`), `working-directory` (`home|inherit|đường dẫn`, tab mới), `keybind` (lặp), `command` / `snippet` (lặp), `ghostty-config`, `config-file`. Các khoá riêng của ShellX (`scrollback-limit`, `window-padding-*`, `confirm-close-surface`, `working-directory`, `keybind`, `command`, `snippet`) không đọc từ file Ghostty. Có `font-size` trong file thì ⌘+/− không còn lưu cỡ (D12). Mặc định mọi khoá = hành vi trước A9 (tiêu chí 1: không file → không đổi gì).

**Tải lại.** Tự động (đọc stat mỗi 1 s, nạp sau 250 ms yên lặng — ghi dở thì chờ), ⌘⇧, / Ctrl+Shift+, , tray → Cấu hình → "Tải lại cấu hình", palette, hoặc `shellx config reload`. File hỏng: giữ cấu hình tốt cuối; từng dòng sai chỉ bỏ dòng đó. ⌘, / Ctrl+, mở file (tạo từ mẫu nếu chưa có); `MainMenu.xib` không còn `keyEquivalent=","` ở mục Preferences để menu không nuốt ⌘, (D46).

**Vấn đề hiển thị thế nào.** Toast "Cấu hình có N vấn đề" khi có lỗi/cảnh báo mới (không lặp lại cho cùng file/dòng/mã; sửa xong tự mất), tray "⚠ N vấn đề cấu hình…", palette "Vấn đề trong cấu hình" và `shellx config check`; bảng liệt kê file:dòng, mức, khoá, gợi ý. Không bao giờ ghi nội dung file vào log, chỉ tên khoá và số dòng (D40).

**Phím tắt.** Cú pháp Ghostty: `keybind = super+shift+t=new_split:down`, `keybind = super+d=unbind`, `keybind = ctrl+a>c=new_tab` (tối đa hai bước; gõ tiền tố hiện chỉ báo + VoiceOver đọc; lặp tiền tố gửi nó tới terminal), `keybind = clear`, action `text:`/`csi:`/`esc:`/`ignore`/`run_command:<tên>`. Quy tắc Alt trái đã mở rộng cho mọi phím tắt Windows: Ctrl + Alt phải (AltGr) không bao giờ kích hoạt phím tắt. Nhãn menu lấy trigger đầu tiên của người dùng (một chord ưu tiên hơn chuỗi hai bước), không có thì mặc định. F6/Shift+F6 không ghi được; Esc/Tab không bị bẫy.

**Bảng lệnh** ⌘⇧P / Ctrl+Shift+P: mọi action đang áp dụng kèm phím tắt, `command` (chạy + Enter) và `snippet` (chỉ gõ chữ) của bạn, mục cấu hình; khớp không phân biệt dấu/hoa thường, khớp ở đầu mọi từ, làm nổi chữ khớp, gần đây lên trước; ↑/↓ không cần modifier, Enter chạy, Esc đóng; tự cập nhật khi file đổi lúc đang mở. Lệnh chạy ở pane đang focus.

**Trình sửa phím tắt** (tray → Cấu hình → "Phím tắt…" hoặc palette): ghi chord, báo xung đột và cho Thay thế, Gỡ, Đặt lại về mặc định, cảnh báo khi một dòng sau ghi đè. Chỉ sửa khối giữa `# >>> shellx-managed keybinds >>>` … `# <<< shellx-managed keybinds <<<` (`kManagedStart`/`kManagedEnd`); phần ngoài khối giữ nguyên từng byte. Ghi nguyên tử (tệp tạm cùng thư mục, 0600 từ lúc tạo, rồi đặt quyền của file gốc, rename), đi xuyên symlink (dotfiles; symlink treo được tạo ở đích), giữ BOM và kiểu xuống dòng; từ chối (không đụng file) khi file quá 256 KiB, UTF-16 không BOM, khối hỏng, hoặc file đổi giữa lúc đọc và lúc ghi. Tự nạp một lần sau khi ghi.

**`shellx config …`** (qua `ui.config.*`, cần cửa sổ ShellX; Rust `term/src/api/config_path.rs`): `shellx config path` (đường file, không cần cửa sổ), `check` (vấn đề của file hiện tại, không áp dụng), `reload` (nạp như ⌘⇧,), `show [--defaults]` (giá trị đang hiệu lực + dòng nguồn; `command` chỉ in giá trị `tên = chữ`, không bao giờ in chú thích/chữ khác trong file; `--defaults` in mẫu). `shellx new-tab`/`workspace new` không `--cwd` theo `working-directory` (D21). **Skill `shellx-config`** (`agent-skills/shellx-config/SKILL.md`) do trình cài skill A7 cài cùng `shellx`: `shellx skills install --claude|--codex|--dir DIR`, `shellx skills print config`; Claude Code dùng nó để thêm keybind/command, kiểm bằng `shellx config check` rồi `reload`.

**Chưa có trong A9 (ghi ledger).** Trình duyệt chờ A6 (action `open_browser`, `browser_*`, phạm vi phím tắt trình duyệt, D30, D35 fallback, Esc cho `browser_stop`, nhóm "Trình duyệt" trong trình sửa); A5b: `ui.config.*` phải qua `DaemonUiProxy` khi daemon vào.

**Đo (D42, đo không chặn).** Từ `apps/desktop`: `flutter test --run-skipped --tags benchmark test/config/config_benchmark_test.dart`. Apple M4, 2026-10-07 (bản JIT test, cận trên): nạp+dựng cấu hình 1.000 dòng `keybind` trung vị ~3,9 ms (bộ nhớ) / ~4,3 ms (đĩa thật), tối đa ≤ 16 ms (mục tiêu ≤ 20 ms); một vòng poll của watcher với danh sách xấu nhất (64 file include + 4 đường Ghostty, 68 `stat`) trung vị ~1,7 ms, tối đa ~2,7 ms, mỗi giây một lần.

Mỗi dòng ⚠ dưới đây ghi đạt/không đạt kèm ngày và máy vào ledger (`ledgers/a1-desktop-terminal.md`, mục A9 — execution). **Danh sách này chặn phát hành (release), không chặn merge** (ruling ledger: A9 như A1–A7). **Các dòng Windows chặn phát hành** (Windows chưa từng chạy).

### ⚠ Thử tay — macOS 13+ và Windows 10 1809+/11
- [ ] **1. Tiêu chí 1** — không có file: ảnh chụp trước/sau A9 giống hệt; ⌘T/⌘D/⌘W/⌘1/⌘⇧U/⌘⇧I/⌘+ như cũ; Windows Ctrl+Shift+T/D, Ctrl+Alt+1.
- [ ] **2. Tiêu chí 2** — `font-size = 16` lưu từ TextEdit / **Notepad** → áp dụng ≤ 1,5 s; `tput cols` đúng ở mọi pane; `vim` vẽ lại. Windows: Notepad lưu tại chỗ (không đổi tên) và thay file bằng rename (trình soạn khác/`mv`) đều được nạp; thay file tại chỗ cùng kích thước trong cùng mili giây là residual đã biết (restamp).
- [ ] **3. Font thật** — `font-family = Fira Code` (đã cài) hiện đúng; tên font không có → cảnh báo "font không tìm thấy" và chữ rơi về font mặc định (fake test không chứng minh được: engine test không có font hệ thống).
- [ ] **4. Tiêu chí 3 (macOS)** — cài Ghostty với `theme = Dracula`, `font-family = Fira Code` trong `~/.config/ghostty/config`: lần mở đầu thấy chúng và thông báo một lần; `ghostty-config = false` quay về mặc định.
- [ ] **5. Tiêu chí 4** — file hỏng (`font-size = to`, `keybind = super+q=new_tab`, một dòng ghi dở): toast, bảng liệt kê file/dòng; phiên chạy tiếp; sửa file thì toast mất.
- [ ] **6. Tiêu chí 5** — `keybind = super+shift+t=new_split:down`, `super+d=unbind`, `ctrl+a>c=new_tab`: menu hiện "Chia xuống dưới ⌘⇧T"; chỉ báo chuỗi, VoiceOver đọc; ⌃A ⌃A gửi ⌃A tới `cat -v`.
- [ ] **7. Tiêu chí 6 (Windows; bàn phím Đức và Ba Lan)** — AltGr+Q gõ `@`, AltGr+số gõ `{ [ ] }` khi có chord gắn Ctrl+Alt, kể cả `keybind` Alt tuỳ biến; Ctrl+Alt **trái** chạy chúng. AltGr = Ctrl trái + Alt phải; kiểm cả khi chord của người dùng dùng Alt.
- [ ] **8. Option-as-Alt (D19, macOS)** — `macos-option-as-alt = true` trong `emacs -nw` (Option+f/b = M-f/M-b) và zsh (di chuyển theo từ); phím chết (dead key, ví dụ Option+e rồi e khi đặt `left` và bấm Option phải) vẫn gõ được dấu; **Option+2 với cài đặt tắt** (`false`) gõ `™`/ký tự gốc như cũ.
- [ ] **9. D46** — ⌘, mở file cấu hình, không bị menu ứng dụng nuốt (`MainMenu.xib` đã bỏ `keyEquivalent`); menu "Preferences…" không còn hiện ⌘,.
- [ ] **10. Tiêu chí 7** — bảng lệnh với VoiceOver/Narrator (danh sách, mục chọn, "không khớp", số kết quả); **gõ Telex tiếng Việt** trong ô tìm (ví dụ `tieesng`, `ddoongj`) cho ra đúng chữ và khớp không phân biệt dấu; **Telex khi đang chờ tiền tố hai bước** (`ctrl+a` rồi gõ Telex) không nuốt/gửi sai phím; `command = …` chạy ở pane đang focus. (Pane trình duyệt chờ A6.)
- [ ] **11. Tiêu chí 8** — trình sửa phím tắt trên file **symlink**, **CRLF**, **BOM** (macOS và Windows; Windows: symlink cần Developer Mode/admin, junction của dotfiles): giữ symlink, kiểu xuống dòng, BOM, byte ngoài khối; xung đột/Thay thế; Đặt lại.
- [ ] **12. Tiêu chí 9** — `shellx config path|check|reload|show` trong một pane ShellX; `shellx skills install --claude`; Claude Code (khởi động lại) dùng skill `shellx-config` để thêm một keybind rồi tự `check` + `reload`.
- [ ] **13. Tiêu chí 10** — chỉ dùng bàn phím qua bảng lệnh, bảng vấn đề, trình sửa phím tắt; VoiceOver/Narrator đọc đúng bảng vấn đề và trình sửa phím tắt (danh sách dùng `SemanticsRole.list`, chưa có `listBox` trong Flutter 3.41.4); F6/Shift+F6 không ghi được; Esc/Tab không bị bẫy.
- [ ] **14. D15** — `theme = Solarized Light` (từ Ghostty): viền focus thấy được trên pane chia; khung giao diện vẫn tối; cảnh báo `lowContrast`; trạng thái rỗng của bảng vấn đề/bảng lệnh đọc được trên nền sáng.
- [ ] **15. IME macOS** — gõ IME (Nhật/Hàn/Telex qua bộ gõ hệ thống) trong terminal khi đang chờ tiền tố hai bước: xterm 4 giữ trạng thái soạn thảo riêng nên bảo vệ chỉ đầy đủ trên Windows và ô nhập Flutter; kiểm không có phím bị nuốt.
- [ ] **16. D42** — file cấu hình 1.000 dòng (`for i in $(seq 1000); do echo "keybind = ctrl+alt+shift+f12=new_tab"; done > …`) tải lại ≤ 20 ms trong bản app thật (Dart DevTools timeline); số benchmark ở trên là JIT test.
- [ ] **17. Linux** — chưa thử (không có máy): đường `$XDG_CONFIG_HOME`/`~/.config`, `chmod` 0600; ghi lại nếu có máy.

## 18. SSH và tmux — A8 (2026-10-07)

Spec `specs/2026-10-07-desktop-ssh-a8-design.md` (D1–D44), plan `plans/2026-10-07-desktop-ssh-a8.md` (có phụ lục giao diện UI-A8), tiến độ/ruling `.superpowers/sdd/2026-10-07-desktop-ssh-a8/` (`progress.md`, `preflight.md`). Branch `feat/desktop-a8`; theo ruling "gates, uniform": merge sau review, danh sách ⚠ bên dưới chặn **phát hành**, các dòng Windows là release blocker.

**Cái gì ở đâu.** Pane SSH là một phiên bình thường chạy `ssh` của hệ thống (đăng nhập — mật khẩu, passphrase, câu hỏi host key — diễn ra trong pane; ShellX không thấy và không lưu). macOS dùng ControlMaster: thư mục điều khiển `/tmp/shellx-ssh-<uid>/` (0700, của bạn, kiểm trước khi dùng; không an toàn thì tắt multiplexing và log một lần `ssh: control dir unsafe`); Windows không multiplex. Bên máy chủ: `~/.cache/shellx/remote-<hash>/` (hook, ghi bằng tệp tạm + `mv`, umask 077, không bao giờ sửa dotfile). Cài đặt: `ssh_recent_targets` (10 máy gần đây), `ssh_plain_targets` (máy không cài hook), `ssh_remote_hook` (mặc định bật); workspace SSH và `launch` trong `layout.json` (A5a). Tray có submenu **SSH** (các máy gần đây, bật/tắt cài hook trên máy chủ, xoá danh sách gần đây); ⌘⇧K / Ctrl+Shift+K mở hộp kết nối (action `ssh_connect`; `tmux_attach` trong bảng lệnh). CLI: `shellx ssh`, `shellx tmux ls|attach`, `ls` có `remote`, sự kiện `pane.replaced` (xem `agent-skills/shellx/reference.md`, mục "SSH and tmux"). Gỡ phía máy chủ: `rm -rf ~/.cache/shellx`. Log không bao giờ chứa đích, host, user, cổng, đường dẫn, nhánh, tên tmux, lệnh (có test).

**Điều người dùng nên biết.**
- Cổng chuyển tiếp (port forward) bị huỷ khi pane cuối của một máy chủ đóng hoặc mất kết nối; sau khi kết nối lại, bấm lại vào cổng.
- Chữ tiếng Việt "Cần đăng nhập" (cần đăng nhập) đang chờ người bản ngữ duyệt.
- File bố cục đã lưu do bạn tự sửa bằng tay mà có `launch` tới máy chủ thì sẽ kết nối tới máy đó khi khởi động (tin cậy cùng người dùng: file nằm trong dữ liệu app của chính bạn).
- Pane mà `ssh` không thể khởi động (thiếu `ssh`) thì không được khôi phục.
- Tắt máy (power off) để các ssh control master cho `ControlPersist` tự dọn.
- Hook hello không có nonce theo từng pane: máy chủ độc hại có thể giả hello trước khi đăng nhập và nhận chữ `--cmd` tại dấu nhắc mật khẩu của nó (nó vốn đã nhận mật khẩu; câu hỏi host key không bị ảnh hưởng). Tương lai: nonce theo pane. Ghi trong `reference.md`.
- Windows: code A8 chưa biên dịch trên máy cục bộ; nhánh `windows-check/a8` sẽ được đẩy để CI build.

**Riêng tư (D36/D37).** Trang riêng tư (vi/en §4) có thêm một gạch đầu dòng SSH, kể cả việc tên máy chủ và thư mục trên đó có thể hiện trong danh sách phiên của điện thoại đã ghép nối (`SessionInfo.cwd` = `<key>:<đường dẫn từ xa>`, protocol không đổi; điện thoại không mở được phiên SSH).

**Hand-off cho A5b (daemon chưa merge).** Bước daemon của A8 bị bỏ qua. Khi A5b vào: `launch`/`remote` phải đi trên dây (A8 đã thêm `remote` vào `summaryToWire/FromWire` + test); `RemoteTools` phải được dựng trong daemon; `ui.ssh.*`/`ui.tmux.*` phải qua `DaemonUiProxy`; "Thoát hẳn" phải chạy `ssh -O exit` cho các master; kiểm tiêu chí 8 (`top` trong pane SSH sống sau ⌘Q).

**Hand-off cho A6 (browser chưa merge).** Ledger ghi "browser pending A6". Khi mở một cổng của máy chủ trong pane trình duyệt, gọi `RemotePortForwards.localPort(pane, N)` trước rồi mở `http://localhost:<cổng đó>/` (cổng local có thể khác N). Mọi action trình duyệt mới của A6 phải được thêm vào bảng A9 (như đã ghi ở A9). Dòng ⚠ 7 phần "⌥-click → pane trình duyệt" và tiêu chí 3 (mệnh đề cuối) chờ A6.

**Hand-off cho A9 (đã merge).** `agent-skills/shellx-config/SKILL.md` đã liệt kê `ssh_connect`/`tmux_attach`. Còn lại: `agent-skills/shellx/SKILL.md` chưa nhắc SSH/tmux — thêm `shellx ssh`, `shellx tmux ls|attach`, và lưu ý `--cmd` chỉ gõ sau hello, cần hook (`reference.md` đã có).

**Đo (D44).** Đo được trên máy dev (không cần máy chủ): phân tích probe 2000 tiến trình + 50 listener, `parseRemoteProbe` (Dart JIT, Apple M4, 2026-10-07, 30 lần): trung vị 0,8 ms, lần đầu 0,4 ms, một lần ngoại lai 14 ms (GC/JIT) — mục tiêu ≤ 5 ms đạt ở trung vị. **Cần đo trên máy thật (chưa đo):** `ssh -G` + spawn ≤ 80 ms (`time` quanh thao tác mở, hoặc Instruments), hộp kết nối ≤ 50 ms với config 200 host (Dart DevTools timeline), chia pane trên master ≤ 300 ms tới prompt (LAN). Ghi số vào ledger.

Mỗi dòng ⚠ dưới đây ghi đạt/không đạt kèm ngày và máy vào ledger (`ledgers/a1-desktop-terminal.md`, mục "A8 (SSH/tmux) — execution").

### ⚠ Thử tay — macOS 13+ và Windows 11
- [ ] **1. macOS → máy chủ Linux** (tài khoản zsh, bash, fish) có khoá trong agent: tiêu chí spec 1, 3, 4 (không hỏi mật khẩu lần hai, ≤ 500 ms trên LAN), 9, 10, 11 (grep log).
- [ ] **2. Tài khoản chỉ mật khẩu và tài khoản OTP (PAM):** dấu nhắc hiện trong pane; chia pane khi đang ở dấu nhắc (D9: gõ trong 3 s thì pane thứ hai không hỏi lại); `grep -r` mật khẩu đã gõ trong thư mục app support và `~/Library/Preferences/pro.shellx.desktop.plist` → không thấy gì.
- [ ] **3. Host key:** lần kết nối đầu (`yes/no` trong pane); khoá bị đổi (cảnh báo của ssh, pane `failed`, `known_hosts` không bị đụng).
- [ ] **4. Tắt Wi-Fi 60 s rồi bật:** dòng + dải ≤ 50 s, đếm ngược, tự kết nối lại vào cùng chỗ, `~/work/api` được khôi phục, có đường kẻ; máy ngủ 5 phút → thử lại khi thức; sai mật khẩu → không bao giờ tự thử lại.
- [ ] **5. tmux:** `main` cục bộ (Homebrew tmux) và trên máy chủ; đóng tab → `tmux ls` vẫn thấy; rớt Wi-Fi → kết nối lại gắn lại và `top` trong tmux vẫn chạy; "Tạo và gắn".
- [ ] **6. Khôi phục (A5a):** tiêu chí spec 7, gồm máy chủ không với tới được (pane `failed`, bố cục giữ). Khi có A5b: tiêu chí 8 (`top` trong pane SSH sống sau ⌘Q).
- [ ] **7. Cổng:** `python3 -m http.server 8000` trên máy chủ → `:8000` hiện trong ≤ 6 s; bấm → trang của máy chủ; local 8000 đang bận → cổng khác, tooltip cho thấy; (⌥-click → pane trình duyệt: **chờ A6**); đóng pane cuối → `ssh -O check` vẫn ổn và forward mất (`lsof -iTCP:8000` rỗng).
- [ ] **8. Thư mục điều khiển:** `ls -ld /tmp/shellx-ssh-$(id -u)` là `drwx------` của bạn; tạo trước bằng user khác (hoặc `chmod 777`) → ShellX log một lần `ssh: control dir unsafe` và SSH vẫn chạy không multiplex.
- [ ] **9. Windows 11** (`ssh.exe` 8.x+, dịch vụ ssh-agent): tiêu chí 1–7 và 10 (mỗi pane tự xác thực; cổng quét mỗi 15 s; forward qua tiến trình `-N`), Ctrl+C, `~.`, đổi cỡ vim, ConPTY với dấu nhắc mật khẩu; không có OpenSSH Client → toast kèm gợi ý Settings. **Release blocker.**
- [ ] **10. Trợ năng:** VoiceOver/Narrator đọc dòng ("…, on devbox, Lost connection to devbox"), dải một lần (không đọc từng giây), gợi ý của hộp thoại; chỉ dùng bàn phím: ⌘⇧K, ↓ Enter, thứ tự Tab theo UI-A8 §6, Ctrl+F6 vào dải.
- [ ] **11. Hiệu năng (D44):** `ssh -G` + spawn ≤ 80 ms; hộp mở ≤ 50 ms với config 200 host; số probe 2000 tiến trình ở trên.
