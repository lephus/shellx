# V2.5 reference research

Research date: 2026-10-16. Web research only; no repository was changed. Downloads, scripts and sampled images live in the session scratchpad, not in the repo.

Topics: (1) Claude desktop app UI, (2) ChatGPT voice mode, (3) Flutter voice stack for Vietnamese + English, (4) the "Online Bike Shopping App" Figma community file.

## TL;DR (ten findings that matter most)

1. **Claude desktop is mid-merge.** It has three top-centre tabs (Chat, Cowork, Code). Since Aug-Oct 2026 Chat and Cowork are merging into one "home composer" (Unified Claude, beta, `desktopHome`); Code stays separate. The Code tab asks for four things before the first message: environment (Local / Cloud / SSH / WSL), project folder or repo, model, permission mode.
2. **Sessions are grouped per project in the sidebar** (filter by status / project / environment, "group by project", archive on hover, auto-archive when the PR merges). Worktrees are a toggle next to the branch name.
3. **Claude's published palette is small and warm:** ink `#141413`, ivory `#FAF9F5`, grays `#B0AEA5` / `#E8E6DC`, accents orange `#D97757`, blue `#6A9BCC`, green `#788C5D` (official brand skill). The in-app fonts (Anthropic Serif / Sans / Mono) are proprietary. Free stand-ins that also cover Vietnamese: Source Serif 4, Newsreader, Lora, Literata, Fraunces (serif); Inter, Be Vietnam Pro, Plus Jakarta Sans (sans).
4. **ChatGPT voice moved into the chat thread on 2025-11-25** (live transcript, visuals, type any time; the orb screen survives as "Separate mode"). On 2026-07-08 **GPT-Live** became the default: a full-duplex model with no separate turn detector. OpenAI's headline latency claim for GPT-4o voice is 232 ms best / 320 ms average, versus 2.8 s / 5.4 s for the old three-model pipeline.
5. **`speech_to_text` is a short-utterance tool, not a conversation engine.** iOS stops recognition tasks after about one minute (Apple docs), Android forces a 1-3 s pause timeout and ~10 s limits, and the plugin sets the iOS audio session to `.playAndRecord` + `.default` mode, which gives **no echo cancellation**.
6. **iOS `.voiceChat` mode alone does not cancel echo** (Apple docs). You need the Voice Processing I/O unit or `AVAudioEngine.inputNode.setVoiceProcessingEnabled(true)` (iOS 13+/macOS 10.15+). Android's `AcousticEchoCanceler` is device-dependent. Barge-in therefore needs a gate and a fallback (headphones / tap to interrupt).
7. **Vietnamese on-device STT is the weak spot of platform APIs.** A 2022 test on iOS 15.4.1 found 22 on-device locales and Vietnamese was not one of them; Apple's current (iOS 27) availability page lists Vietnamese for on-device dictation, but no source says which iOS release added it. For Android the on-device recognizer API exists from API 31, but I could not verify Vietnamese on the platform recognizer.
8. **sherpa-onnx is the one Flutter dependency I found that covers VAD + ASR + TTS on all four of your targets** (iOS 13+ pod, Android arm64/armeabi/x86/x86_64, macOS, Windows). It ships Vietnamese offline Zipformer ASR models (26-68 MB int8 encoders), Vietnamese Piper voices and Supertonic 3 (31 languages incl. Vietnamese). No official streaming Vietnamese model; no published phone latency for the Vietnamese models (a third-party benchmark of other small sherpa models on a 2019 Galaxy S10 shows RTF 0.05-0.12).
9. **Cloud realtime is the smoothness ceiling but not private.** OpenAI GPT-Live is $0.05/min (billed per second, backend extra); Gemini Live lists Vietnamese and costs about $0.005/min in plus $0.018/min out (audio); Azure real-time STT stores nothing at rest. All need server-side key minting.
10. **Online Bike Shopping App** = dark navy neumorphism + frosted glass + a diagonal blue "wedge", Poppins type, cyan-to-indigo gradient buttons. Palette, radii and shadow values below come from a public Flutter port of the same design and from pixel sampling of the published artwork. **Poppins has no Vietnamese coverage** (I checked the font file: `ơ`, `ư` and 84 of 90 letters in U+1EA0-1EF9 are missing).

---

## 0. Method, confidence tags, access limits

Tags used on claims:

- **[OFFICIAL]** the vendor's own docs, blog, source code or header (fetched, or quoted in a search excerpt of that page).
- **[3P]** third-party article, blog, forum, or a competitor's page. Treat as secondary.
- **[UNVERIFIED]** could not be confirmed from any source I could open.
- **[INFERENCE]** my own synthesis, not a sourced fact.

Access limits you should know about:

- `openai.com`, `help.openai.com`, `figma.com`, `medium.com`, several news sites and `developer.android.com` class pages returned HTTP 403 or only navigation chrome to a direct WebFetch. A public text proxy (`r.jina.ai`) did render `openai.com` and `help.openai.com` pages, the Figma Community page, a Medium article, TechRadar, Engadget and Google Cloud pricing pages; I used it for those public pages only, and deliberately **not** for your private Figma file (it would send the file key to a third party). `developer.android.com` class pages stayed unreadable even through the proxy, so for Android I used AOSP source (`android.googlesource.com`), the official API-diff pages and ML Kit docs.
- Apple docs were fetched through Apple's documentation data endpoint (`developer.apple.com/tutorials/data/documentation/...`), which returns the real page text.
- WebFetch answers come from a small summarising model. For numbers that matter I cross-checked against raw sources (raw GitHub files, AOSP, Apple endpoint) or measured them myself (pixel sampling of artwork, font cmap check).
- **The user's Figma link** (`QgQsGtshcpfstl001CslNB`) is a private copy; WebFetch returned only the word "Figma". I used the public Community page (read through a text-proxy), the Dribbble shots, the Community cover image, and a public Flutter port. See section 4.

---

## 1. Claude desktop app UI (macOS / Windows), 2025-2026

### 1.1 Timeline (what the UI is now)

| Date | Change | Source |
|---|---|---|
| 2026-01-12 | Cowork research preview in Claude Desktop (macOS, Max) | [OFFICIAL release notes](https://support.claude.com/en/articles/12138966-release-notes) |
| 2026-02-25 | New "Customize" section in the sidebar groups skills, plugins, connectors | same |
| 2026-04-09 | Cowork generally available on macOS and Windows | same |
| 2026-04-14 | Claude Code desktop redesign: new sidebar of active + recent sessions, drag-and-drop panes, terminal, file editor, diff viewer, preview, side chats, view modes, usage button, streaming | [OFFICIAL blog](https://claude.com/blog/claude-code-desktop-redesign) |
| 2026-07-07 | Default transcript + composer width changed to a narrower, more readable column (user width in Settings > Appearance preserved) | [OFFICIAL changelog v1.19367.0](https://claude.com/docs/cowork/changelog.md) |
| 2026-08-06 | Merged Chat + Cowork home is the default; "New" starts a chat or a task from one composer | changelog v1.26832.0 |
| 2026-09-16 | "Claude Cowork comes to every conversation": Chat and Cowork merge, gradual rollout | [release notes](https://support.claude.com/en/articles/12138966-release-notes) |
| 2026-09-29 | Code tab composer redesigned as a card; "+" menu first in the row under the box, then permission mode, then model | changelog v2.16120.0 |
| 2026-10-08 | `desktopHome` key adds Unified Claude (beta) | changelog v2.31226.0 |
| 2026-10-15 | "Get started with Claude Code" checklist removed from the sidebar | changelog v2.42304.0 |

Unified Claude [OFFICIAL; this page is written for the "Claude Desktop on 3P" deployment, meaning third-party model providers, but it describes the same home screen]: "users type into the message box on the home screen without first choosing between Chat and Cowork"; on a device that can run Cowork every home message starts a Cowork session; "Code stays separate"; earlier chats and tasks are listed together in the sidebar ([doc](https://claude.com/docs/third-party/claude-desktop/unified-claude.md)). In this report "[3P]" always means a third-party source, never that deployment. Before that merge the app had three tabs: Chat, Cowork, Code, "at the top center" ([quickstart](https://code.claude.com/docs/en/desktop-quickstart)).

### 1.2 Layout

#### Left sidebar

[OFFICIAL] from the [desktop docs](https://code.claude.com/docs/en/desktop) and the [changelog](https://claude.com/docs/cowork/changelog.md):

- **"+ New session"** at the top (Cmd/Ctrl+N). Ctrl+Tab / Ctrl+Shift+Tab (or Cmd+Shift+] / [) cycle sessions.
- **Filter and group controls at the top of the sidebar:** filter by status, project or environment; group by project.
- **Per-session actions:** archive icon on hover; rename by clicking the title in the toolbar; Cmd/Ctrl-click opens a second pane (split view); a "needs-input" marker exists on sessions; "Load more" on the All-sessions list; delete from sidebar/recents.
- **Pinned list** shows its first 20 items with a "Show more" link (v2.2553.0). Cmd/Ctrl+B toggles the sidebar (v2.9939.2).
- **Auto-archive** a session when its PR merges or closes ("it archives itself so the sidebar stays focused on what's live") ([blog](https://claude.com/blog/claude-code-desktop-redesign)).
- **Badges / indicators:** "Dispatch" badge for sessions started from the phone; a laptop icon before the session title shows Remote Control status.
- **Other entries:** Home, Projects (the "+" next to it creates a project), Recents (chats and tasks share it, [3P](https://www.weloveclaude.com/features/chat-composer)), Scheduled tasks (with a ⋮ menu), Artifacts, Customize.
- **Account menu in the lower-left corner; the sidebar open/close button is at the top right of the sidebar, and the sidebar cannot be disabled** ([OFFICIAL Help Center](https://support.claude.com/en/articles/8887527-customizing-your-appearance-settings), updated 2026-03-16).
- **Command palette** (first row "New chat" / "New session"; can archive/delete the current chat/project/task from it) (changelog v1.19367.0, v2.31226.0).
- **Window furniture (Code tab):** title-bar buttons Terminal, Changes, Browser; a ⋮ menu opens more panes (Files, Tasks); panes drag, resize and can pop out into their own window.
- [3P, 2026-07-20, A/B test] TestingCatalog reports Anthropic testing Projects in the desktop sidebar above recent conversations, with pin/sort controls, and the Chat/Cowork switcher moving from the prompt bar to the top of the window ([article](https://www.testingcatalog.com/anthropic-tests-new-placement-for-projects-on-claude-desktop/)).

#### Home / empty state

- [OFFICIAL] Home is one composer. App launch opens it on the last-used Chat or Cowork mode (changelog v1.52386.0). With Unified Claude there is no mode choice at all.
- **Greeting + centered composer is not documented by Anthropic anywhere I could open.** The only descriptions are community replicas: an orange sparkle/starburst next to a serif heading "How can I help you today?", a centered rounded composer with a thin border and no shadow, and small rounded chips "Write / Learn / Code / From Drive / From Calendar" ([3P clone](https://www.assistant-ui.com/examples/claude)). **[UNVERIFIED as first-party.]**

#### Composer

[OFFICIAL] Code-tab prompt area ([docs](https://code.claude.com/docs/en/desktop)):

- Before the first message you set: **Environment**, **Project folder**, **Model** (dropdown next to the send button), **Permission mode** (selector next to it; Cmd+Shift+M opens it).
- **"+" button:** Connectors, Plugins, Slash commands, file attachment. **@file** mentions (not in cloud/WSL sessions). Drag-and-drop for images, PDFs, files. `/` opens commands and skills.
- **Suggested prompt** shows as grey ghost text in an empty box; Tab or Right-arrow accepts.
- **Usage ring** next to the model picker shows context window and plan usage.
- **Enter sends; stop button interrupts immediately; typing a correction and pressing Enter queues it** for the next step.
- Redesigned card (v2.16120.0): "+" menu first in the row under the box, ahead of permission mode and model; effort is its own control beside the model name (v2.110.0); Cowork box has an extended-thinking switch beside effort (v2.9939.2).
- Queued messages "now wait in the conversation looking like sent messages, the first waiting message offers Send now" (v1.52386.0); queued messages can be reordered by drag (v1.18286.0).
- Dictation: a **chevron next to the composer's microphone button switches between dictation and voice mode** (v1.25927.0); **Esc ends voice mode** (v1.26832.0).
- Screenshot annotation in the composer (v1.24012.0); a document bar above the composer with live word count and copy button (v1.21459.0).

[3P, last verified 2026-09-13] "We Love Claude" lists the unified composer's "+" menu: Add files or photos, Skills, Connectors, Design system, Plugins, Research, Memory; desktop adds Add folder and Record a skill. Below the box: a "Project or folder" selector, a model-and-effort picker, and a permission control (Manual default / Auto) ([page](https://www.weloveclaude.com/features/chat-composer)).

#### How the conversation renders

- [OFFICIAL] **Transcript view modes**, cycled with Ctrl+O: Normal (tool calls collapsed, full text replies), Thinking, Verbose (every tool call, file read, thinking). The April blog called the three modes Verbose / Normal / Summary; the changelog says Summary was removed before v1.46388.1 ([docs](https://code.claude.com/docs/en/desktop), [changelog](https://claude.com/docs/cowork/changelog.md)).
- Responses **stream** as they are generated ([blog](https://claude.com/blog/claude-code-desktop-redesign)).
- **Diff stats chip** (for example `+12 -1`) appears when files change; click opens a diff viewer (file list left, changes right); click any line to comment; Cmd/Ctrl+Enter submits all comments.
- **Side chat** (Cmd+; or `/btw`) reads the main thread but writes nothing back.
- **Panes:** chat, diff, browser/preview, terminal, file, plan, tasks, subagent, iOS Simulator (macOS). Each can be dragged into a grid.
- In Chat: drafts open **in a panel beside the chat** and can be edited in place (2026-06-12 release note); mobile conversations can render live charts and diagrams (2026-03-25).
- Appearance: Color mode **Light / Match System / Dark**; Chat font **Default / Match System / Dyslexic Friendly** ([OFFICIAL Help Center](https://support.claude.com/en/articles/8887527-customizing-your-appearance-settings)).

#### Permission prompts for code actions

[OFFICIAL] ([docs](https://code.claude.com/docs/en/desktop), [quickstart](https://code.claude.com/docs/en/desktop-quickstart)):

- Five modes via the selector: **Manual** ("asks before editing files or running commands. You see a diff and can accept or reject each change"), **Accept edits**, **Plan** (proposes without editing), **Auto** (a background classifier reviews actions), **Bypass permissions** (no prompts, not in cloud sessions). Older versions called them Ask permissions / Auto accept edits / Plan mode.
- Manual mode shows "a diff view showing exactly what will change", **Accept / Reject buttons** per change, and live updates; rejecting makes Claude ask how to proceed.
- **Site cards:** the first time Claude acts on an external site, a card appears with **Allow once / Always allow / Deny**. **App access:** **Allow for this session / Deny**; tiers View only (browsers), Click only (terminals, IDEs), Full control.
- An **approval card appears before Claude archives a session** (not in Auto or Bypass).
- **Notifications:** OS notification when a session finishes and you are not viewing it; the phone gets a push when a Dispatch task finishes or needs approval.

### 1.3 Choosing the project, folder or repository

**Code tab (local or cloud)** [OFFICIAL, [quickstart](https://code.claude.com/docs/en/desktop-quickstart), [desktop docs](https://code.claude.com/docs/en/desktop)]

1. Open the **Code** tab.
2. In the environment dropdown pick **Local** (your files), **Cloud** (Anthropic-managed, keeps running when the app closes; "Add cloud environment"), **SSH > Add SSH connection...** (Name, SSH host, SSH port, optional key, Worktree folder) or, on Windows, a **WSL** distribution.
3. For Local, click **Select folder** and choose the project directory. For Cloud, select a repository; the **"+" next to the selected repository adds more repositories and each repo gets its own branch selector**.
4. **Worktree:** next to the branch name, select **worktree** to give the session an isolated Git worktree. Default location `<project-root>/.claude/worktrees/`; change it under Settings > Claude Code > "Worktree location"; a "Branch prefix" setting prepends to every worktree branch.
5. Session menu > **Open in > Cloud** continues a local session as a cloud session (conversation carried as a summary); **Open in > editor / file manager** opens the folder.

Recent additions from the changelog: a **"Choose folder"** option to recover a session whose folder is missing (v1.18286.0); admin-configured folders can appear as **ready chips** when users start a session (v1.14271.0).

More picker details from the desktop docs [OFFICIAL, [docs](https://code.claude.com/docs/en/desktop)]: a **`claude://code/new` deep link** opens the new-session page set for a given SSH host, port and folder (`ssh_host`, `ssh_port`, `ssh_folder`) with an optional prefilled prompt (`q`), and Desktop asks you to confirm before saving a new connection; administrators can push SSH connections that show up in each user's environment dropdown; typing `/resume` in the Desktop prompt box lists sessions started from the CLI on this computer, searchable by title, folder or branch, with a preview of where each left off; if the selected folder no longer exists the session fails to load and you pick another folder.

**Newer launcher** [3P, [AlphaSignal, 2026-10-14](https://alphasignal.ai/news/anthropic-s-claude-code-now-runs-nested-sessions-and-saves-dev-environments)]: the new-session screen "surfaces recent folders and lets you save environments combining folders, SSH hosts, or cloud targets", with an optional worktree per folder, and nested sub-sessions that report back to the parent. **[UNVERIFIED against Anthropic docs: the official desktop page does not mention recent folders or saved environments.]**

**Cowork projects** [OFFICIAL, [guide](https://claude.com/docs/cowork/guide/projects.md)]: a project holds description, folders, instructions, links, linked claude.ai projects and project memory; it lives on the computer only. Create with the "+" next to **Projects** in the left navigation: **Start from scratch / Import a project / Use an existing folder**. "Select a project in the sidebar to start a new Cowork session with that project's folders mounted and instructions applied." Archiving a project does not touch the folders.

**Claude Code Projects (beta)** [OFFICIAL, [doc](https://code.claude.com/docs/en/claude-projects)]: one ongoing conversation that starts a cloud-session thread per task, sharing repositories, instructions and memory. Appears as "Projects" in the sidebar of claude.ai/code and of the desktop Code tab; Pro/Max only, rolling out.

**How sessions are grouped per project** [OFFICIAL]: sidebar controls "filter sessions by status, project, or environment, and group them by project"; archive hides sessions from the default list (filter "archived" to see them) ([cloud doc](https://code.claude.com/docs/en/claude-code-on-the-web)).

**Phone side (relevant to a desktop+phone app)** [OFFICIAL, [Remote Control](https://code.claude.com/docs/en/remote-control)]: the phone lists sessions under the **Code** tab; Remote Control sessions show a **computer icon with a green status dot when online**; pairing by **QR code** (spacebar in the CLI) or session URL; the local process makes **outbound HTTPS only, never opens inbound ports**, registers with the API and polls; the server routes messages over a streaming connection; mobile push notifications; "trusted devices" list. Dispatch lets the phone start a task on the desktop.

### 1.4 Visual identity

#### Palette

| Role | Hex | Provenance |
|---|---|---|
| Orange, "primary accent" (the Claude clay) | `#D97757` | **[OFFICIAL]** Anthropic `brand-guidelines` skill: "Orange: #d97757 - Primary accent" ([SKILL.md](https://raw.githubusercontent.com/anthropics/skills/main/skills/brand-guidelines/SKILL.md)); also the coral in the app per [3P fudge.design](https://fudge.design/tokens/claude.ai) |
| Blue (secondary accent) | `#6A9BCC` | **[OFFICIAL]** same skill |
| Green (tertiary accent) | `#788C5D` | **[OFFICIAL]** same skill |
| Dark ink / dark background | `#141413` | **[OFFICIAL]** "Dark: Primary text and dark backgrounds" |
| Light / ivory background | `#FAF9F5` | **[OFFICIAL]** "Light: Light backgrounds and text on dark" |
| Mid gray | `#B0AEA5` | **[OFFICIAL]** "Secondary elements" |
| Light gray | `#E8E6DC` | **[OFFICIAL]** "Subtle backgrounds" |
| Deeper coral (pressed/hover) | `#C6613F` | [3P] fudge.design; shadcn.io "deep" ([page](https://www.shadcn.io/design/anthropic)) |
| Marketing terracotta | `#C96442` (older attribution `#C15F3C`) | [3P] computed styles of public routes ([oh-my-design.kr](https://oh-my-design.kr/design-systems/claude)); `#C15F3C` is attributed to the Geist-designed identity in a [Medium post](https://tao-hpu.medium.com/design-confidence-in-the-age-of-ai-ceca3dda8b9e) (search excerpt), not verified |
| Light canvas / hairlines on the public site | `#F5F4ED`, `#F0EEE6`, `#E3DACC`, border `#D1CFC5` | [3P] shadcn.io, oh-my-design.kr |
| Warm illustration accents | manilla `#EBDBBC`, kraft `#D4A27F`, fig `#C46686`, cactus `#BCD1CA`, heather `#CBCADB`, coral `#EBCECE` | [3P] shadcn.io (marketing sub-pages only) |
| Muted text | `#5E5D59`, `#87867F`, `#3D3D3A` | [3P] shadcn.io, oh-my-design.kr |
| Dark surfaces + text | `#0F0C08`, `#141413`; border `#30302E`; text `#FFFFFF`, `#F8F8F6` | [3P] fudge.design (route mix of login and in-app captures; not labelled measured vs inferred) |
| Action blue in app UI | `#2C84DB` (pressed `#256ABF`, soft `#74ABE2`) | [3P] fudge.design |
| Semantic | green `#4A7B00` / tint `#F2F8EA`; red `#B93535` / tint `#F8ECEC`; warning `#FFC130` | [3P] fudge.design |

**Dark-mode surface hexes for the chat app are not published.** Closest evidence: official dark `#141413`; fudge.design dark values above; a community clone uses `#2B2A27` (page), `#1F1E1B` (composer), `#3D3A35` (border) and is not authoritative ([3P](https://www.assistant-ui.com/examples/claude)). **[UNVERIFIED]** The Help Center confirms only the three color modes (Light, Match System, Dark).

Style rules reported by the extractions [3P]: "one dominant text color, one dominant action color, and the rest reserved for state changes"; flat surfaces, hairline cream borders, ring-style `0 0 0 1px` depth, "light or absent" shadows, no gradients. Radii: shells/major panels 2rem (32 px), smaller cards 1.75rem (28 px), pills fully rounded ([fudge.design](https://fudge.design/tokens/claude.ai)); public-site scale 6 / 8 / 12 / 16 / 24 / 32 px ([oh-my-design.kr](https://oh-my-design.kr/design-systems/claude)).

#### Fonts

- **In-app and site fonts are Anthropic Serif (display, and Claude's reply text by default), Anthropic Sans (controls, UI) and Anthropic Mono.** They are proprietary and not distributed; WOFF2 delivery is not a reuse licence ([3P oh-my-design.kr](https://oh-my-design.kr/design-systems/claude), [3P shadcn.io](https://www.shadcn.io/design/anthropic)). Type scale seen on the site: serif 60 px / weight 400 hero, 56 px / 290 section display, sans 16 px / 400 body, 12 px / 500 uppercase label with 0.08em tracking ([3P fudge.design](https://fudge.design/tokens/claude.ai)).
- Settings > Appearance offers Chat font Default / Match System / Dyslexic Friendly [OFFICIAL, no platform stated]; a [3P guide](https://www.itworkslocally.co.uk/blog/claudes-default-font-is-a-problem-heres-how-to-change-it) says the default is Anthropic Serif and that the native mobile app has no font option, and a closed [GitHub issue](https://github.com/anthropics/claude-code/issues/85636) says Claude Code's interface customization on desktop offers only Anthropic Sans and System.
- History: in 2024 the website used Styrene (Berton Hasebe) for headlines and Tiempos (Klim) for body ([3P type.today](https://type.today/en/journal/anthropic)).
- The official brand-guidelines skill uses freely available stand-ins: **Poppins for headings, Lora for body, with Arial / Georgia fallbacks** [OFFICIAL skill](https://raw.githubusercontent.com/anthropics/skills/main/skills/brand-guidelines/SKILL.md).

#### Free fonts with a similar feel, checked for Vietnamese

Vietnamese coverage taken from Google Fonts subset metadata via the [google-webfonts-helper API](https://gwfh.mranftl.com/api/fonts/lora) (one request per family):

| Family | Role | Has "vietnamese" subset |
|---|---|---|
| Source Serif 4 | Tiempos-like text serif | yes |
| Newsreader | editorial serif | yes |
| Lora | official brand-skill body font | yes |
| Literata | reading serif | yes |
| Fraunces | warmer display serif | yes |
| Crimson Pro | book serif | yes |
| Inter | generic UI sans (suggested stand-in for Anthropic Sans) | yes |
| Be Vietnam Pro | humanist sans designed for Vietnamese | yes |
| Plus Jakarta Sans, Lexend, Montserrat, Manrope | other sans options | yes |
| JetBrains Mono | mono (fudge.design lists it for token strings) | yes |
| **Poppins** | the brand skill's heading font and the Bike app's font | **no** |
| DM Sans | | no |

I verified Poppins directly: the Poppins TTFs bundled in the public bike port contain `á` and `đ` but not `ơ` or `ư`, and only 6 of the 90 letters in U+1EA0-U+1EF9 (so `ạ ả ấ ầ ẩ ẫ ậ ắ ... ự` fall back to another font). Source: [Poppins-Regular.ttf in the port](https://github.com/savykevin100/Online-Bike-Shopping-App/tree/HEAD/assets/fonts), cmap parsed locally.

#### Dark mode

Official: Light / Match System / Dark under Settings > Appearance ([Help Center](https://support.claude.com/en/articles/8887527-customizing-your-appearance-settings)). Developer docs for MCP apps mention "host style variables" for light/dark theming ([doc](https://claude.com/docs/connectors/building/mcp-apps/transparent-theming.md)). The dark values that appear anywhere (`#141413`, `#0F0C08`, `#30302E`, and the clone's `#2B2A27`) are all warm near-blacks, not blue-black [INFERENCE]. `#141413` is the only one Anthropic itself publishes as a dark colour. **[UNVERIFIED for exact app surfaces.]**

### 1.5 Concrete patterns to reproduce in Flutter (desktop + mobile)

Each item notes its basis. "Flutter" hints are mine [INFERENCE].

1. **One home composer for everything.** A single multi-line field on Home; the first message creates a chat/task/session; the app reopens on the last-used mode. *(changelog v1.26832.0, v1.52386.0).* Flutter: `Scaffold` home route with a `ConstrainedBox(maxWidth: ~720)` centred column.
2. **Composer as a card with a control row underneath:** "+" menu first, then project/folder chip, permission-mode chip, model + effort picker, usage ring, send/stop. Same control set on desktop and phone; collapse chips into a bottom sheet on phone. *(composer changelog entries).*
3. **Queued messages while a run is active:** show them as sent bubbles with a "Send now" action on the first; Esc / stop button interrupts; Enter during a run queues. *(docs + v1.52386.0).*
4. **Ghost-text suggested prompt** accepted with Tab / Right-arrow (desktop) or a tap (phone).
5. **`/` and `@` pickers** for commands/skills and files; drag-and-drop attachments; on phone use a "+" sheet.
6. **Sidebar with sections:** Home, Pinned (20 + "Show more"), Projects, Recents, Scheduled, Customize; hover actions (archive/rename); "needs input" marker; unread/finished OS notifications. On phone: a drawer with the same order.
7. **Filter/group header:** status, project, environment filters and a "group by project" toggle. *(docs).*
8. **Environment + folder + branch + worktree chips** shown before the first message. Local / Cloud / SSH are chips in one dropdown; a worktree toggle sits next to the branch name; cloud sessions can add repos with "+", each with its own branch selector. *(docs).*
9. **Project object** = folders + instructions + memory; "Start from scratch / Import / Use existing folder"; selecting a project in the sidebar starts a session already configured. *(Cowork guide).*
10. **Transcript view modes** Normal / Thinking / Verbose cycled by one shortcut; tool calls collapsed by default; streaming text. *(docs).*
11. **Narrow reading column with a user-adjustable width setting.** *(v1.19367.0).*
12. **Diff chip `+N -M` in the transcript header opens a diff pane; line comments sent with the next message (Cmd/Ctrl+Enter).** *(docs).*
13. **Manual-mode approval UX:** diff + Accept / Reject; site card Allow once / Always allow / Deny; app card Allow for this session / Deny; plan approval; a distinct "approval card" before destructive session actions. *(docs).*
14. **Side chat** (Cmd+;) that reads the thread but is ephemeral. *(docs).*
15. **Draggable pane grid** (chat, diff, terminal, preview, files) with pop-out windows; mobile shows one pane at a time with tabs. *(docs, blog).*
16. **Command palette** (New chat / New session / archive / delete). *(changelog).*
17. **Dictation vs voice mode switch on the mic button** (chevron), Esc ends voice mode. *(v1.25927.0, v1.26832.0).*
18. **Quick-entry global shortcut** that opens a compact always-on-top window (double-tap Option on Mac) ([Claude Academy lesson](https://academy.claude.com/courses/claude-101/claude-desktop-app-chat-cowork-code)), and a voice shortcut in Settings > Desktop app > General (changelog v2.2553.0).
19. **Phone as remote control for the desktop session:** session list with a "computer + green dot" online indicator, QR pairing, push notifications, outbound-only desktop connection. *(Remote Control doc).*
20. **Open in new window** for a single conversation beside the main window. *(v2.37337.1).*
21. **Warm paper theme:** ivory `#FAF9F5` / ink `#141413` / subtle fill `#E8E6DC` / hairline about `#D1CFC5` (3P), one accent `#D97757`, serif for reading text, sans for controls, rounded (16-32 px) shells, almost no shadows, flat 1 px borders. *(palette above).*
22. **Colour mode Light / Match System / Dark plus a Chat font option (Default / Match System / Dyslexic Friendly).** *(Help Center).* For Vietnamese pick fonts with the `vietnamese` subset.

### 1.6 Not verified (do not rely on these yet)

- The exact greeting copy and starburst on the empty state (only community clones).
- Exact dark-mode surface hexes of the chat app.
- Recent-folders list and saved multi-folder environments in the Code launcher (only a third-party report dated 2026-10-14).
- The unified composer's menu contents beyond the changelog (third-party page only).
- Whether "Anthropic Serif" is the default chat font on desktop today (third-party guide).


---

## 2. ChatGPT voice mode (Advanced Voice and GPT-Live, 2025-2026)

Sourcing note: openai.com and help.openai.com return 403 to WebFetch, but a text proxy (r.jina.ai) rendered them. Where a claim says [OFFICIAL] below it was read first-hand through that proxy unless it says "excerpt".

### 2.1 Timeline and modes

| Date | Event | Source |
|---|---|---|
| 2024-05 | GPT-4o: "It can respond to audio inputs in as little as 232 milliseconds, with an average of 320 milliseconds". Before: "latencies of 2.8 seconds (GPT-3.5) and 5.4 seconds (GPT-4) on average"; Voice Mode "is a pipeline of three separate models" and GPT-4 "loses a lot of information" ("can't directly observe tone, multiple speakers, or background noises") | [OFFICIAL Hello GPT-4o](https://openai.com/index/hello-gpt-4o/) |
| 2025-03 | Advanced Voice interrupts less; free users get pause tolerance | [3P PCWorld](https://www.pcworld.com/article/2649338/chatgpt-now-speaks-even-more-naturally-with-fewer-interruptions.html), [3P Tom's Guide](https://tomsguide.com/ai/chatgpts-advanced-voice-mode-just-got-a-free-upgrade-heres-whats-new) |
| 2025-11-25 | Voice moves **into the chat window**; orb screen kept as "Separate mode" | [3P TechCrunch](https://techcrunch.com/2025/11/25/chatgpts-voice-mode-is-no-longer-a-separate-interface/) (quotes OpenAI) |
| 2026-07-08 | **GPT-Live-1** (paid) and GPT-Live-1 mini (Free) launch; "GPT-Live-1 does not support video or screen sharing at this time" (Advanced keeps it) | [OFFICIAL release notes](https://help.openai.com/en/articles/6825453-chatgpt-release-notes) |
| 2026-07-23 | Voice available in Work and Codex in the ChatGPT desktop app | release notes |
| 2026-08-03 | OpenAI engineering post on GPT-Live's realtime system | [OFFICIAL post](https://openai.com/index/continuous-voice-interaction-with-gpt-live/) |
| 2026-08-07 | GPT-Live in Voice supports file uploads and Projects | release notes |
| 2026-08-31 | Live Activities show the voice conversation on the iPhone lock screen; "turn on Background conversations in Settings > Voice" | release notes |
| 2026-09-09 | Voice can call GPT-5.6 or GPT-6 Astra "when it needs to search or reason through harder questions"; limits simplified; the Instant / Medium / High intelligence levels deprecated | release notes |
| 2026-09-23 | Live supports plugins on web, iOS and Android; Voice also in Work | release notes |
| 2026-10-15 | GPT-Live-1.1 and GPT-Live-1.1 Quip, "more natural accents across languages", new voices | release notes |
| 2026-09 (day from [3P Emergent](https://emergent.sh/news/gpt-live-1-api-brings-natural-voice): 09-10) | `gpt-live-1` in the API at $0.05 per minute | [OFFICIAL API post](https://openai.com/index/introducing-gpt-live-1-in-the-api/), [model page](https://developers.openai.com/api/docs/models/gpt-live-1) |

Three modes, Settings > Voice ([OFFICIAL Help Center, Voice FAQ](https://help.openai.com/en/articles/8400625-voice-mode-faq)):

- **Live:** "designed for natural back-and-forth conversation"; runs on GPT-Live-1.1 or GPT-Live-1.1 Quip depending on plan; no video or screen sharing.
- **Advanced:** "The previous real-time Voice experience", used for video and screen sharing on supported mobile apps.
- **Standard:** "A turn-by-turn Voice experience that transcribes your speech before generating a response"; audio is deleted after transcription.

### 2.2 Entry point and the full-screen UI

- **Entry** [OFFICIAL Help Center]: iOS/Android, "Select the **Voice icon in the message bar**", allow microphone access, choose a voice on first use; web, select the Voice icon in the prompt window. **"Start with Voice"** makes a new or empty conversation open Voice automatically. Third parties describe the icon as a waveform at the far right of the text box ([3P Engadget](https://www.engadget.com/2230975/how-to-use-chatgpt-voice-mode/)); do not confuse it with the small Dictate microphone, which only types ([3P JustAINews](https://justainews.com/companies/openai/chatgpt-voice-mode-explained/)).
- **Old full-screen screen** (Advanced, 2024-2025): an animated blue circle, a mute button, an option to record live video, an X to return to text; replies were audio-only ([3P TechCrunch](https://techcrunch.com/2025/11/25/chatgpts-voice-mode-is-no-longer-a-separate-interface/)). An older Help Center excerpt put the **microphone (mute) icon at bottom-left and the exit icon at bottom-right**; Standard showed a black circle instead of the blue orb ([3P LearnPrompting](https://learnprompting.org/blog/how-to-use-openai-chatgpt-advanced-voice-mode), excerpt). Reviewers describe the orb as pulsing while the model listens and responds ([3P Toolchase](https://toolchase.com/blog/chatgpt-voice-mode-guide/), [3P TechRadar](https://www.techradar.com/ai-platforms-assistants/chatgpt/chatgpts-new-voice-integration-feels-like-the-missing-piece-in-ai-chat-ive-tried-it-and-its-almost-perfect): "floating orb that pulsed as it talked"). **No source documents distinct orb animations per state.**
- **In-chat voice (Nov 2025) and GPT-Live today.** OpenAI: "You can talk, watch answers appear, review earlier messages, and see visuals like images or maps in real time" and "You can now use ChatGPT Voice right inside chat - no separate mode needed" (quoted by [TechCrunch](https://techcrunch.com/2025/11/25/chatgpts-voice-mode-is-no-longer-a-separate-interface/)). Hands-on: "You just tap the Voice Mode button and start talking"; a live transcript runs in the chat; visual answers appear in the thread (weather as a table, maps as graphics); you tap **End** to stop ([3P TechRadar](https://www.techradar.com/ai-platforms-assistants/chatgpt/chatgpts-new-voice-integration-feels-like-the-missing-piece-in-ai-chat-ive-tried-it-and-its-almost-perfect)). With GPT-Live a "responsive floating orb" appears and you scroll down during the conversation to read a transcript ([3P Engadget](https://www.engadget.com/2230975/how-to-use-chatgpt-voice-mode/)). OpenAI adds **visual cards** (weather, stocks, sports) during voice ([OFFICIAL announcement](https://openai.com/index/introducing-gpt-live/)).
- **Controls** [OFFICIAL Help Center]: "select the microphone control to mute or unmute yourself"; "Select the exit control to end the Voice conversation"; with Live you can type instead of speaking or use the add button to attach an image; with Advanced there is a camera button and Share Screen in the more-options menu.
- **Separate mode** restores the orb screen: Settings > Voice > "Separate mode" ([TechCrunch](https://techcrunch.com/2025/11/25/chatgpts-voice-mode-is-no-longer-a-separate-interface/)).
- **Background and lock screen** [OFFICIAL]: conversations can continue while you use other apps or your phone is locked (control under Settings > Voice); Live Activities show the conversation on iPhone (release notes 2026-08-31).
- **Desktop:** Voice exists in Work and Codex in the ChatGPT desktop app since 2026-07-23, with separate pricing and limits ([release notes](https://help.openai.com/en/articles/6825453-chatgpt-release-notes), Help Center). An earlier third-party list saying GPT-Live was absent from the desktop app is out of date.

### 2.3 Automatic turn detection

- **Before GPT-Live** [OFFICIAL announcement]: the original Voice chained speech-to-text, an LLM and text-to-speech, so "information could be lost across models, and responses were slow and stilted"; Advanced Voice used one model but "still operated through discrete turns" with silence-based turn detection, so a brief pause or noise could cause unnatural interruptions.
- **GPT-Live** [OFFICIAL engineering post]: "removes the turn detector from the audio path" and "Its voice model is full-duplex, which means it can listen and speak at the same time." The model "can make interaction decisions many times per second": speak, keep listening, pause, interrupt, or invoke a tool [OFFICIAL announcement].
- **Pauses** [OFFICIAL announcement]: "If you take a moment to think, ChatGPT Voice now waits instead of jumping in and interrupting." **Backchannel:** short acknowledgments such as "mhmm" or "yeah". **Noise:** better at focusing on the user's voice when there is background noise.
- **API numbers** [OFFICIAL API post]: GPT-Live-1 "improves Full Duplex Bench performance by 30 percentage points over GPT-Realtime-2.1" and, in early Speak evaluations, cut "interruptions by almost 80% versus previous turn-based systems"; it also natively supports turn detection.
- **The older cascaded-style knobs in the Realtime API** ([OFFICIAL Realtime VAD guide](https://developers.openai.com/api/docs/guides/realtime-vad), [accept-call reference](https://developers.openai.com/api/docs/api-reference/realtime-calls/accept-call)):
  - `server_vad`: `threshold` 0.5, `prefix_padding_ms` 300, `silence_duration_ms` **500**; optional `idle_timeout_ms`.
  - `semantic_vad`: a classifier on the words so far; trailing "ummm..." waits longer than a definitive statement; `eagerness` low / medium / high with max timeouts **8 s / 4 s / 2 s** (auto = medium).
  - `create_response` and `interrupt_response` flags (response starts on speech stop; ongoing response is cancelled on speech start); events `speech_started` / `speech_stopped`.
- Gemini Live for comparison: automatic VAD on by default, `silenceDurationMs` about 500-800 ms recommended ([OFFICIAL](https://ai.google.dev/gemini-api/docs/live-guide)).

### 2.4 Interrupting by speaking (barge-in)

- [OFFICIAL Help Center] "Live can listen and speak at the same time," so you can interrupt ChatGPT mid-response. Live "is not yet optimized for conversations with multiple speakers." To reduce unwanted interruptions: use headphones, move somewhere quieter, raise the device volume, on iPhone turn on Voice Isolation (Mic Mode in Control Center), or ask Live to wait until you are ready.
- [OFFICIAL announcement] you can interrupt with a question or ask it to slow down; if asked to stay quiet and listen, it will.
- Advanced (older): "You can talk over it and it stops and listens"; interruption was aggressive and coughs, music or background talk could cut it off ([3P gptprompts](https://gptprompts.ai/chatgpt-voice-mode-guide), [3P Toolchase](https://toolchase.com/blog/chatgpt-voice-mode-guide/)).
- Client duty (any realtime API; Gemini docs): on interruption "the ongoing generation is canceled and discarded", and the client should stop and clear any queued audio playback ([OFFICIAL](https://ai.google.dev/gemini-api/docs/live-guide)).

### 2.5 Mute, captions, live transcript

- **Mute / exit:** see controls above [OFFICIAL]. In the API, muting does not stop the billing clock: "the meter runs the entire time a session is open, including silence and backend work" ([3P DataCamp](https://www.datacamp.com/tutorial/gpt-live-1-api)).
- **Captions** [OFFICIAL Help Center]: with Live, responses appear as text in the chat as they are spoken; on iOS/Android with Advanced, use the cc button. "Voice transcripts are not verbatim records," so they may differ from what was said. OpenAI support says Voice "already supports on-screen text and some caption options" and that word highlighting, auto-scroll and sentence-tap playback were passed on with no timeline ([OpenAI community reply](https://community.openai.com/t/synchronized-transcript-for-read-aloud-and-voice-mode/1391540)).

### 2.5b Languages

[OFFICIAL Help Center] set your most-used language under Settings > Voice > Language "for better accuracy", or ask ChatGPT to switch languages mid-conversation; additional Live voices exist for Brazilian Portuguese, French, German, Hindi, Japanese, Korean, Mexican Spanish and English. [OFFICIAL announcement] GPT-Live is optimized for "some of the most popular languages in ChatGPT", and for certain languages the model may have a non-native accent or gaps in fluency. **Vietnamese is not named in any first-party page I read** (the API post says language availability will expand "over the coming months").

### 2.6 Switching voice and text; what the chat looks like afterwards

- In-chat voice keeps the **same thread**: scroll back, read the live transcript, type any time ([TechCrunch](https://techcrunch.com/2025/11/25/chatgpts-voice-mode-is-no-longer-a-separate-interface/), [3P MundoBytes](https://mundobytes.com/en/chatgpt-finally-integrates-voice-mode/)).
- [OFFICIAL Help Center] "A transcript is added to the chat after the conversation ends" and can be reviewed in chat history. Changing the voice mid-conversation starts a new call in the same chat. Only one Voice conversation can run at a time. A conversation can end at a usage limit, the maximum session length or a context limit.
- [OFFICIAL Help Center] **Retention:** "Clips are retained for 30 days" (Live and Advanced audio, Advanced video), stored with the transcript; deleting the chat removes clips within 30 days; clips are not used for training unless you share them; Standard deletes audio after transcription.

### 2.7 Latency

| Item | Number | Source |
|---|---|---|
| GPT-4o voice, best / average | 232 ms / 320 ms | [OFFICIAL Hello GPT-4o](https://openai.com/index/hello-gpt-4o/) |
| Old voice pipeline (3 models) | 2.8 s (GPT-3.5), 5.4 s (GPT-4) average | same |
| Cascaded stack before first word | up to about 1,700 ms (October 2024 analysis cited via VentureBeat) | [3P DigitalApplied](https://www.digitalapplied.com/blog/openai-gpt-live-voice-models-customer-experience-2026) |
| GPT-Live | **no millisecond figure** in the announcement, the engineering post or the API post; the engineering post names the goal "sub-second responsiveness" | [OFFICIAL](https://openai.com/index/continuous-voice-interaction-with-gpt-live/) |
| GPT-Live frame delivery | after the Go rewrite, the "new system's p95 matching the previous system's p50" | OFFICIAL engineering post |
| GPT-Live session start | WARP "reduces media and data startup from six network round trips to just one" (being standardised in the IETF TSVWG); Instant Connect pre-negotiates SDP parameters so signaling is off the critical path | OFFICIAL engineering post |
| Human turn gap | languages differ "within a range of 250 ms from the cross-language mean" (the mean itself not verified here) | [Stivers et al. 2009 abstract](https://cognitionandculture.net/blogs/icci-blog/universals-and-cultural-variation-in-turn-taking-in-conversation) |

Other engineering points from the post [OFFICIAL]: delegation to bigger models runs on an asynchronous path so a slow tool call "cannot stall the flow of media"; a replacement model instance is prepared alongside the current one and swapped in during context compaction without interrupting media; a silent shadow test sent a growing share of real ChatGPT Voice sessions to the new stack and showed that capacity depends on concurrent sessions staying on schedule, not only GPU throughput.

### 2.8 Documented design rationale

- [OFFICIAL announcement] **Vision:** make collaboration with AI feel as fluid as working with another person, with reasoning happening in the background. **Continuous interaction:** a full-duplex design lets the model respond to pauses, interruptions and backchannel cues. **Decoupling:** separating conversation from deeper work lets the voice layer keep talking while other models work, and lets OpenAI swap in newer models without changing the real-time layer.
- [OFFICIAL engineering post] "sub-second responsiveness" as the goal; remove the turn-detection bottleneck; slow tools must not stall media.
- Why voice moved into the thread (2025-11-25) **[3P reading, not an OpenAI statement]**: the old orb screen showed no text, so a missed word meant leaving voice mode ([PhoneArena](https://www.phonearena.com/news/chatgpt-voice-mode-is-accessible-in-chat_id176082)); a UX write-up names it "modal lockout" ([Modern Engineering Marvels](https://modernengineeringmarvels.com/2025/11/27/chatgpt-voice-mode-now-blends-seamlessly-with-text-chat/)). OpenAI's own wording is the feature description quoted in 2.2.
- OpenAI researcher Manuka Stratta (March 2025): "The model interrupts you less, so you'll have more time to gather your thoughts and not feel like you have to fill in all the gaps and silences all the time." (via coverage of the update, [PCWorld](https://www.pcworld.com/article/2649338/chatgpt-now-speaks-even-more-naturally-with-fewer-interruptions.html), [3P](https://tomsguide.com/ai/chatgpts-advanced-voice-mode-just-got-a-free-upgrade-heres-whats-new)).
- A third-party digest of the engineering post quotes its core principle as "remove layers entirely when possible, and make the ones that remain as transparent as audio should be" ([3P](https://hungrymindsdev.substack.com/p/how-openai-built-gpt-live-for-low)); I did not find that sentence in the proxy rendering of the post, so treat the wording as **[UNVERIFIED]**.

### 2.9 UX principles that make it feel smooth and easy

Evidence in brackets; the "Build" lines are my translation for your app [INFERENCE].

1. **One tap from where you already are.** The voice icon sits inside the message bar; optional "Start with Voice" opens it automatically. *Build:* a mic/wave button in the composer, plus a setting to start new chats in voice.
2. **Voice is a modality of the thread, not a mode.** Live transcript, visuals inline, type or attach an image any time, history stays, one thread (TechCrunch, Help Center, "modal lockout"). *Build:* write voice turns into the same message list as text.
3. **Always show state.** A floating orb that moves while listening/speaking, optional captions, one obvious End, a Mute (Help Center, reviews). *Build:* an animated indicator driven by mic and TTS levels, plus text state for accessibility.
4. **Hands-free turn-taking that waits.** No push-to-talk by default; the model decides when you are done; "waits instead of jumping in"; you can ask it to wait until you are ready (announcement, Help Center). *Build:* VAD endpointing of 500-800 ms with a longer grace after filler words, and a spoken "hold on" command.
5. **Barge-in is instant and clears audio.** Speaking cancels playback and discards the queued tail (Gemini docs, `interrupt_response`). *Build:* stop TTS, flush the audio queue and cancel the pending LLM stream the moment VAD fires.
6. **No dead air.** The voice layer keeps talking or acknowledges ("mhmm", "got it") while heavier work runs in the background; delegation is asynchronous. *Build:* a short spoken or visual "working on it", stream tool progress as cards.
7. **Sub-second feel.** OpenAI's bar is 320 ms average and "sub-second responsiveness"; cascaded stacks sit near 1.7 s. *Build:* budget the loop (section 3.8); start TTS on the first sentence.
8. **Robust to the environment.** Focus on the user's voice in noise; tell users to use headphones, move somewhere quieter, enable Voice Isolation (Help Center). *Build:* detect the output route and raise thresholds or require tap-to-interrupt on speakers.
9. **Continuity.** Voice survives backgrounding and screen lock (opt-in), shows on the lock screen, limits and maximum session length are stated (Help Center, release notes). *Build:* background audio modes and a visible session timer.
10. **Language is a setting plus a voice command.** Set the main language in Settings, or ask to switch mid-conversation (Help Center). *Build:* a default language plus "switch to Vietnamese / English".
11. **Graceful degradation.** A turn-based Standard mode remains for weak connections. *Build:* "tap to talk" fallback.
12. **Cost and privacy are visible.** API meter runs during silence; clips retained 30 days with the transcript; transcripts "are not verbatim records" (DataCamp, Help Center). *Build:* a cloud indicator, retention note and auto-end after inactivity.
13. **Cards for facts.** Weather, stocks, scores and maps appear as cards beside the spoken answer (announcement, TechRadar). *Build:* render tool results as cards in the transcript while TTS speaks a summary.

### 2.10 Gaps

- No source documents the orb's exact state animations, the pixel layout of the in-chat controls, or GPT-Live end-to-end latency in milliseconds.
- Vietnamese quality in ChatGPT voice is **[UNVERIFIED]**: no first-party page names Vietnamese; one vendor blog claims good tone handling and a competitor blog claims the opposite, both marketing ([Phong Vu](https://phongvu.vn/cong-nghe/chatgpt-voice-advanced-song-dong-chan-thuc/), [Kaiwa](https://trykaiwa.com/blog/vietnamese-chatgpt-vs-real-speaking-2026)).

---

## 3. Implementation options for a Flutter voice conversation (Vietnamese + English)

Targets: iOS 15+, Android minSdk 26, macOS, Windows. Goal: smooth spoken conversation, audio kept on the device where possible. "Published N days ago" notes below are relative to the fetch date 2026-10-16.

### 3.1 `speech_to_text` (platform recognizers)

**Package.** 7.5.0 on pub.dev ("published 31 days ago"; 7.6.0 beta exists). Platforms: Android, iOS, macOS (since 7.0.0), web, Windows (beta, since 7.3.0); Linux unsupported ([pub.dev](https://pub.dev/packages/speech_to_text), [changelog](https://pub.dev/packages/speech_to_text/changelog)). Its README says the target is short commands and phrases, not "continuous spoken conversion or always on listening" ([README](https://raw.githubusercontent.com/csdcorp/speech_to_text/main/speech_to_text/README.md)).

**On-device switch.** `SpeechListenOptions(onDevice: true)`: "if true the listen attempts to recognize locally with speech never leaving the device ... If on-device recognition isn't possible, the listen attempt fails" ([API doc](https://pub.dev/documentation/speech_to_text/latest/speech_to_text/SpeechToText/listen.html)). Verified in source:

- iOS sets `requiresOnDeviceRecognition = true` after checking `supportsOnDeviceRecognition` (iOS 13+) ([SpeechToTextPlugin.swift](https://raw.githubusercontent.com/csdcorp/speech_to_text/main/speech_to_text/darwin/speech_to_text/Sources/speech_to_text/SpeechToTextPlugin.swift)).
- Android: `onDevice` defaults to false; with `onDevice` and `SDK_INT >= 31` it calls `createOnDeviceSpeechRecognizer`, otherwise it only sets the hint `EXTRA_PREFER_OFFLINE`; `hasOnDeviceSupport` returns false below API 31; `pauseFor` maps to `EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS` ([SpeechToTextPlugin.kt](https://raw.githubusercontent.com/csdcorp/speech_to_text/main/speech_to_text/android/src/main/kotlin/com/csdcorp/speech_to_text/SpeechToTextPlugin.kt)). Android's own doc says the offline extra may be ignored ([RecognizerIntent source](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/speech/RecognizerIntent.java)), so on API 26-30 you cannot guarantee on-device.

**iOS audio session set by the plugin:** `.playAndRecord`, mode `.default` (the `.measurement` line is commented out), options `.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers` (same Swift file). Apple's `voiceChat` doc says that even chat-mode apps get no echo cancellation unless they use the Voice Processing I/O unit or `AVAudioEngine` voice processing ([Apple voiceChat doc](https://developer.apple.com/tutorials/data/documentation/avfaudio/avaudiosession/mode-swift.struct/voicechat.md)); the plugin uses neither and is not even in a chat mode. **So the plugin gives no barge-in protection** [INFERENCE from those two facts].

#### iOS: limits and Vietnamese on-device status

- **One minute.** "Plan for a one-minute limit on audio duration ... the framework stops speech recognition tasks that last longer than one minute." Also "Individual devices may be limited in the number of recognitions that can be performed per day, and each app may be throttled globally" and "Because speech recognition is a network-based service". Also: "Do not perform speech recognition on private or sensitive information." ([OFFICIAL SFSpeechRecognizer](https://developer.apple.com/tutorials/data/documentation/speech/sfspeechrecognizer.md)).
- **On-device is opt-in and less accurate.** `requiresOnDeviceRecognition` "prevent[s] ... sending audio over the network. However, on-device requests won't be as accurate"; honoured only if `supportsOnDeviceRecognition` is true (iOS 13+/macOS 10.15+) ([OFFICIAL](https://developer.apple.com/tutorials/data/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition.md), [OFFICIAL](https://developer.apple.com/tutorials/data/documentation/speech/sfspeechrecognizer/supportsondevicerecognition.md)). `supportsOnDeviceRecognition` is a hint: models arrive when the system fetches them, and a failed on-device request can return an empty transcript instead of an error ([3P DEV](https://dev.to/tbds_2dadf2b626f315902eae/on-device-speech-recognition-on-ios-the-honest-boundaries-1ndn)).
- **Is Vietnamese on-device?**
  - **2022, iOS 15.4.1, iPhone 7 (airplane-mode test): 22 on-device locales and `vi-VN` is not among them** ([3P Toru Furuya](https://medium.com/@toru_furuya/available-languages-in-on-device-speech-recognition-on-ios-in-2022-8c6383fac9f2), read through a text proxy).
  - **Today:** Apple's "iOS and iPadOS 27 - Feature Availability" page lists "Vietnamese (Vietnam)" under "Dictation: On-Device and Modeless Dictation" ([OFFICIAL](https://www.apple.com/ios/feature-availability/)). No source says which iOS release added it. The keyboard's on-device dictation set and the Speech framework set matched in the 2022 test (same 3P article).
  - **iOS 26+ only:** `SpeechAnalyzer` / `SpeechTranscriber` (on-device models installed through `AssetInventory`, `supportedLocales` / `installedLocales`) ([OFFICIAL](https://developer.apple.com/tutorials/data/documentation/speech/speechtranscriber.md), [OFFICIAL](https://developer.apple.com/tutorials/data/documentation/speech/speechanalyzer.md)). Third-party lists show `vi_VN` in `supportedLocales` ([3P Gubarenko, Beta 3 list](https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide), [3P LoroNote Aug 2026](https://loronote.com/en/blog/apple-speechanalyzer-vs-whisper)). Not usable on your iOS 15-25 devices.
  - **Verdict for iOS 15+:** treat on-device Vietnamese as **not guaranteed**; test `SFSpeechRecognizer(locale: vi-VN).supportsOnDeviceRecognition` per device and OS in airplane mode.

#### Android: on-device recognizer, Vietnamese, limits

- **API levels (verified in the official API-diff pages).** **API 31** added `createOnDeviceSpeechRecognizer`, `isOnDeviceRecognitionAvailable`, `ERROR_LANGUAGE_NOT_SUPPORTED`, `ERROR_LANGUAGE_UNAVAILABLE`, `ERROR_SERVER_DISCONNECTED`, `ERROR_TOO_MANY_REQUESTS` ([OFFICIAL diff 31](https://developer.android.com/sdk/api_diff/31/changes/android.speech.SpeechRecognizer)); the Android 12 source has both on-device methods and neither `checkRecognitionSupport` nor `triggerModelDownload` ([AOSP android12-release](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android12-release/core/java/android/speech/SpeechRecognizer.java)). **Your "API 31+" is right.** **API 33** added `checkRecognitionSupport` (which languages are installed / downloadable on-device), `triggerModelDownload`, `ERROR_CANNOT_CHECK_SUPPORT` ([OFFICIAL diff 33](https://developer.android.com/sdk/api_diff/33/changes/android.speech.SpeechRecognizer)) and, on `RecognizerIntent`, `EXTRA_SEGMENTED_SESSION`, `EXTRA_AUDIO_SOURCE*` and biasing extras ([OFFICIAL diff 33](https://developer.android.com/sdk/api_diff/33/changes/android.speech.RecognizerIntent)). `createOnDeviceSpeechRecognizer` throws `UnsupportedOperationException` when `isOnDeviceRecognitionAvailable` is false ([AOSP main](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/speech/SpeechRecognizer.java)). On API 31-32 you can create the on-device recognizer but cannot ask which languages it has.
- **Vietnamese on the platform on-device recognizer: [UNVERIFIED].** No published list. Query `checkRecognitionSupport` (API 33+) per device at runtime. A third-party guide says Gboard's offline voice-typing packs cover far fewer languages than the cloud service ([3P](https://www.keyboardapps.net/gboard-voice-typing)); no source I found names Vietnamese.
- **Indirect evidence:** ML Kit **GenAI Speech Recognition** (alpha, "not subject to any SLA or deprecation policy") has a *Basic* mode ("traditional on-device speech recognition model, similar to the SpeechRecognizer API", "most Android devices with API level 31 and higher") and an *Advanced* mode (on-device Gemini model, Pixel 10 and 11); **`vi-VN (beta)` is listed in both**; streaming mic input with partial results; 16 kHz mono PCM; model downloaded on demand ([OFFICIAL](https://developers.google.com/ml-kit/genai/speech-recognition/android)). There is no Flutter plugin I could find; it would need a platform channel.
- **Limits and continuous listening.** Android's class doc: the implementation "is likely to stream audio to remote servers" and the API "is not intended to be used for continuous recognition" ([AOSP source](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/speech/SpeechRecognizer.java)). The plugin's docs add: "There is a time limit on listening imposed by both Android and iOS ... Android's limit is usually quite short ... on the order of ten seconds or so"; "notably Android, there is a system imposed pause of from one to three seconds that cannot be overridden"; the beep cannot be disabled ([API doc](https://pub.dev/documentation/speech_to_text/latest/speech_to_text/SpeechToText/listen.html), [pub.dev](https://pub.dev/packages/speech_to_text)). API 33 `EXTRA_SEGMENTED_SESSION` returns results in segments and ends with `onEndOfSegmentedSession`, but "depending on the recognizer implementation, this value may have no effect" ([RecognizerIntent](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/speech/RecognizerIntent.java)); two developer reports say per-segment data differs by engine ([3P](https://github.com/BrockBadeaux14/AnkiVoice/issues/67)).

#### macOS / Windows

macOS uses the same `SFSpeechRecognizer` (macOS 10.15+); Windows support is "in beta" ([pub.dev](https://pub.dev/packages/speech_to_text)). For desktop I would not depend on platform STT (section 3.8).

### 3.2 `flutter_tts` and Vietnamese voices

- **Package:** 4.2.5 (published ~9 months ago), platforms Android, iOS, macOS, web, Windows. API includes `getVoices` (maps with name/locale; iOS and macOS add quality, gender, identifier), `setVoice`, `isLanguageAvailable`, `setSpeechRate`, `awaitSpeakCompletion`, `synthesizeToFile`, `setIosAudioCategory`; Android minSdk 21; pause and speech marks need API 26+ ([pub.dev](https://pub.dev/packages/flutter_tts)).
- **Android:** Google Text-to-speech has a Vietnamese voice pack installed via "Install Voice Data" ([3P guide](https://saomaicenter.org/en/node/64)); Samsung ships a separate "Samsung TTS Vietnamese Voice 1" package (3.2.27.6, about 83 MB, Android 14+ per an APK mirror listing) ([3P APKMirror](https://www.apkmirror.com/apk/samsung-electronics-co-ltd/samsungtts-vietnamese-female/)). Google's Vietnamese voice ids and quality tiers are **[UNVERIFIED]** (no list found): call `getVoices()` on each target device and log the `vi-VN` entries ([Android reference](https://developer.android.com/reference/android/speech/tts/TextToSpeech) says an engine can expose several voices per locale with different features).
- **iOS / macOS:** Apple lists Vietnamese (Vietnam) for VoiceOver, Live Speech and Read & Speak ([OFFICIAL availability page](https://www.apple.com/ios/feature-availability/)); an Anki forum post says Apple's Vietnamese TTS voices exist from iOS 16 / macOS 13 ([3P](https://forums.ankiweb.net/t/basic-vietnamese-for-english-speakers-text-to-speech/25527)). `AVSpeechSynthesisVoice.speechVoices()` lists what is on the device ([OFFICIAL](https://developer.apple.com/tutorials/data/documentation/avfaudio/avspeechsynthesisvoice.md)). **Voice names and quality tiers for Vietnamese: [UNVERIFIED]** (I found no Apple page naming a Vietnamese system voice; the "Linh" name I kept seeing is Microsoft's Azure voice `vi-VN-Linh:MAI-Voice-2-Flash`, or third-party products). Enhanced and premium voices must be downloaded by the user in Settings, and there is no API to discover downloadable-but-missing voices ([3P](https://developer.apple.com/forums/thread/758460), excerpt).
- **Windows:** Vietnamese system TTS voice availability **[UNVERIFIED]** (third-party SAPI5 voices exist, e.g. Sao Mai VNVoice).
- **Quality:** I found **no independent MOS or listening test for any Vietnamese system voice.** The only structured open-model comparison is ViTTS-Bench (open models only): "MMS and Piper are tiny and fast, and struggle with tongue twisters" ([3P](https://github.com/yoonjae26/vietnamese-tts)). Run a native-listener A/B on your target devices.
- **Gotcha:** a language or voice installed after the app started may not show in `getLanguages` until restart on iOS ([3P issue #491](https://github.com/dlutton/flutter_tts/issues/491)).
- **AEC angle [INFERENCE]:** `AVSpeechSynthesizer.write(_:toBufferCallback:)` (iOS 13+/macOS 10.15+) hands you the synthesized buffers ([OFFICIAL](https://developer.apple.com/tutorials/data/documentation/avfaudio/avspeechsynthesizer/write(_:tobuffercallback:).md)), which is how system TTS audio could be played through the same engine that does voice processing.

### 3.3 VAD packages

| Package | Engine | Platforms | Notes | Source |
|---|---|---|---|---|
| `vad` 0.0.8 | Silero VAD v4/v5 via ONNX Runtime FFI (web via JS) | Android, iOS, Linux, macOS, Web, Windows | Uses `record`. Default config: 16 kHz PCM16 with echo cancellation, auto gain, noise suppression on native, but "Echo cancellation is not available on Windows and Linux". Defaults: positive threshold 0.5, negative 0.35, `redemptionFrames` 8, `minSpeechFrames` 3, `preSpeechPadFrames` 1; events `onSpeechStart`, `onSpeechEnd` (audio), `onRealSpeechStart`, `onFrameProcessed`, `onVADMisfire`. Tested on iOS 18.1, Android 10/15, macOS 15.1, Windows 11. | [pub.dev](https://pub.dev/packages/vad) |
| `vad_plus` | Silero VAD v6 (~2.3 MB bundled), `dart:ffi` | Android (minSdk 24), iOS 15.0, macOS 13.4; **no Windows, Linux, web** | Raw mic, **no AEC / NS / AGC**. 32 ms frames; speech start reported eagerly, confirmation about 288 ms; speech ends after about 768 ms of silence; about 96 ms pre-speech padding; MIT; fork of Miracle-Blue/vad_plus. | [GitHub](https://github.com/781flyingdutchman/vad_plus) |
| `flutter_silero_vad` | Silero via Swift/Kotlin | Android, iOS | Unofficial; only `initialize`, `resetState`, `predict` | [GitHub](https://github.com/char5742/flutter_silero_vad) |
| FONNX | generic ONNX runtime for Flutter | iOS, Android, Web, Linux, Windows, macOS | Changelog (July 2026) moves VAD to Silero v6.2.1 | [GitHub](https://github.com/Telosnex/fonnx) |
| sherpa-onnx VAD | Silero via the same runtime as ASR/TTS | all sherpa platforms | one dependency instead of two | [pub.dev](https://pub.dev/packages/sherpa_onnx) |

Endpoint timing seen elsewhere: OpenAI `server_vad` 500 ms default, Gemini 500-800 ms recommended (section 2.3), `vad_plus` 768 ms.

### 3.4 sherpa-onnx for Flutter (ASR + TTS + VAD)

- **Package:** `sherpa_onnx` 1.13.8 (published ~34 days before fetch), Apache-2.0. Federated platform packages: Android (arm64, armeabi, x86, x86_64), iOS (`sherpa_onnx_ios`, podspec `s.platform = :ios, '13.0'`), Linux, macOS, Windows, web; Dart >= 3.2 ([pub.dev](https://pub.dev/packages/sherpa_onnx), [pubspec](https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/master/flutter/sherpa_onnx/pubspec.yaml), [podspec](https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/master/flutter/sherpa_onnx_ios/ios/sherpa_onnx_ios.podspec)). The iOS floor (13.0) is below your iOS 15 target; the Android floor is not stated on the pages I read (the examples README only says to raise `minSdk` if you hit a minSdk error), so confirm it against your minSdk 26 in a spike.
- **Functions:** streaming and non-streaming ASR, TTS, Silero VAD, speaker diarization, keyword spotting, punctuation, speech enhancement ([pub.dev](https://pub.dev/packages/sherpa_onnx)). Flutter examples exist for streaming ASR, VAD + offline ASR from microphone, TTS, punctuation ([flutter-examples](https://github.com/k2-fsa/sherpa-onnx/tree/master/flutter-examples)). Notes from that README: apps run in a sandbox and cannot read arbitrary paths (copy or download models into app storage); "You must call `initBindings()` ... in every isolate".
- **Models are not bundled**; they come from GitHub releases ([pub.dev](https://pub.dev/packages/sherpa_onnx)).
- **Vietnamese ASR (official docs, offline transducer / Zipformer)** ([docs](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/offline-transducer/zipformer-transducer-models.html)):

  | Model | Training data | Files | RTF in docs |
  |---|---|---|---|
  | `sherpa-onnx-zipformer-vi-30M-int8-2026-02-09` | about 6,000 h (from `hynt/Zipformer-30M-RNNT-6000h`) | encoder.int8 26 MB, decoder 4.9 MB, joiner.int8 1.0 MB | 0.011 (0.041 s for 3.74 s audio; 1 thread; `provider=cpu`; CPU not named) |
  | `sherpa-onnx-zipformer-vi-2025-04-20` | about 70k h (from `zzasdf/viet_iter3_pseudo_label`) | encoder 249 MB fp32 | 0.063 |
  | `sherpa-onnx-zipformer-vi-int8-2025-04-20` | same | encoder 68 MB int8 | 0.061 |

  Also listed: `sherpa-onnx-moonshine-base-vi-quantized-2026-02-27` (details not read). **No official streaming Vietnamese model**; a community streaming `zh-en-vi` Zipformer exists on Hugging Face ([3P](https://huggingface.co/lmcu000/sherpa-onnx-streaming-zipformer-zh-en-vi-2e)). The docs show a "VAD + microphone simulated-streaming ASR" recipe for the Vietnamese 30M model, which is the way to get a live feel from an offline model.
- **Accuracy (publisher-run, not independent) [3P]:** Gipformer 1.5 (68M RNN-T, MIT, ONNX) reports VIVOS WER 4.25 and FLEURS 12.65 against PhoWhisper-large 4.73 / 11.18, PhoWhisper-medium 4.93 / 11.34, PhoWhisper-small 6.23 / 14.09 ([model card](https://huggingface.co/g-group-ai-lab/gipformer1.5-68M-rnnt)). It is the same Zipformer-transducer family as the sherpa Vietnamese models but is not listed on the sherpa pages I read. For comparison Vosk's Vietnamese small model scores WER 15.70 on VIVOS ([Vosk](https://alphacephei.com/vosk/models)); `vosk_flutter` has no iOS/macOS support and was last published about 3 years ago ([pub.dev](https://pub.dev/packages/vosk_flutter)).
- **Vietnamese TTS in sherpa-onnx** ([docs list](https://k2-fsa.github.io/sherpa/onnx/tts/all/Vietnamese/index.html)): `vits-piper-vi_VN-25hours_single-low`, `vits-piper-vi_VN-vais1000-medium` (1 speaker, 22.05 kHz) ([page](https://k2-fsa.github.io/sherpa/onnx/tts/all/Vietnamese/vits-piper-vi_VN-vais1000-medium.html)), `vits-piper-vi_VN-vivos-x_low`, and **`supertonic-3-vi`** (10 speakers, 24 kHz, `lang="vi"`, 8 steps; archive `sherpa-onnx-supertonic-3-tts-int8-2026-05-11.tar.bz2`) ([page](https://k2-fsa.github.io/sherpa/onnx/tts/all/Vietnamese/supertonic-3-vi.html)). Prebuilt Android TTS-engine APKs exist.
  - **Supertonic 3** (Supertone): 31 languages including Vietnamese, about 99M parameters, code MIT, **weights OpenRAIL-M**, and an "average RTF of 0.3x on an Onyx Boox Go 6 e-reader, in airplane mode"; **the repo is archived: "Development and support have ended"** ([GitHub](https://github.com/supertone-inc/supertonic)).
  - ViTTS-Bench recommends VieNeu-TTS v3 Turbo as best all-rounder (RTF 0.1) but its mobile SDK is only a roadmap item ([bench](https://github.com/yoonjae26/vietnamese-tts), [VieNeu](https://github.com/pnnbao97/VieNeu-TTS)); not part of sherpa.
  - Voice-dataset licences for the Piper Vietnamese voices are **[UNVERIFIED]**; check before commercial use.
- **Phone latency for the Vietnamese models: [UNVERIFIED]; indicative numbers for other small models exist.** The RTFs above are single-thread desktop CPU runs, and sherpa's TTS pages quote Raspberry Pi 4, not phones ([TTS models](https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/index.html)). A **third-party benchmark dated 2026-09-21** ran sherpa-onnx on a **Samsung Galaxy S10 (Exynos 9820, Android 12)** with a 30 s clip: Moonshine Tiny 27M RTF 0.05 (1.4 s), SenseVoice Small RTF 0.06, Whisper Tiny RTF 0.07 (2.1 s), streaming Zipformer 20M English RTF 0.12 (3.6 s); on a 2019 Windows laptop (Core i5-1035G1) Moonshine Tiny RTF 0.04. It measures speed only, not accuracy, and has no Vietnamese model ([3P voiceping.net](https://voiceping.net/en/blog/research-offline-speech-transcription-benchmark/)). A 30M Vietnamese Zipformer should land in a similar range [INFERENCE]; measure on a mid-range Android and an iPhone before committing. (A blog quoting RTF 0.05 on an iPhone 15 Pro and 0.03 on a Pixel 6 cites no source or method: [ignore](https://www.blog.brightcoding.dev/2025/09/11/sherpa-onnx-unified-speech-recognition-synthesis-and-audio-processing-for-every-platform).)
- **A working Flutter reference:** `yundddd/voice-agent` (Flutter + sherpa-onnx, on-device ASR/TTS round trip, barge-in, even a bridge to a desktop Claude Code session) reports ASR "6.6 s of speech -> text in 150 ms" and TTS 5.1 s of audio in 111 ms on an Intel dev machine, 46 MB arm64 APK, 124 MB default voice pack downloaded on first run; it has **no Vietnamese** ([GitHub](https://github.com/yundddd/voice-agent)).

### 3.5 whisper.cpp-based packages and phone latency

| Package | Version / engine | Platforms and minimums | Notes |
|---|---|---|---|
| `whisper_ggml` | 2.8.1, whisper.cpp v1.9.1 | Android API 24, iOS 15.6, macOS 10.15, Windows 10 x64, Linux x64 | tiny/base/small/medium (multilingual and English-only), large-v3 (multilingual); 99 languages; live mode takes 16 kHz mono PCM16 and emits "full transcript so far", with an adaptive energy gate against silence hallucinations, one live session at a time; Core ML / Metal not mentioned; "an 11-second clip transcribes in ~0.4 s with the base model on an Apple Silicon Mac" ([pub.dev](https://pub.dev/packages/whisper_ggml)) |
| `whisper_ggml_plus` | whisper.cpp v1.8.3 | file-based; optional Metal/Core ML on iOS | large-v3-turbo support ([pub.dev](https://pub.dev/packages/whisper_ggml_plus)) |
| `whisper_flutter_new` | older | Android 5+, iOS 13+ | about 19 months old at fetch ([pub.dev](https://pub.dev/packages/whisper_flutter_new)) |
| `flutter_whisper` | whisper.cpp | Android only | iOS planned ([GitHub](https://github.com/govindtank/flutter_whisper)) |

- **Phone latency evidence is thin.** The only first-party phone row I found: whisper.cpp's benchmark thread, iPhone 13 mini, iOS 16, "NEON BLAS", model base, 4 threads, Load 97, **Enc. 1091** (unit unlabeled, ms in later outputs), opened 2022-10-25 ([discussion](https://github.com/ggml-org/whisper.cpp/discussions/89)). Core ML on the Neural Engine gives "more than x3 faster" than CPU-only, with a slow first run while the ANE compiles ([README](https://github.com/ggml-org/whisper.cpp)). The same third-party benchmark as above ([voiceping.net](https://voiceping.net/en/blog/research-offline-speech-transcription-benchmark/)) measured **whisper.cpp Whisper Tiny on the Galaxy S10 at RTF 3.52 (105.6 s for a 30 s clip)** against sherpa-onnx's Whisper Tiny at RTF 0.07, and whisper.cpp Whisper Base on a 2019 Windows laptop at RTF 0.59; WhisperKit Base ran out of memory on a 4 GB iPad Pro (A12X). The build configuration is not stated, so the whisper.cpp figure may reflect an unoptimised build; treat it as a warning, not a constant. No source gives iPhone numbers for small or medium models.
- **WhisperKit** (Argmax) reports 0.46 s mean latency and 2.2% WER in its paper, hardware not stated in the abstract ([arXiv](https://arxiv.org/abs/2507.10860)); it needs iOS 17 / macOS 14 and its published speed factors come from an M4 Mac mini ([Argmax](https://www.argmaxinc.com/blog/apple-and-argmax)). **Not usable on iOS 15.**
- **Vietnamese accuracy of Whisper-class models:** VinAI's **PhoWhisper** (Whisper fine-tuned on 844 h of Vietnamese) beats prior baselines on Common Voice, VIVOS and VLSP 2020 ([arXiv](https://arxiv.org/pdf/2406.02555)); numbers for stock Whisper sizes on Vietnamese were not retrievable ([UNVERIFIED]). Whether PhoWhisper runs in whisper.cpp builds used by these packages is **[UNVERIFIED]**.
- **Reading [INFERENCE]:** Whisper-class decoding is chunk-based, so on phones expect about a second or more per utterance for base, with small/medium too slow. Use it as a desktop option or a fallback, not as the primary phone engine.

### 3.6 Echo cancellation and barge-in

**iOS / macOS**

- **`.voiceChat` alone is not AEC.** Apple: for apps that use a chat mode but do not use the Voice I/O audio unit or `AVAudioEngine` with `setVoiceProcessingEnabled(_:)`, "the system reduces the processing it applies to audio signals. Specifically, it doesn't apply voice-specific processing, like echo cancellation and automatic gain correction, and disables dynamic processing on input and output, which results in a lower playback level." The mode also applies `allowBluetoothHFP` ([OFFICIAL](https://developer.apple.com/tutorials/data/documentation/avfaudio/avaudiosession/mode-swift.struct/voicechat.md)).
- **`AVAudioIONode.setVoiceProcessingEnabled(_:)`**: iOS 13+, macOS 10.15+, "Enables or disables voice processing on the I/O node" ([OFFICIAL](https://developer.apple.com/tutorials/data/documentation/avfaudio/avaudioionode/setvoiceprocessingenabled(_:).md)). `voiceProcessingOtherAudioDuckingConfiguration` (iOS 17+/macOS 14+) controls ducking of other audio ([OFFICIAL](https://developer.apple.com/tutorials/data/documentation/avfaudio/avaudioinputnode/voiceprocessingotheraudioduckingconfiguration.md)).
- **Field report (2026-04, iOS 18) [3P]:** VPIO is "closer to output subtraction than to a full AEC"; "There is no knob to turn"; attach the playback graph **before** enabling voice processing (reverse order breaks AEC silently); use `.voiceChat`; manual rendering mode does not support it; a residual echo tail remains after TTS stops, so an app-level mic gate is needed: risk window 200-500 ms, "300ms is the wrong answer. 800ms is closer"; "Disarm the gate when new TTS arrives, so barge-in still works" ([Barock](https://barock.dev/2026/04/22/why-your-ios-voice-agent-still-hears-itself)). OpenAI forum: devs had to enable voice processing on both nodes, found AVAudioEngine still interrupted, and moved to an AudioToolbox VPIO unit with a 44.1 kHz rate on macOS ([thread](https://community.openai.com/t/audio-notes-for-openai-realtime-on-apple-platforms/1108404)). On Macs, VPIO failed on Spatial-Audio speakers, Bluetooth headsets and some aggregate devices in one team's report ([3P Forasoft](https://www.forasoft.com/ship-log/spatial-audio-vpio)).

**Android**

- `AcousticEchoCanceler.isAvailable()` "Checks if the device implements acoustic echo cancellation"; "On some devices, an AEC can be inserted by default in the capture path by the platform according to the `MediaRecorder.AudioSource` in use"; check the enabled state after creating it ([OFFICIAL class doc, mirror of the Android reference](https://stuff.mit.edu/afs/sipb/project/android/docs/reference/android/media/audiofx/AcousticEchoCanceler.html)). Quality varies by OEM and many voice apps add their own AEC ([3P](https://www.forasoft.com/learn/audio-for-video/articles-audio/aec-on-bluetooth-speakerphone-airpods)).
- A real Flutter voice agent reports: recorder uses the voice-communication source with platform AEC/AGC; speaking over the TTS mutes it at once; plus a word-overlap guard (drops segments that merely repeat the assistant), an adaptive noise floor with an SNR gate (+14 dB over floor during playback, +30 dB for the first 500 ms), a 120 Hz high-pass, and "Android's AEC is effectively deaf during its lock-in" ([3P voice-agent README](https://github.com/yundddd/voice-agent)).

**Flutter plugins**

- `record` 7.1.2: README matrix: **echo cancel** and auto gain on Android (not the legacy recorder), iOS, web, macOS; **not Windows**; noise suppression only Android and web ([README](https://raw.githubusercontent.com/llfbandit/record/master/record/README.md)). `vad` says the same limitation for Windows and Linux (section 3.3). Min SDK Android 23, iOS 12, macOS 10.15 ([pub.dev](https://pub.dev/packages/record)).
- `flutter_webrtc` 1.6.2: Android, iOS, Linux, macOS, Windows ([pub.dev](https://pub.dev/packages/flutter_webrtc)). It carries libwebrtc's software audio processing; how to feed a locally played TTS stream in as the far-end reference is **[UNVERIFIED]** from the sources I could open.
- `speech_to_text` sets `.playAndRecord` + `.default` (section 3.1): **no AEC**.

**Windows:** the OS has an AEC control interface (`IAcousticEchoCancellationControl`) that lets a capture client pick the render endpoint used as the reference ([OFFICIAL interface doc](https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nn-audioclient-iacousticechocancellationcontrol)); the Microsoft sample for it states **Windows 11 build 22540 or later** ([OFFICIAL sample](https://learn.microsoft.com/en-us/samples/microsoft/windows-classic-samples/acousticechocancellation), as quoted in a search excerpt). Opening a stream with `AudioCategory_Communications` is reported to enable the communications processing chain ([3P lead](https://git.manko.yoga/manawenuz/wz-phone/src/commit/03a80a31966d5f91d67cc41267ed3eb44798a1a4/crates/wzp-client/Cargo.toml), **[UNVERIFIED]**). No Flutter plugin exposes this.

**Barge-in design that follows from the above [INFERENCE]**

1. **Tier 0, no AEC needed:** half-duplex. While TTS plays, ignore VAD (or require a much higher threshold) and offer a tap / key to interrupt.
2. **Tier 1, headphones:** if the output route is wired/Bluetooth headphones, enable full barge-in (no acoustic path back to the mic).
3. **Tier 2, speakers:** voice processing (iOS/macOS VPIO, Android `VOICE_COMMUNICATION` + AEC), plus the gating tricks above (SNR gate, word-overlap guard, post-TTS cool-down 200-800 ms). Windows: headset-only unless you add a software AEC.

### 3.7 Cloud options (audio leaves the device; keys required)

| Option | Vietnamese | Cost (verified rows) | Privacy and retention | Integration notes |
|---|---|---|---|---|
| **OpenAI GPT-Live** (`gpt-live-1`) | not named on the model page or in the API post ("We'll continue to expand voice options and language availability over the coming months") | **$0.05 per minute, billed per second**; backend model and tools billed separately; WebRTC session creation bills 15 s up front (credited) | `/v1/live/sessions`: 30-day abuse-monitoring retention; session storage off by default; ZDR eligible | WebRTC recommended for browser, mobile, server; your server posts the SDP offer with the project key; 24 kHz PCM16 on WebSocket; concurrency limits 50 / 300 / 500 by tier ([model](https://developers.openai.com/api/docs/models/gpt-live-1), [WebRTC guide](https://developers.openai.com/api/docs/guides/voice-webrtc), [Foundry doc](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/gpt-live)) |
| **OpenAI Realtime** (`gpt-realtime-2.1`, `-mini`) | not stated | audio per 1M tokens: 2.1 in $32 / cached $0.40 / out $64; mini $10 / $0.30 / $20 | `/v1/realtime`: 30-day abuse-monitoring retention, ZDR eligible; API data not used for training by default | ephemeral keys via `POST /v1/realtime/client_secrets`; server VAD / semantic VAD; a Flutter wrapper `openai_webrtc` exists (maintenance unclear) ([pricing](https://developers.openai.com/api/docs/pricing), [data](https://developers.openai.com/api/docs/guides/your-data), [realtime](https://developers.openai.com/api/docs/guides/realtime), [pub.dev](https://pub.dev/packages/openai_webrtc)) |
| **OpenAI STT / TTS** | not stated | `gpt-4o-transcribe` $0.006/min; mini $0.003/min; Whisper $0.006/min; `gpt-4o-mini-tts` $0.60 text-in, $12 audio-out per 1M tokens | transcriptions endpoints: no abuse-monitoring retention; `/v1/audio/speech`: 30 days | same pricing and data pages |
| **Gemini Live** | **Vietnamese `vi` is in the supported-languages table** | Gemini 3.8 Live: audio in $3.00 per 1M tokens (about $0.005/min), audio out $12.00 per 1M (about $0.018/min); Gemini 3.5 Transcribe $0.003/min; Gemini 3.8 Flash TTS $9.00 per 1M audio tokens out (through 2026-12-31) | unpaid quota: inputs/outputs used to improve products, human review possible, "Do not submit sensitive ... information"; paid: not used to improve products, logged for a limited period for abuse detection; EEA / Switzerland / UK must use paid | audio-only sessions limited to 15 min by default; 16 kHz in / 24 kHz out; automatic VAD configurable ([pricing](https://ai.google.dev/gemini-api/docs/pricing), [terms](https://ai.google.dev/gemini-api/terms), [live guide](https://ai.google.dev/gemini-api/docs/live-guide)) |
| **Google Cloud STT v2 / TTS** | STT `vi-VN` on `chirp_3` (eu), `chirp_2`, `chirp`, `long`, `short`; TTS Chirp 3 HD lists `vi-VN` (no custom pronunciations for vi-VN; SSML not supported when streaming) | **STT v2 standard $0.016/min** for the first 500,000 min per month (falling to $0.004 above 2M), dynamic batch $0.003/min, billed per second, no free tier in v2. **TTS per 1M characters:** Standard $4 (4M free), WaveNet $4 (4M free), Neural2 $16 (1M free), Polyglot preview $16, **Chirp 3 HD $30 (1M free)**, Studio $160 | data-logging terms not read | ([STT languages](https://docs.cloud.google.com/speech-to-text/docs/speech-to-text-supported-languages), [Chirp 3 HD](https://docs.cloud.google.com/text-to-speech/docs/chirp3-hd), [STT pricing](https://cloud.google.com/speech-to-text/pricing), [TTS pricing](https://cloud.google.com/text-to-speech/pricing), both read through the text proxy) |
| **Azure AI Speech** | `vi-VN` supports fast transcription (real-time column not visible in the page I could read); TTS voices (official language-support page): Standard neural `vi-VN-HoaiMyNeural` (F) and `vi-VN-NamMinhNeural` (M), plus Neural HD Flash `vi-VN-Linh:MAI-Voice-2-Flash` (F) | **[UNVERIFIED]**: pricing page rendered "$-" | **real-time STT: "audio input is processed only on the Azure's server memory, and no data is stored at rest"; for real-time STT, fast transcription, pronunciation assessment and speech translation "Microsoft does not retain or store the data"**; batch uses your storage; containers can run in your own environment (server-side only) | ([language support](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support?tabs=stt), [privacy](https://learn.microsoft.com/en-us/azure/ai-foundry/responsible-ai/speech-service/speech-to-text/data-privacy-security), [TTS voices tab](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support?tabs=tts)) |

Privacy takeaway [INFERENCE]: **STT is the sensitive hop** (raw voice, speaker identity). Cloud TTS only receives text that the LLM path already sees. A relay that mints short-lived keys keeps vendor keys off phones and desktops; OpenAI's docs describe exactly that flow ("use `POST /v1/realtime/client_secrets` to create ephemeral credentials for browser or mobile clients"). Apple/Google platform recognizers in server mode are also third-party cloud ("likely to stream audio to remote servers").

### 3.8 Recommendation matrix, latency budget, plan, risks, open decisions

#### Speech-to-text and speech-to-speech

| Option | Quality | Latency | Vietnamese | Privacy | Cost | Effort / fit |
|---|---|---|---|---|---|---|
| Platform STT, server mode (`speech_to_text`) | good, vendor cloud [UNVERIFIED for vi] | partial results; Android forced 1-3 s pause; iOS 1-min cap | Apple: yes (dictation list); Android: Gboard lists Vietnamese (Play listing excerpt), recognizer itself [UNVERIFIED] | audio to Apple / Google | free (rate limited) | low; short utterances only; no AEC; Windows beta |
| Platform STT, on-device | lower than server (Apple) | low | iOS 15: not in 2022 list; newer iOS: listed for dictation; Android: unverified | stays on device when it works, fails otherwise | free | low-medium; per-device runtime checks; Android needs API 31+ |
| **sherpa-onnx Zipformer vi + Silero VAD** | strong in publisher benchmarks [3P] | endpoint 0.5-0.8 s + decode (desktop RTF 0.011-0.063; Galaxy S10 3P tests of other small sherpa models RTF 0.05-0.12) | yes, official; no official streaming model | fully on-device | free (Apache-2.0 runtime; model licences to check) | medium; all four platforms; models 26-68 MB int8 |
| whisper.cpp (`whisper_ggml`) | base/small modest for Vietnamese [UNVERIFIED] | about 1 s+ per utterance for base on a phone (iPhone 13 mini CPU 1.09 s encoder); one 3P Galaxy S10 test: tiny at RTF 3.52 | yes (99 languages) | on-device | free | low-medium; big models too slow on phones |
| ML Kit GenAI Speech (Android only, alpha) | classic on-device or Gemini Nano (Pixel 10/11) | streaming partials | `vi-VN` beta | on-device | free | medium (native channel); API 31+; alpha |
| Cloud STT (OpenAI / Google / Azure) | best (vendor claims) | network + vendor | Google, Azure yes; OpenAI unverified | audio leaves device (Azure real-time not stored) | OpenAI $0.003-0.006/min; Google v2 $0.016/min (first tier); Azure unverified | low-medium; keys via relay |
| Realtime speech-to-speech (GPT-Live, gpt-realtime, Gemini Live) | highest smoothness: full-duplex, built-in barge-in | OpenAI claims 320 ms average for GPT-4o | Gemini yes; OpenAI unverified | audio + transcripts to vendor; 30-day abuse logs (OpenAI) | GPT-Live $0.05/min + backend; Gemini about $0.023/min audio in+out | medium (WebRTC, ephemeral keys); vendor model is the "brain" unless you delegate |

#### Text-to-speech

| Option | Quality | Latency | Vietnamese | Privacy | Cost | Effort |
|---|---|---|---|---|---|---|
| `flutter_tts` system voices | [UNVERIFIED], no MOS found | low | Android Google/Samsung; iOS/macOS listed by Apple; Windows unknown | on-device | free | low |
| sherpa-onnx Piper vi voices | "tiny and fast, struggle with tongue twisters" (ViTTS-Bench) | fast | yes (3 voices) | on-device | free; dataset licences unverified | low once sherpa is in |
| sherpa-onnx Supertonic 3 vi | no independent MOS; 10 speakers, 24 kHz | RTF 0.3 on an e-reader (vendor) | yes | on-device | weights OpenRAIL-M; **repo archived** | low |
| Cloud TTS (Azure HoaiMy / NamMinh, Google Chirp 3 HD, Gemini, OpenAI) | best | network | Azure, Google yes; Gemini TTS / OpenAI unverified | only text leaves the device | per character / token | low |

#### VAD and AEC picks

- **VAD:** Silero, through sherpa-onnx's built-in VAD if you adopt sherpa (one dependency), else `vad` (all six platforms) or `vad_plus` (mobile + macOS only, lighter).
- **AEC:** iOS/macOS voice-processing engine path (custom native code; plugins do not provide it), Android `VOICE_COMMUNICATION` + platform AEC via `record` `echoCancel`, Windows headset-only or a software AEC. Plan on the three barge-in tiers in 3.6.

#### Latency budget [INFERENCE from sourced numbers]

| Stage | Budget | Evidence |
|---|---|---|
| Endpoint (end-of-speech) | 500-800 ms | OpenAI `server_vad` 500 ms; Gemini 500-800 ms; `vad_plus` 768 ms |
| ASR final decode | 50-300 ms on desktop for 3-4 s of speech; phone: RTF 0.05-0.12 on a 2019 Galaxy S10 for other small models means about 0.2-0.5 s for 4 s of speech [INFERENCE] | sherpa docs RTF 0.011-0.063; 3P voiceping.net |
| LLM first token through your relay | not researched | |
| TTS first audio | start on the first sentence; Piper "tiny and fast"; Supertonic RTF 0.3 on an e-reader | ViTTS-Bench, Supertone |
| Total to first audible word | target about 1.5-2 s; ChatGPT's bar is about 0.3 s | OpenAI Hello GPT-4o claim |

#### Recommended plan [INFERENCE]

1. **Phase 0 (prove the UX):** tap-to-talk with VAD endpointing, `speech_to_text` (explicit consent, server mode) or sherpa, `flutter_tts`, half-duplex with a tap-to-interrupt button. No AEC work.
2. **Phase 1 (true on-device, one engine on four platforms):** sherpa-onnx for VAD + Vietnamese Zipformer ASR + Piper/Supertonic TTS; English via a sherpa English model; model download manager and per-device self-test; platform STT as fallback.
3. **Phase 2 (barge-in):** voice-processing capture path per platform, SNR gate, word-overlap guard, cool-down; headphones tier first.
4. **Phase 3 (optional, opt-in):** cloud realtime (GPT-Live, gpt-realtime or Gemini Live) with ephemeral keys minted by the relay and an always-visible "cloud voice" indicator.

#### Risks

1. Vietnamese on-device accuracy and **Vietnamese-English code-switching** are unmeasured on phones (a Vietnamese medical code-switching benchmark exists but I did not read it).
2. No published phone RTFs for the Vietnamese sherpa models (only third-party numbers for other small models on a 2019 phone); thermal and battery are unknown.
3. Model and voice licences (Supertonic OpenRAIL-M, Piper dataset terms, Zipformer weights) not cleared; Supertonic is archived.
4. App size: ASR 26-68 MB + TTS + English models, delivered by download.
5. AEC varies by device (Android OEMs, macOS Spatial Audio/Bluetooth) and Windows has no plugin-level AEC.
6. iOS audio-session conflicts between `speech_to_text`, `flutter_tts`, `record`/`vad`: pick one owner of the session.
7. Platform STT limits (iOS 1 min, per-day throttles; Android 1-3 s pause) force restart loops and audible beeps on Android.
8. Cloud paths need App Store / Play privacy disclosures and key management.

#### Open decisions for you

1. Is a 100-200 MB on-device speech pack (downloaded on demand) acceptable?
2. Is cloud realtime allowed as an opt-in mode, and may the relay mint its keys?
3. Barge-in scope for v1: headphones only, or speakers with AEC?
4. Vietnamese TTS quality bar and who runs the native-listener test.
5. Vietnamese-English mixing: one multilingual model, or a language switch in the UI?
6. Whether to build a thin native audio engine (VPIO on Apple, AAudio/Oboe or `AudioRecord` on Android) or stay inside existing plugins.

---

## 4. "Online Bike Shopping App" (Figma Community file)

### 4.1 Provenance, and what I could and could not open

- **Your link** `https://www.figma.com/design/QgQsGtshcpfstl001CslNB/Online-Bike-Shopping-App--Community-?node-id=1-4` is a private copy. WebFetch returned only the word "Figma" (a script shell or login gate), so **the file itself was not read.** The port author's README links yet another key, `D8e9p9L3AeUfNnsIvRzMcy` (node `1:4`), also named "(Community)" ([README](https://raw.githubusercontent.com/savykevin100/Online-Bike-Shopping-App/HEAD/README.md)); that suffix suggests both are duplicates of the Community file, whose public page id is `1149336740234053658`. I could not see the original file key.
- **Public Community page:** <https://www.figma.com/community/file/1149336740234053658/online-bike-shopping-app>. A direct fetch returned 403; I read it through a text proxy ([r.jina.ai render](https://r.jina.ai/https://www.figma.com/community/file/1149336740234053658/online-bike-shopping-app)). Facts from it **[3P rendering of an OFFICIAL page]**:
  - Title "Online Bike Shopping App"; author **Sourasith** (`figma.com/@sourasithp`); tags Ecommerce, Shopping, Mobile UI; hashtags #app design, #dark mode, #matte, #neumorphism, #onlinebikeshopapp, #softui, #ui design.
  - Description: "Hi guys! I'm back with another beautiful design, an Online Bike Shopping App. Watch my course on Youtube if you want to learn how to create this beautiful design using the Neumorphism style with a Matte effect."
  - "Last updated 4 years ago"; **"Licensed under CC BY 4.0"**; the page shows "2.3k" and "125k users" (labels not visible, so unclear which is likes and which is views or duplicates) and 28 comments. Two comments praise "only 4 colors" and "the colors and gradients"; none name fonts or plugins.
- **Course:** Design+Code, "UI Design Quick Apps in Figma", lessons "Bike Shopping App Part 1 - Discover Screen", "Part 2 - Detail Screen", "Part 3 - Cart Screen"; one lesson page is dated 2022-02-28; instructor listed as Sourasith Phomhome ([course page](https://designcode.io/quick-apps-figma-bike1/), [Design+Code index](https://designcode.io/quick-apps-figma)). **The lesson bodies did not render, so no values from the course were read.**
- **YouTube course video:** "Figma UI Design Course - Create a Bike Shopping App", DesignCode channel, published 2022-09-13, about 119.6k views when captured; chapters Intro 0:00, First screen 1:48, Second screen 14:27, Third screen 22:49; the description calls it "a unique app UI in dark mode with angled shapes, glass layers and neumorphic buttons in Figma" and links the Community file id `1149336740234053658` ([video](https://www.youtube.com/watch?v=2C2sxQ4hiS8), read through the text proxy). It names no fonts, hex colours or plugins; I could not get the transcript, which is where such values would be spoken.
- **Dribbble:** [Bike Shopping App by Sourasith](https://dribbble.com/shots/20825961-Bike-Shopping-App), tags bikeapp, bikeshoppingapp, darkmode, design, figma, glassmorphism, neumorphism, ui, uidesign, uiux; described as a dark-mode UI "with angled shapes, layered glass effects, and neumorphic buttons" (proxy summary of the page).
- **Images I viewed:** Community cover 1920x960 (`s3-alpha.figma.com/hub/file/2344173673/b242ed93-0bf1-4666-9669-f500865cc360-cover.png`, needs a Figma referer header) and the two 3200x2400 Dribbble shots (`cdn.dribbble.com/userupload/5115982/...`, `.../5116034/...`). Local copies for visual reference only (third-party artwork, do not ship): `/private/tmp/claude-501/-Users-richard-Documents-helper-shellx/c68aea52-eaaf-4b45-9a7d-989a8fedf901/scratchpad/dl-bike-figma-dribbble/` (`figma_cover.png`, `dribbble_1.png`, `dribbble_2.png`).
- **A public Flutter port of this exact design:** [savykevin100/Online-Bike-Shopping-App](https://github.com/savykevin100/Online-Bike-Shopping-App) ("a demonstration of designing an advanced user interface with Flutter ... clip paths, animations and transforms"). Its constants are the author's reading of the design, **not Figma tokens**, but they match my pixel samples of the artwork closely (below). Local copy of the files and its preview screenshots: `.../scratchpad/dl-bike-repo/`. I did not check the repo's licence **[UNVERIFIED]**.
- **To get exact Figma values** you would need to authenticate the Figma tools available in this environment (`mcp__plugin_figma_figma__*`) against your own copy and read variables/design context. I did not attempt that.

### 4.2 Style summary

- **Dark only** (the Community tag is "dark mode"): deep navy surfaces (`#222834` to `#242C3B`) with **neumorphic raised and inset elements** (a dark shadow bottom-right plus a lighter shadow top-left on the same navy), **frosted-glass product tiles** over a vivid blue gradient, and **angled / skewed shapes**: a diagonal blue "wedge" behind the content, product tiles with a slanted top edge, category chips stepping diagonally.
- **One gradient family carries all emphasis:** cyan to indigo (`#34C8E8` to `#4E4AF2`) on buttons, chips, search and active tab; azure to royal blue (`#3CA4EB` to `#4286EE`) on text labels and wedge; price and total in azure (`#3D9CEA`, `#38B8EA`). Commenters say "only 4 colors".
- **Marketing presentation:** tilted, exploded phones on a pale blue-grey backdrop (sampled `#E3EAF3` at top-left to `#C8D4E4` at bottom-right).
- **Screens:** Discover ("Choose Your Bike", gradient search button, "30% Off" promo card, chips, two-column staggered product grid, bottom tab bar), Detail (wedge, image carousel with dots, Description / Specification segmented tabs, price + "Add to Cart" bar), Cart ("My Shopping Cart", line items with +/- steppers, promo field with code "Bike30" and "Apply", subtotal / delivery / discount / total, "Checkout" slider).

### 4.3 Tokens

**Colours** (P = from the Flutter port's `colors.dart` and screens; S = my 5x5-pixel sample of the Dribbble artwork `dribbble_2.png`, original-pixel coordinates, approximate because of lighting and gradients)

| Token | Hex | Source |
|---|---|---|
| Scaffold / page background | `#222834` | P `black70` |
| Cart screen background | `#242C3B` | P `black50`; S measured `#242C3B` (exact) |
| Card gradient / bottom sheet gradient | `#353F54` to `#222834` | P |
| Description card, selected tab fill | `#323B4F` | P |
| Bottom price bar, minus button | `#262E3D` | P; S detail sheet `#242B38` |
| Inactive tab | `#28303F` | P |
| Glass card fill | `#363E51` to `#191E26`, both at 60% opacity | P (`ContainerShapePainter`, `CurvePainter`) |
| Glass card border | promo card: 2 px gradient, white 20% to black 20%; product tiles: 2 px stroke in the same colours as their fill | P |
| Primary (indigo) | `#4B4CED` | P |
| Secondary (cyan) | `#37B6E9` | P |
| **Button / chip / search gradient** | `#34C8E8` to `#4E4AF2` (top-left to bottom-right) | P; S search button `#39AFE7` to `#456BE5`, "All" chip `#34ADDA` to `#4056CA` |
| Text / tab-label gradient | `#3CA4EB` to `#4286EE` | P; S "Add to Cart" `#3BA3EA` to `#4281ED` |
| Diagonal wedge | top `#3BA2EA`, bottom `#3C65CF` (deepening toward indigo) | S |
| Price text | `#3D9CEA` | P |
| Cart total | `#38B8EA` | P |
| Secondary text | white 60% (`#99FFFFFF`); labels white 87%; titles white 100% | P |
| Divider | white 20% | P |
| Promo card (Discover) | `#2C3547` | S |
| Helmet tile (glass over wedge) | `#2D4579` | S |
| Backdrop (marketing shot) | `#E3EAF3` to `#C8D4E4` | S |

Contrast (WCAG, computed by me): white 100% on `#222834` 14.8:1; white 87% 11.5:1; white 60% 6.3:1; price `#3D9CEA` on `#262E3D` 4.6:1; **white labels on the cyan end of the gradient are only 2.0-2.8:1** (`#34C8E8` 2.0, `#39AFE7` 2.5, `#3BA3EA` 2.8) and 3.8-5.9:1 on the indigo end. Keep button text bold and 16 px or larger, or darken the cyan stop.

**Fonts.** The port sets `fontFamily: 'Poppins'` in its theme and declares Poppins Bold 700, SemiBold 600, Regular (mapped to 500) and Medium (mapped to 400); Inter files are in `assets` but not declared ([pubspec](https://raw.githubusercontent.com/savykevin100/Online-Bike-Shopping-App/HEAD/pubspec.yaml)). The artwork typography looks like Poppins (geometric sans, bold titles, light body). **The Figma file's own font is [UNVERIFIED].** Sizes in the port: screen title 20 Bold; product name 16 Bold; category and price 15 Medium at 60% white; promo "30% Off" 26 Bold at 60% white; detail title 17 Bold; body 15 Regular at 60% white; detail price 24 Regular; buttons 15 Medium; cart item name 20 Bold; summary labels 16 Medium; total 17 Bold. **Poppins lacks Vietnamese letters** (section 1.4): swap to Be Vietnam Pro, Plus Jakarta Sans, Montserrat or Inter, which all have the Vietnamese subset.

**Corner radii (P).** 10 (search, back, "All"/chips, gradient buttons, checkout knob), 8 (stepper buttons, promo field), 15 (Description / Specification tabs), 20 and 30 (custom-path product tile and promo card corners), 30 (cart thumbnail), **50 (bottom sheet and price bar)**, 5 (active carousel dot, 9 x 9). Default page margin 15.

**Shadows and neumorphism (P)**

| Element | Fill | Shadows |
|---|---|---|
| Selected tab "Description" | `#323B4F` | `#252B39` offset (4, 4) blur 10, plus `#38445A` offset (-4, -4) blur 10 |
| Inactive tab | `#28303F` | `#202633` offset (4, 4) blur 8 |
| Price bar | `#262E3D` radius 50 | `#1C222E` offset (0, -10) blur 40 |
| Gradient button ("Add to Cart", "Apply", steppers) | gradient | glow `#1A1F2C` offset (0, 30) blur 60 |
| Checkout track | `#242C3B` radius 10 | `#11161E` offset (4, 4) blur 30, plus `#2B3545` offset (-2, -2) blur 8 |
| Promo field | `#242C3B` radius 8 | `#191E29` offset (4, 10) blur 30 |

**Glassmorphism.** The artwork's glass tiles are translucent with a visible background blur and a light edge. The port fakes it with 60%-opacity gradient fills and a 2 px gradient stroke, **without a blur** (no `BackdropFilter`). Whether the Figma file uses background blur (the Dribbble tag says glassmorphism) is **[UNVERIFIED]** until the file is opened.

### 4.4 Signature components (and how the port builds them)

- **Diagonal wedge background:** SVG shapes (`Rectangle 474.svg` bottom-right on Discover, `Rectangle 476.svg` top-right on Detail) painted under the content (`flutter_svg`).
- **Skewed glass cards:** `CustomPainter` paths with quadratic curves; the product tile top edge slopes from left to right; the promo card is 270 px high.
- **Category chips:** a horizontal list rotated -6 degrees (`-pi/30`) with each chip counter-rotated, so chips sit on a rising diagonal; widths 50, heights 50, 30 px spacing, bottom margin `index * 3`. The selected chip uses the cyan-indigo gradient, others the glass gradient.
- **Product grid:** two columns, aspect ratio 0.55, 20 px gap, alternate tiles offset by +30 / -30 px (staggered); heart icon (outline or gradient-filled SVG) at the top-right of each tile; small category label (60% white), bold name, price.
- **Tab bar:** five SVG icons (bicycle, map, person, cart, document; grey when inactive). The **active item is a floating 60 x 60 gradient tile with a slanted top** raised above the bar. Bar height 100, content area 70.
- **Detail screen:** carousel (enlarged centre page) with dots; a bottom sheet that grows from 100 to 500 px over 3 s (`fastOutSlowIn`) while the image area shrinks from 300 to 200; Description / Specification segmented control; price bar with gradient "Add to Cart".
- **Cart:** thumbnails 120 x 110 with radius 30 and a light-to-black gradient (the port's start colour is the literal `0xffFFFF`, which Dart reads as cyan `#00FFFF` at 20% opacity, an author slip; black 60% at the end); +/- steppers 30 x 30 (plus = gradient, minus = flat `#262E3D`); promo field with "Apply" button; **slide-to-confirm "Checkout"** (gradient knob slides across a neumorphic track over 2 s, then navigates).
- **Motion:** page route cross-fade 1 s; the port's durations are long (2-3 s) and look like demo values, not design requirements.
- **Product images:** background-removed cut-outs placed on the tiles.

### 4.5 Caveats for reuse

1. The Figma Community file is **CC BY 4.0**: reuse needs attribution. Dribbble images, the course material and the Unsplash photos used in the port carry their own rights.
2. Dark-only: a light theme would need new values (the pale backdrop is a presentation colour, not an app surface).
3. Accessibility: gradient labels on cyan fail AA (above); 60%-white secondary text passes (6.3:1); inactive grey icons (`#808080`) are 3.7:1.
4. Vietnamese text: do not use Poppins; pick a Vietnamese-capable geometric sans.
5. The port is a demo: heavy `CustomPaint` with `shouldRepaint => true`, long animations; rebuild the shapes as reusable `ShapeBorder` / `ClipPath` widgets if you adopt the look.

---

## 5. Source index

**Topic 1: Claude desktop**
- Desktop docs: <https://code.claude.com/docs/en/desktop>, <https://code.claude.com/docs/en/desktop-quickstart>
- Redesign blog (2026-04-14): <https://claude.com/blog/claude-code-desktop-redesign>
- Desktop changelog: <https://claude.com/docs/cowork/changelog.md>; release notes: <https://support.claude.com/en/articles/12138966-release-notes>
- Unified Claude: <https://claude.com/docs/third-party/claude-desktop/unified-claude.md>; Cowork projects: <https://claude.com/docs/cowork/guide/projects.md>; Cowork overview: <https://claude.com/docs/cowork/overview.md>
- Claude Code Projects: <https://code.claude.com/docs/en/claude-projects>; cloud sessions: <https://code.claude.com/docs/en/claude-code-on-the-web>; Remote Control: <https://code.claude.com/docs/en/remote-control>
- Appearance settings: <https://support.claude.com/en/articles/8887527-customizing-your-appearance-settings>
- Brand skill (hex, fonts): <https://raw.githubusercontent.com/anthropics/skills/main/skills/brand-guidelines/SKILL.md>
- Third-party extractions: <https://fudge.design/tokens/claude.ai>, <https://oh-my-design.kr/design-systems/claude>, <https://www.shadcn.io/design/anthropic>, <https://type.today/en/journal/anthropic>, <https://www.itworkslocally.co.uk/blog/claudes-default-font-is-a-problem-heres-how-to-change-it>, <https://github.com/anthropics/claude-code/issues/85636>
- Third-party UI notes: <https://www.weloveclaude.com/features/chat-composer>, <https://www.testingcatalog.com/anthropic-tests-new-placement-for-projects-on-claude-desktop/>, <https://alphasignal.ai/news/anthropic-s-claude-code-now-runs-nested-sessions-and-saves-dev-environments>, <https://www.assistant-ui.com/examples/claude>
- Font subsets: <https://gwfh.mranftl.com/api/fonts/lora> (and `/poppins`, `/source-serif-4`, `/inter`, `/be-vietnam-pro`, `/newsreader`, `/literata`, `/fraunces`, `/crimson-pro`, `/plus-jakarta-sans`, `/lexend`, `/montserrat`, `/manrope`, `/jetbrains-mono`, `/dm-sans`)

**Topic 2: ChatGPT voice**
- OpenAI (403 to direct fetch; read through the text proxy `https://r.jina.ai/<url>`): <https://openai.com/index/hello-gpt-4o/>, <https://openai.com/index/introducing-gpt-live/>, <https://openai.com/index/continuous-voice-interaction-with-gpt-live/>, <https://openai.com/index/introducing-gpt-live-1-in-the-api/>, <https://help.openai.com/en/articles/8400625-voice-mode-faq>, <https://help.openai.com/en/articles/6825453-chatgpt-release-notes>
- OpenAI developer docs (fetched): <https://developers.openai.com/api/docs/guides/realtime-vad>, <https://developers.openai.com/api/docs/api-reference/realtime-calls/accept-call>, <https://developers.openai.com/api/docs/pricing>, <https://developers.openai.com/api/docs/guides/your-data>, <https://developers.openai.com/api/docs/guides/realtime>, <https://developers.openai.com/api/docs/guides/voice-webrtc>, <https://developers.openai.com/api/docs/models/gpt-live-1>
- Coverage: <https://techcrunch.com/2025/11/25/chatgpts-voice-mode-is-no-longer-a-separate-interface/>, <https://www.thurrott.com/a-i/330108/chatgpts-voice-mode-is-now-built-into-chat-conversations>, <https://mundobytes.com/en/chatgpt-finally-integrates-voice-mode/>, <https://www.phonearena.com/news/chatgpt-voice-mode-is-accessible-in-chat_id176082>, <https://felloai.com/chatgpt-advanced-voice-mode-everything-you-need-to-know/>, <https://gptprompts.ai/chatgpt-voice-mode-guide>, <https://toolchase.com/blog/chatgpt-voice-mode-guide/>, <https://www.digitalapplied.com/blog/openai-gpt-live-voice-models-customer-experience-2026>, <https://dev.to/alifar/openai-gpt-live-brings-continuous-voice-conversations-to-chatgpt-at-scale-3608>, <https://hungrymindsdev.substack.com/p/how-openai-built-gpt-live-for-low>, <https://gigazine.net/gsc_news/en/20260804-openai-gpt-live/>, <https://www.datacamp.com/tutorial/gpt-live-1-api>, <https://www.techradar.com/ai-platforms-assistants/chatgpt/chatgpts-new-voice-integration-feels-like-the-missing-piece-in-ai-chat-ive-tried-it-and-its-almost-perfect>, <https://www.engadget.com/2230975/how-to-use-chatgpt-voice-mode/>, <https://www.pcworld.com/article/2649338/chatgpt-now-speaks-even-more-naturally-with-fewer-interruptions.html>, <https://community.openai.com/t/synchronized-transcript-for-read-aloud-and-voice-mode/1391540>, <https://cognitionandculture.net/blogs/icci-blog/universals-and-cultural-variation-in-turn-taking-in-conversation>

**Topic 3: Flutter voice**
- Apple (data endpoint): `https://developer.apple.com/tutorials/data/documentation/speech/sfspeechrecognizer.md`, `.../speech/sfspeechrecognizer/supportsondevicerecognition.md`, `.../speech/sfspeechrecognitionrequest/requiresondevicerecognition.md`, `.../speech/speechtranscriber.md`, `.../speech/speechanalyzer.md`, `.../avfaudio/avaudiosession/mode-swift.struct/voicechat.md`, `.../avfaudio/avaudioionode/setvoiceprocessingenabled(_:).md`, `.../avfaudio/avaudioinputnode/voiceprocessingotheraudioduckingconfiguration.md`, `.../avfaudio/avspeechsynthesizer/write(_:tobuffercallback:).md`, `.../avfaudio/avspeechsynthesisvoice.md`; availability page <https://www.apple.com/ios/feature-availability/>
- Android: <https://developer.android.com/sdk/api_diff/31/changes/android.speech.SpeechRecognizer>, <https://developer.android.com/sdk/api_diff/33/changes/android.speech.SpeechRecognizer>, <https://developer.android.com/sdk/api_diff/33/changes/android.speech.RecognizerIntent>, <https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/speech/SpeechRecognizer.java>, <https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/speech/RecognizerIntent.java>, <https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android12-release/core/java/android/speech/SpeechRecognizer.java>, <https://developers.google.com/ml-kit/genai/speech-recognition/android>, <https://stuff.mit.edu/afs/sipb/project/android/docs/reference/android/media/audiofx/AcousticEchoCanceler.html>
- Packages: <https://pub.dev/packages/speech_to_text> (+ <https://raw.githubusercontent.com/csdcorp/speech_to_text/main/speech_to_text/README.md>, the Swift and Kotlin sources linked in 3.1), <https://pub.dev/packages/flutter_tts>, <https://pub.dev/packages/vad>, <https://github.com/781flyingdutchman/vad_plus>, <https://pub.dev/packages/sherpa_onnx>, <https://github.com/k2-fsa/sherpa-onnx/tree/master/flutter-examples>, <https://pub.dev/packages/whisper_ggml>, <https://pub.dev/packages/record>, <https://raw.githubusercontent.com/llfbandit/record/master/record/README.md>, <https://pub.dev/packages/flutter_webrtc>
- sherpa docs: <https://k2-fsa.github.io/sherpa/onnx/pretrained_models/offline-transducer/zipformer-transducer-models.html>, <https://k2-fsa.github.io/sherpa/onnx/tts/all/Vietnamese/index.html>, <https://k2-fsa.github.io/sherpa/onnx/tts/all/Vietnamese/supertonic-3-vi.html>, <https://github.com/supertone-inc/supertonic>, <https://github.com/yoonjae26/vietnamese-tts>, <https://github.com/yundddd/voice-agent>
- Accuracy and latency: <https://voiceping.net/en/blog/research-offline-speech-transcription-benchmark/>, <https://huggingface.co/g-group-ai-lab/gipformer1.5-68M-rnnt>, <https://arxiv.org/pdf/2406.02555>, <https://alphacephei.com/vosk/models>, <https://github.com/ggml-org/whisper.cpp/discussions/89>, <https://github.com/ggml-org/whisper.cpp>, <https://arxiv.org/abs/2507.10860>, <https://www.argmaxinc.com/blog/apple-and-argmax>
- AEC field notes: <https://barock.dev/2026/04/22/why-your-ios-voice-agent-still-hears-itself>, <https://community.openai.com/t/audio-notes-for-openai-realtime-on-apple-platforms/1108404>, <https://www.forasoft.com/ship-log/spatial-audio-vpio>, <https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nn-audioclient-iacousticechocancellationcontrol>
- Platform STT locale evidence: <https://medium.com/@toru_furuya/available-languages-in-on-device-speech-recognition-on-ios-in-2022-8c6383fac9f2> (via r.jina.ai), <https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide>, <https://loronote.com/en/blog/apple-speechanalyzer-vs-whisper>, <https://dev.to/tbds_2dadf2b626f315902eae/on-device-speech-recognition-on-ios-the-honest-boundaries-1ndn>
- Cloud: <https://ai.google.dev/gemini-api/docs/live-guide>, <https://ai.google.dev/gemini-api/docs/pricing>, <https://ai.google.dev/gemini-api/terms>, <https://docs.cloud.google.com/speech-to-text/docs/speech-to-text-supported-languages>, <https://docs.cloud.google.com/text-to-speech/docs/chirp3-hd>, <https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support?tabs=stt>, <https://learn.microsoft.com/en-us/azure/ai-foundry/responsible-ai/speech-service/speech-to-text/data-privacy-security>, <https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/gpt-live>, <https://cloud.google.com/speech-to-text/pricing>, <https://cloud.google.com/text-to-speech/pricing>

**Topic 4: Bike app**
- Community page (proxy): <https://r.jina.ai/https://www.figma.com/community/file/1149336740234053658/online-bike-shopping-app>; video: <https://www.youtube.com/watch?v=2C2sxQ4hiS8>; Dribbble: <https://dribbble.com/shots/20825961-Bike-Shopping-App>, <https://dribbble.com/SourasithDesign>; course: <https://designcode.io/quick-apps-figma-bike1/>
- Public Flutter port: <https://github.com/savykevin100/Online-Bike-Shopping-App> (files `lib/core/colors.dart`, `lib/main_screen.dart`, `lib/details_screen.dart`, `lib/checkout_screen.dart`, `lib/painters/*.dart`, `pubspec.yaml`)

**Local artefacts (scratchpad, not in the repo):** `.../scratchpad/dl-bike-repo/` (port source + previews), `.../scratchpad/dl-bike-figma-dribbble/` (cover + Dribbble shots), `.../scratchpad/dl-poppins-font/` (Poppins TTFs), `.../scratchpad/scripts/` (PNG sampler, cmap check, contrast calculator).
