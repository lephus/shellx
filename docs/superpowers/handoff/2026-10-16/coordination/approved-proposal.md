# V2-5 — approved proposal (source of truth for the three specs)

Date: 2026-10-16. The user writes Vietnamese. Their request, verbatim:
> "giao diện update lại chế độ "AI Assiten" giống claude desktop app, cho chọn dự án để làm việc ; Cập nhật lại theme của app, font chữ, commponent bạn có thể tham khảo style app https://www.figma.com/design/QgQsGtshcpfstl001CslNB/Online-Bike-Shopping-App--Community-?node-id=1-4 ; tính năng ra lệnh-thảo luận với AI bằng giọng nói cần làm như GPT - mượt mà và dễ dùng; tên app (cả mobile và desktop) update lại là: "ShellX: Remote AI agents""

On the Figma source the user said: "dựa vào ảnh công khai của file figma". Use the public images only; do not ask for Figma access.

On the proposal the user said: **"làm theo khuyến nghị, Nhưng tên app nên để tên đầy đủ"**. Every recommendation below is approved. The app name is the full name wherever the system shows an app name, the phone home screen included.

Research (read what your spec needs; cite `file:line` from them where useful):
- `SCRATCH/v25-research/design-system-and-naming.md`: themes, fonts, components, tests, and every place the name appears, with what a rename can break.
- `SCRATCH/v25-research/ai-ui-current.md`: the desktop and phone AI UI today; the project and workspace data.
- `SCRATCH/v25-research/voice-current.md`: voice on v2-2b and what is missing for a ChatGPT-style mode.
- `SCRATCH/v25-research/references.md`: the Claude desktop UI, ChatGPT voice principles, Flutter voice options, and the Bike app's style tokens.
- Bike artwork, for viewing only: `SCRATCH/dl-bike-figma-dribbble/{figma_cover,dribbble_1,dribbble_2}.png`.

`SCRATCH` = `/private/tmp/claude-501/-Users-richard-Documents-helper-shellx/c68aea52-eaaf-4b45-9a7d-989a8fedf901/scratchpad`.

## Ordering and branches
- V2-5 starts after V2-2b, V2-3 and V2-4 are merged into `shellx-v2`. Specs are written now; code comes later.
- Order of work: A first, because it touches every screen. Then B. Then C, which touches the same mobile AI page as B. The plans decide whether C's non-overlapping parts can run beside B.
- V2-5 never goes to `main` until the user says so. A push to `main` releases the desktop app.

## A — App name and the new design system (spec: `2026-10-16-v2-5a-name-and-design-system-design.md`)

### A.1 Name: "ShellX: Remote AI agents"
- Every **display** name becomes the full name "ShellX: Remote AI agents". This covers:
  - iOS `CFBundleDisplayName`, i.e. the home-screen label. The user accepts that the system truncates it.
  - The Android launcher label.
  - Android Recents / `MaterialApp` title.
  - The desktop window title when no tab gives one. With a tab, keep the short form "{tab} — ShellX".
  - The tray tooltip.
  - The in-app title on the splash/login/onboarding screens.
  - The mobile Settings version line.
  - The Windows `FileDescription`.
  - The Windows uninstall display name: Inno `UninstallDisplayName`/`AppName` text. These are display only; `AppId` stays and shortcut file names stay.
  - The macOS display name: decide `CFBundleDisplayName` only if it changes no identity. Add a manual check.
- Every **identity** stays "ShellX". That covers:
  - `ShellX.app` and `ShellX.exe`;
  - `PRODUCT_NAME`, `BINARY_NAME`, Windows `ProductName`/`CompanyName`;
  - bundle ids `pro.shellx.desktop` and `com.shellx.prod`;
  - the `local_notifier`/`launch_at_startup` `appName`;
  - Start-menu/desktop shortcut file names;
  - app-data folders;
  - shell-profile markers;
  - installer/dmg file names;
  - `shellx://`, and the `shellx` CLI and helper names.

  Why: a colon is illegal in Windows file names. Changing identities moves the Windows app-data folder, which loses sign-in, device key and trusted phones. It also breaks the release workflow, the installer and the background service (see design-system-and-naming.md §6.3).
- Sentences keep the short word ("Đăng nhập ShellX", "Quit ShellX?").
- Store listings (App Store Connect, Play Console) are edited in the consoles, outside the repo. The spec lists them as a step for the user.
- The website (`web/**`) deploys to production from `main` and needs the user's consent. List website changes as a follow-up; do not include them.
- `release/windows/shellx.iss` and the release workflow belong to a teammate's pipeline on `main`. Change only display strings there, and flag it for the user.

### A.2 Design system (style of the "Online Bike Shopping App" Figma Community file, from public images)
- **Shared tokens** go in a new package `packages/shellx_design`, used by both apps. It holds colours, gradients, radii, spacing, shadows, the type scale and motion. The desktop's existing `static const` token classes stay as the API with new values, so call sites do not churn. Mobile's `AppColors`/`AppTypography` take the new values.
- **Dark palette** from the reference:
  - page `#222834`; surfaces `#242C3B` / `#2C3547` / `#323B4F`;
  - inset `#1C222E`;
  - hairline borders white 8–10%;
  - text white 100% / 87% / 60%;
  - accent gradient `#34C8E8 → #4E4AF2` (top-left to bottom-right);
  - link/price azure `#3D9CEA`;
  - status colours (ok, warn, error) re-tuned for navy.
- **Contrast fix:** white text on the gradient's cyan end is only about 2:1. Deepen the light stop until every point behind bold labels of 15 px or more reaches at least 3:1 (WCAG large text), and body text at least 4.5:1. Pin this with contrast tests, as `design_tokens_test.dart` does today.
- **Font:** **Be Vietnam Pro** for the UI on both apps, bundled under OFL, never fetched at runtime. **JetBrains Mono** stays for terminal and code. Poppins has no Vietnamese, so it is excluded.
  - The desktop today uses the platform font on purpose, for Vietnamese at 13 px. The spec must cover legibility at 11–13 px, keep row heights and the 220 px sidebar, and name a fallback (Inter) if a manual check fails.
  - Mobile replaces Raleway.
- **Shapes:** radius 10 for buttons, chips and icon buttons; 16 for cards and fields; 28 for sheets and big panels; pills for tags.
- **Neumorphism:** subtle. A raised element gets a dark shadow at bottom-right and a light one at top-left on the same navy. Inset is used for fields and tracks.
- **Glass (blur) and the diagonal blue wedge** are used sparingly, never behind the terminal or long text. Allowed places:
  - empty states, including the AI home greeting;
  - login and onboarding;
  - the voice screen;
  - the AI composer card.
- **Components** (both apps):
  - a gradient primary button and a raised secondary button;
  - a rounded-square icon button, filled with the gradient when active;
  - chips and segmented controls with a gradient active state;
  - inset text fields;
  - cards;
  - bottom sheets;
  - dialogs;
  - toasts (fix today's white-in-dark-mode toasts);
  - menus;
  - the mobile bottom bar from B.
- **Modes:** the desktop stays dark only. The phone keeps light, dark and system modes, with a light variant derived from the same palette; dark is the default for new installs.
- **Terminal:** the default "ShellX" terminal palette's background moves to the navy family. ANSI colours stay readable. User terminal themes are untouched.
- **Icons** stay Material, using rounded variants where they exist. The app icon is not part of this work.
- **Tests:** there are no image goldens. Update the exact-value token tests, the contrast tests and any geometry tests that change. Add tests for new tokens and components.
- **Attribution:** the reference file is CC BY 4.0. We take style only (colours, shapes), no assets. Add an attribution line in the licences/credits page anyway (cheap).

## B — "Trợ lý AI" like the Claude desktop app, with a project picker (spec: `2026-10-16-v2-5b-ai-assistant-design.md`)
- **Feature name:** "Giao diện AI" / "AI interface" becomes **"Trợ lý AI" / "AI Assistant"**. "Phiên AI" / "AI session" stays for a session. Product naming: "Claude", never "Claude Code".
- **Desktop:**
  - The sidebar gets a segmented switch **Terminal | Trợ lý AI**. In AI mode the sidebar shows:
    - "+ Phiên mới";
    - **Dự án** (projects = workspaces with a folder); each one expands to its AI sessions, both open and from history (the agent's `session/list {cwd}`);
    - "Gần đây";
    - a status filter: running / needs you / done.
  - Terminal tabs stay in Terminal mode.
  - **AI home** (no session selected): a greeting plus the reference's wedge or glass accent, and a **centred composer card**. Under it, chips: **📁 Dự án ▾ · agent (Claude ▾) · Chế độ ▾ · Model ▾ · 🎙**. The first message creates the session with the chosen project, agent, mode and model. This replaces today's "open a tab at once with the default agent".
  - **Project picker:**
    - search;
    - projects with name, path and git branch;
    - **recent folders** (new persisted list);
    - **"Mở thư mục…"**: the OS folder dialog through a pinned `file_selector` plugin. This reverses V2-1 ruling B7; record that in the spec.
    - "Lưu thành dự án" (creates a workspace with that root).
  - A per-session **agent picker** (today it exists only in Settings).
  - **Session view:**
    - the header shows project, branch, agent and status;
    - the user's messages sit in a bubble and the agent's text is full width;
    - tool calls are collapsed into compact cards;
    - thinking is folded;
    - the existing side panel (Changes / Files / Terminal) stays;
    - the composer card is the same as on the home screen.
- **Phone:**
  - A **bottom bar Máy tính / Trợ lý AI / Cài đặt** in the reference's style: the active item is a raised gradient tile.
  - The "Trợ lý AI" tab works on the selected computer (a machine chip at the top). It shows projects (the desktop's workspaces with roots plus recent AI folders), then a project's sessions (open and history), then a new session in composer-first style (type first; project and agent as chips).
  - The conversation is restyled like the desktop's.
  - **The phone never browses arbitrary folders** (V2-2 D9 stays): it picks only keys the desktop offers.
  - Protocol additions (recent folders, per-project listing) follow V2-2's rules:
    - capability flags;
    - old phones and old desktops keep working;
    - decoding never drops the channel;
    - `toString()` is `Name(…)`;
    - no content in logs.

## C — Voice conversation like ChatGPT, phone first (spec: `2026-10-16-v2-5c-voice-conversation-design.md`)
- **Entry:** a waveform button in the AI composer starts **voice mode inside the thread**. It is an in-thread bar with an animated orb or waveform, driven by mic level and TTS level. An optional full-screen "orb" view exists. Every voice turn is written into the same conversation.
- **Hands-free turns:**
  - End of speech is detected from silence, about 700 ms after the last speech, with a longer grace after filler. The utterance is then **sent automatically**; no "gửi" keyword is needed in voice mode. The dictation keyword stays for the composer's mic.
  - While the agent works, the state is shown as "đang làm…" with a short cue.
  - When the turn ends, **TTS reads the agent's reply**, prose only:
    - code blocks, diffs and tool output are skipped and summarised ("kèm 2 khối code");
    - a long answer is read to the end of its first part, then the app asks "đọc tiếp?".
  - Listening re-arms automatically after the reply.
- **Interrupt:** a tap on the orb stops TTS and listens. Speaking over the reply (barge-in) is phase 2, with headphones first.
- **Captions and controls:** live captions for both sides; Mute; End.
- **Language:** Vietnamese and English, switchable inside voice mode, with a default in Settings.
- **Permissions and questions:** voice mode reads "Claude cần bạn cho phép: …" aloud and shows big Allow/Deny buttons. **Only a tap answers. A voice answer to a permission is never possible.** This keeps the binding rule "no path in which a phone answers without a user tap" and V2-2b D13.
- **Engine, phase 1 (this spec):** the platform speech recogniser (Apple/Google, as today's dictation) plus platform TTS.
  - Own state machine: listen → send → wait → speak → listen.
  - Endpointing from audio levels.
  - Seamless restarts across the iOS ~1 min cap.
  - The Android start beep is a known phase-1 cost.
  - Half-duplex: the mic is closed while TTS plays.
  - One owner of the audio session.
  - Voice mode stops when the app leaves the foreground; no background audio in phase 1.
- **Phase 2 is out of scope for this spec**, listed as a follow-up: the on-device sherpa-onnx pack (~100–200 MB download), barge-in with echo cancellation, and no beeps. **Cloud realtime is not used.**
- **Desktop voice is later**, out of scope.
- **Privacy:** the privacy page must now say the microphone serves AI voice mode and that replies are read aloud on the device. That page is in `web/**`, so it is a follow-up needing deploy consent. In-app permission strings are updated.

## Binding rules from earlier work (apply to every spec)
- ShellX never reads, stores or relays credentials. Never `--hide-claude-auth`. No `SHELLX_*` variable in an agent's environment.
- Never auto-allow a permission request. Never re-apply a remembered no-approval mode. No path in which a phone answers without a user tap.
- No content in logs. `toString()` of new messages and records is `Name(…)`, pinned by tests.
- Product naming: "Claude" or "Claude Agent", never "Claude Code", in feature names and UI strings.
- Strings come in English and Vietnamese, word for word, in the spec.

## Spec format (follow the existing V2 specs)
- Model: `docs/superpowers/specs/2026-10-15-v2-4-tools-phone-design.md` and `2026-10-15-v2-2b-phone-ai-more-design.md`.
- Written in Vietnamese, like those.
- Contents:
  - a numbered decision table whose columns include "Giá nếu sai";
  - what stays out;
  - the data flow, plus the protocol where relevant;
  - a strings table (EN, VI);
  - the test plan;
  - Review Focus, the five most likely failures;
  - "⚠ Kiểm tay", the manual checks on devices;
  - risks;
  - follow-ups;
  - the open items that are the user's to decide. These should be few; the recommendations are already approved.

## UPDATE 2026-10-16 11:25: the user changed two A decisions (binding; overrides A.2's font and icon lines)
The user's words: "tôi muốn bạn sử dụng font chữ SF Mono cho mobile và desktop app ; icon trong app thì dùng cupertino".

- **Font: SF Mono is the app font on mobile and desktop.** It covers the UI chrome, the terminal default and code. Be Vietnam Pro and Raleway are dropped. The user's own terminal `font-family` setting still overrides.
  - **Licence constraint.** Apple's SF fonts may not be bundled or redistributed, and may not be used outside Apple platforms. The spec must verify the current licence text (developer.apple.com/fonts) and state it. Consequences:
    - **iOS and macOS:** use the system's own SF Mono through the OS. It is never bundled. Approach: a small native method gets the system monospaced font (`UIFont`/`NSFont.monospacedSystemFont`). Then either:
      - read its file URL (`kCTFontURLAttribute`) and load the bytes, or
      - rebuild the sfnt from `CTFontCopyTable`.
      Load the result into Flutter with `FontLoader('SF Mono')`. Use font variations or weights as needed. Fallback: Menlo, a public Apple system font, if loading fails. This needs a spike task first, with a pass/fail check on a device and a simulator.
    - **Android and Windows:** SF Mono cannot ship. Use the closest free stand-in with full Vietnamese coverage. Default: **JetBrains Mono**, already bundled in both apps, with Vietnamese verified. The spec may pick a closer OFL lookalike only if its Vietnamese coverage is verified from the font file; record the choice.
  - **Vietnamese:** verify SF Mono's coverage of the Vietnamese letters (U+1EA0–1EF9, ơ, ư, đ) from the system font file on this Mac, using a read-only cmap parse. Do the same for the stand-in.
  - **Layout:** a monospaced UI font is wider. Re-check the 220 px sidebar, rows, chips, buttons, dialogs and the mobile bottom bar. Adjust the type scale (sizes may drop by about 1 px) and state the new scale.
- **Icons: Cupertino icons in both apps.** Use `CupertinoIcons` from the `cupertino_icons` package, with an exact version pin, in place of Material `Icons.*`.
  - One central mapping, e.g. `ShellxIcons` in `packages/shellx_design`, so call sites name roles, not glyphs.
  - Every current icon use gets a Cupertino glyph.
  - Where Cupertino has no fitting glyph, the spec names the fallback for each case: a small custom SVG, or that one Material glyph, listed explicitly.
  - Tray icons and the app icon are not affected.
