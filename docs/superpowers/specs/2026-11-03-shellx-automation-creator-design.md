# ShellX Automation Creator — design

Date: 2026-11-03 · Branch: `feat/shellx-automation-creator` (from `develop`)
Mockup: `.superpowers/brainstorm/11841-1793674974/content/creator-layout.html` (local, not committed)

## Intent

A ShellX user should be able to say in plain words what they want automated and get a
correctly formatted Claude Code **skill**, **workflow** or **cronjob** without knowing
any file format, then see and manage everything they made in one place inside ShellX,
and hear back from it (Mac and iPhone) when it finishes, fails or needs them.

ShellX becomes the single home for these automations: create, view, edit, delete, run,
and receive their notifications. Claude Code is both the assistant that drafts them
and the engine that runs them (decided by the user).

## Terms (user-confirmed)

- **Skill**: a Claude Code skill, `~/.claude/skills/<name>/SKILL.md` with YAML
  frontmatter (`name`, `description`) and a markdown body. Invoked by Claude Code.
- **Cronjob**: a Claude Code run on a schedule on this Mac, e.g. "8:00 every day,
  summarize new PRs in repo X".
- **Workflow**: an ordered chain of steps run by Claude Code one after another.
- **Notification**: when an automation finishes, fails or needs a decision, ShellX
  shows a Mac notification and pushes to the user's paired iPhone.

## Goals

1. An animated entry button at the top of the left sidebar.
2. A creator screen: chat with Claude Code on the left, a live draft on the right over
   a colorful animated perspective grid.
3. The assistant always asks whether and how the user wants to be notified.
4. Output is always in the correct format (modeled on Anthropic's skill-creator skill).
5. A management view listing all automations with add, edit, delete (plus run now and
   enable/disable for cronjobs and workflows).
6. Cronjobs run even when ShellX is not open.

## Non-goals (v1)

- Running automations on remote machines or in the cloud.
- Sharing automations between users or syncing them across Macs.
- Editing automations from the iPhone (iPhone only receives pushes in v1).
- Windows support (Windows build is a separate track).
- Plugin/marketplace skills: shown read-only, not editable.

## Anti-goals

- Producing a skill/cronjob that looks fine in ShellX but Claude Code cannot load or
  that silently never runs. Format validity and "did it actually run" are the product.
- A loud UI: no gradient-filled buttons; colors stay soft (primary `#60a5fa`,
  running = yellow), the motion lives in the border ring and the grid pulses only.
- Requiring an API key: the creator uses the user's existing Claude Code login.
- Touching the user's other launchd jobs or skills that ShellX did not create without an
  explicit, confirmed action.

## Constraints

- App code is Swift (AppKit + SwiftUI), must stay Swift 6.0 compatible
  (`skills/cmux-architecture/references/swift-6-0-compatibility.md`).
- All user-facing strings localized (`skills/cmux-localization`), English + Vietnamese.
- Typing-latency rules apply to the sidebar (`skills/cmux-debugging`): the animated button
  must not invalidate sidebar rows or the terminal on each frame.
- Never quit or relaunch the running ShellX (`/Applications/ShellX.app`); verify in a
  tagged build or via throwaway snapshot tests (see memory: local visual check).
- Relay deploys and app releases need the user's explicit OK.

## Existing pieces to build on (from recon)

| Need | Existing code |
| --- | --- |
| Sidebar top area | `Sources/ShellX/Sidebar/SidebarBrandHeaderView.swift`, `ShellXSidebarHeaderRow.swift` (non-workspace rows at the top of the AppKit table) |
| Headless Claude with streaming | `Sources/Panels/AgentSessionProvider.swift:38` (`claude -p --output-format stream-json --input-format stream-json --include-partial-messages --verbose`), `AgentSessionOwnedProcessLauncher.swift` |
| Mac notification from a CLI | `shellx notify` → socket `notification.create_for_target` → `TerminalNotificationStore` |
| iPhone push | `feed.push` → `ShellXPhonePushForwarder` → shellx-core `notify.phones` → relay `POST /v2/notifications` (accepts only `needs_you` / `resolved`) → APNs |
| Panels / split layout | `Sources/Panels/*`, `RightSidebarMode.swift`, `DockSplitStore.swift` |
| Scheduling | none exists |
| Skill listing | `TextBoxMentionIndexStore.swift` indexes skill roots (read-only) |

## The design

### 1. Sidebar button

- A row directly under the brand header in the sidebar table: `✦ Automations`
  (vi: `✦ Tự động hoá`), trailing count badge of automations.
- Animation: a thin conic multicolor ring (blue → violet → pink → amber → green) rotating
  slowly (~4 s/turn) around the button, and a gentle twinkle on the ✦ glyph. Fill stays
  the normal sidebar row color. Implemented as a self-contained layer (CAShapeLayer /
  CAGradientLayer with a mask) so it never invalidates the table.
- Honors "Reduce Motion": ring static, no twinkle.
- Clicking opens the Automations surface (section 2) in the current window as a panel
  tab, focused on the list if any exist, otherwise straight into the creator chat.

### 2. Automations surface

One panel with two states: **List** and **Creator**.

**List (management view)**
- Filter tabs: All · Skills · Workflows · Cronjobs. `+ New` button opens Creator.
- Each card: type badge, name, one-line description; for cronjobs the human schedule
  ("8:00 every day"), next run, last run result (ok / failed / running in yellow);
  notification targets (Mac / iPhone icons).
- Actions per card: Run now, Enable/Disable (cronjob, workflow), Edit, Delete,
  Reveal in Finder, Open log (last run output).
- **Edit (user decision)** reopens the Creator chat seeded with the current files
  ("start from this file" prompt; no transcripts stored) so the user can say "move it
  to 9:00". A secondary **Edit file** action opens `SKILL.md` / `automation.json` in a
  text editor directly. Same for "Your other skills".
- Delete asks for confirmation and removes the files and any launchd job.
- Skills found in `~/.claude/skills` that ShellX did not create are listed in a
  "Your other skills" group, with edit and delete allowed after a confirmation that says
  ShellX did not create it.

**Creator (chat + live draft)** — matches the mockup:
- Left (~42 %): chat transcript and input. Input row has a type picker
  (Auto · Skill · Workflow · Cronjob, default Auto).
- Right: perspective grid canvas (vanishing point at ~52 % height, faint white lines,
  slowly moving horizontals) with colored light pulses (6 soft colors) traveling along
  the lines. Over it, a draft card that fills in field by field as the assistant learns
  things: type, name, schedule (human + cron), working directory, notifications, steps,
  and the generated `SKILL.md` text typing in. Status: "drafting…" → "✓ ready".
- The grid animation keeps running while the assistant is working and slows to a calm
  idle when waiting for the user. Reduce Motion → static grid.
- When the draft is ready: buttons **Save** and **Keep editing**. Save writes files,
  installs the schedule, returns to the List with the new card highlighted.
- Theme: follows the ShellX theme (light and dark).

### 3. The creator assistant

- Runs Claude Code headless via the same mechanism as `AgentSessionProvider`, with a
  ShellX system prompt appended (`--append-system-prompt`), working directory = a
  scratch dir under the automation store.
- The system prompt is adapted from Anthropic's `skill-creator` skill (Apache-2.0;
  keep its license notice in the bundled resource): capture intent, ask clarifying
  questions one at a time, write a precise `description` that says when to trigger,
  keep `SKILL.md` lean, put long material in `references/`.
- ShellX additions to the prompt: decide the type (skill / workflow / cronjob) or ask;
  for cronjobs ask schedule, working directory and allowed tools; **always ask about
  notifications** (when: finished / failed / needs you / never; where: Mac / iPhone).
- Quick-reply chips: the assistant can offer choices that render as tappable chips
  (as in the mockup). Mechanism: the assistant emits a structured block; ShellX renders
  it and sends the chosen text back as the user's message.
- Live draft: the assistant emits the current draft as a structured JSON block
  (`shellx-draft`) whenever it changes; ShellX parses the latest one to drive the right
  panel. The final draft is what Save writes. The text the user sees in chat excludes
  these blocks.
- Validation before Save (ShellX-side, not the model): frontmatter parses, `name` is
  kebab-case and unique, `description` non-empty and under 1024 chars, cron expression
  valid, working directory exists, `claude` binary resolvable. Failures shown inline on
  the draft card and sent back to the assistant to fix.

### 4. Storage

- **Skill** → `~/.claude/skills/<name>/SKILL.md` (+ optional `references/`), the location
  Claude Code loads. ShellX marks it as its own via a metadata file
  `~/.claude/skills/<name>/.shellx.json` (id, type, notifications, created/updated).
- **Cronjob / workflow** → `~/.shellx/automations/<id>/`:
  - `automation.json`: id, name, type, schedule, working dir, notification settings,
    enabled, steps (workflow), allowed tools / permission mode.
  - `SKILL.md`: the instructions Claude Code runs (workflow: one step per section or a
    `steps` array of prompts in `automation.json`).
  - `runs/<timestamp>/` with `output.jsonl`, `result.json` (status, duration, summary).
- The List reads both locations; the store is the source of truth, the UI only reflects it.

### 5. Running cronjobs (and workflows)

- Each enabled cronjob gets a user LaunchAgent
  `~/Library/LaunchAgents/pro.shellx.automation.<id>.plist` with
  `StartCalendarInterval` derived from the cron expression (cron fields that launchd
  can't express are rejected at validation with a clear message).
- The agent runs `shellx automation run <id>` (new CLI subcommand in the bundled
  `shellx` CLI). That command: resolves `claude`, runs it headless in the working dir
  with the automation's prompt and tool permissions, records the run under `runs/`,
  then notifies according to settings.
- Workflows run their steps in order through the same command; a failing step stops the
  workflow and notifies "failed at step N".
- Run now in the UI calls the same command, so there is one run path for all entrypoints.
- **Permissions (user decision):** unattended runs get only the tools chosen while
  creating. The assistant asks what the job needs (read files, run `gh`, edit code, …)
  and saves an explicit allow-list in `automation.json`, passed as `--allowedTools`.
  Never `bypassPermissions`. A tool outside the list stops the run.
- **"Needs you" (user decision):** the run ends (no paused/resumable runs). ShellX
  notifies "needs you" with the reason; clicking the notification opens that Claude
  session in a ShellX terminal (`claude --resume <session-id>` in the working dir) so
  the user continues by hand. A blocked tool is reported the same way.
- Disable = `launchctl bootout` + keep files; Enable = write plist + `bootstrap`.
- Only `pro.shellx.automation.*` labels are ever touched.

### 6. Notifications

- **Delivery does not depend on ShellX running (user decision).** When the app is
  running, `shellx automation run` posts through the existing socket notification path
  (title = automation name, body = short summary or error). When it is not, the run
  command still delivers immediately: a Mac notification through a notifier that works
  without the main app (e.g. a small helper bundled inside ShellX.app, so the banner
  carries ShellX's name and icon), and, from phase 2, the iPhone push through its own
  route to the relay (reusing the paired-device credentials, not the app process).
  The result is also recorded and shown as unread on the card. Exact mechanism is the
  builder's call; launching or relaunching the main app to deliver is not allowed.
- iPhone: extend the push path with automation kinds (`automation_done`,
  `automation_failed`; "needs you" reuses `needs_you`). Requires changes in the app
  forwarder, shellx-core `notify.phones`, relay `/v2/notifications` (accept the new kinds),
  and the iOS app to display them. Relay deploy needs the user's OK.
- Skills: a skill is invoked by Claude Code inside the user's session, so "notify" for
  a skill means the generated `SKILL.md` ends with a step that calls `shellx notify`
  (Mac) and the iPhone path when the user asked for it.

### 7. Delivery phases

1. **Mac core**: sidebar button, Automations surface (List + Creator), creator assistant,
   skill/cronjob/workflow storage, launchd scheduling, `shellx automation run`, Mac
   notifications. Shippable on its own.
2. **iPhone push**: new push kinds through shellx-core + relay + iOS display; relay deploy.

## Calls I made (not discussed with the user)

- Button label "Automations / Tự động hoá", placed as a row under the brand header; count badge.
- Clicking opens a panel tab (not a separate window).
- Default type picker "Auto" (assistant picks the type).
- Storage paths and the `.shellx.json` marker; `~/.shellx/automations` for cronjobs/workflows.
- launchd (not an in-app timer) so jobs run while ShellX is closed.
- Other skills not made by ShellX are shown and can be edited/deleted after a warning.
- Workflow = ShellX's own ordered prompt chain (not Claude Code's native Workflow
  script format; user confirmed "a chain of steps"). Steps share one Claude conversation
  (each step resumes the previous session with `--resume`), stop on first failure.
- Workflows may have an optional schedule; scheduled workflows get a LaunchAgent exactly
  like cronjobs. A cronjob is a single-step scheduled automation.
- Phase 1 still asks the iPhone question and saves the choice; the card shows iPhone as
  "after the next update" until phase 2 delivers it. Nothing is sent as a fake `needs_you`.
- Skills notify through a new `shellx automation notify --name <n> --status done|failed|needs-you
  --body <text>` command that needs no workspace/surface, so it works from any terminal
  or cron run; it uses the same delivery path as `shellx automation run`.
- Deleting a skill or automation moves its folder to the Trash (recoverable), never `rm`.
- iPhone push split into phase 2 because it needs a relay deploy.

## Left to the builder

- Exact Swift types/files, how the panel registers (new `PanelType` vs reuse), the
  structured-block syntax for chips and drafts, the grid renderer (Metal/CALayer/Canvas),
  cron→launchd mapping details, test strategy within `skills/cmux-testing`.
