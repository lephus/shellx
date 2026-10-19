# Task 15 report
Status: DONE. Files: windows/README.md, windows/G1-G3-CHECKLIST.md (docs only). Commit message "docs(shellx-windows): README, accessibility stopgap, G1/G3 checklists"; not pushed.
- Flags/env/shortcuts verified against main.rs, keys.rs, local_pty.rs, core_service.rs (SHELLX_API_BASE debug-only), strings.rs, paths.rs, shellx-native.iss, workflow artifact names. Extra flag documented: --smoke-panes.
- A11y: term_view.rs already writes the window title (focused pane only) as "<cursor line, else terminal title> - ShellX" (BASE_TITLE "ShellX"), not "ShellX - <tab title>". Documented as built (Narrator Insert+T). No code change needed.
- Run id 39176242679 appears only in G1-G3-CHECKLIST.md section "Run id"; README points there.
- G3 steps for 12b (pairing UI) and 13b (remote view) marked "(nếu bản build có)".
- Concern: README says cmux-tui crates are under "their own licenses" (did not verify exact license); controller may refine.
