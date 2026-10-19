# Task 6 report — ShellX name in the UI, CLI help and About (lane L2)

Status: DONE_WITH_CONCERNS
Commit: f2dd7a202e on shellx/l2-look (base 5c3df0464e), 328 files, +13270/-12163. Not pushed.

## What changed

1. **`scripts/shellx/rebrand_strings.py`** (new; `--check`, `--list`). It rewrites only the four letters of each `cmux` it changes, token by token, so `git diff` shows only changed values. A word-level diff check gives 16 523 `cmux`→`ShellX`/`shellx` swaps (9 889 `ShellX`, 6 676 `shellx`), no other edits, and numstat insertions == deletions on every rebranded file. A second run is a no-op (`--check` exits 0).
   - Scope: every locale's `stringUnit.value` in Resources/{Localizable,InfoPlist,ConfigPackErrors}.xcstrings, TunnelExtension/InfoPlist.xcstrings, Packages/macOS/*/Sources/**/*.xcstrings and Packages/Shared/*/Sources/**/*.xcstrings (iOS catalogs left out). It also covers the English `source` and identity `values` in scripts/localization-allowed-omissions.json and localization-plurals.json, the `NS*UsageDescription` strings in Resources/Info.plist, Swift `defaultValue:` literals of the localization calls (String(localized:), LocalizedStringResource, localized/localizedCount/localizedFormat/automationLocalized, *Localiz*.string) in Sources/, CLI/, Packages/macOS/*/Sources and Packages/Shared/*/Sources, and plain CLI help literals in CLI/*.swift (those containing `Usage: cmux `, `Run 'cmux ` or `'cmux --help'`).
   - Counts (clean run from 5c3df0464e): 11 433 values in 283 files. That is 10 285 catalog values (859 of them English), 821 Swift defaultValue literals, 249 plain CLI help literals, 51 metadata entries and 27 Info.plist usage strings.
2. **Menus** (Sources/cmuxApp.swift): "About ShellX", "Quit ShellX", "Open shellx.json", "Make ShellX the Default Terminal". These come only from the rebranded defaultValues and catalog; no code change. The Cloud/Help/docs items were left alone.
3. **Accent color label**: "cmux Blue" → "ShellX Blue" (settings.app.accentColor.cmux, through the script). The keymap preset shows "ShellX (Default)". `CmuxAccentColorMode` values were not changed.
4. **About**:
   - Sources/AboutLicenseContent.swift adds `struct Attribution { name, license, url: URL? }` and the static members `sourceCodeURL` (= `ShellXBrand.sourceCodeURL`), `sourceCodeDisplay` ("github.com/lephus/shellx"), `licenseLine` and `attributions`. The attributions are cmux (Manaflow, Inc.) GPL-3.0-or-later, Ghostty MIT, coolicons by Kryston Schwarze CC BY 4.0, and Space Grotesk OFL-1.1.
   - The default `repositoryURL` is now `sourceCodeURL`, and the license heading reads "ShellX Project License".
   - Sources/App/About/AboutPanelView.swift now shows `Image("ShellXLogo")` (the drop shadow is gone), "ShellX", the version rows, the `Link` license line "GPL-3.0-or-later — source: github.com/lephus/shellx", and a "Credits" list (rows reuse AboutPropertyRow). Lines 10–11 (githubURL/docsURL) are untouched for L1.
   - Two new catalog keys, `about.shellx.licenseLine` and `about.shellx.credits`, are translated in all 9 locales. They were added with localize_changes.insert_catalog_entry and `localization_catalog.py merge`.
5. **CLI help**: usage and help text says `shellx <subcommand>`, e.g. "Usage: shellx notify [flags]" and "Run 'shellx --help'". The executable and program-name plumbing were not touched.
6. **Tests**:
   - New tests/test_shellx_branding.py (unittest, 9 tests), registered in tests/test-execution.toml (linux-guard lane).
   - New cmuxTests/ShellXAboutTests.swift (Swift Testing, 4 tests, wired with scripts/sync-test-wiring → pbxproj +4 lines).
   - cmuxTests/AboutLicensesResourceTests.swift now expects lephus/shellx in the default commit URL.
   - 70 string expectations in 37 existing test files (cmuxTests, cmuxCLITests, cmuxUITests, package Tests) were synced to the new UI/CLI text, e.g. "Usage: shellx vm dev", "Quit ShellX?", "[ShellX] press Enter…". This was a one-off scratch helper: it matches test literals against the rebranded strings and skips path/file-name fixtures, literals still produced by untouched source, and plumbing inputs/negative asserts (6 files excluded by hand).

## Rules and preserved cases
In order, per ASCII-bounded word `cmux` (any case; ASCII boundaries so "cmuxを"/"cmux가" are words):
1. **Own paths** (global constraints): `~/.config/cmux`→`shellx`, `.cmux/`→`.shellx/`, `cmux.json`→`shellx.json`, `.local/state/cmux`→`shellx`, `Application Support/cmux`→`ShellX`, `bin/cmux`→`bin/shellx`, `cmux.app`→`ShellX.app`.
2. **Never rewritten**: URLs/domains (cmux.com, `<vm>.cmux.sh`, founders@cmux.com, github.com/manaflow-ai/cmux, cmux://); anything glued with `. / - @ $ \ = & ? # : ~` before it or `.x :x /x` after it; `CMUX_*` and `cmux_*` (the boundary excludes `_`); option/setting values (`--agent cmux`, `chat.defaultAgent cmux`).
   - Hyphen: in English and Swift defaults `cmux-tui`, `cmux-cli`, `cmux-chat`, `cmux-cua`, `cmux-remote-status` are kept. The exceptions are compound adjectives (`cmux-aware/-managed/-owned…` → `ShellX-…`).
   - In translations, `cmux-<word>` is kept only if the same token is in the English value. Otherwise it is a compound ("cmux-Browser" → "ShellX-Browser").
3. **Command → `shellx`**: `` `cmux `` / `` `cmux` ``, a quoted bare `'cmux'`, a leading `cmux: `, `cmux` before ` -`, ` <`, ` [` or after `Usage: `, `cmux %1$@` in CLI keys, and `cmux <subcommand>` per the ruling below.
4. **Everything else → `ShellX`**.

PRESERVE_VALUES = {"cmux (Manaflow, Inc.)", "Copyright (c) 2024-present Manaflow, Inc."}. PRESERVE_KEYS is empty, because no catalog value is upstream credit; the attribution list is code.

32 English occurrences are kept: cmux-tui ×~20, cmux.com URLs, founders@cmux.com, cmux-chat, cmux-cua, `<port>.cmux.sh`, cmux:exec/cmux:work refs, `~/cmux` in a debug prompt, cmux-remote-status, and the Kiro `--agent cmux` / `chat.defaultAgent cmux` values.

## TDD evidence
- **RED**: `python3 tests/test_shellx_branding.py` before the script existed gave `Ran 9 tests … FAILED (failures=4, errors=4)`: 4 ERRORs (the script was missing, so PRESERVE_KEYS/rebrand could not load) and 4 FAILs (About regex not found; cli.help.notify was still "Usage: cmux notify"; menu.app.about was 'About cmux'; `--check` exit 2). test_identifiers_and_env_names passed at base, as intended.
- **GREEN** (after the commit):
  - `python3 tests/test_shellx_branding.py` → `Ran 9 tests … OK`
  - `python3 scripts/shellx/rebrand_strings.py --check` → exit 0
  - `python3 scripts/localization_catalog.py check` → `10 catalogs, 9 locales: 0 parity errors`
  - `python3 scripts/localization_defaults.py` → `6840 … comparisons: 0 mismatches` (base: 6839/0; +2 new keys, −1, see concerns)
  - test_localizable_xcstrings_structure, test_localization_defaults, test_lint_xcstrings, test_localization_catalog, test_localize_changes, test_merge_xcstrings and test_shellx_* all report `OK` / exit 0
  - `python3 scripts/verify-local.py --all --jobs 3` → `PASSED: 15/15`
- **Base comparison**: I ran the 99 tests/test_*.py that read Sources, CLI or catalogs. 41 fail both before and after my change (they need a built CLI binary (CMUX_CLI_BIN), web/, or the CI env). No test fails only after my change.
- **Swift**: `swiftc -typecheck` of AboutLicenseContent + AboutPanelView + AboutPropertyRow + AboutVisualEffectBackground against swift-built CmuxFoundation and ShellXBrand modules (in scratch) passes.
- **Not run (lane rule)**: ShellXAboutTests and the other app-hosted/CLI tests (no app builds). That means the 70 synced test expectations have not been run either.

## Rulings
- Ruling: CLI command detection uses a static SUBCOMMANDS list plus context signals.
  - Strong signals: the subcommand is hyphenated; the occurrence is quoted; flags or placeholders follow; Usage:/run/retry/try/`$`/`|` precedes it; the translation's English value used the same subcommand as a command.
  - Weak signals: a CLI key, a line start, See/Use. These are enough for verbs but, for noun-like subcommands (browser, cloud, workspace, session…), only inside CLI help.
  - Never a command: after an article, or with a comma right after the subcommand.
  - Why: subcommands such as browser and session are also everyday nouns ("the cmux browser"), so a word list alone misfires.
  - Cost if wrong: a handful of strings read "ShellX vm …" or "shellx browser" in odd prose; `--list` shows every decision.
- Ruling: added path rules beyond the plan (`.local/state/cmux`, `Application Support/cmux`, `bin/cmux`, `cmux.app`) — the global constraints define these names on disk — cost if wrong: a few strings name paths L1 does not rename.
- Ruling: TunnelExtension/InfoPlist.xcstrings is in scope — it shares the global `CFBundleDisplayName` omission record, so leaving it out made `localization_catalog.py check` fail 7 times — cost if wrong: the disabled tunnel extension's display name reads "ShellX Cloud Tunnel".
- Ruling: the localization metadata JSON (omissions/plurals `source` and identity `values`) is rebranded with the same rules — the checker matches them byte for byte against the English value — cost if wrong: none (check stays green).
- Ruling: option/setting values (`--agent cmux`, `chat.defaultAgent cmux`) are kept — they name the Kiro agent identifier the hooks register — cost if wrong: L1 renames that agent, and these two strings must be updated with it.
- Ruling: the cmux attribution has `url: nil` — L1's no-phone-home guard forbids "manaflow" hosts in Sources — cost if wrong: no clickable upstream link (the name and license are shown).
- Ruling: About uses the existing `about.appName` key (now "ShellX") rather than `ShellXBrand.appName` verbatim — the key is translated in every locale and is idempotent — cost if wrong: none.
- Ruling: the license line is the localized `Link` "GPL-3.0-or-later — source: %@", where %@ = host+path of ShellXBrand.sourceCodeURL (repo move: lephus/shellx, not shellx-pro) — cost if wrong: one string.
- Ruling: I synced existing test expectations that assert rebranded UI/CLI text, but left path fixtures and plumbing (cmux.json files, .local/state, `cmux ssh-pty-attach` initial commands, CmuxSettingChange.commandLineDescription) — L1 renames those — cost if wrong: some app tests fail at the checkpoint run and are fixed there.
- Ruling: CMUXMobileCore (Packages/Shared) is in scope per the controller; iOS packages are not — cost if wrong: none for macOS.

## Concerns
1. **About 648 non-localized literals in 154 product source files still say "cmux"** (logs, debug, some user-visible CLI and app errors, e.g. "Cloud VM access requires sign-in. Run `cmux auth login`", "does not support secure cmux handoff"). They are outside the controller scope (only defaultValues and CLI help). `CmuxSettingChange.commandLineDescription` ("cmux config set …", shown in the confirm alert) is in this group.
2. **AboutPanelView still points at manaflow-ai** for its GitHub button (line 10) and the commit link (~line 56). I left them for L1 to avoid an adjacent-line conflict; L1's no-phone-home guard will flag them. `correspondingSourceURL` still checks the bundle id "com.cmuxterm.app" (L1 Task 2).
3. **The `markdown.web.remoteImageConsentMessage` key is shared with the iOS CmuxAgentChatUI package**, which is out of scope. That key's two defaults now disagree, so localization_defaults skips it: one comparison fewer, not an error.
4. **Pre-existing drift**: some Swift defaults differ from the catalog English, e.g. "cmux destination" vs "Destination". `./scripts/localize-changes` would "fix" these by rewriting the catalog English and marking 78 translations needs_review. I reverted that.
   - The tool also crashes here: it needs web/i18n/routing.ts, which ShellX removed. Use insert_catalog_entry plus `localization_catalog.py merge` instead.
5. **Task 12 (vi) staging** (l10n/en-to-ids.json, batches) is keyed by the old English text. Strings containing cmux no longer match after this change, so restage or rebrand the batches before import.
6. **Merge conflicts with L1** are likely in CLI/cmux.swift and CLI/CMUXCLI+*.swift (help literals), AboutPanelView/AboutLicenseContent, and any catalog values L1 edits. After merging, rerun `python3 scripts/shellx/rebrand_strings.py` and then `--check`.
7. **Disk**: `df -h /` shows 11–12 GB available, below the 15 GB lane floor. I don't know whether it was already that low before I started. My scratch builds are deleted.
8. **ShellXAboutTests imports ShellXBrand** (as the brief asks). cmuxTests has no explicit ShellXBrand package dependency; it relies on the module being in BUILT_PRODUCTS_DIR, as other package imports in cmuxTests do. Not verified, since no app test build was allowed.

## Files
- New: scripts/shellx/rebrand_strings.py, tests/test_shellx_branding.py, cmuxTests/ShellXAboutTests.swift
- Hand edits: Sources/AboutLicenseContent.swift, Sources/App/About/AboutPanelView.swift, cmuxTests/AboutLicensesResourceTests.swift, tests/test-execution.toml, cmux.xcodeproj/project.pbxproj (sync-test-wiring), Resources/Localizable.xcstrings (2 new keys)
- Script edits: 283 files (catalogs, metadata JSON, Info.plist, Swift defaults/help literals)
- Test expectation sync: 37 test files

## Fix round 1 (worktree shellx-wt-l2-fix, branch shellx/l2-look-t6fix)
Commit: 0fae2bd257 on top of f2dd7a202e. 13 files, explicit paths staged.

**Finding:** localization helpers were missed. About 31 keys had "ShellX" in the catalog but a Swift default that still said "cmux".

**Change**
- `rebrand_strings.py` has a new `default_sites(raw)` function (used by both the rewrite and the tests). It finds Swift localization defaults in four places:
  - the existing String(localized:) and LocalizedStringResource calls;
  - any call whose key argument is a literal catalog key, either the first argument or a `key:`/`localized:`/`*Key:` label, followed by a `defaultValue:` literal. This covers `CmuxConfigValidationLocalization().format`, `localization.format`, `format(key:defaultValue:)`, `localizedPassthroughString` and `mobilePanelArtifactFileError`;
  - a positional default right after the key (`workflowText("key", "Default")`);
  - a `let/var defaultValue = "..."` local, tied to the first catalog-key literal later in the same function.
- Catalog keys are loaded once from the rewritten catalogs.
- The rerun changed 32 more values in 10 Swift files:
  - CLI/CMUXCLI+{Config,ConfigValidation,CoderouterPassthrough,DocsSettings}.swift
  - CLI/cmux.swift (let defaultValue ×4)
  - CmuxConfigSemanticValidator.swift
  - CmuxSettingChangeError.swift ×4
  - SudoCLIMessages.swift ×2
  - CmuxSidebarProviderDescriptor.swift
  - TerminalController+MobileSurfaces.swift
- `--check` exits 0 on two consecutive runs.

**Covering tests**, three new ones in tests/test_shellx_branding.py (12 tests now):
- `test_helper_defaults_are_found`: the detector sees one example of each helper form.
- `test_no_cmux_in_swift_localization_defaults`: no Swift default anywhere in the four source roots contains a cmux the rules would rewrite.
- `test_swift_defaults_match_catalog_english`: a real text-parity test. It compares 9 993 Swift defaults with the catalog English (it fails if fewer than 9 000 are compared). Defaults that contain an interpolation are skipped.
  - The exemption list is tests/shellx_default_drift.json: 137 keys where the Swift default already differed from the catalog English at base 5c3df0464e. That is upstream drift, which localization_defaults.py misses because it only compares format specifiers.
  - The base mismatch set (154 sites) and the post-fix set are identical, so no new drift was introduced.

**Evidence**
- RED: with the 10 Swift files restored to f2dd7a202e, `python3 tests/test_shellx_branding.py` gives FAILED (failures=3):
  - "32 Swift defaults still say cmux"
  - "31 Swift defaults differ from the catalog English"
  - `--check` would change values
- GREEN: `python3 tests/test_shellx_branding.py` → Ran 12 tests … OK (~24 s).
- `python3 scripts/shellx/rebrand_strings.py --check` → 0, twice.
- `python3 scripts/localization_catalog.py check` → 10 catalogs, 9 locales: 0 parity errors.
- `python3 scripts/localization_defaults.py` → 6840 comparisons, 0 mismatches.
- lint-xcstrings passed; test_localizable_xcstrings_structure, test_localization_defaults, test_lint_xcstrings and test_localization_catalog all exit 0.

**Ruling:** pre-existing drift is exempted by key in a JSON list instead of being "fixed" — copy decisions for those 137 keys belong to upstream/L0, and rewriting either side would hide real translation work — cost if wrong: drift on those keys stays unguarded until the list shrinks.

**Note:** "Keep cmux signed in" became "Keep ShellX signed in" (rules apply as written).
