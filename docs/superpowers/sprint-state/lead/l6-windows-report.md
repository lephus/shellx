# l6-windows — lane report (interim, 2026-10-19 ~04:50 +07)

Branch `shellx/l6-windows` (lephus/shellx), worktree `~/Documents/myProjects/shellx-wt-l6`. SDD ledger: `.superpowers/sdd/2026-10-19-native-desktop-w4-windows-mvp-plans/progress.md` in the worktree.

## Status
- Done + reviewed: Task 1 (workspace, CI; run 39165923924 green), Task 2 (palette/strings/keys/paste), Task 3 (split tree/tabs/selection), Task 4 (sidebar, pairing/connection state machines, update rule, core API + FakeCore).
- Implemented, in review: Task 5 (TermCore/PtyLink, ConPTY link, palette, fonts; CI 39167342800 green).
- Running: Task 6 (shellx-remote in-process client), Task 7 (app shell).

## Rulings (so far)
See ledger section "Preflight rulings" and later `Ruling:` lines. Key one: the lane plan has no Task sections (file ends at line 139); tasks were reconstructed by the controller from the plan header + spec + K3/D5.

## G1 checklist (user, Windows 11 PC, ~20 min) — gate result decides GPUI vs fallback
Download the spike (old repo, still valid ≤ 30 days):
`gh run download 39149103261 -R lephus/shellx-pro -n shellx-term-spike -D shellx-term-spike`
or the current lane build (has the §7.4 palette + JetBrains Mono): `gh run download 39167342800 -R lephus/shellx -n shellx-desktop -D shellx-desktop`
1. Gõ `tiếng Việt` trong PowerShell bằng Telex có sẵn của Windows, Unikey, EVKey → chữ đúng, không mất/lặp ký tự; khung gợi ý IME nằm gần con trỏ (lệch vị trí = lỗi thẩm mỹ, chấp nhận).
2. Scale 150 % và 200 % (Settings → Display) → chữ sắc nét, không mờ.
3. Typometer: ShellX vs Windows Terminal, cùng cỡ chữ, 5 lần mỗi bên → ghi median.
4. Narrator → dự kiến KHÔNG đọc được (GPUI 0.2.2 chưa có UIA) — chỉ ghi nhận.
Pass = 1 đúng với cả 3 bộ gõ. IME hỏng (chữ sai/mất) → lane chuyển nhánh dự phòng (chỉ terminal tại chỗ).
