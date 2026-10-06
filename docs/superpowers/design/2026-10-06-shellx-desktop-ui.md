# ShellX desktop A1 — UI design (tokens, layout, components, copy)

- **Date:** 2026-10-06 · **Scope:** A1 of `docs/superpowers/specs/2026-10-06-desktop-terminal-a1-design.md` (binding). Only what that spec lists is rendered; slots for A2/A4 are reserved but empty.
- **Sources:** mobile design `2026-09-25-shellx-mobile-ui.html` (`--t-*`, `--a-*` dark), `apps/mobile/lib/core/design/terminal_colors.dart`, cmux.com (dense dark vertical tabs, context lines, notification ring/badge).
- **Principle:** the window is a terminal first. Chrome is quiet (one dark family), state is shown with small marks, never with layout jumps that resize the PTY (a resize makes the desktop the driver — D6).

---

## 1. Design tokens

A1 ships **one dark theme** for the whole window, dialogs included (terminals are dark in both app themes on mobile too). No light theme in A1; system light mode does not change the window. Implement as `ShellxDesktopColors` (const `Color`s) + `ThemeData` built from them in `ui/theme/`; replace `colorSchemeSeed: 0xFF2563EB` in `app.dart` entirely.

### 1.1 Color

Contrast measured with WCAG 2.x formula against the surface the token is used on.

| Token | Hex | Source | Use | Contrast |
|---|---|---|---|---|
| `bgTerminal` | `#0B1215` | `--t-bg` | terminal pane, pane header (macOS) | — |
| `bgSidebar` | `#111B1E` | `--t-chrome` | sidebar, Windows header row | — |
| `rowHover` | `#172427` | new | sidebar row hover, icon button hover | — |
| `rowSelected` | `#1F2F34` | `--t-chrome2`, lightened (final wave S-7) | selected row, tooltip bg, neutral toast | 1.26 vs sidebar (was 1.14) |
| `rowPressed` | `#26393E` | new (raised with `rowSelected`, so hover < selected < pressed) | pressed row/button, row × hover | — |
| `line` | `#243337` | `--t-line` | sidebar/pane divider (1 px), menu separators | — |
| `surface` | `#172023` | `--a-surface` dark | dialogs, context menu | — |
| `surfaceInset` | `#0D1315` | `--a-bg` dark | text-field fill | — |
| `border` | `#2B373A` | `--a-border` dark | dialog/menu/toast outline (decorative) | — |
| `borderInput` | `#5E7176` | new | text-field outline (non-text ≥ 3:1) | 3.23 on surface |
| `textPrimary` | `#D4E1E4` | `--t-fg` | row titles, strip text, terminal fg | 13.1 on sidebar, 11.5 on selected |
| `textTitle` | `#E8F0F2` | `TerminalColors.title` | selected row title, dialog title | 13.3 on selected |
| `textSecondary` | `#93A5A9` | `--muted` dark | pane header title, hints, icons | 6.8 on sidebar, 6.0 on selected |
| `textDialog2` | `#A7B6BA` | `--a-text2` dark | dialog body, field labels | 7.9 on surface |
| `textPlaceholder` | `#6F8186` | `--a-muted` dark | placeholder only | 4.6 on surfaceInset |
| `dim` | `#6C8288` | `--t-dim` | **decorative only** (disabled icons, scrollbar hover); never body text on sidebar (4.3) | — |
| `accent` | `#5FD4E2` | `--t-cyan` | focus ring, selected bar, links, phone-viewing icon, running dot | 10.0 on sidebar |
| `primary` | `#2DBFCF` | `--a-primary` dark | primary button fill | — |
| `onPrimary` | `#04282D` | `--a-on-primary` dark | text on primary | 7.0 |
| `primarySoft` | `#0E363C` | `--a-primary-soft` dark | input focus halo, selection in lists | — |
| `ok` | `#7ED492` | `--t-green` | idle dot | 9.8 |
| `warn` | `#E9C46A` | `--t-yellow` | driver pill text/icon, phone-driving icon | 9.2 on pill bg |
| `warnBg` / `warnBorder` | `#2A2412` / `#4A3F1C` | `driverBannerBackground/Border` | driver pill | — |
| `err` | `#F07178` | `--t-red` | exited dot, exit code in exit line | 6.1 on sidebar |
| `errDialog` | `#F26A70` | `--a-err` dark | form errors, destructive button fill | 5.6 on surface |
| `onErr` | `#2A0A0C` | new | text on destructive button | 6.2 |
| `noticeBg` / `noticeText` / `noticeBorder` | `#2A1416` / `#FFD9DB` / `#5A2A2E` | `TerminalColors.notice*` | error toast | 13.4 |
| `scrim` | `#99000000` (black 60 %) | `--a-scrim` dark | behind dialogs | — |
| `scrollThumb` / `scrollThumbHover` | `#2B373A` / `#3A4A4E` | — | overlay scrollbars | — |

Terminal ANSI palette: reuse `TerminalColors.theme` from mobile **verbatim** (copy the file into `apps/desktop/lib/src/ui/theme/terminal_colors.dart` in A1; extract to a shared package later, §7). Selection `#665FD4E2`, cursor `#D4E1E4`.

### 1.2 Spacing, radii, sizes

- **Spacing scale (px):** `s2=2, s4=4, s6=6, s8=8, s12=12, s16=16, s20=20, s24=24, s32=32`. Nothing off-scale except the fixed sizes below.
- **Radii:** `r4` badges/kbd hints · `r6` rows, buttons, inputs, menu items, tooltips · `r8` context menu, toast, QR tile · `r12` dialogs · `rPill=999` driver pill.
- **Fixed sizes:** sidebar 220 · row 30 (+2 gap) · header band 38 (macOS) / 36 (Windows) · pane header 28 (macOS only) · signed-out strip 36 · driver pill 28 · button 32 · input 36 · icon 16 (glyph in 28 hit box) · row marks 14 · dot 8.
- **Hit targets:** every pointer target ≥ 24×24 (WCAG 2.2 2.5.8); icon buttons are 28×28.

### 1.3 Typography

UI font: **platform default** — do not set `fontFamily` in `ThemeData` (Flutter resolves to SF Pro on macOS, Segoe UI on Windows). Styles that replace the ambient text style (button labels, tooltips, text fields, the dialog text theme) copy the theme's platform family explicitly (`uiFont`, final wave P-4), so they never fall back to the engine default. Terminal and code: **JetBrains Mono** (bundle `JetBrainsMono-{Regular,Bold,Italic,BoldItalic}.ttf` from `apps/mobile/assets/fonts/`, SIL OFL; add to `pubspec.yaml` `fonts:`).

| Style | Size / line height | Weight | Use |
|---|---|---|---|
| `caption` | 11 / 14 | 500 | shortcut hints in menus/tooltips; reserved for A2 context line |
| `small` | 12 / 16 | 400 | pane header title, tooltips, toast secondary |
| `body` | 13 / 18 | 400 | row title, strips, menu items, toast |
| `bodyStrong` | 13 / 18 | 600 | selected row title, button labels |
| `dialogBody` | 14 / 20 | 400 | dialog text, field values |
| `label` | 12.5 / 16 | 600 | field labels |
| `dialogTitle` | 17 / 22 | 600 | dialog title |
| `emptyTitle` | 15 / 20 | 600 | empty-state title |
| `terminal` | JetBrains Mono 13, `TerminalStyle(height: 1.2)` | 400 | default; ⌘+/⌘− steps of 1, clamp 9–28, ⌘0 → 13; persisted |

Text scales with the OS setting; row height grows with `MediaQuery.textScaler` (min 30, computed as `max(30, 18 * scale + 12)`).

### 1.4 Elevation

Dark UI: elevation = outline + shadow, no tint.
- `e0` sidebar/pane — flat, separated by 1 px `line`.
- `e1` context menu, tooltip, toast, driver pill — 1 px `border` + `BoxShadow(0, 4, blur 16, #73000000)`.
- `e2` dialog — 1 px `border` + `BoxShadow(0, 16, blur 48, #8C000000)` over `scrim`.

### 1.5 Motion

| Token | Duration | Curve | Use |
|---|---|---|---|
| `fast` | 80 ms | `easeOut` | hover/pressed fills, icon colour |
| `base` | 150 ms | `easeOutCubic` | dialog in (fade + scale 0.98→1), strip fade, pill fade |
| `exit` | 120 ms | `easeIn` | dialog/toast/pill out |
| `toast` | 160 ms in (fade + translateY 8→0), visible 4 s (6 s for errors), 120 ms out | | toast |

Tab switching, selection and row insertion are **instant** (terminal users switch fast). No pulsing/looping animation in A1. When `MediaQuery.disableAnimationsOf(context)` is true every duration is `Duration.zero` (toast still auto-dismisses on its timer).

---

## 2. Window layout

Window: resizable, min 640×400, default 1100×720, bounds remembered (spec §3.2). Window title (Mission Control, taskbar, ⌘\`): `"{tabTitle} — ShellX"`, or `"ShellX"` with no tabs.

```
macOS (titlebar transparent, fullSizeContentView, traffic lights over the sidebar)
x=0                 220 221                                                  W
┌────────────────────┬┬──────────────────────────────────────────────────────┐ y=0
│ ● ● ●          [+] ││                  zsh — ~/work                        │ header band 38 │ pane header 28
│                    ││───────────────────────── (no line; same bg) ─────────│
│ ▌● zsh 1           ││ ~/work $ _                                           │ rows start y=42
│  ● claude      👁 ││                                                      │
│  ● htop      📱    ││                                                      │
│  ○ build           ││                                                      │
│                    ││                                                      │
└────────────────────┴┴──────────────────────────────────────────────────────┘
```

### 2.1 Title bar

- **macOS:** `windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true)` → transparent unified title bar, traffic lights at their system position (first light centre ≈ x 20, y 14). Sidebar **header band 38 px**; its content is aligned to the traffic-light centre line y = 14, not to the band centre. The left 80 px of the band stays empty. Whole band + pane header are drag areas (`DragToMoveArea`); double-click follows the system "double-click title bar" setting (window_manager default).
- **Pane header (macOS only):** 28 px, `bgTerminal`, draggable, shows the selected tab title centred, `small`, `textSecondary`, one line, ellipsis, max-width 60 % of pane. It replaces the hidden system title. No bottom border.
- **Windows:** keep the **native title bar** in A1 (system caption buttons, snap layouts, dark mode via `windowManager.setBrightness(Brightness.dark)`); its text is the window title above. Sidebar header band 36 px, no pane header. Custom Windows caption = later milestone.

### 2.2 Sidebar (220 px, resizable in a later milestone)

- Background `bgSidebar`; right edge 1 px `line` (`VerticalDivider(width: 1)`), then the terminal pane.
- **Header band:** `+` icon button right-aligned, 8 px from the sidebar's right edge (macOS centre y 14; Windows vertically centred in 36).
- **List:** starts 4 px under the band; horizontal margin 6 px; row height 30; gap 2 px between rows; bottom padding 8 px. Scrolls when overflowing.
- **Scrollbar:** overlay `RawScrollbar`, thickness 6, radius 3, 2 px from right edge, thumb `scrollThumb` (hover `scrollThumbHover`), visible while scrolling or while the pointer is over the list, fades after 800 ms (`fast` fade; instant with reduced motion). Never reserves layout width.

**Tab row anatomy (A1, single line; reserved slots shown in brackets):**

```
|6|8 |—8—|  title (flex, 1 line, ellipsis)  |4|📱|4|👁|4|×|  [badge A4]  |8|
     dot                                       14    14  20   reserved 0 px in A1
     [A4 ring: 2 px accent outline on the whole row, inset 0]
     [A2 context line: second line, caption 11/14, textSecondary, "main · ~/work · :3000" → row 46 px]
```

- Left padding 8, status dot slot 16 (dot 8 centred), title `body`, trailing marks 14 px icons with 4 px gap, then the close button, right padding 8.
- **Close button (final wave, ruling I6):** `Icons.close` 14 in a 20×20 visual (`r4`) inside a 24×24 hit area; shown on hover and on the selected row; its slot is always reserved so a title never re-truncates on hover. Hover: `rowPressed` fill, glyph `textSecondary` → `textPrimary`. Tooltip "Đóng tab  ⌘W" / "Close tab  Ctrl+Shift+W" (`terminalCloseTabTooltip`). Same rules as ⌘W (D15 confirm while a command runs). Not a tab stop and not in semantics (the list is one tab stop; the row's "Đóng tab" custom action and ⌘W cover keyboard and screen readers).
- Marks in fixed order: phone-origin then phone-viewing. Marks never truncate; the title truncates.
- A2 will add the second line by making the row height 46 and the title line `bodyStrong`; build the row as a `Column` with an optional second child now so A2 is additive.

### 2.3 Terminal pane

- `TerminalView` fills the pane under the pane header (macOS) or from the top (Windows); padding `EdgeInsets.fromLTRB(10, 6, 10, 6)` inside `bgTerminal`. Overlay scrollbar same spec as the sidebar (xterm scrollback).
- Overlays (never change terminal size): **driver pill** (top right, §2.5), **toast** (bottom centre). The terminal is clipped to its area (a buffer scrolled by part of a row never paints over the strip or the pane header). A narrower window drops blank rows under the cursor before pushing lines into the scrollback (xterm's reflow keeps them otherwise), so the prompt stays on screen. Layout rows (change size, acceptable because they are rare and appear before phones attach): **signed-out strip** (top of pane).
- Inactive tabs stay mounted offstage (`IndexedStack` or `Offstage`) so output keeps writing (spec §5).

### 2.4 Signed-out strip (D11)

Top of the terminal pane (under the macOS pane header), full pane width, height 36, bg `rowSelected`, bottom 1 px `line`. Left 12: `Icons.cloud_off_outlined` 16 `textSecondary`, 8 gap, text `body` `textPrimary` "Đăng nhập để dùng từ điện thoại". Right 8: text button "Đăng nhập…" (`bodyStrong`, `accent`, 28 high, padding 0/10, hover `rowHover`) → opens the login dialog. No dismiss. Disappears with `base` fade when signed in.

### 2.5 Driver pill (D6)

When the selected session's driver is `phone`: floating pill, **top right** of the pane, 8 px below the pane header/strip and 12 px from the right edge (final wave S-2: the centre sat on the most-read rows). While the cursor is on the rows that corner covers (a fresh prompt on row 1), the pill moves to the **bottom right** (8/12 px), so it never hides the line being typed; it stays top right while a toast owns the bottom. Height 28 (min), padding 5/12, `rPill`, bg `warnBg`, 1 px `warnBorder`, `e1`. Content: `kPhoneIcon` (`Icons.phone_iphone_outlined`) 14 `warn`, 6 gap, text `body` `warn` "Điện thoại đang dùng terminal này — gõ để dùng lại", max-width `min(560, pane − 24)`, ellipsis. Pane narrower than 520 (final wave S-1): the short copy `terminalDriverPhoneShort` "Điện thoại đang dùng — gõ để dùng lại" / "Phone in control — type to take over", wrapping to a second line (the pill grows) rather than cutting the instruction. **Not interactive** (`IgnorePointer`), so clicks reach the terminal; any key or resize in the window makes the desktop driver and the pill fades out (`exit`). Live region: announced once on appear.

### 2.6 Exit state (D14)

Exit code 0: tab closes (no UI). Non-zero: the line is **written into the tab's xterm buffer** (copyable, no layout change), after a newline if the cursor is not at column 0:

`ESC[2m[Tiến trình đã thoát, mã ESC[22;31mNESC[39;2m] — Enter để đóngESC[0m` and cursor hidden (`ESC[?25l`).

Row: dot becomes the hollow red ring, title colour `textSecondary`. In that tab Enter (or ⌘W / Ctrl+Shift+W, or "Đóng tab") closes it; other keys are ignored. Semantics announces "đã thoát, mã N".

### 2.7 Empty state

Shown in the pane when there are no tabs (last tab closed; spawn failed on launch). Centred column, max-width 320: `Icons.terminal` 32 `textSecondary` → 12 → title `emptyTitle` `textPrimary` "Không có tab nào đang mở" → 6 → body `body` `textSecondary` (centred) → 16 → primary button "Mở tab mới" (32 high) → 8 → hint `caption` `textSecondary` "⌘T" / "Ctrl+Shift+T". Sidebar list is empty (header band and `+` remain). Recommendation (not in spec, harmless): ⌘W on the empty state hides the window.

### 2.8 Toast (floating notice)

Bottom centre of the terminal pane, 16 px above the bottom edge, max-width 420, min-height 36, padding 8/12, `r8`, `e1`. Variants: **error** (`noticeBg`, 1 px `noticeBorder`, text `noticeText`, `Icons.error_outline` 16) for session limit / spawn failure; **neutral** (`rowSelected`, `border`, `textPrimary`) reserved. One at a time (new replaces old). Trailing close icon button 24×24 (`Icons.close` 14). Pauses its timer while hovered. `Semantics(liveRegion: true)`.

---

## 3. Components

States use these fills unless stated: hover `rowHover` (`fast`), pressed `rowPressed`, focused = **2 px `accent` ring inside the radius** shown only for keyboard focus (`FocusableActionDetector` `onShowFocusHighlight`), disabled = 38 % opacity, no hover.

### 3.1 Tab row (`SessionTabRow`)

| State | Visual |
|---|---|
| Default | transparent, title `body` `textPrimary` |
| Hover | `rowHover`; × close button shown; tooltip with full title after 500 ms if truncated, placed **beside the sidebar** (x = 226, centred on the row, max-width 360) so it never covers the next row |
| Selected | `rowSelected`, title `bodyStrong` `textTitle`, 3 px × 18 px `accent` bar at the row's left edge, vertically centred, `r4` ends; × close button shown |
| Selected + hover | `rowSelected` (no change) |
| Pressed | `rowPressed` |
| Focused (keyboard) | focus ring; may combine with selected (the selected bar then moves 1 px inside the 2 px ring, so both show) |
| Exited (non-zero) | hollow red dot, title `textSecondary` |
| Disabled | n/a |

**Status dot (8 px):** idle = filled `ok`; running a command (`runningCommand`) = 1.5 px `accent` ring with a 4 px filled `accent` centre (a target; final wave S-3 — `ok` vs `accent` is 1.02:1, so the shapes must differ); exited non-zero = 1.5 px `err` ring, transparent centre. Shape + colour + Semantics, never colour alone.

**Marks (14 px, `Icons.*_outlined`, monochrome — not emoji, so both OSes match):**
- Phone origin (`origin == phone`): `Icons.phone_iphone_outlined` (final wave P-1: notch and home bar read as a phone at 14 px; `smartphone` read as an empty rectangle), `textSecondary`. Tooltip "Mở từ điện thoại".
- Phone viewing (`phoneAttached`): `Icons.visibility`, `accent`; when the phone is also the driver: `warn` colour. Tooltip "Điện thoại đang xem" / "Điện thoại đang dùng".

**Interaction:** click = select + focus terminal. Middle-click = close (same rules as ⌘W). Secondary click / `Shift+F10` / Menu key = context menu. New phone-origin tabs are appended and not selected (spec).

**Context menu:** `e1`, `surface`, `r8`, padding 4, min-width 180; item height 28, padding 0/10, `body`, hover `rowSelected` `r6`; shortcut hint right-aligned `caption` `textSecondary`; a disabled item stays in place at 38 %. Tab row items: **"Đóng tab"** (`⌘W` / `Ctrl+Shift+W`). Esc closes the menu; ↑/↓ + Enter operate it.

**Terminal context menu (final wave, ruling I6):** secondary click in the terminal opens the same menu with **"Sao chép" / "Copy"** (`⌘C` / `Ctrl+Shift+C`, disabled without a selection), **"Dán" / "Paste"** (`⌘V` / `Ctrl+Shift+V`), **"Chọn tất cả" / "Select all"** (`⌘A` / `Ctrl+Shift+A`; the whole buffer, scrollback included, like Terminal.app, iTerm2 and Windows Terminal). They run the window's own shortcut actions. When the program has taken the mouse (vim, htop with mouse mode) the click goes to the program instead, as in other terminals. The keyboard returns to the terminal afterwards.

**Close with running command (D15):** confirm dialog (§4) before closing; otherwise close immediately.

### 3.2 New-tab button (`+`)

28×28 hit, 24×24 visual, `r6`, `Icons.add` 16 `textSecondary`; hover `rowHover` + icon `textPrimary`; pressed `rowPressed`; focus ring. Busy (open in flight): icon replaced by a 12 px `CircularProgressIndicator(strokeWidth: 1.5)`, further clicks ignored. Never disabled for the 32 limit — the attempt shows the limit toast. Tooltip "Tab mới  ⌘T".

### 3.3 Buttons (dialogs, strip, empty state)

Height 32, min-width 80, padding 0/14, `r6`, label `bodyStrong`.
- **Primary:** `primary` / `onPrimary`; hover lighten 8 % (`#4CCAD8`); pressed `#26A9B8`.
- **Secondary:** transparent, 1 px `borderInput`, `textPrimary`; hover `rowHover`.
- **Destructive:** `errDialog` / `onErr`; hover `#F4848A`.
- **Text:** `accent`, no fill; hover `rowHover`.
- Focus (keyboard): the 2 px `accent` ring inside the radius, except on **filled** buttons (primary, destructive), where it is drawn **outside** the button with a 2 px gap (final wave S-9: `accent` on `primary` is 1.27:1; outside it is ≥ 9:1 on `surface` / `bgTerminal`).
- Disabled: 38 % opacity. Loading: label stays, 14 px spinner replaces leading space; width does not change.
- Default button (Enter) = primary; Esc = cancel.

### 3.4 Text field

Height 36 (padding 8/10 around the 20 px `dialogBody` line, `isDense`), `surfaceInset`, 1 px `borderInput`, `r6`, value `dialogBody` `textTitle`, placeholder `textPlaceholder`. Focus: 1 px `accent` + 3 px `primarySoft` halo. Error: 1 px `errDialog`, helper text `small` `errDialog` 4 px below. Label `label` `textDialog2` 6 px above (`LabeledField`, merged with the field for screen readers; never a floating label inside the outline). Fields 16 apart. Password fields keep the existing show/hide behaviour. The `+3 px primarySoft` focus halo is not built in A1 (the 1 px accent outline is the focus cue).

### 3.5 Tooltip

`rowSelected`, 1 px `border`, `r6`, padding 4/8, `small` `textPrimary`, wait 500 ms, shortcut part in `caption` `textSecondary`.

### 3.6 Keyboard focus order and regions

Regions cycle with **Ctrl+F6** (forward) / **Ctrl+Shift+F6** (back) from the terminal, on both OSes, because Tab belongs to the shell inside the terminal; plain **F6** / **Shift+F6** also cycle when the focus is outside the terminal. Inside the terminal plain F6 reaches the program (htop sorts, mc moves) — controller ruling, final wave I7:
1. Terminal (initial focus; regained after any dialog/menu closes and after selecting a tab).
2. Sidebar: `+` button → tab list (one tab stop: ↑/↓ and Home/End **select** the tab at once — the terminal on the right follows while the keyboard stays in the list, like the tab lists of most terminals; Enter/Space/Esc give the keyboard back to the terminal; Shift+F10 / Menu key open the row menu). Final wave S-6 ruling: the doc follows the code, no separate roving highlight. Tab/Shift+Tab move between `+` and the list. Esc returns to the terminal.
3. Signed-out strip button (only when visible).
Global shortcuts (spec criterion 2) work from every region. In dialogs: normal Tab order, top to bottom, actions last (primary last on macOS, first on Windows — matches visual order).

### 3.7 Accessibility

- Sidebar: `Semantics(label: "Danh sách tab", container: true)`; each row `Semantics(button: true, selected: isSelected, label: <row label>, onTap, customSemanticsActions: {Đóng tab})`. Row label = parts joined with ", ": title · status · [origin] · [viewing/driving] · position. Example vi: "claude, đang chạy lệnh, mở từ điện thoại, tab 2 trên 4"; en: "claude, running a command, opened from your phone, tab 2 of 4".
- Terminal pane: `Semantics(label: "Terminal {title}")`. Driver pill / toast: `liveRegion: true`. Dot and marks are `ExcludeSemantics` (their meaning is in the row label).
- Contrast: all text pairs in §1.1 ≥ 4.5:1; non-text (input outline, focus ring, dot, marks) ≥ 3:1.
- VoiceOver/Narrator focus follows region changes; dialogs are `barrierDismissible: false` for confirms, focus-trapped, initial focus on the first field (forms) or the safe action (confirms).

---

## 4. Dialogs (legacy pages → `showDialog` over the terminal window)

`WindowRouter` routes now open dialogs; one at a time (opening a route replaces the open dialog). The window no longer resizes per route (drop `windowSizeFor`). If the window is hidden when a route opens (tray click), show the window first.

| Dialog | Width | Content (reuse current page bodies) |
|---|---|---|
| Login / register | 400 | email, password, [confirm], error, primary, switch link, forgot hint |
| Onboarding | 480 | three sections + finish (scroll if needed) |
| Pairing | 400 | instructions, QR tile 216×216 (`#FFFFFF`, padding 12, `r8` — QR needs a light quiet zone), countdown `small`, warnings |
| Change password | 400 | note, two fields, `[Hủy] [Primary]` (macOS) / `[Primary] [Hủy]` (Windows); done: message + Close |
| Confirm (short) | 400 | title + body |
| Confirm (long, `confirm.long`) | 520, max-height 80 % window, body scrolls | |

- Container: `surface`, `r12`, `e2`, padding 24, over `scrim`. Spacing: title → 8 → body/fields (fields 16 apart) → 24 → actions.
- **Height follows the content** (final wave M-2): only the width is fixed; max height = window − 48 (long confirm: 80 % of the window). When the content is taller, the body scrolls with its scrollbar shown while the title stays and the actions (confirm, change password, onboarding) stay **pinned** under a 1 px `line` (shown only while the body overflows), so the primary action is always on screen even at 640×400. No `Spacer`s.
- Header: `dialogTitle` `textTitle`, left-aligned. **macOS:** no close button (Esc / Cancel). **Windows:** 28×28 close icon button right inset 12, vertically centred on the 22 px title line (top = 24 + (22 − 28) / 2 = 21, final wave P-3), tooltip "Đóng"; the title keeps 44 px clear of it.
- Actions row, right-aligned, 8 px gap. **macOS:** `[Hủy] [Primary]` (primary rightmost, default). **Windows:** `[Primary] [Hủy]`. Destructive confirms use the destructive style for the action and initial focus on Cancel. Form dialogs without Cancel (login when forced) show only primary.
- Esc = cancel/close (current `CallbackShortcuts` moves into each dialog). Enter submits forms.
- Scrim click: closes informational dialogs (pairing, change-password done); ignored for forms and confirms.

---

## 5. Copy (vi + en, ARB keys)

Tone (same as mobile): plain, short, second person, no blame, verbs on actions, "terminal"/"tab"/"shell" kept in English inside Vietnamese text. Desktop says **tab** for a window entry, **phiên** only when talking about the session limit (shared with the phone). Ellipsis "…" only when an action opens another step.

| Key | vi | en |
|---|---|---|
| `trayOpenTerminal` | Mở cửa sổ terminal | Open terminal window |
| `terminalNewTab` | Tab mới | New tab |
| `terminalNewTabTooltip` | Tab mới  {shortcut} | New tab  {shortcut} |
| `terminalCloseTab` | Đóng tab | Close tab |
| `terminalDefaultTitle` | {shell} {index} | {shell} {index} |
| `windowTitle` | {title} — ShellX | {title} — ShellX |
| `terminalExitedLine` | [Tiến trình đã thoát, mã {code}] — Enter để đóng | [Process exited with code {code}] — press Enter to close |
| `terminalDriverPhone` | Điện thoại đang dùng terminal này — gõ để dùng lại | Your phone is using this terminal — type to take it back |
| `terminalSignedOutStrip` | Đăng nhập để dùng từ điện thoại | Sign in to use this computer from your phone |
| `terminalSignedOutAction` | Đăng nhập… | Sign in… |
| `terminalEmptyTitle` | Không có tab nào đang mở | No tabs open |
| `terminalEmptyBody` | Mở tab để chạy một shell mới. Phiên bạn mở từ điện thoại cũng hiện ở đây. | Open a tab to start a new shell. Sessions you open from your phone show up here too. |
| `terminalEmptyAction` | Mở tab mới | Open new tab |
| `terminalSessionLimit` | Đã mở tối đa {max} phiên. Đóng bớt tab để mở tab mới. | You've reached the limit of {max} sessions. Close a tab to open a new one. |
| `terminalSpawnFailed` | Không mở được shell: {reason, select, notFound{không tìm thấy shell} denied{không có quyền chạy shell} other{lỗi hệ thống}}. Hãy thử lại. | Couldn't start the shell: {reason, select, notFound{shell not found} denied{permission denied} other{system error}}. Try again. |
| `toastDismiss` | Đóng thông báo | Dismiss |
| `confirmCloseRunningTitle` | Đóng “{title}”? | Close “{title}”? |
| `confirmCloseRunningBody` | Lệnh đang chạy trong tab này sẽ bị dừng. | The command running in this tab will be stopped. |
| `confirmCloseRunningAction` | Đóng tab | Close tab |
| `sidebarLabel` | Danh sách tab | Tabs |
| `sidebarStatusIdle` | đang chờ lệnh | idle |
| `sidebarStatusRunning` | đang chạy lệnh | running a command |
| `sidebarStatusExited` | đã thoát, mã {code} | exited with code {code} |
| `sidebarPhoneOrigin` | Mở từ điện thoại | Opened from your phone |
| `sidebarPhoneViewing` | Điện thoại đang xem | Your phone is viewing |
| `sidebarPhoneDriving` | Điện thoại đang dùng | Your phone is using it |
| `sidebarPosition` | tab {index} trên {count} | tab {index} of {count} |
| `terminalPaneLabel` | Terminal {title} | Terminal {title} |
| `terminalCloseTabTooltip` | Đóng tab  {shortcut} | Close tab  {shortcut} |
| `terminalDriverPhoneShort` | Điện thoại đang dùng — gõ để dùng lại | Phone in control — type to take over |
| `terminalCopy` / `terminalPaste` / `terminalSelectAll` | Sao chép / Dán / Chọn tất cả | Copy / Paste / Select all |
| `confirmCloseAllTitle` | Đóng tất cả {count} tab? | Close all {count} tabs? (1: Close 1 tab?) |
| `confirmCloseAllBody` | Mọi shell trong các tab này sẽ bị dừng, kể cả lệnh đang chạy. | Every shell in these tabs will be stopped, with any command still running. |
| `confirmCloseAllAction` | Đóng tất cả | Close all |

Semantics use the lower-case variants of origin/viewing ("mở từ điện thoại"; en "opened from your phone") — add `…Semantics` keys if the translator needs separate casing.

**Existing strings that D7 makes wrong (update in A1):**

| Key | vi (new) | en (new) |
|---|---|---|
| `confirmSignOutBody` | Điện thoại đang kết nối sẽ bị ngắt và mọi điện thoại đã ghép sẽ bị gỡ. Các tab terminal trên máy này vẫn chạy. Sau khi đăng nhập lại, bạn phải ghép nối lại điện thoại. | Connected phones will be disconnected and every paired phone will be removed. Terminal tabs on this computer keep running. After signing in again you must pair your phones again. |
| `confirmRemoteOffBody` | Điện thoại đang kết nối sẽ bị ngắt. Các tab terminal trên máy này vẫn chạy. | Connected phones will be disconnected. Terminal tabs on this computer keep running. |
| `onboardingTrayHint` | "Terminal của bạn ở cửa sổ ShellX. ShellX cũng có mặt trên thanh menu (khay hệ thống): chọn “Ghép nối điện thoại…” ở đó để kết nối điện thoại." | "Your terminal is in the ShellX window. ShellX also stays in the menu bar (system tray): choose “Pair phone…” there to connect your phone." (final wave: no double "lives") |
| `confirmQuitBody` | "{count} tab đang mở sẽ bị đóng. Điện thoại không kết nối được máy này cho tới khi ShellX chạy lại." | "{count} open tabs will be closed. …" (final wave: the desktop says tab) |
| `authForgotPasswordHint` | "Quên mật khẩu? Trên một máy tính khác vẫn đang đăng nhập ShellX, chọn “Đổi mật khẩu…” trong menu khay." | "Forgot your password? On another computer that is still signed in to ShellX, choose “Change password…” in the tray menu." (final wave P-5) |

`confirmQuitBody` keeps its meaning (quit still closes every shell) but counts tabs. Tray "Đóng" on one session follows ⌘W (D15 confirm while a command runs); tray "Đóng tất cả" always asks with the count (final wave I2). Shortcut labels are built from the platform (`⌘T` / `Ctrl+Shift+T`), not translated.

**Tray:** "Mở cửa sổ terminal" / "Open terminal window" is the first item, followed by a separator, then the existing status line and items (sentence case, matching current tray strings such as "Pair phone…"). The macOS app menu (shown while the Dock icon is visible, D10) uses the system Quit item wired to the Dart quit flow.

---

## 6. Wireframes

### 6.1 Main window, 4 tabs (macOS) — tab 1 selected; tab 2 phone-viewing; tab 3 phone-origin; tab 4 exited non-zero

```
┌────────────────────────┬─────────────────────────────────────────────────────────┐
│ ● ● ●              [+] │                        zsh 1                            │
│                        │                                                         │
│▌● zsh 1                │ richard@mbp ~ % git status                              │
│ ● claude           👁  │ On branch main                                          │
│ ● htop          📱     │ nothing to commit, working tree clean                   │
│ ○ build                │ richard@mbp ~ % █                                       │
│                        │                                                         │
│                        │                                                         │
│                        │                                                         │
│                        │                                                         │
└────────────────────────┴─────────────────────────────────────────────────────────┘
 ▌ = 2px accent bar + rowSelected   ● green idle / ● cyan running   ○ red ring = exited
 📱 = Icons.phone_iphone_outlined (textSecondary)   👁 = Icons.visibility (accent)
```

Tab 4 selected shows the exit line in the buffer:

```
│ ○ build  (selected)    │ error: build failed                                     │
│                        │ [Tiến trình đã thoát, mã 2] — Enter để đóng             │
```

### 6.2 Phone driving (tab 2 selected)

```
┌────────────────────────┬─────────────────────────────────────────────────────────┐
│ ● ● ●              [+] │                        claude                           │
│                        │  > Thinking…  ╭───────────────────────────────────────╮ │
│ ● zsh 1                │               │ ▯ Điện thoại đang dùng terminal này —… │ │
│▌◉ claude       👁   ×  │               ╰───────────────────────────────────────╯ │
│ ● htop          📱     │   (content at the phone's width)                        │
│ ○ build                │                                                         │
└────────────────────────┴─────────────────────────────────────────────────────────┘
 pill: top right (bottom right while the cursor is under it), warnBg, warnBorder,
 warn text; 👁 turns warn while the phone drives; ◉ = running (target dot)
```

### 6.3 Signed out

```
┌────────────────────────┬─────────────────────────────────────────────────────────┐
│ ● ● ●              [+] │                        zsh 1                            │
│                        ├─────────────────────────────────────────────────────────┤
│▌● zsh 1                │ ☁̸ Đăng nhập để dùng từ điện thoại            Đăng nhập… │
│                        ├─────────────────────────────────────────────────────────┤
│                        │ richard@mbp ~ % █                                       │
└────────────────────────┴─────────────────────────────────────────────────────────┘
```

### 6.4 Empty state

```
┌────────────────────────┬─────────────────────────────────────────────────────────┐
│ ● ● ●              [+] │                         ShellX                          │
│                        │                                                         │
│                        │                          >_                             │
│                        │                Không có tab nào đang mở                 │
│                        │       Mở tab để chạy một shell mới. Phiên bạn mở        │
│                        │          từ điện thoại cũng hiện ở đây.                 │
│                        │                    [ Mở tab mới ]                       │
│                        │                          ⌘T                             │
└────────────────────────┴─────────────────────────────────────────────────────────┘
```

### 6.5 Dialog over the window (confirm close, macOS) + toast

```
┌────────────────────────┬─────────────────────────────────────────────────────────┐
│░░░░░░░░░░░░░░░░░░░░░░░░│░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│
│░░░░░░░░░░░░░░░░░░░╭──────────────────────────────────────╮░░░░░░░░░░░░░░░░░░░░│
│░░░░░░░░░░░░░░░░░░░│ Đóng “claude”?                       │░░░░░░░░░░░░░░░░░░░░│
│░░░░░░░░░░░░░░░░░░░│ Lệnh đang chạy trong tab này sẽ      │░░░░░░░░░░░░░░░░░░░░│
│░░░░░░░░░░░░░░░░░░░│ bị dừng.                             │░░░░░░░░░░░░░░░░░░░░│
│░░░░░░░░░░░░░░░░░░░│                    [ Hủy ] [Đóng tab]│░░░░░░░░░░░░░░░░░░░░│
│░░░░░░░░░░░░░░░░░░░╰──────────────────────────────────────╯░░░░░░░░░░░░░░░░░░░░│
│░░░░░░░░░░░░░░░░░░░░░░░░│░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│
└────────────────────────┴─────────────────────────────────────────────────────────┘
 Dialog 400 wide, centred on the window. Windows: [Đóng tab] [Hủy] + ✕ at top-right.

 Toast (no dialog), bottom-centre of the pane:
 │            ╭──────────────────────────────────────────────────╮            │
 │            │ ⓘ Đã mở tối đa 32 phiên. Đóng bớt tab để mở tab mới. ✕ │       │
 │            ╰──────────────────────────────────────────────────╯   16px     │
```

---

## 7. Consistency with mobile

**Shared verbatim (same hex):** terminal palette `--t-*` and `TerminalColors.theme` (ANSI + bright), `title`, notice tokens, driver banner tokens, dark `--a-*` surface/border/text/primary/err family, scrim 60 %, JetBrains Mono for terminal, copy tone and terms ("phiên", "Đóng tab", "Hủy", "Đăng nhập…"), driver message pattern (mobile "Máy tính đang dùng terminal này" ↔ desktop "Điện thoại đang dùng terminal này").

**Deliberate desktop differences:** system UI font instead of Raleway (native density, Vietnamese diacritics render best in SF/Segoe at 13 px); smaller radii (6/12 vs 13–18) and 32 px controls (pointer, not touch); dark-only window.

**Follow-ups for mobile (do not change in A1):**
1. Move `TerminalColors` + spacing/radius tokens into a shared package (e.g. `packages/shellx_design`) so both apps import one source.
2. `--t-dim #6C8288` on `--t-chrome` is 4.3:1 — fails 4.5:1 for small text; use `#93A5A9` for text, keep dim for decoration.
3. Light `--a-primary #0097A8` with white text is 3.5:1 — fails for button labels under 18.66 px bold; darken to `#007785` (the doc's `--accent`) for filled buttons in light mode.
4. `errorSessionLimit` says 10 — the limit becomes 32 (D8); make it a `{max}` parameter fed from the server.
5. Show phone-origin / desktop-origin and the driver banner for shellx sessions too (spec §3.3, A2+), using the same pill tokens as desktop.
6. Adopt the desktop status-dot semantics (idle / running / exited ring) in the mobile tab strip for one vocabulary across devices.
