# ShellX v1.0 — Bàn giao để tiếp tục (tạm dừng 2026-09-25)

Tài liệu này đủ để một phiên Claude mới (hoặc chính phiên cũ khi resume) tiếp tục đúng chỗ. Đọc hết trước khi làm gì.

## 1. Bối cảnh

- Sản phẩm: điều khiển terminal máy tính (macOS/Windows) từ điện thoại, qua relay Cloudflare, mã hóa đầu cuối Noise.
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
| 03 | `shellx_agent` + `shellx_client` + E2E | `feat/shellx-v1-agent-client` · `.worktrees/agent-client` | Task 1–5 xong. **Task 6 đã sửa xong (1cc10c6), chưa chạy review lại**. Còn Task 7–15 |
| 04 | Desktop (Flutter) | `feat/shellx-v1-desktop` · `.worktrees/desktop` (tách từ nhánh plan 03) | Task 1 xong. **Task 2 dở dang** — commit WIP `wip(desktop): Task 2 l10n…`. Làm tiếp Task 2–5; **dừng trước Task 6** cho tới khi plan 03 Task 9 (`AgentService`) được merge vào nhánh này |
| 05 | Mobile (Flutter) | `feat/shellx-v1-mobile` · `.worktrees/mobile` | Plan đã viết lại trên base yallabb + thiết kế đã duyệt (efbfb1c, 19 task, đã replay xanh). Task 1–8 chỉ cần core; Task 9 cần plan 03 Task 10; Task 10–19 cần plan 03 Task 11–14 và pairing id |

Ledger chi tiết (mỗi task, mọi phán quyết "Ruling", mọi lỗi nhỏ hoãn lại):
- Đang chạy: `.worktrees/<relay|agent-client|desktop>/.superpowers/sdd/<plan>/progress.md` (gitignored, trên đĩa).
- Bản sao trong repo: `docs/superpowers/ledgers/` (plan06, plan02 đầy đủ; plan01/03/04 là snapshot lúc tạm dừng).

## 3. Việc cần làm ngay khi tiếp tục (theo thứ tự)

1. **Relay Task 10 vòng sửa 3**: giao implementer mới (sonnet) hoàn tất từ commit WIP, theo thiết kế: `relay/scripts/prompter.ts` với `createLinePrompter` (stdin không phải TTY: đọc `fs.readFileSync(0)` một lần, lười — chỉ khi cần hỏi), `createTtyPrompter` (readline/promises, reject khi 'close'), `createPrompter()`; mật khẩu trước, xác nhận sau; lỗi một dòng + exit 1; 4 lệnh smoke (xem ledger relay). Sau đó review ngắn.
2. **Relay Task 11**: README/runbook + phán quyết: kiểm tra Workers Logs (observability) có ghi IP/header client không; nếu có thì tắt invocation logs trong `relay/wrangler.jsonc` (privacy policy cam kết IP chỉ dùng tạm cho rate limit). Rồi review cuối toàn nhánh relay (opus) → một lượt sửa → merge vào `feat/shellx-v1`, và merge `feat/shellx-v1` vào nhánh plan 03 (E2E Task 15 cần relay thật: `cd relay && npm run dev -- --ip 127.0.0.1 --port 8787`).
3. **Plan 03**: chạy review ngắn cho Task 6 (base c29cbdd → 1cc10c6), rồi Task 7 → 15. Gộp vào lượt sửa cuối của plan 03 các lỗi nhỏ đã ghi "FOLD INTO FINAL FIX WAVE" (Task 4: N1–N4).
4. **Plan 04**: hoàn tất Task 2 (từ WIP), Task 3–5; chờ plan 03 Task 9 rồi merge và làm Task 6–11. Ghi nhớ các điểm mang theo trong ledger desktop (một `SecureKeyValueStore`/`TrustedStore` dùng chung; đường phục hồi từ `replaced`; dừng relay trước `api.logout()`; Windows `SetQuitOnClose(true)` phải thành ẩn xuống tray).
5. **Plan 05**: dùng bản plan đã viết lại theo base yallabb (§6). Các task không cần `ClientService` (scaffold, adapter nền tảng, text lỗi, phím/extra keys, khóa sinh trắc) có thể làm trước; phần còn lại chờ plan 03 Task 12–14.
6. Cuối cùng: chạy CI đầy đủ trên `feat/shellx-v1`, bật check "CI result" bắt buộc, rồi hỏi người dùng về PR vào `main` và việc triển khai Cloudflare.

## 4. Việc chờ người dùng (không chặn code)

- **Cloudflare**: mua `shellx.pro` (DNS trên Cloudflare), gói Workers Paid; khi relay xong sẽ nhờ chạy `! npx wrangler login` (OAuth, không gửi key qua chat). Mọi thao tác tạo tài nguyên/deploy phải hỏi trước.
- **GitHub Environment `release`** (tag `desktop-v*` + nhánh `main`) với 13 secret — xem `release/README.md`.
- **Pháp lý**: tên pháp nhân/địa chỉ cho privacy/terms; nhờ người có chuyên môn xem lại (hiện ghi "ShellX", luật Việt Nam, 16 tuổi, log ≤ 30 ngày).
- **Ký Windows**: Azure Trusted Signing có thể không nhận nhà phát hành ở Việt Nam → phương án chứng chỉ OV.
- **Icon/thương hiệu**: chưa có kế hoạch nào; app đang dùng icon mặc định Flutter.

## 5. Quy tắc làm việc đã thống nhất

- Người dùng nói tiếng Việt; trả lời bằng tiếng Việt.
- Không push, không deploy, không tạo tài nguyên Cloudflare khi chưa hỏi.
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
