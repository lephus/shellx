# Task 11 report: update check, banner, forced-update overlay, settings/about

Status: DONE. Commit 56acdac036 on shellx/l6-windows, pushed. CI run 39176242679 green (model, remote-e2e, app, installer); GPUI code compiled on the first try.

## Built
- Model: update.rs gained CHECK_INTERVAL_SECS (6 h), is_https, download_url (https only). strings.rs gained 11 Str (Account, Updates, Language, LanguageHint, LanguageName, CheckUpdate, Checking, SignedIn, Close, FontCredits, CheckFailed; count test 61) and minimum_version(). Tests: https_only, download_url_needs_https.
- core_service.rs: run_version_check(core) (from_result(version_check)); Mac test with FakeCore.
- ui/account.rs: the 10b worker now takes Job::{Account, VersionCheck}; one thread model. Check at startup (queued after first account call, so config.set is already sent) and every 6 h; check_update() for the button; errors -> Unknown; a failed check never lifts an active Required. Keeps sign-in email (shown only while LoggedIn), banner_hidden (reset by each check result).
- ui/update_banner.rs: 32 px banner (PRIMARY_SOFT/PRIMARY_LINE/PRIMARY_TEXT, primary Download -> cx.open_url only for https, "x" hides until next check); forced overlay below the title bar (BG at 0.85, RAISE/BORDER card, min version, Download, no skip), occlude() blocks mouse, key handler swallows keys.
- ui/settings.rs: 360 px right panel (RAISE, left BORDER), Esc / close button; sections Tai khoan (email or "Da dang nhap" / "Chua dang nhap", logout button, logout notice), Cap nhat (version, status, Download when available, "Kiem tra cap nhat"), Ngon ngu (read-only + hint), Gioi thieu (ShellX 2.0.0, cmux credit, coolicons CC BY 4.0, fonts OFL, source link via open_url).
- root.rs/titlebar.rs/mod.rs: small hunks. open_settings(window, cx) toggles; while Required, all app commands and keys are ignored and focus_terminal puts focus on the overlay; terminals keep running.
- shell_info SHELL_STRINGS extended; --smoke-ui-assets now reports 38 strings x 2 languages, PASS.

## Evidence
Mac, CARGO_INCREMENTAL=0 --locked: shellx-model 128 passed; shellx-app bin 70 passed; --smoke-ui-assets PASS. CI all 4 jobs green.

## Concerns
- Overlay starts below the title bar (so caption buttons keep working); title-bar sidebar toggle still works under it, settings is blocked.
- Panel/overlay layout, focus hand-off and Esc are unverified at runtime (GPUI, CI-compiled only). Manual: set an update_required response and confirm keys/mouse are dead in terminals; open Ctrl+, and Esc; Download opens the browser.
- After a restart the email is unknown, so the panel shows "Da dang nhap" (core exposes no email).
- Keys other than Esc pressed with the panel open still reach root app commands (e.g. Ctrl+Shift+T works and keeps focus on the panel).
- Auto-update install is out of scope (opens browser).
