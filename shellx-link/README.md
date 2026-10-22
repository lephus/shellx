# shellx-link

ShellX Link is the phone-to-Mac protocol for ShellX: Noise sessions, a message codec, a relay client and sessions. It is a standalone Swift package that the ShellX Mac app and the future iOS app both use.

It is MIT licensed (see `LICENSE`), unlike the rest of this repository. For that reason it must not depend on, link to or copy code from GPL parts of the repo (`Sources/`, `ios/`, `Packages/`, `cmux-tui/`). Reading them to understand a protocol is fine. `scripts/shellx/check-link-license.sh` enforces the boundary.
