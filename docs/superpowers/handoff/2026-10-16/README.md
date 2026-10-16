# Bàn giao V2 — 16/10/2026, 15:00

Lúc 14:2x ngày 16/10 bạn yêu cầu: "đẩy toàn bộ code, spec, memory mới nhất lên git lúc 15h chiều nay; và dừng code. Tôi sẽ tiếp tục code sau". Mọi agent dừng lúc 15:00. Thư mục này gom tất cả những gì cần để làm tiếp.

> Không có gì được đẩy lên `main`. Mỗi lần đẩy `main` là một lần phát hành app desktop (`release-desktop.yml`). Các thay đổi `relay/**`, `web/**`, `deploy/**` nằm trên `main` thì tự deploy lên production (`deploy.yml`).

## 1. Nhánh và trạng thái

Bảng mã commit chính xác lúc dừng nằm ở cuối file, mục "Trạng thái nhánh lúc 15:00".

| Nhánh | Nội dung | Trạng thái |
|---|---|---|
| `shellx-v2` | V2-1, V2-2a, **V2-3 và V2-4 (đã gộp, 16/10 ~15:10)**, 3 spec V2-5, plan V2-5a (chưa xong), thư mục bàn giao này | Ổn định. Kiểm toàn bộ trên bản gộp V2-3 + V2-4: core 404, agent 970, client 247, e2e 16, acp 87, ai 576, desktop 3890, mobile 1361, tất cả qua |
| `v2-2b` | V2-2b: AI trên điện thoại, phần 2 (26 việc) | Việc 1–25 đã xong và review. Việc 26 đã code và commit, test xanh, nhưng **review việc 26 chưa xong**. **Chưa review toàn nhánh.** Gói diff cho review toàn nhánh đã soạn sẵn trong `.superpowers/sdd/…` (xem `sdd/v2-2b/handoff-20-26.md`) |
| `v2-5a-wip-union` | **Bản thử nghiệm**: gộp tạm cả 4 nhánh, cộng code V2-5a việc 1–4 và một phần việc 5. Do agent viết plan làm để kiểm chứng plan. Cách giải xung đột khi gộp ở đây **không phải** bản gộp chính thức | Việc 1 (thử SF Mono) đạt cả 5 điều kiện trên macOS và trình giả lập iOS 26. Có thể lấy lại code các việc 1–4 sau khi gộp chính thức |
| `v2-2b-relay` | Relay B6 (category/tag cho nút trên thông báo) và trang quyền riêng tư (việc 26) | **Chưa deploy.** Cần bạn đồng ý |
| `v2-3` | V2-3: tool trên desktop | Xong, đã gộp vào `shellx-v2` |
| `windows-check/v2-3` | Bản V2-3 để CI Windows build | Xem tab Actions trên GitHub |
| `v2-4` | V2-4: tool trên điện thoại (16 việc) | **Xong**: review toàn nhánh, đợt sửa và review lại đều đã đóng. Đã gộp vào `shellx-v2` (rebase). Quyết định I3 đổi hành vi: điện thoại giãn nhịp mở luồng 100 rồi 50/giây, trang dev nhiều module tải chậm hơn thay vì lỗi 503 |

## 2. Việc còn lại, theo thứ tự

### V2-4: xong
Đã review, sửa, review lại và gộp vào `shellx-v2` (16/10 ~15:10). Ghi chú gộp với V2-2b: `sdd/v2-4/handoff-15-16.md`, mục "Integration notes".

### V2-2b: hoàn tất rồi gộp
- Xong việc 26. Đây là trang quyền riêng tư (nằm trên `v2-2b-relay`), quét quyền riêng tư và test đầu–cuối với relay chạy cục bộ.
- Review toàn nhánh (`14e9eb1..HEAD` trên `v2-2b` và `5929cdc..HEAD` trên `v2-2b-relay`). Đợt sửa sau review phải gồm:
  - option id chứa surrogate đơn lẻ làm mất cả thông báo; cần quay về thông báo thường;
  - sheet cấu hình giữ trạng thái đang gửi theo từng instance, nên trả lời đến lúc sheet đang đóng có thể đóng luôn trang phiên;
  - xem lại: nút Allow chỉ kiểm option id, không kiểm tên option;
  - rà các chỗ `Watch(` trên mobile (khoảng 46–49) xem có lỗi "watch cũ" như F43 không.
- Gộp vào `shellx-v2`. Xung đột cần giữ cả hai bên:
  - ARB, rồi chạy `flutter gen-l10n` (desktop) và `intl_utils` (mobile);
  - `settings_store.dart` và số khoá trong `settings_ownership_test.dart` (của nhánh kia + 1);
  - `messages.dart`, `session_router.dart`, `lib/shellx_agent.dart`, `machine_client.dart`;
  - mobile `pubspec.yaml`, `Info.plist`, Android manifest, `Podfile.lock` (giữ `COCOAPODS: 1.16.2`);
  - `app_router.gr.dart` và `dependency.config.dart`: chạy lại build_runner;
  - test "tripwire" `AiHost.runtime` trong `apps/desktop/test/tools/tool_ports_test.dart`: cập nhật bản sao trong `ai_runtimes.dart`.

### V2-5a: tên app và giao diện mới
- Viết nốt plan `docs/superpowers/plans/2026-10-16-v2-5a-name-and-design-system.md`. Các task còn "UNFINISHED" đã có dàn ý.
- Code. Hai việc đầu tiên:
  - thử nạp SF Mono của hệ thống trên Mac và iPhone, với 5 điều kiện đạt/không đạt; không đạt thì dùng JetBrains Mono;
  - ⚠ tài khoản Keychain của kho khoá bí mật desktop lấy theo bundle id. App thật giữ `pro.shellx.desktop`; bản thử dùng tài khoản riêng. Phải xong việc này trước mọi lần chạy cả app.

### V2-5b và V2-5c
Viết plan sau khi plan 5a xong, vì hai plan này dùng tên component và icon của 5a. Sau đó code. 5b có thể tách thành nhánh desktop và nhánh điện thoại sau bước giao thức.

### Kiểm tay trên máy thật
Danh sách gom từ các file `handoff-*.md` và từ mục "⚠ Kiểm tay" trong các spec:
- V2-2b §10: kiểm mục 8 cả khi có và khi không có dịch vụ nền;
- V2-3 §11, V2-4 §10;
- V2-5a, b, c.

## 3. Quyết định đang chờ bạn
- Đồng ý deploy relay và trang quyền riêng tư (nhánh `v2-2b-relay`). Trước khi deploy:
  - gửi thử một thông báo FCM thật có category và tag;
  - xem cảnh báo "1 high severity vulnerability" của `npm ci`.
- Khi nào đưa V2 lên `main`. `shellx-v2` dựa trên `main` cũ (`5929cdc`); `main` đã có thêm commit phát hành của đồng đội.
- Xoá workspace thì các tool của nó bị xoá theo mà không báo: giữ như vậy hay hỏi xác nhận?
- Câu chữ V2-2b:
  - "Đã nối lại sau khi ShellX khởi động lại." hiện cả khi không khởi động lại. Đề xuất đổi thành "Đã nối lại phiên.".
  - "từ điện thoại" không cho biết điện thoại nào, khi có nhiều điện thoại.
- Báo đồng đội: V2-5a đổi 3 dòng hiển thị trong `release/windows/shellx.iss`.
- Các quyết định cũ còn chờ xác nhận:
  - thông báo 60 giây vẫn gửi cả khi ShellX đang mở;
  - thông báo câu hỏi không kèm nội dung câu hỏi;
  - chế độ `auto` của Claude/Codex và `auto_edit` của Gemini là chế độ thường;
  - nội dung thông báo FCM có tên hành động (N3);
  - danh sách kiểm lần đầu chạy;
  - có xoá nhánh cũ `v2-2-phone`, `v2-2-int` trên origin không;
  - M-10 còn mở.
- Bản build thử cô lập (`pro.shellx.desktop.itest` / `.smoketest`) đã tra cứu Keychain của app thật, vì tài khoản Keychain cố định. Không thấy hỏi quyền hay ghi gì, nhưng chưa xác minh. Việc sửa đã có trong plan V2-5a. Nếu thấy macOS hỏi quyền Keychain cho một app lạ, chọn Từ chối.
- Các file thử nghiệm còn lại trong `~/Library/Preferences` thật: `pro.shellx.desktop.itest.plist` và `pro.shellx.desktop.smoketest.plist`. Không phải dữ liệu thật của bạn. Muốn dọn: `defaults delete pro.shellx.desktop.itest` và `defaults delete pro.shellx.desktop.smoketest`.

## 4. Làm tiếp bằng Claude Code (nếu muốn dùng lại quy trình)
- Quy trình là subagent-driven development của plugin superpowers. Brief chung cho người điều phối: `coordination/controller-common.md`. Hai mục "Harness note" và "Scratch hygiene" là bài học rút ra trong hai ngày này.
- Sổ theo dõi của từng plan nằm ở `.superpowers/sdd/<tên-plan>/`, thư mục này git-ignore. Bản sao đã có ở `sdd/`. Chép lại vào đúng chỗ thì người điều phối làm tiếp từ đúng điểm dừng.
- Worktree: `.claude/worktrees/{v2-2b, v2-2b-relay, v2-4}` còn dùng. `v2-3`, `v2-4` và `int` đã gộp, xoá được.
- Flutter: `PATH=~/fvm/versions/3.41.4/bin:$PATH`.

## 5. Nội dung thư mục
- `coordination/`:
  - `top-ledger.md`: sổ điều phối, gồm mọi quyết định cấp trên và lý do;
  - `controller-common.md`;
  - `approved-proposal.md`: đề xuất V2-5 bạn đã duyệt, kèm bản cập nhật font và icon;
  - `verify-dir.sh`.
- `research/`: 4 báo cáo nghiên cứu cho V2-5 (giao diện và tên, AI hiện tại, giọng nói hiện tại, tham khảo Claude, ChatGPT và Figma).
- `sdd/<plan>/`: sổ (`progress.md`) và bàn giao (`handoff-*.md`) của V2-2b, V2-3, V2-4.
- `memory/`: bộ nhớ dài hạn của Claude cho dự án này.

## Trạng thái nhánh lúc 15:00

| Nhánh | Commit | Ghi chú |
|---|---|---|
| `main` (origin) | `e74b02f3` | không đụng tới |
| `shellx-v2` | (commit chứa thư mục này) | gốc `6a51fd3` = V2-3 đã gộp |
| `v2-2b` | `2e354765` | `14e9eb1..` 42 commit; việc 26 chưa đóng review; chưa review toàn nhánh |
| `v2-2b-relay` | `b8d0197b` | `c6cf495` relay B6 + `b8d0197` trang quyền riêng tư; chưa deploy |
| `v2-3` | `73b9bdfc` | đã gộp vào `shellx-v2` (rebase) |
| `v2-4` | `adbdaf76` | xong; đã gộp vào `shellx-v2` dưới dạng rebase (`61d83574`) |
| `v2-5a-wip-union` | `61dddcb3` | bản thử nghiệm, xem bảng ở mục 1 |

Sổ của từng phần kết thúc bằng điểm tiếp tục chính xác: `sdd/v2-2b/progress.md` (mục STOP ORDER), `sdd/v2-4/progress.md`, `sdd/v2-4/handoff-15-16.md` ("Next steps to resume"), `sdd/v2-2b/handoff-20-26.md`.
