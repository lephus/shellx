# ShellX Automation Flowchart Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show every skill, workflow and cronjob as a view-only vertical flowchart, by default. It appears on the creator's draft card and on a new detail page for saved automations. A **Draw flowchart** (Vẽ sơ đồ) button covers automations that have no flowchart or whose flowchart is out of date.

**Architecture:**
- **Workflow:** the page draws the chart itself from the data it already has (`steps`, `schedule`, `notify`).
- **Skill and cronjob:** Claude describes the flow as structured JSON. It sends the flow inside the creator's `shellx-draft` block, or returns it from a one-shot headless call made by the Draw flowchart button.
- **Storage:** the Swift side stores the flow in a ShellX-owned cache, together with a SHA-256 of the `SKILL.md` it was drawn from. The hash decides whether the flow is current, stale or missing.
- **Rendering:** the page lays the chart out with a small hand-written layered layout and renders it as SVG.

**Tech Stack:**
- Swift 6.0: package `Packages/macOS/ShellXAutomations` (Swift Testing), app target `cmux` (XCTest), CryptoKit.
- React 19 + bun test in `webviews/`.
- Claude Code CLI (`claude -p`).

**Spec:** `docs/superpowers/specs/2026-11-05-shellx-automation-flowchart-design.md`. Mockups: `.superpowers/brainstorm/automation-flowchart/` (local only).

## Global Constraints

- The chart is view only: no editing, dragging or adding nodes. The creator chat works exactly as today.
- Default view is **Flowchart** on both the draft card and the detail page. The toggle has two labels: "Flowchart" and "Text".
- **Visual language:**
  - start pill: soft green border;
  - step: rounded box with step number, `#60a5fa` border;
  - automatic decision: grey diamond;
  - waiting for the user (`askUser`): soft purple diamond;
  - notify pill (workflow and cronjob only): blue;
  - end: grey pill;
  - running step: soft yellow fill and border with "● running".
- Use soft colors and no gradients. Yellow is reserved for "running". The chart follows `data-au-appearance` (dark/light).
- Never write into the folder of a skill ShellX did not create. Flows live only in `automationsRoot/.flows/`.
- A missing or malformed `flow` never blocks a draft or a save, and never becomes a validation issue.
- Hash = SHA-256 hex of the whole `SKILL.md` text, UTF-8 encoded, frontmatter included. Workflows store no flow and no hash.
- The Draw flowchart call:
  - uses no tools and a 120 s time limit;
  - runs in `automationsRoot/.creator`;
  - creates no run record, no run lock, no notification and no log.
- `lastRun.currentStep` is 1-based, so the running node is `steps[currentStep - 1]`.
- **Copy:**
  - "Drawn by Claude from SKILL.md · see Text for the details" (vi: "Sơ đồ do Claude vẽ từ SKILL.md · xem bản Văn bản để biết chi tiết").
  - The button is "Draw flowchart" (vi: "Vẽ sơ đồ").
  - Every new UI string goes in `webviews/src/automations/labels.ts`, `Sources/ShellX/Automations/ShellXAutomationsLabels.swift` (keys `automations.label.<key>`) and `Resources/Localizable.xcstrings`, translated for en, de, fr, ar, es, zh-Hant, zh-Hans, ko, ja and vi. Read `skills/cmux-localization/SKILL.md` first.
- App-linked Swift must stay Swift 6.0 compatible.
- **Commands:** use only the repo scripts.
  - package tests: `swift test --package-path Packages/macOS/ShellXAutomations --filter <Name>`
  - app tests: `scripts/shellx/test-app.sh <Suite>`
  - webviews tests: `cd webviews && bun test src/automations`
  - bundle: `./scripts/build-webviews-app.sh`
  - Never run bare `xcodebuild`.
- Commit each failing test before its fix (repo testing policy). Record the red and green results of the same command.
- Work on branch `feat/shellx-automation-flowchart`, which is cut from `develop` and already holds the spec commit.

## Review Focus

1. **An early creator draft that has a name but no `flow` yet.** The card shows the "Claude is drawing the flowchart…" placeholder, not an empty SVG or an error. Pinned in Task 6.
2. **A flow whose edge points to an unknown node, or that has duplicate ids.** The draft card falls back to Text, and the detail page shows the missing state. Nothing throws. Pinned in Tasks 1 and 5.
3. **A loop, for example "not enough freed → measure again".** Layout terminates, and the back edge is routed to the right of every node, not through boxes. Pinned in Task 5.
4. **The user edits the `SKILL.md` on the card, then saves without sending another message.** The saved flow is stale, and the detail page offers Draw flowchart. Pinned in Task 4.
5. **The automation is deleted, or changes on disk, while its detail page is open.** Deleted: the page returns to the list. Changed: the page reloads its data. Pinned in Task 7.

---

### Task 1: Flow model, fingerprint and lenient draft decoding (package)

**Files:**
- Create: `Packages/macOS/ShellXAutomations/Sources/ShellXAutomations/Model/ShellXAutomationFlow.swift`
- Create: `Packages/macOS/ShellXAutomations/Sources/ShellXAutomations/Model/ShellXFlowFingerprint.swift`
- Modify: `Packages/macOS/ShellXAutomations/Sources/ShellXAutomations/Model/ShellXAutomationDraft.swift` (add `flow`)
- Modify: `Packages/macOS/ShellXAutomations/Sources/ShellXAutomations/Creator/ShellXCreatorDraftPayload.swift`
- Test: `Packages/macOS/ShellXAutomations/Tests/ShellXAutomationsTests/ShellXAutomationFlowTests.swift`
- Test: `Packages/macOS/ShellXAutomations/Tests/ShellXAutomationsTests/ShellXAssistantBlockParserTests.swift` (add cases)

**Interfaces:**
- Produces:
  - `public struct ShellXAutomationFlow: Codable, Sendable, Equatable { public var trigger: String?; public var nodes: [Node]; public var edges: [Edge] }`
  - `public struct Node: Codable, Sendable, Equatable { id: String; type: NodeType; label: String; detail: String? }`
  - `public enum NodeType: String, Codable, Sendable { case step, decision, askUser, end }`
  - `public struct Edge: Codable, Sendable, Equatable { from: String; to: String; label: String? }`
  - `public var isUsable: Bool`: true when `nodes` is non-empty, ids are unique and non-empty, and every edge's `from` and `to` name a node.
  - `public enum ShellXFlowFingerprint { public static func of(_ markdown: String) -> String }`: lowercase SHA-256 hex.
  - `ShellXAutomationDraft.flow: ShellXAutomationFlow?` (init parameter `flow: ShellXAutomationFlow? = nil`, placed last).

- [ ] **Step 1: Write the failing tests**

`ShellXAutomationFlowTests`:
- `decodesClaudeJSON`: decoding `{"trigger":"When the disk is full","nodes":[{"id":"measure","type":"step","label":"Measure"},{"id":"ok","type":"askUser","label":"Approve?"},{"id":"stop","type":"end","label":"Stop"}],"edges":[{"from":"measure","to":"ok"},{"from":"ok","to":"stop","label":"No"}]}` gives 3 nodes, `nodes[1].type == .askUser` and `edges[1].label == "No"`.
- `isUsableRejects`: `isUsable` is false for no nodes, for a duplicate id, and for an edge to `"missing"`. It is true for the flow above.
- `fingerprintIsSHA256`: `ShellXFlowFingerprint.of("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"`.

Add to `ShellXAssistantBlockParserTests`:
- `draftKeepsUsableFlow`: a `shellx-draft` block with a valid `flow` yields `draft.flow?.nodes.count == 3`.
- `draftDropsBadFlow`: a block whose `flow` is `"oops"`, or whose flow is unusable, still yields a draft with the same `name`, and `draft.flow == nil`.

- [ ] **Step 2: Run** `swift test --package-path Packages/macOS/ShellXAutomations --filter "ShellXAutomationFlow|ShellXAssistantBlockParser"`. Expected: build failure (types missing). Commit the tests: `test(shellx): automation flow model and lenient draft flow`.

- [ ] **Step 3: Implement.** In `ShellXCreatorDraftPayload`, add `var flow: ShellXAutomationFlow?` with a custom `init(from:)`. It decodes `flow` using `try? c.decodeIfPresent` and keeps it only if `isUsable`. Every other field decodes as today. `draft` passes `flow` through. Use `import CryptoKit` for the fingerprint.

- [ ] **Step 4: Run** the same command. Expected: PASS. Then run the whole package with `swift test --package-path Packages/macOS/ShellXAutomations`. Expected: PASS.

- [ ] **Step 5: Commit** `feat(shellx): automation flow model and lenient draft flow`.

---

### Task 2: Flow cache in the store (package)

**Files:**
- Create: `Packages/macOS/ShellXAutomations/Sources/ShellXAutomations/Model/ShellXFlowRecord.swift`
- Modify: `Packages/macOS/ShellXAutomations/Sources/ShellXAutomations/Store/ShellXAutomationStore.swift`
- Test: `Packages/macOS/ShellXAutomations/Tests/ShellXAutomationsTests/ShellXAutomationStoreTests.swift` (add cases)

**Interfaces:**
- Consumes: `ShellXAutomationFlow` and `ShellXFlowFingerprint` (Task 1).
- Produces:
  - `public struct ShellXFlowRecord: Codable, Sendable, Equatable { public var flow: ShellXAutomationFlow; public var sourceHash: String; public var drawnAt: Date }`
  - `public enum ShellXFlowStatus: String, Sendable { case current, stale, missing, derived }`
  - `ShellXAutomationStore` gains:
    - `public func flowRecord(id: String) throws -> ShellXFlowRecord?`
    - `public func saveFlow(_ record: ShellXFlowRecord, id: String) throws`
    - `public func removeFlow(id: String) throws`
    - `public nonisolated static func flowStatus(kind: ShellXAutomationKind, record: ShellXFlowRecord?, skillMarkdown: String) -> (status: ShellXFlowStatus, flow: ShellXAutomationFlow?)`
  - `flowStatus` returns:
    - `.derived` and nil for a workflow;
    - `.missing` and nil when there is no record or the record's flow is unusable;
    - `.stale` and nil when the hash differs;
    - `.current` and the flow otherwise.

- [ ] **Step 1: Write the failing tests** (temp store, as the existing store tests do)
- `flowRoundTrip`: `saveFlow` then `flowRecord(id:)` returns an equal record for a ShellX id, and also for `"external:my-skill"`.
- `flowFileLocation`: the record is written under `automationsRoot/.flows/`. Nothing is created inside `skillsRoot/my-skill/`, and `list()` returns the same automations before and after the save.
- `deleteRemovesFlow`: after `delete(id:)`, `flowRecord(id:)` is nil.
- `flowStatusCases`: assert all four `flowStatus` outcomes described in Interfaces.

- [ ] **Step 2: Run** `swift test --package-path Packages/macOS/ShellXAutomations --filter ShellXAutomationStore`. Expected: FAIL. Commit the tests.

- [ ] **Step 3: Implement.** The file name is `<id>.json` when `isSafeID(id)`. Otherwise it is `_` followed by the lowercase hex of the id's UTF-8 bytes, then `.json`. `_` cannot occur in a safe id, so the two forms never collide. Writes are atomic and use the store's `encoder()`. The flow methods do not touch the change stamp. `delete(id:)` also calls `removeFlow(id:)`, ignoring a missing file.

- [ ] **Step 4: Run** the same command. Expected: PASS.

- [ ] **Step 5: Commit** `feat(shellx): store automation flows apart from skill folders`.

---

### Task 3: Shared flow rules and the one-shot flow drawer (package + resource)

**Files:**
- Create: `Resources/shellx-automations/flow-rules.md`
- Create: `Packages/macOS/ShellXAutomations/Sources/ShellXAutomations/Creator/ShellXFlowDrawer.swift`
- Test: `Packages/macOS/ShellXAutomations/Tests/ShellXAutomationsTests/ShellXFlowDrawerTests.swift`
- Test: `Packages/macOS/ShellXAutomations/Tests/ShellXAutomationsTests/ShellXFlowDrawerLiveTests.swift` (gated on `SHELLX_LIVE_CLAUDE=1`, like `ShellXAutomationRunnerLiveTests`)
- Test fixture: `Packages/macOS/ShellXAutomations/Tests/ShellXAutomationsTests/Fixtures/disk-cleanup-SKILL.md` (the skill from the spec's example: measure, report, user approves, delete approved only)

**Interfaces:**
- Consumes: `ShellXClaudeLaunching` (existing) and `ShellXAutomationFlow` (Task 1).
- Produces:
  - `public struct ShellXFlowDrawer: Sendable`, with:
    - `init(launcher: any ShellXClaudeLaunching, rules: String, workingDirectory: URL)`
    - `func draw(skillMarkdown: String) async throws -> ShellXAutomationFlow`
  - `public enum ShellXFlowDrawError: Error, Equatable { case failed(String), invalidFlow }`

`flow-rules.md` is the single source of the fidelity rules and the schema. Both the creator prompt (Task 4) and the drawer use it. Its content:
- the JSON schema from Task 1, with `type` one of `step`, `decision`, `askUser` or `end`;
- "the first node is where the work starts; ShellX draws the start pill and, for cronjobs, the notification itself";
- draw only what `SKILL.md` says;
- every point where the user is asked, or must approve, is an `askUser` node;
- every destructive or irreversible action is its own `step`;
- automatic conditions are `decision` nodes, and the edges leaving a decision carry short labels;
- labels are at most about 6 words, in the language `SKILL.md` is written in, or the user's language in the creator;
- `trigger` is a short phrase from the description, for skills only;
- loops are allowed as edges back to an earlier node.

- [ ] **Step 1: Write the failing tests** (`ShellXFlowDrawerTests`, with a fake `ShellXClaudeLaunching` that records its arguments and returns a canned `ShellXClaudeResult`)
- `drawsFromFencedBlock`: if the result text is prose followed by a `shellx-flow` fenced JSON block, the drawer returns that flow.
- `drawsFromBareJSON`: if the result text is the JSON alone, the drawer returns it.
- `promptCarriesRulesAndSkill`: the prompt contains the `rules` string and the full markdown. `allowedTools == []`, `resumeSessionId == nil`, the `workingDirectory` is the one given to `init`, and the transcript URL is under `FileManager.default.temporaryDirectory`.
- `failsOnErrorResult`: `isError: true` or `exitCode != 0` throws `.failed`, carrying `resultText` or else `stderrTail`.
- `failsOnUnusableFlow`: a result whose flow has an edge to an unknown node throws `.invalidFlow`.

- [ ] **Step 2: Run** `swift test --package-path Packages/macOS/ShellXAutomations --filter ShellXFlowDrawer`. Expected: FAIL. Commit the tests.

- [ ] **Step 3: Implement** `draw`. The prompt is: "Draw the flowchart of the Claude Code skill below. Reply with exactly one `shellx-flow` fenced block holding the JSON and nothing else." Then come the rules, then the markdown in a fence one backtick longer than its longest backtick run. The transcript goes to a fresh file under `FileManager.default.temporaryDirectory`, deleted afterwards. Parsing takes the first fenced block tagged `shellx-flow`, otherwise the whole trimmed text, then decodes and checks `isUsable`.

- [ ] **Step 4: Run** the same command. Expected: PASS.

- [ ] **Step 5: Live check.** `ShellXFlowDrawerLiveTests.drawsDiskCleanup` uses the real resolved `claude` (`ShellXClaudeProcess`, time limit 120 s) on the fixture. It asserts that the flow contains at least one `askUser` node and at least one `step`.

Run `SHELLX_LIVE_CLAUDE=1 swift test --package-path Packages/macOS/ShellXAutomations --filter ShellXFlowDrawerLiveTests`. Expected: PASS. If you cannot run it, say so in the PR. It is skipped without the env var.

- [ ] **Step 6: Commit** `feat(shellx): draw an automation flow with one headless Claude call`.

---

### Task 4: Controller: creator flow, save, detail and draw (app)

**Files:**
- Modify: `Resources/shellx-automations/creator-system-prompt.md`
- Modify: `Sources/ShellX/Automations/ShellXAutomationsRuntime.swift`
- Modify: `Sources/ShellX/Automations/ShellXAutomationsController.swift`
- Modify: `Sources/ShellX/Automations/ShellXAutomationsBridgeContract.swift`
- Modify: `Sources/ShellX/Automations/ShellXAutomationsBridgeFailure.swift`
- Modify: `Sources/ShellX/Automations/ShellXAutomationsDTOEncoder.swift`
- Test: `cmuxTests/ShellXAutomationsControllerTests.swift` (add cases; no new test file, so wiring is unchanged)

**Interfaces:**
- Consumes: Tasks 1 to 3.
- Produces:
  - **Bridge `automations.detail`** `{id}` returns `{automation: AutomationDTO, skillMarkdown: String, flow: FlowDTO | null, flowStatus: "current"|"stale"|"missing"|"derived"}`.
  - **Bridge `automations.drawFlow`** `{id}` returns the same object after drawing.
    - It fails with code `failed` and a localized message if the automation is a workflow, if a draw for that id is already running, or if Claude cannot be resolved.
    - It fails with the localized `drawFailed(detail)` when the drawer throws.
  - **Draft DTO:** `encoder.draft(_:)` adds `"flow"`, with `FlowDTO` or `NSNull()`. `FlowDTO` = `{trigger?, nodes: [{id,type,label,detail?}], edges: [{from,to,label?}]}`.
  - **New controller init parameter** `flowDrawer: @escaping (_ skillMarkdown: String) async throws -> ShellXAutomationFlow`. The runtime builds it as `ShellXFlowDrawer(launcher: ShellXClaudeProcess(executable:environment:timeLimit: .seconds(120)), rules:, workingDirectory: automationsRoot/.creator)` from `claudePath.launch()`. With no Claude, it throws `ShellXFlowDrawError.failed(<localized "Claude Code was not found">)`.

**Prompt changes:**
- `creator-system-prompt.md` gains a "Flowchart" section, inserted after "The live draft".
- That section holds the literal placeholder `{{SHELLX_FLOW_RULES}}`. The runtime replaces it with the text of `flow-rules.md` in `creatorSystemPrompt()`.
- The `shellx-draft` schema example gains `"flow": {…}`.
- Rules in the section:
  - send `flow` with every skill or cronjob draft;
  - omit `flow` for workflows;
  - after a message that starts "I edited the draft myself", always answer with a full draft whose `flow` matches the edited `SKILL.md`.

**Controller state:**
- `latestFlowHash: String?` holds the fingerprint of the `skillMarkdown` of the draft that carried the current `flow`.
- In `creatorDidEmit(.draft)`, set it to the fingerprint of that draft's markdown when `draft.flow != nil`, and to nil otherwise.
- `editDraft` does not change it. `endSession` clears it.

- [ ] **Step 1: Write the failing tests** (existing fixture and fake launcher; inject a fake `flowDrawer`)
- `draftEventCarriesFlow`: when the fake Claude emits a draft with a flow, the page event's `draft["flow"]` has the nodes.
- `saveStoresFlowWithDraftHash`: a skill draft with a flow is saved, so `store.flowRecord(id:)` exists with `sourceHash == ShellXFlowFingerprint.of(markdown)`.
- `saveAfterCardEditStoresStaleFlow`: the draft has a flow, then `creator.edit` changes `skillMarkdown`, then the user saves. The record's hash is the old markdown's, and `automations.detail` reports `flowStatus == "stale"` with `flow == null` (Review Focus 4).
- `saveWithoutFlowSucceeds`: a skill draft without a flow saves fine, and detail reports `"missing"`.
- `workflowDetailIsDerived`: for a saved workflow, detail reports `"derived"` and no record exists.
- `editSeedsCurrentFlow`: `creator.start {editId}` for a skill with a current record sends a seeded draft whose `flow` is the record's flow. For a stale record, the seeded draft has `flow == NSNull`.
- `drawFlowSavesAndReturnsCurrent`: `automations.drawFlow` on an external skill calls the fake drawer with its `SKILL.md`, then returns `flowStatus == "current"`. Nothing new appears in the skill's folder.
- `drawFlowRejectsWorkflowAndConcurrent`: a workflow id fails. A second call while the first one's fake drawer is suspended fails, and the first one still succeeds.
- `drawFlowFailureIsReported`: a throwing drawer gives an `ok: false` reply whose message contains the drawer's detail. No record is written.
- `creatorPromptHasFlowRules`: the prompt the runtime passes to the creator contains a known sentence from `flow-rules.md`, and does not contain `{{SHELLX_FLOW_RULES}}`.

- [ ] **Step 2: Run** `scripts/shellx/test-app.sh ShellXAutomationsControllerTests`. Expected: FAIL (build or assertions). Commit the tests.

- [ ] **Step 3: Implement.**
  - Add the two `Method` cases and `FlowDTO` encoding.
  - Add the failures `drawFailed(_:)`, `drawInProgress` and `flowNotForWorkflow`, each with `String(localized:defaultValue:)`.
  - In `saveDraft`, after a successful `store.save` and scheduling:
    - if `saved.kind != .workflow` and the draft has a flow and `latestFlowHash` is set, call `saveFlow(ShellXFlowRecord(flow:sourceHash:drawnAt:), id: saved.id)`;
    - if `saved.kind == .workflow`, call `removeFlow(id:)`;
    - a flow write error is logged and never fails the save.
  - `startCreator(editId:)` reads the record and uses `flowStatus` to seed the draft.
  - `drawFlow` reads `SKILL.md` off the main actor, records `inFlightDraws: Set<String>`, calls `flowDrawer`, saves the record with the fingerprint of the markdown it sent, and returns detail.
  - Add the new error strings to `Localizable.xcstrings` for all locales.

- [ ] **Step 4: Run** the same command. Expected: PASS. Also run `python3 scripts/localization_catalog.py check`. Expected: PASS.

- [ ] **Step 5: Commit** `feat(shellx): creator sends a flow, saved automations keep it, Draw flowchart redraws it`.

---

### Task 5: Chart model, layout and SVG component (web)

**Files:**
- Modify: `webviews/src/automations/types.ts` (flow types, `flow` on `AutomationDraft`, `AutomationDetail`, new methods)
- Create: `webviews/src/automations/flowChart.ts` (pure model and layout)
- Create: `webviews/src/automations/FlowChart.tsx`
- Modify: `webviews/src/automations/styles.css`
- Test: `webviews/src/automations/flowChart.test.ts`
- Test: `webviews/src/automations/FlowChart.test.tsx`

**Interfaces:**
- **Types:**
  - `FlowNodeType = "step" | "decision" | "askUser" | "end"`
  - `FlowNode = { id: string; type: FlowNodeType; label: string; detail?: string }`
  - `FlowEdge = { from: string; to: string; label?: string }`
  - `AutomationFlow = { trigger?: string; nodes: FlowNode[]; edges: FlowEdge[] }`
  - `AutomationDraft.flow?: AutomationFlow | null`
  - `FlowStatus = "current" | "stale" | "missing" | "derived"`
  - `AutomationDetail = { automation: AutomationDTO; skillMarkdown: string; flow: AutomationFlow | null; flowStatus: FlowStatus }`
  - `AutomationsMethod` gains `"automations.detail" | "automations.drawFlow"`.
- **Functions:**
  - `usableFlow(flow: unknown): AutomationFlow | null` applies the same rule as Swift `isUsable`, plus known `type` values.
  - `ChartShape = "start" | "step" | "decision" | "askUser" | "end" | "notify"`
  - `ChartNode = { id: string; shape: ChartShape; label: string; number?: number; detail?: string }`
  - `ChartModel = { nodes: ChartNode[]; edges: FlowEdge[] }`. The first node is the start node.
  - `ChartSource = { kind: AutomationKind; description: string; schedule?: AutomationSchedule | null; notify: AutomationNotify; steps: AutomationStep[]; flow: AutomationFlow | null }`
  - `buildChart(source: ChartSource, label: AutomationLabelResolver): ChartModel | null`: null when a skill or cronjob has no usable flow.
  - `layoutChart(model: ChartModel): ChartLayout`, where:
    - `ChartLayout = { width: number; height: number; nodes: PlacedNode[]; edges: PlacedEdge[] }`
    - `PlacedNode = ChartNode & { x: number; y: number; w: number; h: number; lines: string[] }`
    - `PlacedEdge = { from: string; to: string; label?: string; points: [number, number][]; back: boolean }`
  - `FlowChart({ layout, label, runningNodeId?, busy? })` renders the SVG plus a visually hidden ordered list.

**`buildChart` rules:**

*Start node (`id "start"`):*
- skill: `flow.trigger`, or else the description cut to 80 characters with an ellipsis;
- workflow or cronjob: `schedule.human`, or else `label("flowStartManual")` ("Runs when you press Run now").

*Body:*
- Workflow: step nodes `step-1`…`step-n`, labelled with the step titles and numbered 1…n, connected in a chain.
- Skill and cronjob: the flow's nodes. `step` nodes are numbered in the order they appear in `flow.nodes`. Add an edge `start → nodes[0]`.

*Notify node (`id "notify"`):*
- Only for workflow and cronjob, and only when `notify.on` is non-empty.
- Label: `label("flowNotify", { targets, events })`, using the same target and event texts as `DraftCard`.
- Connected from every node that has no outgoing edge.
- For a workflow with an empty `notify.on`, add an `end` node `id "done"`, labelled `label("flowDone")`, in its place.

**`layoutChart` algorithm.** The tests do not determine this, so follow these rules:
1. **Back edges:** DFS from `start` in edge order. An edge to a node on the current DFS stack is a back edge.
2. **Ranks:** rank = longest path from `start` over the remaining edges. Unreachable nodes go below the last rank, in input order.
3. **Columns:** column 0 holds the main path, which follows the first outgoing edge of every node. Any other child is placed in the next free column to the right, within its rank. A node keeps the first column it was given.
4. **Geometry:** a main box is about 300 wide and a side box about 170. Ranks are about 26 apart vertically. Diamonds are about 140 × 88. Wrap labels to at most 36 characters per line and 3 lines, and end with "…" if cut.
5. **Forward edges:** a straight vertical line within one column. Across columns, an elbow: horizontal out of the diamond's side, then vertical. An edge that merges back into column 0 from the right runs down the right side, then left into the target's right edge.
6. **Back edges:** routed through a lane at `x = max node right + 24`, entering the target from the right. Set `back: true`.
7. **Edge labels:** placed next to the first segment.

- [ ] **Step 1: Write the failing tests**

`flowChart.test.ts`:
- `usableFlowRejectsBadData`: returns null for `null`, `{nodes: []}`, a duplicate id, an edge to an unknown id, and `type: "loop"`. Returns the flow for a valid one.
- `workflowChart`: steps `["Fetch", "Summarize"]`, a schedule with human text "Mondays 09:00", and `notify.on = ["done"]`. The node ids are `["start", "step-1", "step-2", "notify"]`, the start label is "Mondays 09:00", and the step numbers are `[1, 2]`.
- `workflowWithoutNotifyEndsDone`: the last node is `done`.
- `skillChartUsesTrigger`: the disk-cleanup-like flow (measure → report → askUser → (yes) delete → measure-again → end, (no) stop). The start label is the trigger, `start → measure` exists, and there is no `notify` node.
- `cronjobAddsNotifyAfterTerminals`: both terminal nodes have an edge to `notify`.
- `skillWithoutFlowIsNull`: `buildChart` returns null.
- `layoutBranchGoesRight`: the `stop` node's x is greater than the `askUser` node's x. `delete` has the same x as `askUser`. The y values strictly increase along the main path.
- `layoutRoutesLoopOutside` (Review Focus 3): add an edge `measure-again → measure`. Layout terminates, that edge has `back: true`, and every point of it lies at x ≥ (max placed node `x + w`).
- `wrapsLongLabels`: a 200-character label gives 3 lines, and the last line ends with "…".

`FlowChart.test.tsx`:
- `rendersShapesAndA11yList`: renders one `polygon` per decision or askUser node. `data-shape` attributes match the shapes. A visually hidden `<ol>` lists every node label in rank order, and the branch edges' labels are written as "Approve? → No: Stop".
- `marksRunningNode`: `runningNodeId="step-2"` sets `data-running="true"` on that node only, and the text "● running" (`label("flowRunning")`) is shown.

- [ ] **Step 2: Run** `cd webviews && bun test src/automations/flowChart.test.ts src/automations/FlowChart.test.tsx`. Expected: FAIL. Commit the tests.

- [ ] **Step 3: Implement** `flowChart.ts`, `FlowChart.tsx`, and the CSS tokens for the shapes from Global Constraints, in both appearances.
  - Use SVG `<title>` for `detail`.
  - Add labels `flowStartManual`, `flowNotify` ("Notify {targets} · {events}"), `flowDone` ("Done") and `flowRunning` ("● running") to `labels.ts`, Swift labels and the catalog, translated.

- [ ] **Step 4: Run** the same command, then `bun test src/automations && bun run lint`. Expected: PASS.

- [ ] **Step 5: Commit** `feat(shellx): lay out and draw automation flowcharts`.

---

### Task 6: Flowchart / Text switch on the creator's draft card (web)

**Files:**
- Create: `webviews/src/automations/ViewSwitch.tsx`
- Modify: `webviews/src/automations/store.ts`
- Modify: `webviews/src/automations/DraftCard.tsx`
- Modify: `webviews/src/automations/CreatorView.tsx`
- Modify: `webviews/src/automations/labels.ts`, Swift labels, catalog
- Test: `webviews/src/automations/DraftCard.test.tsx`, `webviews/src/automations/store.test.ts` (add cases)

**Interfaces:**
- Consumes: `buildChart`, `layoutChart`, `FlowChart` and `usableFlow` (Task 5).
- Produces:
  - `type DraftViewMode = "flow" | "text"`
  - `ViewSwitch({ mode, onChange, label })`: a two-button segmented control with `aria-pressed`. The labels are `label("viewFlow")` ("Flowchart") and `label("viewText")` ("Text").
  - `CreatorState` gains `draftView: DraftViewMode` (initially `"flow"`) and `flowCurrent: boolean`.
  - `AutomationsStore.setDraftView(mode: DraftViewMode): void`.
  - `DraftCard` gains the props `view: DraftViewMode`, `onViewChange` and `flowCurrent: boolean`.

**Behavior:**
- A `draft` event sets `flowCurrent = usableFlow(draft.flow) !== null`.
- `editDraft` sets `flowCurrent = false`.

*In flow mode, the card keeps the header, Name and Description. In place of the Steps, Tools and Skill fields it shows one of:*
- the chart;
- `label("flowDrawing")` ("Claude is drawing the flowchart…"), when the draft has no usable flow yet and is not a workflow;
- the chart dimmed, with `label("flowOutdated")` ("Out of date: Claude redraws it with the next draft"), when `flowCurrent` is false but a flow exists.

*Also in flow mode:*
- The Claude-drawn chart carries the caption `label("flowCaption")`.
- While `locked`, the chart gets `data-busy="true"`.
- If `buildChart` returns null for a draft that has a flow, because the flow is unusable, the card shows the text view (Review Focus 2).

*Text mode is today's card, unchanged.*

- [ ] **Step 1: Write the failing tests**
- `defaultsToFlowchart`: a ready skill draft with a usable flow renders the SVG and the caption. The `SKILL.md` textarea is not rendered. The switch shows Flowchart pressed.
- `switchShowsText`: clicking Text renders today's fields, and the textarea is editable as before.
- `earlyDraftShowsDrawing` (Review Focus 1): a skill draft with a name and no flow shows "Claude is drawing the flowchart…".
- `workflowNeedsNoFlow`: a workflow draft with steps renders the chart, with no drawing placeholder.
- `badFlowFallsBackToText`: a draft whose flow has an edge to an unknown node renders the Text fields.
- Store: `editMarksFlowOutdated`: after a `draft` event with a flow, `editDraft({skillMarkdown})` sets `flowCurrent` to false. The next `draft` event with a flow sets it back to true.

- [ ] **Step 2: Run** `cd webviews && bun test src/automations/DraftCard.test.tsx src/automations/store.test.ts`. Expected: FAIL. Commit the tests.

- [ ] **Step 3: Implement.** Add the labels `viewFlow`, `viewText`, `flowDrawing`, `flowOutdated` and `flowCaption` (the en and vi copy is in Global Constraints) to all three places, translated.

- [ ] **Step 4: Run** the same command, then `bun test src/automations && bun run lint`. Expected: PASS.

- [ ] **Step 5: Commit** `feat(shellx): the automation draft card opens as a flowchart`.

---

### Task 7: Detail page for saved automations (web)

**Files:**
- Create: `webviews/src/automations/AutomationActions.tsx` (the action buttons, moved out of `AutomationCard`)
- Create: `webviews/src/automations/DetailView.tsx`
- Modify: `webviews/src/automations/AutomationCard.tsx` (the name button opens the detail page and uses `AutomationActions`)
- Modify: `webviews/src/automations/store.ts`
- Modify: `webviews/src/automations/AutomationsApp.tsx`
- Modify: `webviews/src/automations/labels.ts`, Swift labels, catalog
- Test: `webviews/src/automations/DetailView.test.tsx`, `webviews/src/automations/store.test.ts`, `webviews/src/automations/AutomationCard.test.tsx`

**Interfaces:**
- Consumes: Task 4 bridge methods, Task 5 chart, Task 6 `ViewSwitch` and `DraftViewMode`.
- Produces:
  - `AutomationsState.view: "list" | "creator" | "detail"`
  - `AutomationsState.detail: DetailState | null`, where `DetailState = { id: string; loading: boolean; data: AutomationDetail | null; error: string | null; drawing: boolean; mode: DraftViewMode }`.
  - `AutomationsStore` methods:
    - `openDetail(id: string): Promise<void>` sets `view: "detail"` and `mode: "flow"`, then requests `automations.detail`;
    - `closeDetail(): void` returns to the list and keeps `focusId = id`;
    - `setDetailView(mode: DraftViewMode): void`;
    - `drawFlow(): Promise<void>`.

**Behavior:**

*Opening and loading:*
- The card name's `onClick` keeps the `markRead` call and calls `openDetail` instead of `selectCard`.
- `automations.changed` while `view === "detail"`: run `reload()`, then request `automations.detail` again.
  - If the id is gone, either because the list no longer has it or because the reply is not found, go back to the list (Review Focus 5).
- Deleting from the detail page goes back to the list after `confirmDelete`.
- A `focus` event still switches to the list, as today.
- `startCreator` (Edit) from the detail page works as it does from the list.

*`DetailView` layout:*
- `← label("back")`, kind badge, name and `ViewSwitch`.
- A summary line: description; schedule with next run; last run status with step progress. Use the same helpers as `AutomationCard`.
- `AutomationActions`.
- The body, which is one of:
  - **Flow mode, `flowStatus` current or derived:** the chart.
    - It carries the caption, except for workflows.
    - `runningNodeId = "step-" + lastRun.currentStep` when a workflow's `lastRun.status === "running"`.
  - **Flow mode, missing or stale:** the empty state.
    - Text: `label("flowMissing")` ("This automation has no flowchart yet"), or `label("flowStale")` ("The content changed since the flowchart was drawn").
    - A primary button `label("drawFlow")` ("Draw flowchart"). While `drawing` it is disabled and reads `label("drawingFlow")` ("Drawing…").
    - The hint `label("drawFlowHint")` ("Claude reads SKILL.md and draws it, it takes a few seconds").
    - If the draw failed, the error and the same button to try again.
  - **Text mode:** read-only. A workflow shows its steps as an ordered list of title plus prompt. Every kind shows `skillMarkdown` in `<pre className="au-pre">`.

- [ ] **Step 1: Write the failing tests** (`store.test.ts` uses the existing fake bridge)
- `openDetailLoads`: `openDetail("a")` requests `automations.detail {id: "a"}`, and the state has `view: "detail"`, `mode: "flow"` and the data.
- `changedReloadsDetail`: an `automations.changed` event re-requests detail for the open id.
- `changedGoneReturnsToList`: if detail replies with not found after `changed`, then `view === "list"` and `detail === null`.
- `deleteFromDetailReturnsToList`.
- `drawFlowUpdatesDetail`: `drawFlow()` sets `drawing` and requests `automations.drawFlow {id}`. On ok it replaces `data`. On error it sets `error` and clears `drawing`.
- `DetailView.test.tsx`:
  - `missingShowsDrawButton`;
  - `staleShowsChangedText`;
  - `currentShowsChartAndCaption`;
  - `workflowRunningHighlightsStep`: `currentStep: 2` gives `data-running` on `step-2`;
  - `textModeIsReadOnly`: there is no textarea, and `pre` holds the markdown.
- `AutomationCard.test.tsx`: `nameOpensDetail`. Clicking the name calls `openDetail` with the id, and `markRead` too when unread.

- [ ] **Step 2: Run** `cd webviews && bun test src/automations`. Expected: FAIL. Commit the tests.

- [ ] **Step 3: Implement.** Add the labels `flowMissing`, `flowStale`, `drawFlow`, `drawingFlow` and `drawFlowHint` to all three places, translated. The vi value of `drawFlow` is "Vẽ sơ đồ".

- [ ] **Step 4: Run** `bun test src/automations && bun run lint`. Expected: PASS.

- [ ] **Step 5: Commit** `feat(shellx): a detail page shows a saved automation's flowchart`.

---

### Task 8: Bundle, full verification and PR

**Files:**
- Modify: `Resources/markdown-viewer/webviews-app/` (regenerated)

- [ ] **Step 1: Bundle.** Run `./scripts/build-webviews-app.sh && ./scripts/build-webviews-app.sh --check`. Expected: PASS. Commit the regenerated bundle with `build(shellx): rebuild the automations web surface`.

- [ ] **Step 2: Full checks.** Run:

```
python3 scripts/verify-local.py && swift test --package-path Packages/macOS/ShellXAutomations && (cd webviews && bun test src/automations && bun run build) && ./scripts/build-webviews-app.sh --check && python3 scripts/localization_catalog.py check && scripts/shellx/test-app.sh ShellXAutomationsControllerTests && scripts/test-unit.sh build
```

Expected: all pass. The app tests listed as already red on develop in project memory do not count. Report them as pre-existing.

- [ ] **Step 3: Visual check.** Render the draft card and the detail page for disk-cleanup, a cronjob and a workflow, in dark and light. Use a tagged build if the user launches it (`CMUX_TAG=automation-flow`), or a throwaway render test that writes a PNG. Compare the result against the mockups.

- [ ] **Step 4: Review.** Use a review subagent per `skills/cmux-review/SKILL.md`, correctness first. Fix its findings.

- [ ] **Step 5: Open the PR to `develop`.** Follow STYLE.md. The `## Changelog` line is: `Added: Automations show skills, workflows and cronjobs as a flowchart, and saved ones open in a detail page with a Draw flowchart button.` Disclose whether the live drawer test was run. Merging needs the user's explicit "merge".
