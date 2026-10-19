# l0-setup (L0.1) report — 2026-10-19 (resumed after the repo move)

Branch: `shellx/sprint` on lephus/shellx (worktree `~/Documents/myProjects/shellx-wt-sprint`), pushed.
Head: `c3afe0da80` — L1–L3 branch from this sha.

## Done
- W1 Task 1 (ShellXBrand package + `scripts/shellx/test-app.sh`, pbxproj wiring): already complete in the SDD ledger
  (`.superpowers/sdd/2026-10-18-native-desktop-w1-mac-local/progress.md`, "Task 1: complete", review clean). Review loop not re-run.
- `ac8a020db5` fix(shellx): `ShellXBrand.sourceCodeURL` = `https://github.com/lephus/shellx` (the W1 plan already says this; the code still had shellx-pro). swift test 4/4.
- `ac170427f5` chore(shellx): dropped verify-local's `config-schema` check (`scripts/generate-cmux-config-schema.py --check`):
  its source `web/data/cmux.schema.json` was in cmux's BUSL `web/` and is gone. Also removed its 2 rows from
  `tests/test_verify_local.py::test_current_ci_schema_and_sync_inputs_select_their_checks`. Removed: that one check and those 2 test rows, nothing else.
  Locally: `CI=1 verify-local --all` 15/15 PASSED, test_verify_local 45 OK, test_shellx_* 2+7 OK.
- `c3afe0da80` ci(shellx): `shellx-mac.yml` comments now describe lephus/shellx; `paths-ignore` relay/**, web/**, deploy/**, docs/**, deploy.yml.
  Submodules (recursive checkout of the manaflow-ai ghostty/bonsplit/homebrew-cmux URLs) work on CI. Build phases only use `workers/cmux-paste-text` (kept).

## CI
- shellx-mac run 39165768325 (head c3afe0da80): checkout, static checks (verify-local --all), ShellX guard tests, ShellXBrand tests,
  GhosttyKit download, SPM resolve: all green. Run finished green at 22:13Z (~74 min cold; build step ~60 min). ready c3afe0da80.
  Check: `gh run view 39165768325 -R lephus/shellx`.

## Rulings
- sourceCodeURL → lephus/shellx — the repo-move rule plus the W1 plan text — cost if wrong: a one-line revert.
- config-schema check dropped instead of re-homing the schema JSON (it was BUSL web/) — cost if wrong: the generated schema Swift can drift without a check until ShellX owns a schema source.
- paths-ignore for server/site/docs pushes — saves macOS runner slots for L4/L7 branches — cost if wrong: such a branch gets no Mac CI (use workflow_dispatch).

## Known, not fixed (not run by shellx-mac; ledger ruling (2) leaves these for W1)
cmux tests that still point at removed web/, workers/, workflows: tests/test_cmux_schema_parity.py, test_cmux_config_schema_embed.py,
test_cmux_settings_supported_paths.py, test_cli_config_doctor.py (schema json), test_ci_*.py, test_web_validation.py,
test_tui_publish_workflow_security.py, test_e2e_backend_scripts.py, test_reuse_app_host_products.py (some of these may still pass).

## K-change requests
None.

## Needs user
- Nothing blocking. (Local `main` has 5aa31145aa (docs) that is not pushed; it does not affect shellx/sprint.)
