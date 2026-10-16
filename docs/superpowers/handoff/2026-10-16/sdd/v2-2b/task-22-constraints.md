# Task 22 constraints (verbatim excerpts) — AI sessions on the machine list

## Spec `docs/superpowers/specs/2026-10-15-v2-2b-phone-ai-more-design.md` (binding; Vietnamese) — criteria 10, 14 (lines 40, 44); B1, B21 (lines 75, 95):

10. **Danh sách máy.** Mở danh sách máy: mỗi máy đang online có dòng "✦ 2 phiên AI · 1 cần bạn" trong ≤ 3 s.
14. **Bản cũ.** Điện thoại V2-2b với desktop V2-2a, hoặc cửa sổ V2-2b với dịch vụ nền V2-2a: không hiện nút nào của V2-2b, phần V2-2a chạy như cũ. Điện thoại V2-2a với desktop V2-2b: như cũ. Mọi test hiện có vẫn xanh.

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| B1 | Khả năng (hai lớp) | Điện thoại chỉ dùng một tính năng V2-2b khi **cả hai**: (a) router báo `ai: 2` trong `session.list.result` (`kAiProtocol = 2` ở tiến trình giữ relay: daemon khi bật dịch vụ nền), chứng minh đường chuyển tiếp hiểu V2-2b; (b) listing của cửa sổ có `"f": [...]` liệt kê tính năng hub làm được (`config`, `blob`, `files`, `changes`, `revert`, `item`, `history`, `folder`, `push_answer`, `acp_head`). Thiếu một trong hai thì nút tương ứng không hiện. | — |
| B21 | Danh sách máy | Khi danh sách máy đang hiện và relay đã nối: mở kênh tới tối đa **6** máy đang online đã ghép đôi (máy dùng gần nhất trước), lấy listing AI, giữ nghe tới khi rời màn, app vào nền hoặc máy offline thì nhả. Thẻ máy có dòng "✦ 2 phiên AI · 1 cần bạn" (màu cảnh báo khi có phiên chờ); chạm dòng này → phiên đang chờ (một phiên) hoặc bộ chọn phiên. Máy lỗi bắt tay thì không hiện lỗi trên danh sách. Kéo xuống để làm mới. | Mỗi lần mở danh sách tốn một lần bắt tay mỗi máy (pin, dữ liệu). |

## Spec §5 (line 170), §7 (lines 190–191, 199), §8 B21 (line 217), §10 item 9 (line 244), §12 (lines 258–259, 264):

| Khoá | EN | VI |
|---|---|---|
| `machineAiLine` | ✦ {n} AI sessions · {w} need you | ✦ {n} phiên AI · {w} cần bạn |

| Tình huống | Hành vi |
|---|---|
| Danh sách máy với máy chưa tin cậy | Không hiện dòng AI, không báo lỗi |

- **B21:** mở/nhả kênh theo màn, tối đa 6, máy lỗi im lặng.
9. Danh sách máy với 2–3 máy online: dòng AI, pin không tụt bất thường sau 10 phút mở màn.

| Rủi ro | Mức | Xử lý |
|---|---|---|
| Mở kênh tới nhiều máy tốn pin | Thấp–TB | Tối đa 6, chỉ khi màn đang hiện |

## Plan rulings R3, R10, R11 (plan lines 53, 60, 61):

- **R3 — capability = router `ai ≥ 2` AND listing `f`** (B1): learned from `session.list.result` and the window's listing; the AI session page asks `session.list` once when the protocol is unknown (opened from a push) and holds the listing while open. *Cost if wrong:* one extra round trip when a page opens cold.
- **R10 — the machine's AI line opens the session or a chooser** (B21): exactly one session waiting → that session; otherwise the session picker's AI group in a sheet over the machine list. *Cost if wrong:* one more tap.
- **R11 — a second line string** (B21): `machineAiSessions` "✦ 2 phiên AI" when nobody waits, since "· 0 cần bạn" reads wrong. *Cost if wrong:* one more string.

## Plan Global Constraints: Naming, No content in logs, Old peers, Mobile (plan lines 79, 82, 84, 87):

- **Naming:** "Claude" or "Claude Agent", never "Claude Code", in feature names and UI strings.
- **No content in logs (D12, B25):** no prompt, agent text, path, file name, diff, image, URL, header or body in any log; new log lines print only `error.runtimeType`. `toString()` of every new `ai.*` message is `'<Type>(…)'`; of every new body/view/record `'…'` (`with Redacted`) or `'<Name>(…)'`; each pinned by a test. Push data carries only an integer id, two option ids and a tag beyond V2-2a's (B25).
- **Old peers:** a malformed `ai.*` message is skipped and an unknown kind ignored, never dropping the channel; every V2-2b feature is gated by router `ai ≥ 2` AND listing `f` (R3); an older desktop or service never receives a V2-2b request; an older phone ignores `body`, `f`, `src`, `img` and the new header keys.
- **Mobile:** strings in `apps/mobile/lib/l10n/intl_en.arb` and `intl_vi.arb` (same keys; `test/l10n_test.dart` checks), generated with `cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH dart run intl_utils:generate`; routes and DI with `cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH dart run build_runner build --delete-conflicting-outputs`; generated files committed. Colours and type from `context.colors` / `context.typo` only; no looping animation except a spinner while loading and the existing mic pulse. Page width 120 (`apps/mobile/analysis_options.yaml`).

## Controller rulings and cross-task contracts (SDD ledger)

- Ruling (F44): the line's tap that opens the one waiting session pushes `AiSessionRoute(key: ValueKey('ai:<agentId>/<sid>'), agentId: …, machineName: …, sid: …)` — the route key every AI-session open path carries since Task 15 (auto_route 11.1 only updates a same-named page without a distinct key); the brief's push omits it.
- Ruling (F11): where a brief's format command names whole directories, any file outside the task's Files block that it changes is restored to HEAD and reported, never committed.
- Ruling (F12): after `dart run intl_utils:generate` in apps/mobile, run `~/fvm/versions/3.41.4/bin/dart format lib/shared/src/l10n.dart lib/shared/src/intl/messages_en.dart lib/shared/src/intl/messages_vi.dart` from apps/mobile so the commit holds only the new entries; `intl_utils` may renumber its `mN` helpers (generator output, acceptable).
- Task 6 contract: `openAiChooser(BuildContext context, {required String agentId, required String machineName, required AiMachine ai, required AiListing listing, bool replace = false})`; `MachineAi.can` reads the listing kept across a lost channel.
- Mobile `flutter analyze` has one pre-existing info (`unnecessary_import`, `test/features/terminal/ime_in_place_edit_test.dart:2:8`) — not this task's finding.
