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

- **VPS** (runbook `deploy/README.md`): quốc gia đặt VPS đã điền là Việt Nam (2026-09-27; bộ chặn `[quốc gia]` vẫn giữ cho lần sửa sau); user deploy trong nhóm `docker`, `~/phu/shellx/data` thuộc uid 1000; tên network của nginx-proxy vào `~/phu/shellx/.env`; 4 secret `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY`, `VPS_KNOWN_HOSTS` và biến `VPS_APP_DIR` (mặc định `phu/shellx`), `VPS_SSH_PORT` (tuỳ chọn, chỉ số, mặc định `22`) — tất cả là Environment secret/variable của hai GitHub Environment `production` (dùng bởi `deploy.yml`) và `release` (dùng bởi `publish`), không phải repository secret; sau lần deploy đầu: công khai 2 package GHCR `shellx-relay`, `shellx-web` và chép (không symlink) 4 file `~/phu/shellx/nginx-proxy/*` vào `vhost.d` của nginx-proxy rồi tạo lại container ShellX. Mọi lệnh trên VPS do người dùng chạy hoặc cho phép rõ ràng.
- **Dọn Cloudflare** (khi nameserver đã về nhà đăng ký): xóa zone `shellx.pro` trên Cloudflare, `npx wrangler logout`, xóa secret `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`.
- **GitHub Environment `release`** (tag `desktop-v*` + nhánh `main`) với 11 secret ký — xem `release/README.md`.
- **Pháp lý**: tên pháp nhân/địa chỉ cho privacy/terms; nhờ người có chuyên môn xem lại (hiện ghi "ShellX", luật Việt Nam, 16 tuổi, log ≤ 30 ngày).
- Chính sách quyền riêng tư hứa log vận hành ≤ 30 ngày, nhưng Docker xoay vòng log theo dung lượng (10 MB × 3) nên khi ít traffic log có thể lâu hơn 30 ngày — người dùng chọn: sửa câu chữ, hoặc định kỳ tạo lại container.
- **nginx-proxy vẫn log IP client ở khối redirect HTTP→HTTPS (I3):** các file `deploy/nginx-proxy/*` chỉ tắt `access_log` trong khối server HTTPS (khối duy nhất nginx-proxy include chúng vào) — khối cổng 80 (dùng chung cho mọi site sau nginx-proxy) vẫn giữ access log mặc định, và không thể sửa an toàn từ file của ShellX. Xem `deploy/README.md` bước 6 để kiểm chứng (`nginx -T`, `curl -sI http://shellx.pro/`, `docker logs`) và ba lựa chọn: bật `DISABLE_ACCESS_LOGS` toàn proxy (ảnh hưởng site khác), công bố việc này trong chính sách quyền riêng tư, hoặc giới hạn log retention của nginx-proxy. Người dùng chọn một, code chưa tự quyết và văn bản quyền riêng tư chưa đổi.
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
