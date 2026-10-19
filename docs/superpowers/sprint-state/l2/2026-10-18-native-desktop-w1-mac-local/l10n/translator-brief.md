# Vietnamese translation batch brief (ShellX for Mac)

ShellX is a macOS terminal app (a rebranded fork of the open-source terminal "cmux", built on Ghostty) with workspaces, split panes, a sidebar, a command palette, an embedded browser and AI coding agents (Claude Code, Codex, ...). You translate its English UI strings into natural, concise Vietnamese, the way Apple's own Vietnamese macOS localization reads.

Input: `batch-NN.en.json` = a list of `{"i": <int>, "en": "<English>", "comment": "<developer note, may be empty>"}`.
Output: `batch-NN.vi.json` = ONE JSON object `{"<i as string>": "<Vietnamese>", ...}` with every `i` of the input, nothing else. Valid JSON, UTF-8, real Vietnamese characters (not \u escapes needed, either is fine).

## Glossary (binding)
workspace → "phiên"; pane → "khung"; split → "chia khung"; tab / surface → "tab"; sidebar → "thanh bên"; command palette → "bảng lệnh"; notification → "thông báo"; agent → "agent"; browser → "trình duyệt"; machine → "máy"; settings → "Cài đặt"; terminal → "terminal"; window → "cửa sổ"; shortcut → "phím tắt"; folder → "thư mục"; file → "tệp"; session (of an agent) → "phiên"; copy → "Sao chép"; paste → "Dán"; close → "Đóng"; open → "Mở"; quit → "Thoát"; preferences → "Cài đặt"; theme → "giao diện màu" (Ghostty theme: "theme"); font → "phông chữ"; update → "cập nhật"; feedback → "góp ý"; error → "lỗi".

## Keep verbatim (exactly, same order and count)
- Format placeholders: `%@`, `%d`, `%ld`, `%lld`, `%1$@`, `%2$lld`, `%.1f`, `%#@name@`, `%%` … — every placeholder of the English must appear in the Vietnamese in the SAME ORDER and count. If Vietnamese word order wants a different order, rephrase so the order stays.
- `\n` line breaks: same number of newlines as the English.
- Brand and product names: ShellX, Ghostty, Claude Code, Codex, GitHub, macOS, Safari, Chrome, SSH, Git, iTerm2, VS Code, Xcode, Finder, etc.
- Command names, CLI flags, code in backticks, file paths, URLs, environment variables (`CMUX_*`), config keys, JSON, key caps (⌘ ⌥ ⇧ ⌃ ↩ Tab, "⌘K"), keyboard key names when written as key caps.
- Strings that are only a technical token, a brand, a format string with no words, or a symbol: copy them unchanged.

## Product name rebrand
The English still says "cmux" in places. In your Vietnamese: the product name "cmux" → "ShellX"; the command `cmux …` (in code/backticks or clearly a shell command) → `shellx …`; `cmux.json` → `shellx.json`; `~/.config/cmux` → `~/.config/shellx`; `.cmux/` → `.shellx/`. Exception: text that credits the upstream project (e.g. "based on cmux", "cmux (Manaflow, Inc.)", license/attribution text) keeps "cmux". Leave `CMUX_` env var names and `com.cmuxterm…` identifiers unchanged.

## Style
- Menu items, buttons, titles: sentence case, first letter capital ("Mở phiên mới", "Chia khung sang phải"). Keep trailing "…" if the English has it.
- Short labels stay short (UI space is limited). No ending period on labels unless the English has one.
- Use "bạn" for "you". Avoid Sino-Vietnamese bureaucratic wording; prefer everyday tech wording ("Không tìm thấy", "Thử lại", "Bật/Tắt").
- Keep English technical terms common in Vietnamese dev culture when a translation would be odd (commit, branch, port, log, token, prompt, terminal, agent, tab).
- Use the comment for context; never translate the comment itself.

## Process
1. Read the input file. Translate every entry.
2. Write the output file with the Write tool (one JSON object).
3. Run `python3 /Users/lehuuphu/Documents/myProjects/shellx-wt-l2/.superpowers/sdd/2026-10-18-native-desktop-w1-mac-local/l10n/validate_batch.py NN` for each of your batches; fix every problem it prints until it prints OK.
4. Do not edit any other file. Do not touch the git repo. Do not dispatch subagents.
