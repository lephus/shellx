# ShellX Automation Flowchart — design

Date: 2026-11-05 · Base: `develop` (the automations creator shipped in 1.6.1)
Mockups (local, not committed): `.superpowers/brainstorm/automation-flowchart/flow-layout.html`
(option A chosen) and `saved-view.html` (option B chosen).

## Intent

In the automations creator, the draft card shows a skill, workflow or cronjob as text:
name, description and the full `SKILL.md`. To understand what it will do, the user has to
read it. The user wants a **flowchart view, shown by default**, so that one glance tells
them which steps the automation goes through, where it branches, and where it stops to
wait for them. The text view stays for anyone who wants the details.

The same flowchart must also be visible later, when the user opens an automation they
already saved, to review how it runs.

## Goals

1. The creator's draft card has a **Flowchart / Text** switch. Flowchart is the default.
2. Clicking a saved automation's name in the list opens a **detail page** for it, with
   a ← back button to the list and the same Flowchart / Text switch, defaulting to
   Flowchart.
3. The flowchart shows branches: decisions, and the points where the automation waits for
   the user to choose or approve something.
4. When a saved automation has no flowchart, or its flowchart no longer matches its
   content, the detail page offers a **Vẽ sơ đồ** ("Draw flowchart") button. The flowchart
   is only drawn when the user presses it.

## Non-goals

- Changing how automations are made. Creating and editing still happen by chatting with
  Claude in the creator, exactly as today. The flowchart only adds a visual view next to
  the existing text.

- Editing on the chart. It is view only: no dragging or adding nodes, and no editing
  labels (decided by the user). Changes still go through the chat or the text view.
- iPhone and Windows. Automations are Mac-only today.
- Drawing flowcharts in the background without the user pressing the button (decided by
  the user).

## Anti-goals

- **A chart that misrepresents the automation.** This is the failure that matters most.
  For example, if `disk-cleanup` loses its "you approve what to delete" decision, the user
  will believe the skill deletes on its own. That chart is worse than no chart. Every
  point where the skill asks the user, and every destructive action, must appear.
- A chart that is silently stale. If the content changed after the chart was drawn, the
  UI must say so instead of showing the old chart as current.

## What the user decided

- **Layout:** a classic vertical flowchart (option A). Each step is a box, decisions are
  diamonds, and branch edges are labelled ("Có" / "Không"). The horizontal option and
  the timeline/checklist option were rejected.
- **Detail view:** a separate detail page that replaces the list in the panel and has a
  back button (option B). Expanding the card inline in the list was rejected.
- Missing or stale charts are drawn on demand through the **Vẽ sơ đồ** button.
- The chart is for viewing only.

## Visual language

Shown in the mockups. The colors were proposed by Claude, and the user did not object:

| Node | Look |
| --- | --- |
| Start: the trigger phrases for a skill, the schedule for a workflow or cronjob, or "Chạy khi bấm" when there is no schedule | pill, soft green border |
| Step | rounded box with step number, `#60a5fa` border |
| Automatic decision (a condition the run evaluates itself) | diamond, grey |
| Waits for the user (approve or choose) | diamond, soft purple |
| Notification (workflow and cronjob only) | pill at the end that shows where and when it notifies, e.g. "🔔 Báo về Mac + iPhone · khi xong · khi lỗi" |
| End / stop | grey box or pill |
| Running step (detail page, workflow) | soft yellow fill and border with "● đang chạy" |

These follow the user's color taste: soft colors, no gradients, primary `#60a5fa`, and
yellow reserved for "running". That is why the "waits for you" diamond is purple rather
than yellow. The chart follows the panel's dark/light appearance, as the rest of the
automations surface does.

## Where the steps come from

- **Workflow:** ShellX draws the chart from the data it already has, with no Claude
  involved. The chart is start (schedule or manual) → each step's title, in order →
  notification. Workflow steps run in sequence, so the chart has no branches. Because
  nodes map one to one onto `steps`, the detail page can highlight `lastRun.currentStep`
  while a run is in progress. `currentStep` is 1-based (the runner sets it to `index + 1`),
  so the highlighted step is `steps[currentStep - 1]`.
- **Skill and cronjob:** their behavior lives only in the prose of `SKILL.md`. Claude
  describes the flow as structured data, and ShellX lays it out and draws it. ShellX
  adds the cronjob's start node (schedule) and notification node itself, from the draft's
  `schedule` and `notify`, so those always match the real settings. For a skill, the flow
  also carries a short `trigger` label, written by Claude from the description, and
  ShellX draws it as the start pill.
- **Caption (Claude's call):** a chart drawn by Claude (skill and cronjob) carries a small
  muted caption under it, "Sơ đồ do Claude vẽ từ SKILL.md · xem bản Văn bản để biết chi
  tiết". This keeps the user aware that the text is the source of truth. A heuristic
  validator, for example "the text mentions approval but the flow has no `askUser`", was
  considered and dropped: it is fragile, and the prompt rules plus this caption carry the
  fidelity goal.

### In the creator

The `shellx-draft` block in `Resources/shellx-automations/creator-system-prompt.md` gains
a `flow` field. Claude must send it for a skill or cronjob whenever it sends a draft,
and leaves it out for a workflow. The prompt has to stress fidelity:

- Draw the flow only from what `SKILL.md` says.
- Include every point where the skill asks the user or waits for approval, as a
  "waits for you" decision.
- Include every destructive or irreversible action as a step.
- Keep each label short, in the user's language.

When the user edits the text on the card, the chart is marked as out of date until Claude
sends the next draft with a new `flow`. The creator already tells Claude once that the user
edited the draft, so the prompt must also tell Claude to answer that with a full draft
that includes an updated `flow`. The user does not have to press anything in the creator.

These are all Claude's calls:

- A draft without `flow` is accepted. It is never a validation issue, so it never starts a
  fix-up turn and never blocks Save. The card shows a "drawing" placeholder until a flow
  arrives.
- When a `flow` arrives, ShellX records the hash of the `skillMarkdown` from that **same**
  draft. Saving stores the flow with that recorded hash, never with a hash of the saved
  text. A flow that went out of date before Save is therefore saved as stale and shows
  the Vẽ sơ đồ state, rather than looking current.

### For saved automations

The flow is saved with the automation, together with a fingerprint (hash) of the
`SKILL.md` it was drawn from. On load:

- if the hash matches, show the chart;
- if there is no flow (skills made outside ShellX, or saved before this feature), or the
  hash differs because the user edited the file by hand ("Edit file") or outside ShellX,
  show the empty state with the **Vẽ sơ đồ** button. When a stale flow exists, the
  empty state says the content changed since the chart was drawn.

The hash covers the whole `SKILL.md`, frontmatter included, because the skill's trigger
label comes from the description (Claude's call). Workflows store no flow and no hash:
their chart is always derived live from `steps`, `schedule` and `notify`, so it cannot go
stale.

**Vẽ sơ đồ** runs one headless Claude call that reads only the `SKILL.md`, uses no
tools, follows the same fidelity rules and returns the flow. It shows progress while it
runs, saves the result with the new hash, and on failure shows the error with a way to try
again. The headless run should reuse the existing Claude resolution (login-shell PATH),
as the runner does.

Claude's call: it is a lightweight one-shot call, separate from the automation runner.

- The markdown goes in the prompt, and tools are disabled.
- It does not count as a run: no run record, no run lock, no notification, no log.
- Its working directory is the creator's scratch folder.

External skills (`origin: "external"`) get the detail page and Vẽ sơ đồ like any other
skill. Their `SKILL.md` is read through the bridge, read only. Their flow goes only into
the ShellX-owned cache.

**Storage constraint (Claude's call):** never write into the folder of a skill that ShellX
did not create. The rule since 1.6.0 is that only its `SKILL.md` changes. The flow
therefore lives somewhere ShellX owns, keyed by automation id. A ShellX-owned cache under
the automations root, used for all kinds, keeps this in one place. The builder picks the
exact path and file format.

## Flow data shape

These are the minimum fields. The exact schema is the builder's call.

- `nodes`: `id`, `type` (`step` | `decision` | `askUser` | `end`), `label` (short), and an
  optional `detail` (one line, used for hover or accessibility).
- `edges`: `from`, `to`, and an optional `label` (the branch name).
- `trigger` (skill only): a short label for the start pill.
- Claude does not produce the start node and the notification node. ShellX adds them,
  using `trigger` for a skill and `schedule` / `notify` for a cronjob.
- Loops ("not enough space freed → measure again") can happen. Layout must route back
  edges cleanly, for example around the side, rather than break.
- Invalid flow data (unknown node ids, no nodes) must not break the card. Fall back to the
  "no chart" state, or in the creator to the text view, and never block saving the
  automation.

## Detail page (new)

Today, clicking a card name only selects the card (`store.selectCard`). It will now open
the detail page instead. The detail page has:

- **Header:** a ← back button, the kind badge, the name, and the Flowchart / Text switch.
- **Summary line:** description, schedule and next run, and last run status.
- **Actions:** the same actions as the list card (Run now, Enable/Disable, Edit, Edit file,
  Reveal, Open log, Continue in terminal, Delete), behaving the same.
- **Body:** the chart, or the empty state, or the text view.

The text view is read only. It shows `SKILL.md`, and for a workflow its steps. Editing
stays with **Edit** (the creator) and **Edit file**. The page loads the `SKILL.md` and flow
it needs through the bridge, because today's `AutomationDTO` does not carry the markdown.

Other behavior:

- If the automation is deleted from the detail page, the panel returns to the list.
- If the automation changes on disk while its page is open, the page refreshes
  (`automations.changed`).
- Banner focus (`focus` event) keeps working as it does today.

## Constraints

- **Code location:** the web surface is in `webviews/src/automations/` (React, tested with
  bun). The Swift side is `Packages/macOS/ShellXAutomations` and
  `Sources/ShellX/Automations`. App-linked Swift must stay Swift 6.0 compatible.
- **Libraries:** no diagram library is in `webviews` today. If one is added, for example
  for layered layout, it must bundle locally (the surface runs offline in a WKWebView)
  and be small. A small hand-written layered layout is also acceptable. This is the
  builder's call.
- **Localization:** all new UI strings (switch labels, Vẽ sơ đồ, empty or stale
  messages, back) go through `labels.ts` and `Localizable.xcstrings`, following
  `skills/cmux-localization`. Node labels come from Claude in the user's language.
- **Accessibility:** the chart is SVG. Provide a text alternative, for example a visually
  hidden ordered list of the steps and branches. Respect `reduceMotion` for any busy or
  running animation.
- **Busy state:** while Claude rewrites the draft (`locked`), the chart uses the same busy
  effect as the text fields do today.
- **Process:** follow repo rules. A failing behavioral test is committed before its fix.
  Use scoped verification (`python3 scripts/verify-local.py`), and run
  `scripts/sync-test-wiring` if test files are added. Work goes on a branch from `develop`.

## Left to the builder

- The diagram layout approach or library, edge routing, and node sizing for long labels.
- The exact flow schema, the storage path and format, and the hashing method.
- How the detail page fits into the store and router of `AutomationsApp`.
- The bridge method names and shapes for loading detail data and drawing a flow.
- How much the creator chart shows while an early draft has no `flow` yet. For example, a
  "Claude đang vẽ sơ đồ…" placeholder.
- The test split between bun (layout, rendering, store, fallbacks) and Swift (payload
  decode, persistence, hash staleness, headless draw).
