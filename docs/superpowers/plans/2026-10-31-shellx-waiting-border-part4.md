# ShellX waiting border (part 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** while an agent waits for the user's answer (`needsInput`), its tab shows a thin multicolor border that runs around it — on the Mac sidebar row and on the iPhone ("Needs you" cards and the agent's tab chip).

**Spec:** `docs/superpowers/specs/2026-10-29-shellx-mobile-home-focus-design.md` §6.7 (user decisions 2026-10-31).

## Global Constraints

- Trigger: only the agent "waits for the user's answer" state (iPhone: `AgentState.needsInput` / the HomeFocus "needs you" group; Mac: the agent status the sidebar already derives for a pending permission/question). Never for working, done, idle or ended.
- Look: stroke ~2 pt (Mac sidebar row 1.5–2 pt), an `AngularGradient` over `#60a5fa → #a78bfa → #f472b6 → #fbbf24 → #60a5fa`, following the row's/card's own rounded shape (same corner radius), drawn as an overlay that never covers or shifts text and does not change layout size.
- Motion: the gradient rotates around the shape, one turn ≈ 3 s, linear, forever while waiting. With Reduce Motion on (Mac `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`, iOS `@Environment(\.accessibilityReduceMotion)`) the border stays still (same colors).
- Cost: the animation must run on the render server / GPU path (e.g. `TimelineView(.animation)` or a repeating `withAnimation` on an angle, or a CA layer), add no per-frame work on the main thread beyond SwiftUI's animation, and stop entirely when not waiting. On the Mac, never touch typing-latency-sensitive code paths (read `skills/cmux-debugging/SKILL.md`), and keep SwiftUI list snapshot boundaries intact.
- Accessibility: purely decorative (`accessibilityHidden`); the waiting state is already announced by existing labels.
- One shared view per platform (`WaitingBorder` / modifier `.waitingBorder(isActive:cornerRadius:)`), used by every entry point on that platform.
- Mac app code stays Swift 6.0 compatible; no submodule (Bonsplit/Ghostty) changes in this part — pane tab-bar tabs are out of scope.
- Commit the failing test first; stage by explicit path.

---

### Task A: iPhone

**Files:** new `shellx-ios/ShellX/UI/Common/WaitingBorder.swift` (or the folder shared UI already uses); `shellx-ios/ShellX/UI/Home/FocusRowView.swift` (needs-you cards); `shellx-ios/ShellX/UI/Workspaces/PaneChips.swift` (chip whose agent is `.needsInput`); tests in `shellx-ios/ShellXTests` (render tests where the repo snapshots views).

- [ ] Failing tests: a pure predicate (e.g. `WaitingBorder.isActive(for:)` / `FocusRowView.showsWaitingBorder`) true only for needs-input; the chip predicate likewise; a render test (static frame) that the needs-you card draws the border and a running card does not; Reduce Motion → no animation (a static flag on the view model / style).
- [ ] Implement the shared modifier and use it in both places.
- [ ] `toknix run shellx-ios/scripts/dev.sh test all` green. Commit `feat(shellx-ios): a multicolor border runs around an agent that waits for you`.

### Task B: Mac sidebar

**Files:** find where the sidebar row draws its agent name effect (`Sources/ShellX/AgentActivity/*`, `Sources/VerticalTabsSidebar*.swift`, `Workspace+AgentNameEffects.swift`, `Workspace+ProgramStatus.swift`) and where the row knows its agent waits for the user; new `Sources/ShellX/AgentActivity/WaitingBorder.swift`; tests in `cmuxTests/` (run `./scripts/sync-test-wiring` after adding a file).

- [ ] Failing tests: the row's "waiting" predicate is true only for the needs-input/permission state (not working, not done); Reduce Motion → static.
- [ ] Implement the shared border and apply it to the sidebar row; no Bonsplit changes.
- [ ] `toknix run scripts/shellx/test-app.sh <the suites you touched>` green. Commit `feat(shellx): a multicolor border runs around a tab whose agent waits for you`.

### Task C: Dogfood

- [ ] Rebuild the tagged Mac app (`reload.sh --tag push-needs-you`, no launch) and reinstall the iPhone app; checklist: trigger a permission prompt in a Claude tab → the Mac sidebar row and the iPhone card/chip show the running border; answer it → the border stops; Reduce Motion → still border.
