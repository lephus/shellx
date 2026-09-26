# ShellX v1.0 — Bàn giao để tiếp tục (cập nhật 2026-09-26: cả 6 plan đã merge)

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
| 03 | `shellx_agent` + `shellx_client` + E2E | đã merge (e5aecb0), worktree đã xóa | ✅ Xong (agent 167, client 98, e2e 7 trên relay local). Ledger: `docs/superpowers/ledgers/plan03-agent-client.md` |
| 04 | Desktop (Flutter) | đã merge (25ddd75), worktree đã xóa | ✅ Xong (desktop 269, PTY integration 21 trên macOS). Windows **chưa kiểm chứng** cho tới khi chạy Windows CI (checklist trong ledger). Ledger: `docs/superpowers/ledgers/plan04-desktop.md` |
| 05 | Mobile (Flutter) | đã merge (0e9ca47), worktree đã xóa | ✅ Xong (mobile 501 test; build debug APK + iOS đã chạy). App id `com.shellx.prod`, logo mới. Ledger: `docs/superpowers/ledgers/plan05-mobile.md` |

Ledger chi tiết (mỗi task, mọi phán quyết "Ruling", mọi lỗi nhỏ hoãn lại):
- Bản sao trong repo: `docs/superpowers/ledgers/` (plan01–06 đầy đủ; các file `.snapshot.md` là bản lúc tạm dừng).

## 3. Trạng thái và việc tiếp theo

Toàn bộ code v1.0 đã nằm trên `feat/shellx-v1` (chưa push). Kiểm chứng trên máy lúc merge plan 05: core 261, client 98, agent 167, desktop 269, mobile 501 test xanh; `flutter analyze` sạch cho mọi package/app; relay (238) và web không đổi kể từ lúc merge; e2e 7/7 lúc merge plan 03.

Việc còn lại — tất cả cần người dùng quyết/cung cấp:
1. **Push + PR vào `main`** để CI chạy trên Windows (desktop Windows chưa kiểm chứng; checklist trong `ledgers/plan04-desktop.md`), rồi bật check "CI result" bắt buộc.
2. **Triển khai Cloudflare** (mục 4).
3. **Kiểm tra thủ công trên thiết bị thật** — mobile: đăng nhập, quét QR (kể cả Android "Quét lại" cùng mã, cấp quyền camera từ Cài đặt), Face ID khi mở lại, IME tiếng Việt / phím cứng gửi trùng, dán từ gợi ý clipboard của bàn phím; desktop: đăng nhập GUI, ghép nối, banner thông báo, ⌘Q.
4. Việc gia cố nên làm sau (không chặn phát hành): một test tích hợp mobile chạy `ClientBackend` → `TerminalPageController` qua relay trong bộ nhớ của `shellx_e2e` với `SessionManager` thật; khoảng hẹp `PendingUnpairs.retry` có thể xóa một lần ghép nối lại diễn ra đúng lúc đăng nhập (xem ledger plan 05).

## 4. Việc chờ người dùng (không chặn code)

- **Cloudflare**: mua `shellx.pro` (DNS trên Cloudflare), gói Workers Paid; khi relay xong sẽ nhờ chạy `! npx wrangler login` (OAuth, không gửi key qua chat). Mọi thao tác tạo tài nguyên/deploy phải hỏi trước.
- **GitHub Environment `release`** (tag `desktop-v*` + nhánh `main`) với 13 secret — xem `release/README.md`.
- **Pháp lý**: tên pháp nhân/địa chỉ cho privacy/terms; nhờ người có chuyên môn xem lại (hiện ghi "ShellX", luật Việt Nam, 16 tuổi, log ≤ 30 ngày).
- **Ký Windows**: Azure Trusted Signing có thể không nhận nhà phát hành ở Việt Nam → phương án chứng chỉ OV.
- **Icon/thương hiệu**: mobile đã dùng logo người dùng gửi (2026-09-26); cần bản 1024×1024 hoặc SVG để icon App Store nét (thay `apps/mobile/assets/branding/*` rồi chạy `apps/mobile/tool/gen_app_icons.py`). Desktop/web chưa đổi logo.

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

## 7. Quyết định ngày 2026-09-26

- App mobile: bundle id iOS và applicationId/namespace Android là **`com.shellx.prod`** (thay `pro.shellx.mobile` trong plan/ledger cũ). Desktop giữ `pro.shellx.desktop`.
- Logo mobile: nguồn `apps/mobile/assets/branding/logo_shellx_{rounded,square}.png`; icon iOS (RGB, không alpha), Android adaptive (+ monochrome) và logo trong app sinh bằng `apps/mobile/tool/gen_app_icons.py`.
