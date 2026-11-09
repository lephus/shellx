# ShellX Link for Kotlin

The Kotlin/JVM port of ShellX Link for the Android app: plain JVM libraries with no Android dependency. It is MIT
licensed like the Swift package (see [../LICENSE](../LICENSE)). It must not depend on, link to or copy code from
the GPL parts of the repository (`Sources/`, `ios/`, `Packages/`, `cmux-tui/`, `shellx-core/`).
`scripts/shellx/check-android-license.sh` checks its Gradle files, dependencies and files.

| Module | Package | What |
| --- | --- | --- |
| `link-core` | `com.shellx.link.core` | frames, Noise, relay control and the Link session (plan 3B) |
| `link-account` | `com.shellx.link.account` | the relay's HTTP API (plan 3B) |

Tests run on the JVM with JUnit 5. They read the shared vectors from `../../vectors/` and `../../spec/vectors/`,
relative to each module folder: the same files the Swift tests read.

    shellx-android/scripts/dev.sh test link

The Android build includes this one with `includeBuild("../shellx-link/kotlin")` and depends on
`com.shellx.link:link-core` and `com.shellx.link:link-account`. After a dependency change, run
`shellx-android/scripts/dev.sh lock` and update `scripts/shellx/android-license-allowlist.txt`.
