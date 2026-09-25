# flutter_pty 0.4.2 — ShellX copy

Vendored from pub.dev `flutter_pty` 0.4.2 (https://github.com/TerminalStudio/flutter_pty,
MIT, see `LICENSE`). `apps/desktop` depends on it by path. The first commit that added
this directory is the pristine package; every later change is listed here and can be
reviewed as a diff on top of that commit.

## Packaging

| File | Change | Why |
|---|---|---|
| `android/`, `ios/`, `linux/`, `example/` | Removed. | ShellX ships the desktop agent for macOS and Windows only. |
| `pubspec.yaml` | `flutter.plugin.platforms` lists only `macos` and `windows`. | Same. |
