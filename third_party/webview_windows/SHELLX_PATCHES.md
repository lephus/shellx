# ShellX patches to webview_windows 0.4.0

Vendored from pub.dev `webview_windows` 0.4.0 (BSD-3-Clause, jns.io) because
the last release is from 2024 and ShellX A6 needs five native additions
(spec 2026-10-07-desktop-browser-a6-design.md D2). Keep every change listed
here; re-apply them on any upgrade.

| # | Patch | Files | Added in |
|---|---|---|---|
| a | `capturePreview` → PNG bytes (`ICoreWebView2::CapturePreview`) | windows/webview.cc, webview.h, webview_bridge.cc, lib/src/webview.dart | A6 Task 8 |
| b | `setForwardedAccelerators` + `acceleratorKey` event (`AcceleratorKeyPressed`) | same | A6 Task 8 |
| c | Downloads cancelled + `downloadBlocked` event (`DownloadStarting`) | same | A6 Task 8 |
| d | Top-level navigation to non-http(s)/about schemes cancelled + `navigationBlocked` event (`NavigationStarting`) | same | A6 Task 8 |
| e | `moveFocus` (`ICoreWebView2Controller::MoveFocus`, programmatic) | same | A6 Task 8 |
| f | `environment.sdk` widened from `<3.0.0` to `<4.0.0` so the package resolves with Dart 3 (no code change); `example/`, `pubspec.lock`, `.iml` removed | pubspec.yaml | A6 Task 1 |
