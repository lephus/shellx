# ShellX remove a gone session from the phone (part 5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** a session whose Mac answered `not_found` ("This session is gone from the Mac") can be removed from the iPhone, so a ghost "Running" card stops sitting on the home screen. iOS only; works with any Mac version.

**Spec:** `docs/superpowers/specs/2026-10-29-shellx-mobile-home-focus-design.md` §6.8.

## Global Constraints

- Only a session the phone has seen answered `not_found` (`AgentThreadModel.noteNotFound` → `sessionGone`) can be removed. A session that was never answered `not_found` never gets the action, anywhere.
- Removal is phone-local: nothing is sent to the Mac.
- A removal is keyed by Mac id + session id and stamped with the session's `state`, `stateSinceMs` and `lastActivityMs` at removal. The session is hidden while the Mac still reports exactly that stamp; any change shows it again.
- Persist in `UserDefaults` (own key, e.g. `shellx.removedGone`), pruned 30 days after each removal (phone clock); unreadable data counts as none. Model it on `EndedDismissals`/`EndedDismissalStore` (`shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Home/EndedDismissals.swift`): a pure `Sendable`/`Codable` value type plus a `@MainActor @Observable` store.
- One shared filter hides removed sessions from every phone list and count that `hub.reachableSessions` feeds: home groups (Needs you / Running / Just finished, and Ended), the outside-workspace list, workspace-list agent cards, and the counts shown for them.
- "Known gone this run": an in-memory set of refs the agent screen saw answered `not_found`; the home and outside-workspace swipe action appears only for these.
- Strings in `shellx-ios/ShellX/Localizable.xcstrings` with `en` "Remove from This Phone", `vi` "Gỡ khỏi điện thoại", and comments; `check-strings.py` must pass. No confirmation dialog, no ellipsis.
- Agent screen: the action sits next to the gone line and in the `•••` menu, only when not embedded; after removal the screen goes back.
- Commit the failing test first; stage by explicit path. Never touch `shellx-ios/ShellX/UI/Settings/AboutSection.swift` or `shellx-ios/ShellXTests/AccountRenderTests.swift` (someone else's WIP).

---

### Task 1: iPhone

**Files:** new `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Home/GoneRemovals.swift` (value type + store); `HomeFocus.swift` (or the shared filter's home); `shellx-ios/ShellX/UI/Agent/AgentView.swift`, `AgentScreen.swift`; `shellx-ios/ShellX/UI/Home/*` and `shellx-ios/ShellX/UI/Workspaces/WorkspaceListView.swift` (lists, swipes, counts); app wiring where `EndedDismissalStore` is created; tests in `ShellXAppCoreTests` and `ShellXTests`.

- [ ] Failing tests:
  - value type: hides only on an exact stamp match; a newer `lastActivityMs`, other `stateSinceMs` or other `state` shows again; other Mac/session unaffected; prune at 30 days; Codable round trip; the store survives a relaunch and reads junk as none;
  - the shared filter removes the session from every home group and its counts;
  - the agent screen offers the action only when gone and not embedded; the home / outside-workspace swipe only for a known-gone ref (a live `.working` session never gets it).
- [ ] Implement.
- [ ] `toknix run shellx-ios/scripts/dev.sh test all` green (the standing `AttachmentPreparerTests.testCancellingAHungFileReadStopsIt` red excepted). Commit `feat(shellx-ios): a session gone from its Mac can be removed from the phone`.

### Task 2: Dogfood

- [ ] Reinstall the iPhone app; open the ghost "mobile-app" session of "Richard's Mac mini (2)" → "Remove from This Phone" → it leaves Running and the count; relaunch the app → still gone.
