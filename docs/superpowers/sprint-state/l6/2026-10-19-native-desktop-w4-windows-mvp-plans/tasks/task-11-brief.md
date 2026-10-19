# Task 11: Update check, update banner, settings/about panel

Binding constraints: `../constraints.md`; spec §11 (Windows: same check and forced update as Mac, via `/v1/version` through shellx-core `version.check`), §7.4 (buttons: primary = PRIMARY_SOFT bg / PRIMARY_LINE border / PRIMARY_TEXT; secondary = RAISE / BORDER / TEXT; no gradients). Model: `shellx_model::update::{UpdateStatus, from_result, banner}`, `core_api::version_check`, strings (UpdateAvailable, UpdateRequired, UpToDate, Download, Settings, About, Version, IconCredits, CmuxCredits, Logout). Files: `ui/settings.rs` (new), small hooks in `ui/root.rs` / `ui/titlebar.rs` (Settings button + Ctrl+, already emit OpenSettings).

## Update
- `version.check` off the UI thread at startup (after `config.set`) and every 6 h; result → `UpdateStatus` (errors → Unknown, silent).
- Available: a 32 px banner at the top of the main area: bg PRIMARY_SOFT, 1 px PRIMARY_LINE bottom border, text PRIMARY_TEXT `update_available(lang, v)`, primary button `Str::Download` → `cx.open_url(download_url)` (only `https://` URLs; ignore others), and a close "×" that hides it until the next check.
- Required: a modal overlay over the whole window (bg BG at 0.85, card RAISE/BORDER) with `Str::UpdateRequired`, the min version, and the Download button; terminals stay running underneath but input is blocked while the overlay is shown (spec forced update). No "skip".
- Up to date / Unknown: nothing shown.

## Settings / About panel
- Opened by the title bar gear or Ctrl+, ; closed by Esc or a close button. Right-side panel 360 px (bg RAISE, left border BORDER) over the main area.
- Sections: Tài khoản (email if known from login, else "Chưa đăng nhập"; secondary button Đăng xuất → account logout from Task 10), Cập nhật (current version 2.0.0, status text, secondary button "Kiểm tra cập nhật" → immediate `version.check`), Ngôn ngữ (read-only: "Tiếng Việt" / "English" + hint "đặt SHELLX_LANG=en để dùng tiếng Anh"), Giới thiệu: "ShellX 2.0.0", `Str::CmuxCredits`, `Str::IconCredits` (required by CC BY 4.0), "JetBrains Mono, Space Grotesk — SIL OFL 1.1", source link `https://github.com/lephus/shellx` (opens with `cx.open_url`). Add any new strings to `shellx-model/src/strings.rs` (both languages, `Str::ALL`, the count test).

## Tests
- Model tests for any new pure logic (e.g. URL allow rule `is_https(url)`, 6 h scheduling) in shellx-model.
- `--smoke-ui-assets` extended to check the new strings are non-empty.

## CI / acceptance
- `app` job green. Stage only your files. Push.

## Commit
`feat(shellx-app): update check with banner and forced-update overlay, settings and about panel`
