# Task 1 report
Implemented ShellXBrand package (ShellXBrand, ShellXColor/ShellXPalette, ShellXFeatures), scripts/shellx/test-app.sh (exec-forwards -only-testing:cmuxTests/<Suite> to scripts/test-unit.sh test; exits 2 with usage on zero suites), pbxproj wiring (XCLocalSwiftPackageReference + product dependency + PBXBuildFile) for the `cmux` app target and `cmux-cli` target (not cmuxTests), workspace group entry in cmux.xcworkspace/contents.xcworkspacedata. Branch step skipped per controller.
TDD: RED `swift test --package-path Packages/Shared/ShellXBrand` -> "error: target 'ShellXBrand' referenced in product 'ShellXBrand' is empty" (no sources). GREEN: 4 tests in 1 suite passed.
verify-local `--all --jobs 3`: initially failed project/test-wiring (pbxproj not normalized); ran scripts/normalize-pbxproj.py; then 16/16 PASSED. No app build run (CI).
Concerns: app link unverified locally (CI). Test-app.sh not executed against xcodebuild.
