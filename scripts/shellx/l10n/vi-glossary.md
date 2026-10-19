# ShellX Vietnamese (vi) glossary and style

Binding for every Vietnamese string in the macOS catalogs (Resources/*.xcstrings,
TunnelExtension/InfoPlist.xcstrings, Packages/macOS/*/Sources/**/*.xcstrings).
Translate the way Apple's own Vietnamese macOS reads: short, plain, everyday wording.

Workflow: `python3 scripts/shellx/l10n/export_missing.py --out <dir>` writes batches
(at most 300 units each) of missing vi units; translate each batch into
`<batch>.vi.json` = `{"<id>": "<Vietnamese>"}`; then
`python3 scripts/shellx/l10n/import_translations.py --map <dir>/*.vi.json` merges them
and `python3 scripts/localization_catalog.py check` must stay green.

## Glossary

| English | Vietnamese |
| --- | --- |
| workspace | phiên |
| pane | khung |
| split (verb / menu) | chia khung (menu: "Chia sang phải", "Chia xuống dưới") |
| tab / surface | tab |
| sidebar | thanh bên |
| command palette | bảng lệnh |
| notification | thông báo |
| agent | agent |
| browser | trình duyệt |
| machine | máy ("this Mac" → "máy này") |
| settings / preferences | Cài đặt |
| terminal | terminal |
| window | cửa sổ |
| shortcut | phím tắt |
| folder | thư mục |
| file | tệp |
| session (of an agent) | phiên |
| copy / paste | Sao chép / Dán |
| close / open / quit | Đóng / Mở / Thoát |
| theme | giao diện màu (a Ghostty theme stays "theme") |
| font | phông chữ |
| update | cập nhật |
| feedback | góp ý |
| error | lỗi |
| focus (keyboard focus) | tiêu điểm |
| toggle X | Bật/tắt X |
| About X | Giới thiệu về X |
| waiting for you (sidebar pill) | chờ bạn |

## Keep verbatim

- Format placeholders (`%@`, `%d`, `%ld`, `%lld`, `%1$@`, `%2$lld`, `%.1f`, `%#@name@`, `%%`):
  same placeholders, same order, same count as the English. Rephrase rather than reorder.
- Line breaks: the same number of `\n` as the English.
- `ShellX`, product and brand names (Ghostty, Claude Code, Codex, GitHub, macOS, Safari,
  Chrome, SSH, Git, VS Code, Xcode, Finder, ...).
- Command names (`shellx …`), CLI flags, code in backticks, file paths, URLs, environment
  variables (`CMUX_*`), config keys, JSON, key caps (⌘ ⌥ ⇧ ⌃ ↩, "⌘K").
- Text that credits the upstream project keeps "cmux" (e.g. "based on cmux").

## Style

- Menu items, buttons, titles: sentence case ("Mở phiên mới", "Chia sang phải");
  keep a trailing "…" when the English has one.
- Short labels stay short; no final period unless the English has one.
- "you" → "bạn". Avoid bureaucratic Sino-Vietnamese wording; prefer "Không tìm thấy",
  "Thử lại", "Bật/Tắt".
- Keep English dev terms Vietnamese developers use as-is: commit, branch, port, log,
  token, prompt, terminal, agent, tab, shell, PTY.
- Settings search alias/keyword strings keep the English words and append Vietnamese
  keywords, so both languages find the row.
- A Vietnamese value identical to the English (OK, Tab, Codex, a CLI format line) needs
  an `identityLocales.vi` reason in `scripts/localization-allowed-omissions.json`.
