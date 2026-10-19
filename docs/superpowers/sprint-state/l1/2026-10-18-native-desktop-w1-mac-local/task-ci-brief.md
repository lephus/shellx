### Task L1-CI: opt-in CI job for app-hosted ShellX Swift suites (controller ruling R5)

Why: Tasks 3, 4, 5 add app-hosted Swift Testing suites under `cmuxTests/` (ShellXPathsTests, ShellXNoPhoneHomeTests,
ShellXCloudOffTests). They need the `cmux-unit` scheme (a full app + test-host compile, ~55-60 min cold) which must not
run on this Mac (one local Xcode build; disk tight). The existing `.github/workflows/shellx-mac.yml` (owned by lane L0;
do NOT edit it) builds only the app scheme.

**Files:**
- Create: `.github/workflows/shellx-mac-unit.yml`

**Requirements:**
- Triggers: `workflow_dispatch` (input `suites`, default `ShellX` meaning "every cmuxTests suite whose name starts with ShellX") and `push` to `shellx/**` — but the job runs on push only when the head commit message contains `[unit]` (`if: github.event_name == 'workflow_dispatch' || contains(github.event.head_commit.message, '[unit]')`). Same `paths-ignore` as shellx-mac.yml.
- `concurrency: shellx-mac-unit-${{ github.ref }}`, cancel in progress. `permissions: contents: read`. `runs-on: macos-26`, `timeout-minutes: 150`.
- Reuse the setup steps of shellx-mac.yml verbatim and in the same order where they apply (checkout with submodules + persist-credentials false, select Xcode, GhosttyKit cache + sha-pinned download, Bun, Rust, SPM cache + sanitize + resolve, mtimes normalization, same env block: CMUX_CI_REQUIRED_MACOS_SDK_MAJOR, CMUX_SKIP_ZIG_BUILD, CMUX_WIREGUARD_GO_REQUIRE, DERIVED_DATA, SOURCE_PACKAGES). Pin actions to the same SHAs as shellx-mac.yml. Use a separate DerivedData cache key prefix `shellx-dd-unit-v1-` (restore + save with the same prune/size guard), because test builds differ from app builds.
- Suite resolution: expand the `suites` input. `ShellX` (default and the push case) → list every `cmuxTests/ShellX*.swift` file, take the `@Suite`/struct name = file basename, and pass each as an argument to `scripts/shellx/test-app.sh`. Any other value = space-separated explicit suite names. If no suite files exist, print a notice and exit 0.
- Run: `scripts/shellx/test-app.sh <suites…>` with `-derivedDataPath "$DERIVED_DATA" -clonedSourcePackagesDirPath "$SOURCE_PACKAGES" -disableAutomaticPackageResolution COMPILER_INDEX_STORE_ENABLE=NO` forwarded (test-app.sh → scripts/test-unit.sh forwards extra args to xcodebuild; check it does, extend test-app.sh to pass through args after a `--` separator if needed, keeping its current usage working). Tee to `$RUNNER_TEMP/unit.log`; fail on `** TEST FAILED **` / missing `** TEST SUCCEEDED **`; upload the log on failure (same upload-artifact pin).
- Header comment explaining the opt-in and why (one short paragraph).
- Validate YAML locally: `python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" .github/workflows/shellx-mac-unit.yml` (if PyYAML is missing, use `ruby -ryaml -e 'YAML.load_file(ARGV[0])'`). If `actionlint` is installed, run it.
- Commit: `ci(shellx): opt-in shellx-mac-unit job for app-hosted ShellX suites`.
