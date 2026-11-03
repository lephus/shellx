# ShellX Automation Creator — Phase 1 (Mac core) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An animated "✦ Automations" button in the ShellX sidebar opens a panel where Claude Code drafts skills, workflows and cronjobs with the user in chat, shows a live draft over a colorful grid, saves them in the right format, runs cronjobs/workflows on a schedule through launchd (even with ShellX closed), notifies on the Mac, and lists everything for run / enable / edit / delete.

**Architecture:** A new SwiftPM package `ShellXAutomations` owns the domain: values, validation, cron→launchd mapping, the on-disk store, the launchd scheduler, the headless runner, the notifier client and the creator chat session. The bundled CLI gets `shellx routine run|notify|list`, the single run path used by launchd, "Run now" and skills. A tiny `ShellX Notifier.app` helper inside ShellX.app posts Mac banners whether or not ShellX runs. The UI is a new `webviews/` React surface (`automations`) hosted in a new `.automations` panel, following the Git Graph precedent (`Sources/GitGraph/`, `webviews/src/git-graph/`).

**Tech Stack:** Swift 6.0 (SwiftPM package, app target `cmux`, CLI target `cmux-cli`), Swift Testing for the package, XCTest app tests, React 19 + Vite + bun test (`webviews/`), launchd user agents, UserNotifications, Claude Code CLI (`claude -p … --output-format stream-json`).

**Spec:** `docs/superpowers/specs/2026-11-03-shellx-automation-creator-design.md` (phase 1 only; iPhone push is phase 2). Mockup: `.superpowers/brainstorm/11841-1793674974/content/creator-layout.html`.

**Branch:** `feat/shellx-automation-creator` (exists, from `develop`). Commit after every task.

## Deviations from the spec (decided while planning)

- **CLI name.** `shellx automation …` already exists (event automations, `CLI/CMUXCLI+Automation.swift`). The new command is **`shellx routine run|notify|list`**. UI copy, storage paths and launchd labels keep the spec's "automation" names.
- **Spec's "`shellx automation notify`"** becomes `shellx routine notify`.
- **One Mac delivery path.** The notifier helper posts every automation banner, also while ShellX runs, so there is no second, socket-based path and no new socket method. The app learns about new runs by watching a change stamp file in the store.
- **Clicks on banners** open `shellx://automations/<id>`; ShellX shows the Automations panel focused on that card. A "needs you" card offers **Continue in terminal** (`claude --resume <session>`), which is how the spec's "opens that Claude session" is reached.
- **Swift type prefix** `ShellXAutomation*` avoids clashes with the existing `AutomationRule`/`AutomationEngine`.

## Global Constraints

- App-linked Swift stays Swift 6.0 compatible. The package builds in Swift 6 language mode with `ExistentialAny` and `InternalImportsByDefault` (copy `Packages/macOS/CmuxSidebarGit/Package.swift`), platform `.macOS(.v14)`.
- Follow `skills/cmux-architecture`: one major type per file; no free functions; no namespace-enums; no singletons in the package; `FileManager`, paths, environment, clock and process runners arrive through `init`; mutable shared state in `actor`s; no locks, no `DispatchQueue.main.async`, no Combine in new code, no `asyncAfter`, no sleeping to poll.
- Package location: `Packages/macOS/ShellXAutomations`. Wire it per `skills/cmux-architecture/references/package-boundaries.md` into targets **`cmux`, `cmuxTests` and `cmux-cli`**, then `scripts/normalize-pbxproj.py && scripts/check-pbxproj.sh && python3 scripts/check-workspace-package-groups.py --write && python3 scripts/check-package-resolved-policy.py`.
- Storage (spec §4), for the release bundle id `pro.shellx.desktop`:
  - skills: `~/.claude/skills/<name>/SKILL.md` + marker `~/.claude/skills/<name>/.shellx.json`;
  - cronjobs/workflows: `~/.shellx/automations/<id>/` with `automation.json`, `SKILL.md`, `runs/<yyyyMMdd-HHmmss>/{output.jsonl,result.json}`, `launchd.log`;
  - launchd: `~/Library/LaunchAgents/pro.shellx.automation.<id>.plist`, label `pro.shellx.automation.<id>`.
  - Any other bundle id (tagged/dev builds): automations root `~/.shellx/automations-dev/<bundle-id>/`, label prefix `pro.shellx.automation.dev.<bundle-id>.`. Skills root is always `~/.claude/skills` (Claude Code only reads there).
- ShellX only ever boots out, writes or deletes plists whose label starts with its own label prefix.
- `name`: `^[a-z0-9]+(-[a-z0-9]+)*$`, max 64 chars, unique across skills and automations. `description`: non-empty, max 1024 chars.
- Unattended runs: `--allowedTools` = the saved allow-list only. **Never** `--dangerously-skip-permissions` or `bypassPermissions`. A permission denial ends the run as **needs you**.
- "Needs you" marker in the final assistant text: a line `SHELLX_NEEDS_YOU: <reason>`.
- Run history: keep the newest **30** runs per automation; prune older ones after each run.
- Cron: 5 numeric fields (`*`, `n`, `a-b`, lists, `*/n`, `a-b/n`), day-of-week `0-7` (7 = Sunday). Reject names (`MON`), `@daily` shortcuts, and expressions restricting **both** day-of-month and day-of-week. Max **200** launchd calendar entries.
- Notification copy: title = automation name; body = summary (done), error (failed) or reason (needs you), truncated to **180** characters with "…".
- iPhone target: saved, never sent in phase 1; the card shows it as "after the next update".
- Animation: ring colors `#60a5fa`, `#a78bfa`, `#f472b6`, `#fbbf24`, `#34d399` (conic, ~4 s per turn), grid pulse colors those five plus `#22d3ee`. No gradient fills on buttons. Running state = yellow (`#fbbf24`). Honor Reduce Motion (static ring, static grid, no twinkle).
- Every new user-facing string: `String(localized:defaultValue:)` in `Resources/Localizable.xcstrings` with `en, de, fr, ar, es, zh-Hant, zh-Hans, ko, ja, vi`; webview copy comes from the host as labels (like `GitGraphLabels.swift`). Check with `python3 scripts/localization_catalog.py check`. (`./scripts/localize-changes` is broken in this fork.)
- Build/test only through repo scripts: package `swift test --package-path Packages/macOS/ShellXAutomations --filter <Name>`; app tests `scripts/shellx/test-app.sh <Suite>`; app build `scripts/test-unit.sh build`; webviews `cd webviews && bun test <path>`, `./scripts/build-webviews-app.sh`. Never bare `xcodebuild`, never an untagged dev app.
- Wire new app files with `python3 scripts/wire-app-sources.py <files>`; after adding a `cmuxTests/` file run `./scripts/sync-test-wiring`.
- Never quit, relaunch or replace the running `/Applications/ShellX.app`. Never touch the user's real `~/.claude/skills`, `~/.shellx` or `~/Library/LaunchAgents` from tests: every test uses a temp directory and fake launchctl/claude.
- The creator system prompt is adapted from Anthropic's `skill-creator` (Apache-2.0). Ship its license text next to the prompt.

## Review Focus

1. **Cron the Mac can't schedule.** `*/7 * * * *` style expansions over 200 entries, `0 9 1 * 1` (both day fields), `@daily`, `MON`, out-of-range values must be rejected at Save with a field message, never installed half-working. Tests: Task 1 `ShellXCronExpressionTests`.
2. **Hostile or colliding names.** `../x`, `My Skill`, `a--b`, 65 chars, a name equal to an existing external skill or automation must be refused before any file is written. Tests: Task 1 `ShellXAutomationValidatorTests`, Task 2 `savesNeverEscapeRoots`.
3. **Claude Code missing or misbehaving.** No `claude` on disk, not logged in (non-zero exit), killed mid-run, output without a `result` event, a model that ignores the marker: each yields a recorded **failed** run with a readable message and a "failed" banner, never a silent nothing. Tests: Task 4 `ShellXAutomationRunnerTests`.
4. **Overlapping runs.** launchd fires while "Run now" is running (or a wake coalesces a missed run): the second run is recorded as **skipped**, posts nothing, and never deletes the first run's lock. A stale lock from a crashed run is taken over. Tests: Task 4 `skipsWhileLocked`, `takesOverStaleLock`.
5. **Model output that breaks the draft.** Malformed or partial `shellx-draft` JSON, two drafts in one message, a fence left open mid-stream: the panel keeps the last good draft and never shows raw block text in chat. Tests: Task 6 `ShellXAssistantBlockParserTests`.

---

### Task 1: Package skeleton, values, validation and cron mapping

**Files:**
- Create: `Packages/macOS/ShellXAutomations/Package.swift`
- Create: `Packages/macOS/ShellXAutomations/Sources/ShellXAutomations/Model/` — `ShellXAutomationKind.swift`, `ShellXNotifyEvent.swift`, `ShellXNotifyTarget.swift`, `ShellXNotifySettings.swift`, `ShellXSchedule.swift`, `ShellXWorkflowStep.swift`, `ShellXAutomationDraft.swift`, `ShellXAutomation.swift`, `ShellXAutomationOrigin.swift`, `ShellXRunRecord.swift`, `ShellXRunStatus.swift`, `ShellXRunTrigger.swift`
- Create: `.../Validation/ShellXAutomationValidator.swift`, `ShellXValidationIssue.swift`, `ShellXSkillFrontmatter.swift`
- Create: `.../Schedule/ShellXCronExpression.swift`, `ShellXCronError.swift`
- Test: `Packages/macOS/ShellXAutomations/Tests/ShellXAutomationsTests/ShellXCronExpressionTests.swift`, `ShellXAutomationValidatorTests.swift`, `ShellXSkillFrontmatterTests.swift`

**Interfaces:**
- Produces (all `public`, `Codable, Sendable, Equatable`, JSON camelCase):
  - `enum ShellXAutomationKind: String { case skill, workflow, cronjob }`
  - `enum ShellXNotifyEvent: String { case done, failed, needsYou }`, `enum ShellXNotifyTarget: String { case mac, iphone }`
  - `struct ShellXNotifySettings { var on: [ShellXNotifyEvent]; var targets: [ShellXNotifyTarget] }`
  - `struct ShellXSchedule { var cron: String; var human: String }`
  - `struct ShellXWorkflowStep { var title: String; var prompt: String }`
  - `struct ShellXAutomationDraft { var kind; var name: String; var description: String; var schedule: ShellXSchedule?; var workingDirectory: String?; var notify: ShellXNotifySettings; var allowedTools: [String]; var steps: [ShellXWorkflowStep]; var skillMarkdown: String }`
  - `enum ShellXAutomationOrigin: String { case shellx, external }`
  - `struct ShellXAutomation: Identifiable { let id: String; var kind; var name; var description; var schedule; var workingDirectory; var notify; var allowedTools; var steps; var enabled: Bool; var origin; var createdAt: Date; var updatedAt: Date; var directory: URL; var lastRun: ShellXRunRecord? }` (`directory` and `lastRun` excluded from `automation.json` coding)
  - `enum ShellXRunStatus: String { case running, done, failed, needsYou, skipped }`, `enum ShellXRunTrigger: String { case schedule, manual }`
  - `struct ShellXRunRecord { var status; var trigger; var startedAt: Date; var finishedAt: Date?; var sessionId: String?; var summary: String?; var reason: String?; var failedStep: Int?; var unread: Bool }`
  - `struct ShellXValidationIssue { enum Field: String { case name, description, schedule, workingDirectory, skillMarkdown, claude }; let field: Field; let code: String; let message: String }`
  - `struct ShellXSkillFrontmatter { let name: String; let description: String; init(markdown: String) throws }` (YAML between leading `---` lines; only `name`/`description` scalars needed, quoted or plain)
  - `struct ShellXCronExpression { init(_ text: String) throws(ShellXCronError); func launchdCalendarIntervals(limit: Int = 200) throws(ShellXCronError) -> [[String: Int]]; func nextFireDate(after: Date, calendar: Calendar) -> Date? }` — keys `Minute`, `Hour`, `Day`, `Weekday`, `Month`; a `*` field is omitted.
  - `struct ShellXAutomationValidator { init(existingNames: Set<String>, directoryExists: @Sendable (String) -> Bool, claudeAvailable: Bool); func validate(_ draft: ShellXAutomationDraft, replacingName: String?) -> [ShellXValidationIssue] }`

- [ ] **Step 1: Write failing tests**

```swift
@Test func dailyAtEight() throws {
    #expect(try ShellXCronExpression("0 8 * * *").launchdCalendarIntervals() == [["Minute": 0, "Hour": 8]])
}
@Test func everyFifteenMinutesWeekdays() throws {
    let entries = try ShellXCronExpression("*/15 9-10 * * 1-5").launchdCalendarIntervals()
    #expect(entries.count == 4 * 2 * 5)
    #expect(entries.contains(["Minute": 45, "Hour": 10, "Weekday": 5]))
}
@Test func sundayAsSeven() throws {
    #expect(try ShellXCronExpression("0 0 * * 7").launchdCalendarIntervals() == [["Minute": 0, "Hour": 0, "Weekday": 0]])
}
@Test(arguments: ["@daily", "0 8 * * MON", "61 * * * *", "0 9 1 * 1", "* * *", "*/7 * * * *"])
func rejected(_ text: String) {
    #expect(throws: ShellXCronError.self) { try ShellXCronExpression(text).launchdCalendarIntervals() }
}
```
(`*/7 * * * *` = 9 minutes × 24 hours = 216 entries > 200. `*/15 * * * *` = 96 entries is allowed.)
Also `nextFire`: `ShellXCronExpression("0 8 * * *").nextFireDate(after: 2026-11-03 09:00 local, calendar: fixed TZ)` == 2026-11-04 08:00.

Validator tests: `rejectsBadNames` over `["../x", "My Skill", "a--b", String(repeating: "a", count: 65), ""]` → each yields a `.name` issue; `rejectsDuplicateName` with `existingNames: ["pr-digest"]` → `.name` issue code `duplicate`, but not when `replacingName == "pr-digest"`; `cronjobNeedsScheduleAndDirectory` → `.schedule` and `.workingDirectory` issues; `skillMarkdownMustMatchName` (frontmatter `name` ≠ draft name → `.skillMarkdown` issue); `claudeMissing` (`claudeAvailable: false` and kind cronjob → `.claude` issue; kind skill → none); `descriptionTooLong` (1025 chars).

- [ ] **Step 2: Run** `swift test --package-path Packages/macOS/ShellXAutomations` — Expected: build failure / FAIL (types missing).
- [ ] **Step 3: Implement** the types above. Cron: expand each field to a sorted `Set<Int>`; the result is the cartesian product of the non-`*` fields; throw `.tooManyEntries` above `limit`, `.unsupported` for names/shortcuts, `.bothDayFields`, `.outOfRange(field:)`, `.malformed`.
- [ ] **Step 4: Run** the same command — Expected: PASS.
- [ ] **Step 5: Commit** `feat(shellx): automation values, validation and cron mapping`

### Task 2: Environment and on-disk store

**Files:**
- Create: `.../Store/ShellXAutomationEnvironment.swift`, `ShellXAutomationStore.swift`, `ShellXTrashing.swift`, `ShellXFileManagerTrasher.swift`, `ShellXSkillMarker.swift`
- Test: `ShellXAutomationEnvironmentTests.swift`, `ShellXAutomationStoreTests.swift`

**Interfaces:**
- Consumes: Task 1 values.
- Produces:
  - `struct ShellXAutomationEnvironment: Sendable { let skillsRoot: URL; let automationsRoot: URL; let launchAgentsDirectory: URL; let labelPrefix: String; let cliPath: String; let notifierAppPath: String; init(bundleIdentifier: String, home: URL, cliPath: String, notifierAppPath: String) }` (release vs dev rules from Global Constraints; `changeStampURL` = `automationsRoot/.changed`)
  - `protocol ShellXTrashing: Sendable { func trash(_ url: URL) throws }` — concrete `ShellXFileManagerTrasher` uses `FileManager.trashItem`.
  - `struct ShellXSkillMarker: Codable { let id: String; var notify: ShellXNotifySettings; var createdAt: Date; var updatedAt: Date; let bundleIdentifier: String }`
  - `actor ShellXAutomationStore { init(environment:, fileManager: FileManager = .default, trasher: any ShellXTrashing, now: @Sendable () -> Date); func list() throws -> [ShellXAutomation]; func automation(id: String) throws -> ShellXAutomation?; func automation(named: String) throws -> ShellXAutomation?; func save(_ draft: ShellXAutomationDraft, replacing id: String?) throws -> ShellXAutomation; func setEnabled(id: String, _ enabled: Bool) throws -> ShellXAutomation; func delete(id: String) throws; func beginRun(id: String, trigger: ShellXRunTrigger, pid: Int32, isProcessAlive: @Sendable (Int32) -> Bool) throws -> URL?; func finishRun(id: String, runDirectory: URL, record: ShellXRunRecord) throws; func runs(id: String, limit: Int) throws -> [ShellXRunRecord]; func markRead(id: String) throws; func touchChangeStamp() throws }`
  - Ids: ShellX-made = UUID string; external skills = `external:<dirname>` (origin `.external`, `kind .skill`, notify empty, `enabled true`).
  - `beginRun` creates `run.lock` with `O_CREAT|O_EXCL` holding the pid and a `runs/<stamp>/` directory with a `running` `result.json`; returns `nil` when a live process holds the lock; replaces a lock whose pid is dead.

- [ ] **Step 1: Write failing tests** (all on a temp `home`):
  - `releaseAndDevRoots`: bundle `pro.shellx.desktop` → `~/.shellx/automations`, prefix `pro.shellx.automation.`; bundle `pro.shellx.desktop.dev.foo` → `~/.shellx/automations-dev/pro.shellx.desktop.dev.foo`, prefix `pro.shellx.automation.dev.pro.shellx.desktop.dev.foo.`.
  - `savesSkillWhereClaudeLoadsIt`: save a skill draft → `skillsRoot/pr-digest/SKILL.md` equals `draft.skillMarkdown`, `.shellx.json` exists; `list()` returns it with origin `.shellx`.
  - `savesCronjob`: `automationsRoot/<uuid>/automation.json` decodes to the draft fields, `SKILL.md` written, `enabled == true`.
  - `listsExternalSkills`: a pre-existing `skillsRoot/other/SKILL.md` without marker → listed with id `external:other`, origin `.external`; a folder without `SKILL.md` (like `synced/`) is ignored.
  - `savesNeverEscapeRoots`: saving with name `../evil` throws and writes nothing outside the roots.
  - `editRenamesSkillFolder`: replacing id with a new name moves the folder.
  - `deleteMovesToTrash`: fake trasher records the folder URL; nothing removed with `removeItem`.
  - `keepsThirtyRuns`: 31 finished runs → `runs/` holds 30, oldest gone.
  - `skipsWhileLocked` / `takesOverStaleLock`: `beginRun` with a live pid → `nil`; with `isProcessAlive` false → new run URL.
  - `changeStampIsAtomic`: `touchChangeStamp()` writes `.changed` via replace (the directory's entry changes).
- [ ] **Step 2: Run** `swift test --package-path Packages/macOS/ShellXAutomations --filter "ShellXAutomationStore|ShellXAutomationEnvironment"` — Expected: FAIL.
- [ ] **Step 3: Implement.** Writes are atomic (`Data.write(options: .atomic)`); dates ISO-8601 in JSON; every save/delete/finishRun ends with `touchChangeStamp()`.
- [ ] **Step 4: Run** the same command — Expected: PASS.
- [ ] **Step 5: Commit** `feat(shellx): automation store`

### Task 3: launchd scheduler

**Files:**
- Create: `.../Schedule/ShellXLaunchctlRunning.swift`, `ShellXProcessLaunchctl.swift`, `ShellXLaunchAgentScheduler.swift`
- Test: `ShellXLaunchAgentSchedulerTests.swift`

**Interfaces:**
- Consumes: `ShellXAutomationEnvironment`, `ShellXAutomation`, `ShellXCronExpression`.
- Produces:
  - `protocol ShellXLaunchctlRunning: Sendable { func run(_ arguments: [String]) async throws -> (status: Int32, output: String) }`; concrete `ShellXProcessLaunchctl` runs `/bin/launchctl`.
  - `struct ShellXLaunchAgentScheduler: Sendable { init(environment:, launchctl: any ShellXLaunchctlRunning, userID: uid_t, fileManager: FileManager = .default); func label(for id: String) -> String; func plistData(for automation: ShellXAutomation) throws -> Data; func install(_ automation: ShellXAutomation) async throws; func remove(id: String) async throws; func sync(_ automations: [ShellXAutomation]) async throws }`
  - Plist: `Label`; `ProgramArguments = [cliPath, "routine", "run", id, "--trigger", "schedule"]`; `StartCalendarInterval` from the cron; `StandardOutPath`/`StandardErrorPath` = `<automation dir>/launchd.log`; `WorkingDirectory` = the automation's working dir; `ProcessType = "Background"`; no `RunAtLoad`.
  - `install`: write plist, `bootout gui/<uid>/<label>` (ignore "not loaded"), `bootstrap gui/<uid> <plist>`. `remove`: `bootout` then delete the plist. `sync`: installs enabled scheduled automations whose plist is missing or differs (also when `cliPath` changed after an app move/update) and removes plists with our prefix that have no enabled automation.

- [ ] **Step 1: Write failing tests** with a recording fake launchctl and temp dirs: `plistMatchesSpec` (decode with `PropertyListSerialization`, assert every key above); `installBootsOutThenBootstraps` (exact argv sequence); `removeOnlyOwnLabels` (`remove(id:)` for a label outside the prefix never calls launchctl — call `sync` with a foreign plist `com.google.keystone.agent.plist` in the dir and assert it is untouched); `syncRewritesWhenCliPathChanged`; `disabledAutomationIsRemoved`; `skillsAreNeverScheduled`.
- [ ] **Step 2: Run** `swift test --package-path Packages/macOS/ShellXAutomations --filter ShellXLaunchAgentScheduler` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the same — Expected: PASS.
- [ ] **Step 5: Commit** `feat(shellx): launchd scheduler for automations`

### Task 4: Headless runner and notification decision

**Files:**
- Create: `.../Run/ShellXClaudeExecutableResolver.swift`, `ShellXClaudeLaunching.swift`, `ShellXClaudeProcess.swift`, `ShellXClaudeResult.swift`, `ShellXStreamJSONResultReader.swift`, `ShellXAutomationRunner.swift`, `ShellXNotifying.swift`, `ShellXAutomationNotification.swift`
- Test: `ShellXStreamJSONResultReaderTests.swift`, `ShellXClaudeExecutableResolverTests.swift`, `ShellXAutomationRunnerTests.swift`, fixtures `Tests/ShellXAutomationsTests/Fixtures/*.jsonl`

**Interfaces:**
- Consumes: store (Task 2).
- Produces:
  - `struct ShellXClaudeExecutableResolver { init(environment: [String: String], home: URL, isExecutable: @Sendable (String) -> Bool, loginShellLookup: @Sendable () -> String?); func resolve() -> String? }` — order: `$SHELLX_CLAUDE_PATH`, `~/.claude/local/claude`, `~/.local/bin/claude`, `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`, then `loginShellLookup` (`/bin/zsh -lc 'command -v claude'`). Never ShellX's own `shellx-claude-wrapper`.
  - `struct ShellXClaudeResult { var sessionId: String?; var resultText: String?; var isError: Bool; var permissionDenials: [String]; var exitCode: Int32; var stderrTail: String }`
  - `struct ShellXStreamJSONResultReader { mutating func ingest(line: String); var result: ShellXClaudeResult { get } }` — reads `system/init` `session_id`, the final `result` event (`result`, `is_error`, `permission_denials[].tool_name`).
  - `protocol ShellXClaudeLaunching: Sendable { func run(prompt: String, workingDirectory: URL, allowedTools: [String], resumeSessionId: String?, transcript: URL) async throws -> ShellXClaudeResult }`; `ShellXClaudeProcess` builds argv `[claude, "-p", prompt, "--output-format", "stream-json", "--verbose", "--allowedTools", allowedTools.joined(separator: ","), ("--resume", id)?]`, appends every stdout line to `transcript`, drains pipes on detached tasks.
  - `struct ShellXAutomationNotification: Sendable, Equatable { let title: String; let body: String; let url: URL; let group: String }`; `protocol ShellXNotifying: Sendable { func post(_ n: ShellXAutomationNotification) async throws }`
  - `actor ShellXAutomationRunner { init(store: ShellXAutomationStore, claude: (any ShellXClaudeLaunching)?, notifier: any ShellXNotifying, pid: Int32, isProcessAlive: @Sendable (Int32) -> Bool, now: @Sendable () -> Date); func run(id: String, trigger: ShellXRunTrigger) async -> ShellXRunRecord }`
  - Prompt per step: the automation's `SKILL.md` body (frontmatter stripped) for a cronjob, or the step prompt for a workflow, then the fixed runner suffix: `"\n\nYou are running unattended. If you need the user to decide or approve something, stop and end your final message with one line: SHELLX_NEEDS_YOU: <short reason>."`
  - Outcome: `claude == nil` → failed "Claude Code was not found."; exit ≠ 0 or `isError` or no result → failed (`stderrTail` last line or "Claude Code exited with status N."); denials → needsYou "Needs permission for: <tools>"; marker → needsYou(reason); else done(summary = result text without marker). Workflow steps resume the previous `sessionId`; first non-done step stops with `failedStep` (1-based).
  - Notify only when the status is in `notify.on` and `targets` contains `.mac`; `url = shellx://automations/<id>`; `group = id`. Skipped runs never notify.

- [ ] **Step 1: Write failing tests:** reader fixtures (`success.jsonl`, `permission-denied.jsonl`, `error.jsonl`, `no-result.jsonl` — copy real event shapes from a local `claude -p "say hi" --output-format stream-json --verbose` run in a temp dir); resolver order; runner with fake claude + fake notifier:
  `doneNotifiesWithSummary` (body truncated to 180 + "…"), `failedWhenClaudeMissing`, `failedOnNonZeroExit`, `failedWhenNoResultEvent`, `needsYouOnPermissionDenial`, `needsYouOnMarker` (summary excludes the marker line), `workflowResumesSessionAndStopsAtFailedStep` (second call gets `resumeSessionId == "s1"`, record `failedStep == 2`, third step never runs), `notifyRespectsSettings` (`on: [.failed]` + done → no post; `targets: [.iphone]` → no post), `skipsWhileLocked` (no claude call, no post, status `.skipped`), `recordsRunAndTouchesStamp`.
- [ ] **Step 2: Run** `swift test --package-path Packages/macOS/ShellXAutomations --filter "ShellXStreamJSON|ShellXClaudeExecutable|ShellXAutomationRunner"` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the same — Expected: PASS.
- [ ] **Step 5: Commit** `feat(shellx): headless automation runner`

### Task 5: Notifier helper app, CLI `shellx routine`, project wiring

**Files:**
- Create: `workers/shellx-notifier/main.swift`, `workers/shellx-notifier/Info.plist`
- Create: `scripts/shellx/build-shellx-notifier.sh`
- Modify: `scripts/build-app-bundled-resources.sh` (call the notifier build into `${DEST}/../Library/ShellX Notifier.app`, mirroring the Computer Use helper block), `scripts/sign-cmux-bundle.sh` (sign `Contents/Library/ShellX Notifier.app` with the Developer ID identity, hardened runtime and `$HELPER_ENTITLEMENTS`, before the main app; add to the header's ordered list), `scripts/reload.sh` only if it enumerates helpers.
- Create: `Packages/macOS/ShellXAutomations/Sources/ShellXAutomations/Notify/ShellXNotifierClient.swift`
- Create: `CLI/CMUXCLI+Routine.swift`; Modify: `CLI/cmux.swift` (early socket-free dispatch next to `if command == "docs"` at ~line 6526: `if command == "routine" { try await runRoutineCommand(commandArgs: commandArgs, jsonOutput: jsonOutput); return }`, plus help text)
- Modify: `cmux.xcodeproj/project.pbxproj` (package into `cmux`, `cmuxTests`, `cmux-cli`; `CMUXCLI+Routine.swift` into `cmux-cli`)
- Test: `ShellXNotifierClientTests.swift` (package); `cmuxCLITests/RoutineCommandTests.swift` if `cmuxCLITests` can exercise arg parsing, else package-level `ShellXRoutineArgumentsTests.swift` with the parser moved into the package as `struct ShellXRoutineArguments`.

**Interfaces:**
- Consumes: Tasks 2–4.
- Produces:
  - Helper: bundle id `<main bundle id>.notifier`, name `ShellX Notifier`, `LSUIElement = true`, icon `AppIcon.icns` copied from `Resources/` (or the built app's Resources). Args `--title T --body B --url U --group G`. Posts one `UNNotificationRequest` (thread id `G`, `userInfo["url"] = U`), requests authorization on first use, quits after the add completes; when relaunched by a click, `didReceive` opens `U` with `NSWorkspace` and quits.
  - `struct ShellXNotifierClient: ShellXNotifying { init(helperAppPath: String, runOpen: @Sendable ([String]) async throws -> Int32) }` → argv `["/usr/bin/open", "-g", "-n", "-a", helperAppPath, "--args", "--title", …, "--url", …, "--group", …]`.
  - `struct ShellXRoutineArguments` parsing:
    - `routine run <id> [--trigger schedule|manual]`
    - `routine notify --name <name> --status done|failed|needs-you --body <text>` (posts regardless of settings; url `shellx://automations/<id>` when the name matches, else `shellx://automations`)
    - `routine list [--json]` (name, kind, enabled, last status)
  - Paths from the CLI: `cliPath` = the running executable; `notifierAppPath` = `<bundle>/Contents/Library/ShellX Notifier.app` derived from `.../Contents/Resources/bin/shellx`; bundle id read from `<bundle>/Contents/Info.plist`.

- [ ] **Step 1: Write failing tests:** `ShellXNotifierClientTests.exactArgv`; `ShellXRoutineArgumentsTests` (`run abc` → `.run(id: "abc", trigger: .manual)`; `--trigger schedule`; `notify` missing `--status` → error; unknown subcommand → usage error).
- [ ] **Step 2: Run** `swift test --package-path Packages/macOS/ShellXAutomations --filter "ShellXNotifierClient|ShellXRoutineArguments"` — Expected: FAIL.
- [ ] **Step 3: Implement** helper, build script (compile with `xcrun --sdk macosx swiftc -O -target <arch>-apple-macos14.0` per arch, `lipo` for universal, ad-hoc sign like `scripts/build-plain-text-paste-worker.sh`), client, CLI command, pbxproj wiring.
- [ ] **Step 4: Verify**
  - `swift test --package-path Packages/macOS/ShellXAutomations` — PASS
  - `scripts/normalize-pbxproj.py && scripts/check-pbxproj.sh && python3 scripts/check-workspace-package-groups.py --check && python3 scripts/check-package-resolved-policy.py` — clean
  - `scripts/test-unit.sh build` — BUILD SUCCEEDED; the built app contains `Contents/Library/ShellX Notifier.app` and `codesign --verify --deep --strict` passes on it.
  - Manual: run the built app's `Contents/Resources/bin/shellx routine notify --name test --status done --body hi` → a "ShellX Notifier" banner appears (first time: allow notifications); clicking it opens a `shellx://automations` URL (ShellX ignores it until Task 8).
- [ ] **Step 5: Commit** `feat(shellx): shellx routine CLI and notifier helper`

### Task 6: Creator assistant session

**Files:**
- Create: `Resources/shellx-automations/creator-system-prompt.md`, `Resources/shellx-automations/LICENSE-skill-creator.txt` (Apache-2.0 text from the skill-creator plugin), and add both to the app's bundled resources.
- Create: `.../Creator/ShellXCreatorEvent.swift`, `ShellXCreatorChoices.swift`, `ShellXAssistantBlockParser.swift`, `ShellXCreatorProcessLaunching.swift`, `ShellXCreatorProcess.swift`, `ShellXCreatorSession.swift`, `ShellXCreatorSeed.swift`
- Test: `ShellXAssistantBlockParserTests.swift`, `ShellXCreatorSessionTests.swift`

**Interfaces:**
- Produces:
  - `struct ShellXCreatorChoices: Codable, Sendable, Equatable { let question: String; let multi: Bool; let options: [String] }`
  - `enum ShellXCreatorEvent: Sendable, Equatable { case textDelta(String); case assistantMessage(text: String, choices: ShellXCreatorChoices?); case draft(ShellXAutomationDraft); case busy(Bool); case failed(String) }`
  - `struct ShellXAssistantBlockParser { mutating func ingest(delta: String) -> String /* visible text only */; func finish(fullText: String) -> (visible: String, draft: ShellXAutomationDraft?, choices: ShellXCreatorChoices?) }` — blocks are fenced ```` ```shellx-draft ```` / ```` ```shellx-choices ```` with JSON bodies; text after an unclosed `shellx-` fence is hidden until it closes; the last valid draft wins; invalid JSON is dropped.
  - `protocol ShellXCreatorProcessLaunching: Sendable { func start(arguments: [String], workingDirectory: URL) async throws -> (lines: AsyncThrowingStream<String, any Error>, send: @Sendable (String) async throws -> Void, stop: @Sendable () async -> Void) }`
  - `actor ShellXCreatorSession { init(launcher: any ShellXCreatorProcessLaunching, claudePath: String, systemPrompt: String, workingDirectory: URL, localeIdentifier: String, cliPath: String);` (replaces `{{SHELLX_CLI}}` in the prompt with the absolute `cliPath`, so skills call the CLI by full path and work from any terminal) var events: AsyncStream<ShellXCreatorEvent> { get }; func start(seed: ShellXCreatorSeed?) async throws; func send(_ text: String) async throws; func cancel() async }`
  - Arguments: `["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--include-partial-messages", "--verbose", "--append-system-prompt", prompt, "--allowedTools", "Read,Glob,Grep", "--disallowedTools", "Bash,Edit,Write,NotebookEdit,WebFetch,WebSearch"]`. User messages are written as `{"type":"user","message":{"role":"user","content":[{"type":"text","text":…}]}}` lines.
  - `struct ShellXCreatorSeed { let automation: ShellXAutomation; let skillMarkdown: String }` → first user message: "Edit this existing <kind> named <name>." plus `automation.json` and `SKILL.md` in fenced blocks.
  - System prompt content (`creator-system-prompt.md`), in this order: Apache-2.0 attribution line; role (help the user create a Claude Code skill, workflow or cronjob for ShellX); reply in the user's language (locale hint appended by the session); ask one question at a time; skill-creator rules (capture intent, precise trigger-oriented `description` ≤ 1024 chars, kebab-case `name` ≤ 64, lean `SKILL.md`, frontmatter `name`/`description`); type choice; for cronjob/workflow ask schedule (numeric 5-field cron only, never both day fields), working directory and which tools it may use (map to Claude Code tool patterns such as `Read`, `Grep`, `Bash(gh pr list:*)`, `Edit`); **always ask about notifications** (when: done / failed / needs you / never; where: Mac / iPhone) using a `shellx-choices` block; emit an updated `shellx-draft` block whenever the draft changes, matching the `ShellXAutomationDraft` JSON schema (include the schema verbatim); for skills that asked for notifications, end `SKILL.md` with a step that runs `"{{SHELLX_CLI}}" routine notify --name <name> --status done|failed|needs-you --body "<summary>"`; never write files yourself.

- [ ] **Step 1: Write failing tests:** parser — `hidesDraftBlockFromChat`, `lastValidDraftWins` (two blocks, second malformed → first kept), `unclosedFenceStaysHiddenAcrossDeltas` (split ```` ``` ```` and `shellx-draft` across three deltas), `parsesChoices`, `plainCodeFencesStayVisible` (```` ```bash ```` is shown); session with a fake launcher that replays a fixture stream → events sequence `[.busy(true), .textDelta…, .draft(d), .assistantMessage(text:, choices:), .busy(false)]`, `sendWritesStreamJSONUserLine` (exact JSON line), `seedFirstMessageContainsFiles`, `processExitBecomesFailed`.
- [ ] **Step 2: Run** `swift test --package-path Packages/macOS/ShellXAutomations --filter "ShellXAssistantBlockParser|ShellXCreatorSession"` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the same — Expected: PASS.
- [ ] **Step 5: Commit** `feat(shellx): automation creator session`

### Task 7: Webviews `automations` surface

**Files:**
- Create: `webviews/src/automations/types.ts`, `bridge.ts`, `store.ts`, `labels.ts`, `AutomationsApp.tsx`, `ListView.tsx`, `AutomationCard.tsx`, `CreatorView.tsx`, `ChatTranscript.tsx`, `DraftCard.tsx`, `PerspectiveGrid.tsx`, `ConfirmDialog.tsx`, `styles.css`
- Create: `webviews/src/surfaces/automationsSurface.tsx`
- Modify: `webviews/src/main.tsx` (kind `"automations"`), plus every page/chunk touch point the Git Graph added (`grep -rn "git-graph\|gitGraph" webviews/vite.config.mjs scripts/build-webviews-app.sh` and `WebviewsAppPage`) so the build emits `automations.html` and `chunks/automationsSurface.mjs`.
- Test: `webviews/src/automations/store.test.ts`, `bridge.test.ts`, `DraftCard.test.tsx`

**Interfaces:**
- Produces (page side of the bridge; host side in Task 8). Handler name `shellxAutomations`; the page posts `{method, params}` and gets `{ok, result}` / `{ok:false, error:{code,message}}`; the host pushes `window.shellxAutomations.receive(event)`.
  - Methods: `app.context` → `{labels, focusId?, reduceMotion}`; `automations.list` → `{automations: AutomationDTO[]}`; `automations.runNow {id}`; `automations.setEnabled {id, enabled}`; `automations.delete {id}`; `automations.reveal {id}`; `automations.editFile {id}`; `automations.openLog {id}`; `automations.continueInTerminal {id}`; `automations.markRead {id}`; `creator.start {editId?}`; `creator.send {text}`; `creator.cancel`; `creator.save` → `{automation}` or `{issues: ValidationIssueDTO[]}`.
  - Events: `automations.changed`; `creator.event` with `{type: "textDelta"|"assistantMessage"|"draft"|"busy"|"failed"|"validation", …}`; `focus {id}`.
  - `AutomationDTO` mirrors `ShellXAutomation` + `lastRun` + `nextRun?: string` (ISO) + `iphonePending: boolean`.
- UI per spec §2 and the mockup: List with filter tabs All/Skills/Workflows/Cronjobs, `+ New`, cards (type badge, name, description, human schedule, next run, last result with running in yellow, Mac/iPhone icons, unread dot, actions); external skills under "Your other skills". Creator: chat left 42 %, input with type picker Auto/Skill/Workflow/Cronjob (the chosen type is prepended to the first message as "Type: cronjob."), choices render as chips (multi-select chips + "Send"), right side `PerspectiveGrid` + `DraftCard` that reveals fields as they appear, status "drafting…" / "✓ ready", Save / Keep editing; validation issues shown inline on the card. Delete confirm is an in-page dialog (never `window.confirm`); external skills get the extra "ShellX did not create this skill" warning. All text from `labels`; all user/model text rendered as React text (no `dangerouslySetInnerHTML`).
  - `PerspectiveGrid`: canvas 2D, vanishing point at 52 % height, faint white lines, horizontals drifting toward the viewer, 16 pulses in the six pulse colors moving along random lines; speed ×1 while `busy`, ×0.3 idle; static frame when `reduceMotion` or `prefers-reduced-motion`; follows light/dark via CSS variables from `appearance.ts`.

- [ ] **Step 1: Write failing tests:** `store.test.ts` — `appliesDraftEventsKeepingLastGood`, `textDeltasAppendToStreamingMessage`, `assistantMessageReplacesStreaming`, `filtersByKind`, `externalSkillsGroupedSeparately`, `focusEventSelectsCard`; `bridge.test.ts` — request/reply pairing and error mapping (copy Git Graph's bridge tests' shape); `DraftCard.test.tsx` — fields appear only once present, issues render under their field, iPhone shows the pending label.
- [ ] **Step 2: Run** `cd webviews && bun test src/automations` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Verify** `cd webviews && bun test src/automations && bun run lint && cd .. && ./scripts/build-webviews-app.sh && ./scripts/build-webviews-app.sh --check && ls Resources/markdown-viewer/webviews-app/automations.html` — all pass.
- [ ] **Step 5: Commit** `feat(shellx): automations web surface`

### Task 8: App host — panel, controller, library, URL route

**Files:**
- Create: `Sources/ShellX/Automations/ShellXAutomationsBridgeContract.swift`, `ShellXAutomationsController.swift`, `ShellXAutomationsLabels.swift`, `ShellXAutomationsLibrary.swift`, `ShellXAutomationsPanel.swift`, `ShellXAutomationsPanelView.swift`, `ShellXAutomationsWebView.swift`, `ShellXAutomationsURL.swift`, `AppDelegate+ShellXAutomations.swift`
- Modify: `Sources/Panels/Panel.swift` (`case automations`, decoder), every exhaustive `switch` the compiler flags (same sites as `.mobilePairing`: `Workspace.swift`, `PanelContentView.swift`, `Workspace+SurfaceNavigation.swift` (+ `SurfaceKind.automations`), `ClosedItemHistory+PanelTitle.swift`, `ContentView+CommandPaletteSurfaceMetadata.swift`, `CmuxLifecycleEventPublishing.swift`, `TerminalController+MobileSurfaces.swift`, `Workspace+LayoutCapture.swift` (not restorable: excluded from layout capture like `.mobilePairing`), `PaneDropContainer.swift`, `ContentView+SidebarSurfaceKind.swift`, `Canvas/WorkspaceCanvasHostView.swift` (icon `sparkles`), `Search/GlobalSearchDocuments.swift`); `Sources/AppDelegate.swift` `application(_:open:)` (route `shellx://automations[/<id>]` before the auth/external handlers); `Resources/Localizable.xcstrings`.
- Reuse: `GitGraphPageAssets(root:page:)` with a new `WebviewsAppPage.automations`, and `GitGraphURLSchemeHandler` (generalize its name only if it hard-codes Git Graph; otherwise pass the assets).
- Test: `cmuxTests/ShellXAutomationsControllerTests.swift`, `cmuxTests/ShellXAutomationsURLTests.swift`, `cmuxTests/ShellXAutomationsLibraryTests.swift`

**Interfaces:**
- Consumes: package (Tasks 1–6), page contract (Task 7).
- Produces:
  - `@MainActor @Observable final class ShellXAutomationsLibrary { init(store: ShellXAutomationStore, scheduler: ShellXLaunchAgentScheduler, changeStampURL: URL); private(set) var automations: [ShellXAutomation]; var count: Int { get }; var unreadCount: Int { get }; func reload() async; func startWatching(); func stopWatching() }` — watches `automationsRoot` with a `DispatchSource` file-system source (carve-out comment) and reloads on change; on first load calls `scheduler.sync`.
  - `@MainActor final class ShellXAutomationsController { init(library:, store:, scheduler:, creatorFactory: @escaping (ShellXCreatorSeed?) -> ShellXCreatorSession, runLauncher: @escaping @Sendable (String) -> Void, terminalOpener: @escaping (ShellXAutomation) -> Void, fileOpener: @escaping (URL) -> Void, makeValidator: @escaping (_ replacingName: String?) async -> ShellXAutomationValidator); func handle(method: String, params: [String: Any]) async -> [String: Any]; var emit: (([String: Any]) -> Void)?; func focus(id: String?) }`
    - `creator.save`: validate → on issues emit `validation` and return them (also send a short "Fix: …" user message to the session so the model corrects the draft) → `store.save` → for enabled scheduled kinds `scheduler.install` → return the automation.
    - `automations.runNow`: `runLauncher(id)` spawns `<cliPath> routine run <id> --trigger manual` detached (one run path).
    - `automations.delete`: `scheduler.remove(id:)` then `store.delete(id:)`.
    - `automations.continueInTerminal`: opens a terminal tab in the focused workspace at the working directory running `claude --resume <lastRun.sessionId>`, via the same API the existing "new terminal with command" path uses (`grep -rn "initialCommand" Sources/Workspace*.swift`).
  - `final class ShellXAutomationsPanel: Panel` (`panelType = .automations`, title "Automations", icon `sparkles`), owns one controller + web view; `AppDelegate.openShellXAutomations(focusId: String?)` reuses an existing `.automations` panel in the focused workspace (like `MobilePairingPanel` at `AppDelegate.swift:~8759`) or creates one, then `focus(id:)`.
  - `struct ShellXAutomationsURL { init?(_ url: URL); let focusId: String? }` — accepts `shellx://automations` and `shellx://automations/<id>` only.
  - App composition: `AppDelegate` builds `ShellXAutomationEnvironment(bundleIdentifier: Bundle.main.bundleIdentifier, home:, cliPath: <bundle>/Contents/Resources/bin/shellx, notifierAppPath: <bundle>/Contents/Library/ShellX Notifier.app)`, the store, scheduler and `shellXAutomationsLibrary` at launch and starts watching.

- [ ] **Step 1: Write failing tests:** URL parsing (accepts both forms; rejects `shellx://auth/...`, `shellx://automations/../x`, other schemes); controller with temp-dir store, fake launchctl, fake creator: `listReturnsDTOs`, `saveRejectsInvalidDraftWithIssues`, `saveInstallsSchedule` (fake launchctl saw bootstrap), `deleteBootsOutBeforeTrash` (order), `runNowUsesRunLauncher`, `externalSkillDeleteRequiresConfirmFlag` (`automations.delete` for an `external:` id without `confirmedExternal: true` → `notAllowed`); library `reloadsWhenStampChanges`.
- [ ] **Step 2: Run** `python3 scripts/wire-app-sources.py Sources/ShellX/Automations/*.swift && ./scripts/sync-test-wiring && scripts/shellx/test-app.sh ShellXAutomationsControllerTests ShellXAutomationsURLTests ShellXAutomationsLibraryTests` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the same tests — Expected: PASS; then `python3 scripts/localization_catalog.py check` — clean.
- [ ] **Step 5: Commit** `feat(shellx): automations panel and controller`

### Task 9: Animated sidebar button

**Files:**
- Create: `Sources/ShellX/Sidebar/ShellXAutomationsSidebarButton.swift`
- Modify: `Sources/ShellX/Sidebar/SidebarBrandHeaderView.swift` (add the button between the brand line and "YOUR MACHINES"), `Sources/ShellX/Sidebar/ShellXSidebarHeaderRow.swift` (`ShellXSidebarHeaderMetrics.automationsRowHeight = 36`, `brandHeight = brandLineHeight + automationsRowHeight + 26` = 98), `Resources/Localizable.xcstrings`
- Test: `cmuxTests/ShellXAutomationsSidebarButtonTests.swift`

**Interfaces:**
- Consumes: `AppDelegate.shared?.shellXAutomationsLibrary` (count), `AppDelegate.openShellXAutomations(focusId:)`.
- Produces: `@MainActor final class ShellXAutomationsSidebarButton: NSView { var count: Int; var reduceMotion: Bool; var onClick: (() -> Void)?; var isRingAnimating: Bool { get } }`
  - Layout: full row width minus the row paddings, 28 pt tall, corner radius 9, normal sidebar row fill; label `✦ Automations` / vi `✦ Tự động hoá` (`sidebar.automations.button`), trailing count pill hidden at 0, small unread dot when `unreadCount > 0`.
  - Ring: `CAGradientLayer` (`type = .conic`, the five ring colors) masked by a 1 pt `CAShapeLayer` stroke of the rounded rect; a `CABasicAnimation` on `transform.rotation.z` of the gradient (duration 4, repeat ∞) — layer-only, so the table never re-renders; ✦ twinkle = 2.4 s scale/opacity animation on its own layer. Reduce Motion (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`, observe `accessibilityDisplayOptionsDidChangeNotification`) removes both animations. Animations pause while the window is not visible (`viewDidMoveToWindow` / occlusion).
  - Count updates: the brand cell re-arms `withObservationTracking` on the library's `count`/`unreadCount` and updates only the button.
  - Accessibility label "Automations, <count>"; tooltip "Create and manage skills, workflows and cronjobs".

- [ ] **Step 1: Write failing tests:** `ringAnimatesByDefault` (`isRingAnimating == true` once in a window), `reduceMotionStopsRing`, `countPillHiddenAtZero`, `clickCallsOnClick`, `brandHeaderHeightIs98`.
- [ ] **Step 2: Run** `python3 scripts/wire-app-sources.py Sources/ShellX/Sidebar/ShellXAutomationsSidebarButton.swift && ./scripts/sync-test-wiring && scripts/shellx/test-app.sh ShellXAutomationsSidebarButtonTests` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the same plus existing sidebar suites `scripts/shellx/test-app.sh $(ls cmuxTests | grep -E '^Sidebar(Brand|WorkspaceTable).*Tests.swift' | sed 's/.swift//' | tr '\n' ' ')` — Expected: PASS (row-height expectations updated only where they assert the brand height).
- [ ] **Step 5: Commit** `feat(shellx): animated Automations button in the sidebar`

### Task 10: End-to-end verification and visual check

**Files:**
- Create: `Packages/macOS/ShellXAutomations/Tests/ShellXAutomationsTests/ShellXAutomationRunnerLiveTests.swift` (kept; skipped unless `SHELLX_LIVE_CLAUDE=1`)
- A throwaway snapshot test (deleted before commit).

- [ ] **Step 1: Full checks** — `python3 scripts/verify-local.py && swift test --package-path Packages/macOS/ShellXAutomations && (cd webviews && bun test src/automations && bun run build) && ./scripts/build-webviews-app.sh --check && python3 scripts/wire-app-sources.py --check && python3 scripts/localization_catalog.py check && scripts/test-unit.sh build` — all pass.
- [ ] **Step 2: One real Claude run.** The live test uses a temp store, the real resolved `claude`, a cronjob whose `SKILL.md` body is "Reply with the word ok.", `allowedTools: []`, and a recording notifier. Run `SHELLX_LIVE_CLAUDE=1 swift test --package-path Packages/macOS/ShellXAutomations --filter ShellXAutomationRunnerLiveTests` — Expected: record status `done`, summary contains "ok", one notification recorded. It never touches the user's real store, skills or LaunchAgents.
- [ ] **Step 3: Visual check** per memory "local visual check": a throwaway test renders the sidebar brand cell and the automations panel (web view snapshot after load with a fixture list and a fixture creator draft) to PNGs in the scratchpad; compare with the mockup; then delete the test and run `./scripts/sync-test-wiring`.
- [ ] **Step 4: Tagged-build dogfood (only if the user asks):** `CMUX_TAG=automations` per `skills/cmux-dev-workflow/references/tagged-builds.md`; uses the dev store/label prefix, so it never touches release automations.
- [ ] **Step 5: Commit** any fixes; push `feat/shellx-automation-creator`; open a PR to `develop` with the `## Changelog` line `Added: Automations — create Claude Code skills, workflows and cronjobs from the sidebar, with notifications.` and the disclosed skipped verification.
