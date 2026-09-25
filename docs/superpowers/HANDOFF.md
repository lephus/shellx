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
| 01 | Relay | `feat/shellx-v1-relay` · `.worktrees/relay` | Task 1–9 xong. **Task 10 đang ở vòng sửa 3** — commit WIP `wip(relay): Task 10 fix round 3…` (chưa review). Còn Task 11, rồi review cuối + merge |
| 03 | `shellx_agent` + `shellx_client` + E2E | `feat/shellx-v1-agent-client` · `.worktrees/agent-client` | Task 1–5 xong. **Task 6 đã sửa xong (1cc10c6), chưa chạy review lại**. Còn Task 7–15 |
| 04 | Desktop (Flutter) | `feat/shellx-v1-desktop` · `.worktrees/desktop` (tách từ nhánh plan 03) | Task 1 xong. **Task 2 dở dang** — commit WIP `wip(desktop): Task 2 l10n…`. Làm tiếp Task 2–5; **dừng trước Task 6** cho tới khi plan 03 Task 9 (`AgentService`) được merge vào nhánh này |
| 05 | Mobile (Flutter) | chưa bắt đầu | Chờ plan 03 (`ClientService`) |

Ledger chi tiết (mỗi task, mọi phán quyết "Ruling", mọi lỗi nhỏ hoãn lại):
- Đang chạy: `.worktrees/<relay|agent-client|desktop>/.superpowers/sdd/<plan>/progress.md` (gitignored, trên đĩa).
- Bản sao trong repo: `docs/superpowers/ledgers/` (plan06, plan02 đầy đủ; plan01/03/04 là snapshot lúc tạm dừng).

## 3. Việc cần làm ngay khi tiếp tục (theo thứ tự)

1. **Relay Task 10 vòng sửa 3**: giao implementer mới (sonnet) hoàn tất từ commit WIP, theo thiết kế: `relay/scripts/prompter.ts` với `createLinePrompter` (stdin không phải TTY: đọc `fs.readFileSync(0)` một lần, lười — chỉ khi cần hỏi), `createTtyPrompter` (readline/promises, reject khi 'close'), `createPrompter()`; mật khẩu trước, xác nhận sau; lỗi một dòng + exit 1; 4 lệnh smoke (xem ledger relay). Sau đó review ngắn.
2. **Relay Task 11**: README/runbook + phán quyết: kiểm tra Workers Logs (observability) có ghi IP/header client không; nếu có thì tắt invocation logs trong `relay/wrangler.jsonc` (privacy policy cam kết IP chỉ dùng tạm cho rate limit). Rồi review cuối toàn nhánh relay (opus) → một lượt sửa → merge vào `feat/shellx-v1`, và merge `feat/shellx-v1` vào nhánh plan 03 (E2E Task 15 cần relay thật: `cd relay && npm run dev -- --ip 127.0.0.1 --port 8787`).
3. **Plan 03**: chạy review ngắn cho Task 6 (base c29cbdd → 1cc10c6), rồi Task 7 → 15. Gộp vào lượt sửa cuối của plan 03 các lỗi nhỏ đã ghi "FOLD INTO FINAL FIX WAVE" (Task 4: N1–N4).
4. **Plan 04**: hoàn tất Task 2 (từ WIP), Task 3–5; chờ plan 03 Task 9 rồi merge và làm Task 6–11. Ghi nhớ các điểm mang theo trong ledger desktop (một `SecureKeyValueStore`/`TrustedStore` dùng chung; đường phục hồi từ `replaced`; dừng relay trước `api.logout()`; Windows `SetQuitOnClose(true)` phải thành ẩn xuống tray).
5. **Plan 05**: bắt đầu khi `ClientService` (plan 03 Task 12–14) xong.
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
