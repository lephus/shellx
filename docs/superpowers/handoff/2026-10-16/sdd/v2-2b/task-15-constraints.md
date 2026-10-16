# Task 15 constraints (verbatim excerpts) — phone: "Lịch sử phiên" and "Dùng thư mục này"

## Spec `docs/superpowers/specs/2026-10-15-v2-2b-phone-ai-more-design.md` (binding; Vietnamese) — success criteria 8, 9, 14 (lines 38–39, 44); B17, B18 (lines 91–92):

8. **Lịch sử.** "Lịch sử phiên" liệt kê phiên cũ của agent; chạm một phiên → máy tính mở tab AI mới (không chuyển tab đang xem) và điện thoại vào phiên đó với lịch sử phát lại.
9. **Thư mục.** Tab AI chưa có thư mục: điện thoại chọn một thư mục máy tính đưa ra → agent chạy.
14. **Bản cũ.** Điện thoại V2-2b với desktop V2-2a, hoặc cửa sổ V2-2b với dịch vụ nền V2-2a: không hiện nút nào của V2-2b, phần V2-2a chạy như cũ. Điện thoại V2-2a với desktop V2-2b: như cũ. Mọi test hiện có vẫn xanh.

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| B17 | Lịch sử phiên | `ai.history {sid, rid, cursor?}` → `{"sessions": [{"acp", "title", "at"}], "next"?, "current"?}` (≤ 50 mỗi trang, tiêu đề cắt ≤ 120 ký tự); agent của phiên chưa sẵn sàng → `not_ready` (điện thoại thử lại khi phiên chạy); agent không hỗ trợ `session/list` → nút không hiện (cờ trong header). Mở một mục: `ai.open` thêm `resume: <acp>` và khoá thư mục của phiên đó → desktop mở tab AI mới tiếp phiên cũ (`select: false`), phát lại như D15. | Hai tab cùng một phiên agent nếu người dùng mở hai lần (desktop cũng vậy). |
| B18 | Chọn thư mục | `ai.folder {sid, rid, folder}` (khoá từ listing, D9) cho tab `no_folder`: desktop làm như nút "Dùng thư mục này" của tab (quên runtime cũ, đặt `cwd`), rồi agent chạy (D15). Điện thoại: thay câu "Chọn thư mục trên máy tính" bằng danh sách thư mục và nút "Dùng thư mục này". | — |

## Spec §5 strings (lines 149–150, 168–169) and §8 tests (lines 215, 220):

| Khoá | EN | VI |
|---|---|---|
| `aiHistory` | Session history | Lịch sử phiên |
| `aiUseFolder` | Use this folder | Dùng thư mục này |

- **B17/B18:** trang lịch sử, `not_ready`, `resume` mở tab không chọn; khoá thư mục lạ bị từ chối.
- **App mobile (widget):** từng màn mới, chống chạm 400 ms ở hoàn tác, các trạng thái.

## V2-2 spec D9, D14 (`docs/superpowers/specs/2026-10-14-v2-2-phone-ai-design.md` lines 96, 101):

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| D9 | Phiên mới từ điện thoại | Chỉ với agent máy tính báo sẵn sàng (chưa biết thì coi là sẵn sàng, như V2-1b) và một **thư mục do máy tính đưa ra:** gốc dự án của các workspace cục bộ, cộng thư mục của các tab AI đang mở. Điện thoại gửi khoá (`ws:<id>` hoặc `path:<thư mục>`), không bao giờ gửi đường dẫn tự gõ. Tab AI mới vào đúng workspace, **không được chọn** trên desktop, và agent chạy ngay. Cấu hình nhớ theo agent được dùng như desktop, không bao giờ áp lại "Bỏ qua mọi quyền" (V2-1a R6). | Dự án chưa thuộc workspace nào phải đặt gốc trên máy tính trước. |
| D14 | Một phiên không chạy được | Tab AI chưa có thư mục, hoặc agent đã tắt/xoá trong Cài đặt: danh sách ghi "Chọn thư mục trên máy tính" / "Agent đang tắt trên máy tính"; mở ra thì thấy đúng câu đó, không có ô nhập. | — |

## Plan rulings R3, R15 (plan lines 53, 65):

- **R3 — capability = router `ai ≥ 2` AND listing `f`** (B1): learned from `session.list.result` and the window's listing; the AI session page asks `session.list` once when the protocol is unknown (opened from a push) and holds the listing while open. *Cost if wrong:* one extra round trip when a page opens cold.
- **R15 — a V2-2b request the computer cannot take fails at once on the phone** (`AiRequestException('unsupported')`, nothing sent). *Cost if wrong:* none.

## Plan Global Constraints: Naming, No content in logs, Old peers, Mobile (lines 79, 82, 84, 87):

- **Naming:** "Claude" or "Claude Agent", never "Claude Code", in feature names and UI strings.
- **No content in logs (D12, B25):** no prompt, agent text, path, file name, diff, image, URL, header or body in any log; new log lines print only `error.runtimeType`. `toString()` of every new `ai.*` message is `'<Type>(…)'`; of every new body/view/record `'…'` (`with Redacted`) or `'<Name>(…)'`; each pinned by a test. Push data carries only an integer id, two option ids and a tag beyond V2-2a's (B25).
- **Old peers:** a malformed `ai.*` message is skipped and an unknown kind ignored, never dropping the channel; every V2-2b feature is gated by router `ai ≥ 2` AND listing `f` (R3); an older desktop or service never receives a V2-2b request; an older phone ignores `body`, `f`, `src`, `img` and the new header keys.
- **Mobile:** strings in `apps/mobile/lib/l10n/intl_en.arb` and `intl_vi.arb` (same keys; `test/l10n_test.dart` checks), generated with `cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH dart run intl_utils:generate`; routes and DI with `cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH dart run build_runner build --delete-conflicting-outputs`; generated files committed. Colours and type from `context.colors` / `context.typo` only; no looping animation except a spinner while loading and the existing mic pulse. Page width 120 (`apps/mobile/analysis_options.yaml`).

## Controller rulings and cross-task contracts (SDD ledger)

- Ruling (F12): after `dart run intl_utils:generate` in apps/mobile, run `~/fvm/versions/3.41.4/bin/dart format lib/shared/src/l10n.dart lib/shared/src/intl/messages_en.dart lib/shared/src/intl/messages_vi.dart` from apps/mobile so the commit holds only the new entries (the generator writes 80 columns, the committed files are at 120). The generator also renumbers its `mN` helpers in messages_en/vi.dart when a string with arguments is added: generator output, acceptable.
- Ruling (F11): a format command naming whole directories never commits a file outside the task's Files block (restored to HEAD and reported).
- Task 6 contract (H1): `AiSessionController(@factoryParam String agentId, @factoryParam String sid, SessionHolder session, AiDrafts drafts, WorkspaceRegistry registry)` positional in this order; `can(feature)` reads `MachineAi._listing` (kept across a lost channel); page `_Header({…, VoidCallback? onSubtitle, List<AiHeaderAction> menu = const []})`, the "⋯" menu `Key('ai.menu')`.
- Task 14 (done): `MachineAi.history(sid, {cursor})` and `MachineAi.chooseFolder(sid, folder)` go through `_feature(AiFeature.history|folder, …)`; `MachineAi.resume(agent, folder, acp)` goes through `_feature(AiFeature.history, null, …)` (an `ai.open {resume}`). The hub answers `not_ready` while the agent does not run, `refused` for an agent without `session/list`; history titles are cut to 120 characters (F28). The desktop opens a resumed session in a new tab that is not selected.
- Mobile `flutter analyze` has one pre-existing info (`unnecessary_import`, `test/features/terminal/ime_in_place_edit_test.dart:2:8`) — not a task's finding.
