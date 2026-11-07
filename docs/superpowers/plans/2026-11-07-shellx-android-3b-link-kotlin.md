# ShellX Link for Kotlin (plan 3B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Translate the phone side of ShellX Link (codec, Noise XX, pairing, relay client, secure channel, Link session, relay HTTP account API) from `shellx-link/Sources` (Swift, MIT) to pure Kotlin/JVM in `shellx-link/kotlin`, proven against the shared golden vectors, as the library plan 3C builds the Android app core on.

**Architecture:** Two modules in the standalone Gradle build that plan 3A created. `link-core` (`com.shellx.link.core`) holds the message model and a strict JSON codec, Noise_XX_25519_ChaChaPoly_SHA256, pairing offers, the relay control protocol and client connector over an abstract `RelaySocket`, `SecureChannel`, and `LinkClient`: a coroutine and `Flow` session behind the `LinkSession` interface that 3C consumes and fakes. `link-account` (`com.shellx.link.account`) holds `RelayApi` over OkHttp, `PhonePairing`, the OkHttp `RelaySocket` and `LinkConnector` (ticket → relay2 circuit → `LinkClient`). Phone side only: no Link host, no relay host registration, no password login.

**Tech Stack:** Kotlin/JVM (JVM target 17), kotlinx-coroutines, kotlinx-serialization-json (`JsonElement` API only, no compiler plugin), BouncyCastle `bcprov-jdk18on` lightweight API, JCA SHA-256 and HMAC, OkHttp 5 with `mockwebserver3`, JUnit 5 with `kotlin("test")`, the Gradle wrapper from 3A.

**Spec:** `docs/superpowers/specs/2026-11-07-shellx-android-app-design.md` (S3) §7.1 and §5. Cross-plan names: `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` §1, §2, §5, §8. Protocol (source of truth): `shellx-link/spec/PROTOCOL.md`. Reference code: `shellx-link/Sources/**`, `shellx-link/Tests/**`.

## Global Constraints

- **Licence (S3 §5, `shellx-link/README.md`):** everything under `shellx-link/kotlin/` is MIT (`shellx-link/LICENSE`). Translate only `shellx-link/Sources` and `shellx-link/Tests`. Never copy from or link to `Sources/`, `Packages/`, `ios/`, `cmux-tui/`, `shellx-core/` (GPL), test data included: Task 5 writes its relay control samples by hand in the key order of the MIT Swift encoder (`shellx-link/Sources/ShellXLinkRelay/RelayControl.swift`). No Gradle path leaves `shellx-link/kotlin/`.
- **Vectors (contracts §5):** read at test time, in place, from `../../spec/vectors/` and `../../vectors/` relative to the module directory (Gradle's test working directory). Never copy them.
- **Dependencies:** main code uses `org.jetbrains.kotlinx:kotlinx-coroutines-core` and `org.jetbrains.kotlinx:kotlinx-serialization-json` (Apache-2.0), `org.bouncycastle:bcprov-jdk18on` (link-core), `com.squareup.okhttp3:okhttp` (link-account, Apache-2.0). Tests use JUnit 5 with `kotlin("test")` (contracts §5) and `com.squareup.okhttp3:mockwebserver3`. Nothing else, and nothing from Android.
- **BouncyCastle:** under the Bouncy Castle Licence (MIT-style), which S3 §5 allows by name. Use only the lightweight classes `org.bouncycastle.crypto.agreement.X25519Agreement`, `org.bouncycastle.crypto.params.{X25519PrivateKeyParameters, X25519PublicKeyParameters, KeyParameter, AEADParameters}` and `org.bouncycastle.crypto.modes.ChaCha20Poly1305`. Never call `Security.addProvider` and never name provider `"BC"`.
- **Why BC for some primitives and JCA for others (minSdk 26, S3 §5):** Android API 26 has no JCA X25519 (`XDH`) and no `ChaCha20/Poly1305/NoPadding` (Conscrypt adds the cipher at API 28 and X25519 later), so both come from BC. `MessageDigest("SHA-256")` and `Mac("HmacSHA256")` exist at every API level, so SHA-256 and HMAC use JCA.
- **Android API 26 floor for main sources:** use only Java APIs that Android 8.0 has. Forbidden: `java.util.HexFormat`, `java.net.http`, `InputStream.readAllBytes`/`transferTo`, `Thread.ofVirtual`, `ProcessBuilder.Redirect.DISCARD`. Kotlin stdlib equivalents are fine. Tests run on JDK 17 and may use any JDK 17 API. Task 15 greps for these.
- **Layout (contracts §5):** modules `link-core` (package `com.shellx.link.core`) and `link-account` (package `com.shellx.link.account`), each one flat package with no sub-packages. Kotlin JVM, JVM target 17, JUnit 5. Gradle coordinates `com.shellx.link:link-core` and `com.shellx.link:link-account`.
- **Secrets (PROTOCOL.md §9, §10):** tokens, tickets, private keys, pairing codes, proofs and message content never appear in `toString()`, exception messages or `LinkLog`. Every type that holds one overrides `toString()` and prints `<redacted>` in its place. A data class holding a `ByteArray` overrides `equals`/`hashCode` with `contentEquals`/`contentHashCode` and prints `<N bytes>`.
- **Coroutines:** never swallow `CancellationException`. Any `catch (e: Throwable)` or `catch (e: Exception)` around suspending code rethrows it first. `runCatching` is allowed only inside `withContext(NonCancellable)` cleanup. No public function lets `TimeoutCancellationException` out: use `withTimeoutOrNull` and throw the named `TimedOut` exception.
- **Exceptions:** sealed classes. A case without fields is a `class` (new instance per throw), never an `object`. A case with fields is a `data class` so tests can compare it.
- **Test methods:** `@Test fun name() { runBlocking { … } }` with a block body. Never write `fun name() = runBlocking { … }`: when the last expression is not `Unit`, JUnit 5 silently skips the method. Use `kotlin.test` assertions.
- **Protocol values (PROTOCOL.md, `ShellXLink.swift`):** prologue ASCII `shellx-link/1`. Frame ≤ 65 519 UTF-8 bytes. `call_id` 1–64 UTF-8 bytes. Chunk ≤ 45 000 bytes. Attachment 1–10 485 760 bytes, ≤ 5 per message. Relay control `protocol` 5. Timings: ping 20 s, idle 45 s, call timeout 10 s, relay control timeout 10 s, slot-offline retries 0.5, 1 and 2 s, pairing poll 2 s for at most 300 s, HTTP connect/read/write 15 s.
- **Versions:** take every version from the catalog that the `shellx-link/kotlin` build loads: 3A's `shellx-link/kotlin/gradle/libs.versions.toml`, or the file named in its `settings.gradle.kts`. Add a missing library at the newest stable release on Maven Central at execution time (no `-alpha`, `-beta`, `-rc`, `-M`) that is compatible with the catalog's Kotlin version. If the build reports "compiled with an incompatible version of Kotlin", step down one minor version. OkHttp and mockwebserver3 share one 5.x version. Find each version with 3A's `latest` helper (3A Task 0 Step 4) on `https://repo1.maven.org/maven2/<group with / for .>/<artifact>/maven-metadata.xml`, with `5` as the second argument for OkHttp.
- **Dependency locking (3A):** every runtime classpath is locked, here and in `shellx-android/` (whose `:core` and `:app` resolve these libraries through `includeBuild`). A dependency change is followed by `shellx-android/scripts/dev.sh lock`, then 3A's allowlist procedure (3A Task 3 Step 6) until `bash scripts/shellx/check-android-license.sh` prints `check-android-license: ok`, and the lockfiles and allowlist are committed with it (Task 1 Step 5).
- **Commits:** `feat(shellx-link): …` with an explicit `git add <paths>`; never `git add -A`.

## Review Focus

These are inputs the spec implies but that no translated Swift test covers, ordered by how likely they are to hurt a user. Each has a test in its owning task.

1. **A caller is cancelled mid-call** (the screen closes and `viewModelScope` is gone). The session must stay usable: later calls get answers, the cipher stream never desyncs, and the late answer is dropped. Tests: Task 8 `cancelledCallerLeavesTheSessionUsable` and `cancellingManyCallersNeverBreaksTheCipherStream`.
2. **The network dies silently** (Wi-Fi hands over to LTE and no FIN arrives). Within `idleTimeout` the watchdog closes the circuit, the in-flight call throws `SessionClosed`, and all four push Flows complete, so 3C reconnects. Test: Task 8 `silentHostIsClosedByTheWatchdog`.
3. **The session ends while uploads wait for their turn.** Every queued upload and message fails promptly with `SessionClosed` (wrapped in `MessageUploadException` for a message) instead of hanging. Test: Task 9 `closingWithQueuedUploadsFailsThemAll`.
4. **The Mac's ping nonce is above `Long.MAX_VALUE`.** The Mac starts its pinger at a random uint64, so this happens half the time. The phone must echo the exact value in its `pong`. Test: Task 8 `hostPingWithAnyUint64NonceIsEchoed`.
5. **A base URL has a trailing slash or a path prefix** (`https://relay.shellx.pro/`, `…/api/`). Every route is joined once (`/v1/auth/nonce`, `/api/v1/auth/nonce`), never as `//v1/…`. Test: Task 10 `baseUrlPathAndTrailingSlashJoinOnce`.

## Conventions used below

- Paths are relative to the worktree root. Prefixes:
  - `core/` = `shellx-link/kotlin/link-core/src/main/kotlin/com/shellx/link/core/`
  - `core-test/` = `shellx-link/kotlin/link-core/src/test/kotlin/com/shellx/link/core/`
  - `account/` = `shellx-link/kotlin/link-account/src/main/kotlin/com/shellx/link/account/`
  - `account-test/` = `shellx-link/kotlin/link-account/src/test/kotlin/com/shellx/link/account/`
- `gw <args>` means `(cd "$(git rev-parse --show-toplevel)/shellx-link/kotlin" && JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}" ./gradlew --console=plain <args>)`. Run it from anywhere inside the worktree.
- **PASS** means the output has `BUILD SUCCESSFUL` and no `FAILED`. A **red** run is `BUILD FAILED` with the compile error or the failing test named in the step.
- Swift file references are the reference to translate; read the named file before its task.

## File map

| Area | Main files | Task |
| --- | --- | --- |
| Build | `shellx-link/kotlin/gradle/libs.versions.toml`, `shellx-link/kotlin/build.gradle.kts`, `link-core/build.gradle.kts`, `link-account/build.gradle.kts` | 1 |
| Model | `core/ShellXLink.kt`, `core/OpenEnums.kt`, `core/Models.kt`, `core/Bytes.kt` | 1 |
| Codec | `core/LinkMessage.kt`, `core/JsonFields.kt`, `core/LinkCodec.kt` | 2 |
| Noise | `core/NoiseKeys.kt`, `core/NoiseCipherState.kt`, `core/NoiseHandshake.kt` | 3 |
| Pairing | `core/PairingOffer.kt` | 4 |
| Relay control | `core/RelayControl.kt`, `core/RelayTicket.kt`, `core/RelayEndpoint.kt` | 5 |
| Circuits | `core/RelaySocket.kt`, `core/RelayCircuit.kt`, `core/RelayClientConnector.kt`, `core/InMemoryCircuit.kt` | 6 |
| Channel | `core/SecureChannel.kt` | 7 |
| Session | `core/LinkSession.kt`, `core/Liveness.kt`, `core/LinkClient.kt` | 8, 9 |
| HTTP API | `account/ApiModels.kt`, `account/HttpSupport.kt`, `account/RelayApi.kt` | 10, 11 |
| Pairing flow | `account/PhonePairing.kt` | 12 |
| Connector | `account/OkHttpRelaySockets.kt`, `account/LinkConnector.kt` | 13 |
| Live relay test | `account-test/RelayIntegrationTest.kt` and helpers | 14 |

---

### Task 0: Set up the worktree

**Files:** none.

- [ ] **Step 1: Create the worktree.** Use superpowers:using-git-worktrees. The branch is `feat/shellx-android-3b-link-kotlin`, created from `develop`. Use the native worktree tool when there is one. Otherwise run `git worktree add .worktrees/android-3b-link-kotlin -b feat/shellx-android-3b-link-kotlin develop`. Work only inside that worktree from now on.

- [ ] **Step 2: Check that plan 3A is merged.** 3A creates the Gradle build this plan fills.

```bash
test -f shellx-link/kotlin/settings.gradle.kts && test -x shellx-link/kotlin/gradlew && grep -nE 'link-core|link-account' shellx-link/kotlin/settings.gradle.kts
```

Expected: the include lines for both modules. If a file is missing, stop and report "plan 3A is not merged into develop". Change nothing.

- [ ] **Step 3: Read 3A's build.** Read `shellx-link/kotlin/settings.gradle.kts`, the root `build.gradle.kts` (if any), the version catalog, and both module `build.gradle.kts` files. Note four things:
  - the Kotlin version;
  - the catalog aliases for the Kotlin JVM plugin and JUnit 5;
  - how the JVM target 17 is set;
  - any placeholder source or test.

  Then read `docs/superpowers/plans/2026-11-07-shellx-android-3a-scaffold.md` for what it says about `shellx-link/kotlin`. If this plan, the contracts file or the 3A plan is missing from the worktree (plan files may still be uncommitted in the primary checkout, which `git worktree list` shows), read them there. Do not commit them on this branch.

- [ ] **Step 4: Run the baseline.** Run `gw test`. Expected: PASS (`NO-SOURCE` for empty modules is fine). If it fails before you change anything, stop and report.

---

### Task 1: Build wiring, model types and byte helpers

**Files:**
- Modify: `shellx-link/kotlin/gradle/libs.versions.toml` (or the catalog found in Task 0)
- Modify, or create if absent: `shellx-link/kotlin/build.gradle.kts`, `shellx-link/kotlin/link-core/build.gradle.kts`, `shellx-link/kotlin/link-account/build.gradle.kts`
- Modify (Step 5): the `gradle.lockfile` of `link-core`, `link-account`, `shellx-android/core` and `shellx-android/app` (rewritten by `dev.sh lock`), `scripts/shellx/android-license-allowlist.txt`, and `docs/superpowers/ledgers/shellx-android-parity.md` (row `6.2-15`)
- Create: `core/ShellXLink.kt`, `core/OpenEnums.kt`, `core/Models.kt`, `core/Bytes.kt`
- Test: `core-test/TestSupport.kt`, `core-test/ModelTest.kt`, `core-test/BytesTest.kt`

Reference: `shellx-link/Sources/ShellXLinkCore/ShellXLink.swift` and `Messages/*.swift` (types only).

**Interfaces:**
- Produces (public, `com.shellx.link.core`):

```kotlin
object ShellXLink {
    const val PROTOCOL_VERSION = 1
    const val MAX_ATTACHMENT_BYTES = 10_485_760
    const val MAX_ATTACHMENTS_PER_MESSAGE = 5
    const val MAX_PENDING_UPLOADS = 5
    val UNSENT_UPLOAD_LIFETIME: Duration = 300.seconds
    const val MAX_ATTACHMENT_CHUNK_BYTES = 45_000
    const val ATTACHMENTS_FEATURE = "attachments"
    const val WORKSPACES_FEATURE = "workspaces"
    const val WORKSPACE_CONTROL_FEATURE = "workspace_control"
    const val AGENT_CLOSE_FEATURE = "agent_close"
    const val TERMINAL_CLOSE_FEATURE = "terminal_close"
    const val MAX_WORKSPACE_TITLE_BYTES = 512
}

// Open enums (PROTOCOL.md §3 "Extension"): an unknown wire value is kept as is.
@JvmInline value class PermissionMode(val wire: String) { companion object { val ONCE = PermissionMode("once"); /* … */ } }
```

  | Type | Constants (`NAME` = wire value) |
  | --- | --- |
  | `PendingKind` | `PERMISSION`, `QUESTION`, `EXIT_PLAN`="exit_plan" |
  | `PermissionMode` | `ONCE`, `ALWAYS`, `ALL`, `DENY` |
  | `ExitPlanMode` | `ULTRAPLAN`, `AUTO_ACCEPT`="auto_accept", `MANUAL`, `DENY` |
  | `ReplyOutcome` | `DELIVERED`, `ALREADY_HANDLED`="already_handled", `UNKNOWN` |
  | `AgentState` | `IDLE`, `WORKING`, `NEEDS_INPUT`="needs_input", `ENDED` |
  | `ChatEntryRole` | `USER`, `AGENT`, `SYSTEM` |
  | `ChatEntryKind` | `PROSE`, `THOUGHT`, `TOOL_USE`="tool_use", `STATUS`, `OTHER` |
  | `ChatSendOutcome` | `SUBMITTED`, `NOT_FOUND`="not_found", `BUSY`, `FAILED` |
  | `ChatInterruptOutcome` | `SENT`, `NOT_FOUND`, `FAILED` |
  | `AttachmentKind` | `IMAGE`, `FILE` |
  | `WorkspaceControlOutcome` | `OK`, `NOT_FOUND`, `REFUSED`, `FAILED` |

  A wire value not written out is the lower-case constant name.

```kotlin
data class PendingItem(
    val requestId: String, val kind: PendingKind, val agent: String, val workspaceId: String,
    val workspaceTitle: String, val toolName: String? = null, val toolInputPreview: String? = null,
    val createdAtMs: Long, val modes: List<String> = emptyList(),
    val questions: List<PendingQuestion>? = null, val planPreview: String? = null,
) { companion object { const val MAX_PREVIEW_BYTES = 8192 } }
data class PendingQuestion(val id: String, val header: String? = null, val prompt: String,
    val multiSelect: Boolean, val options: List<PendingQuestionOption>)
data class PendingQuestionOption(val id: String, val label: String, val description: String? = null)
sealed interface LinkDecision {
    val kind: String                       // "permission" | "question" | "exit_plan" | the unknown kind
    data class Permission(val mode: PermissionMode) : LinkDecision
    data class Question(val selections: List<String>) : LinkDecision
    data class ExitPlan(val mode: ExitPlanMode, val feedback: String? = null) : LinkDecision
    data class Other(override val kind: String) : LinkDecision
}
data class AgentSession(val sessionId: String, val agent: String, val workspaceId: String,
    val workspaceTitle: String, val title: String? = null, val state: AgentState,
    val stateSinceMs: Long? = null, val lastActivityMs: Long? = null)
data class ChatEntry(val id: String, val rev: Long, val seq: Long, val role: ChatEntryRole,
    val kind: ChatEntryKind, val text: String, val truncated: Boolean? = null,
    val toolName: String? = null, val tsMs: Long) {
    companion object {
        const val MAX_TEXT_BYTES = 4096
        /** Of two emissions of one entry, the one with the higher `rev`; `a` when equal. */
        fun newer(a: ChatEntry, b: ChatEntry): ChatEntry
    }
}
data class LinkWorkspace(val workspaceId: String, val title: String, val order: Int,
    val directory: String? = null, val branch: String? = null, val ports: List<Int>? = null,
    val terminals: List<LinkTerminal>)
data class LinkTerminal(val terminalId: String, val title: String, val order: Int,
    val selected: Boolean, val sessionId: String? = null)
```

  Integer types: wire counters and times (`revision`, `seq`, `rev`, `before_seq`, `*_ms`) are `Long`. Sizes, offsets, limits, orders and ports are `Int`. `nonce` is `ULong`. Host-only helpers (`withPreviewLimit`, `withoutTitle`, `withTextCap`, `shrunk`, `truncatedPreview`) are not ported.

- Produces (internal, `core/Bytes.kt`):

```kotlin
internal fun ByteArray.toHex(): String                          // lowercase
internal fun hexToBytesOrNull(text: String): ByteArray?         // even length, [0-9a-f] only
internal fun ByteArray.toBase64Url(): String                    // RFC 4648 §5, no padding
internal fun base64UrlToBytesOrNull(text: String): ByteArray?   // [A-Za-z0-9_-] only, no '='
internal fun ByteArray.toBase64(): String                       // standard, padded
internal fun canonicalBase64ToBytesOrNull(text: String): ByteArray?  // java.util.Base64 basic decoder; null unless re-encoding gives `text`
internal fun sha256(data: ByteArray): ByteArray                 // JCA MessageDigest
internal fun hmacSha256(key: ByteArray, data: ByteArray): ByteArray  // JCA Mac; key is never empty
internal fun constantTimeEquals(a: ByteArray, b: ByteArray): Boolean
internal val String.utf8Size: Int
```

- [ ] **Step 1: Wire the build.**
  - **Catalog.** Add these entries, each under an alias of this name, unless the catalog already has the same module (then use that alias):
    - `kotlinx-coroutines-core` = `org.jetbrains.kotlinx:kotlinx-coroutines-core`
    - `kotlinx-serialization-json` = `org.jetbrains.kotlinx:kotlinx-serialization-json`
    - `bouncycastle-bcprov` = `org.bouncycastle:bcprov-jdk18on`
    - `okhttp` = `com.squareup.okhttp3:okhttp`
    - `okhttp-mockwebserver3` = `com.squareup.okhttp3:mockwebserver3`

    Versions follow Global Constraints.
  - **Root build.** If 3A set no group, add `allprojects { group = "com.shellx.link"; version = "0.1.0" }` to `shellx-link/kotlin/build.gradle.kts`.
  - **Module builds.** Keep 3A's plugin, JVM-17 and JUnit lines, and make each module contain:

```kotlin
// link-core/build.gradle.kts
plugins { `java-library`; /* 3A's Kotlin JVM plugin alias */ }
dependencies {
    api(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.bouncycastle.bcprov)
    testImplementation(kotlin("test"))          // plus 3A's JUnit 5 entries
}
tasks.test {
    useJUnitPlatform()
    outputs.upToDateWhen { false }              // vectors live outside this build (contracts §5)
}
// link-account/build.gradle.kts: same plugins and test block, and
dependencies {
    api(project(":link-core"))
    api(libs.okhttp)
    implementation(libs.kotlinx.serialization.json)
    testImplementation(kotlin("test"))
    testImplementation(libs.okhttp.mockwebserver3)
}
```

  Do not apply the Kotlin serialization compiler plugin.

- [ ] **Step 2: Write the failing tests.** Also create `core-test/TestSupport.kt`:

```kotlin
suspend fun <T> within(timeout: Duration = 5.seconds, block: suspend CoroutineScope.() -> T): T = withTimeout(timeout, block)
/** Polls [condition] every 5 ms until it holds or [timeout] passes; returns the last result. */
suspend fun eventually(timeout: Duration = 2.seconds, condition: () -> Boolean): Boolean
```

```kotlin
class BytesTest {
    @Test fun hexIsLowercaseAndStrict() {
        assertEquals("00ff10", byteArrayOf(0, -1, 16).toHex())
        assertContentEquals(byteArrayOf(0, -1, 16), hexToBytesOrNull("00ff10"))
        for (bad in listOf("00FF10", "0", "zz")) assertNull(hexToBytesOrNull(bad), bad)
    }
    @Test fun base64UrlHasNoPaddingAndOnlyItsAlphabet() {
        val key = byteArrayOf(0xFB.toByte(), 0xFF.toByte(), 0xBF.toByte()) + ByteArray(29)
        assertEquals("-_-_" + "A".repeat(39), key.toBase64Url())
        assertContentEquals(key, base64UrlToBytesOrNull("-_-_" + "A".repeat(39)))
        assertNull(base64UrlToBytesOrNull("+/+/" + "A".repeat(39)))
        assertNull(base64UrlToBytesOrNull("QQ=="))
    }
    @Test fun canonicalBase64RejectsEverythingButPaddedStandardText() {
        assertContentEquals("hello world".encodeToByteArray(), canonicalBase64ToBytesOrNull("aGVsbG8gd29ybGQ="))
        assertContentEquals(ByteArray(0), canonicalBase64ToBytesOrNull(""))
        for (bad in listOf("QQ", "QQ=", "Q Q==", "QQ==\n", "-_8=", "QR==", "%%%")) assertNull(canonicalBase64ToBytesOrNull(bad), bad)
    }
    @Test fun sha256AndHmacMatchPublishedVectors() {
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", sha256("abc".encodeToByteArray()).toHex())
        // RFC 4231 test case 1
        assertEquals("b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
            hmacSha256(ByteArray(20) { 0x0b }, "Hi There".encodeToByteArray()).toHex())
    }
    @Test fun constantTimeEqualsComparesLengthAndContent() {
        assertTrue(constantTimeEquals(byteArrayOf(1, 2), byteArrayOf(1, 2)))
        assertFalse(constantTimeEquals(byteArrayOf(1, 2), byteArrayOf(1, 3)))
        assertFalse(constantTimeEquals(byteArrayOf(1, 2), byteArrayOf(1)))
    }
}
class ModelTest {
    @Test fun openEnumsKeepUnknownWireValues() {
        assertEquals(PermissionMode.ONCE, PermissionMode("once"))
        assertEquals("bypass2", PermissionMode("bypass2").wire)
        assertEquals(ExitPlanMode.AUTO_ACCEPT, ExitPlanMode("auto_accept"))
        assertEquals(ReplyOutcome.ALREADY_HANDLED, ReplyOutcome("already_handled"))
        assertEquals(PendingKind.EXIT_PLAN, PendingKind("exit_plan"))
        assertEquals(AgentState.NEEDS_INPUT, AgentState("needs_input"))
        assertEquals(ChatEntryKind.TOOL_USE, ChatEntryKind("tool_use"))
        assertEquals(ChatSendOutcome.NOT_FOUND, ChatSendOutcome("not_found"))
        assertEquals(WorkspaceControlOutcome.REFUSED, WorkspaceControlOutcome("refused"))
    }
    @Test fun decisionKindIsTheWireKind() {
        assertEquals("permission", LinkDecision.Permission(PermissionMode.ONCE).kind)
        assertEquals("question", LinkDecision.Question(listOf("a")).kind)
        assertEquals("exit_plan", LinkDecision.ExitPlan(ExitPlanMode.MANUAL).kind)
        assertEquals("teleport", LinkDecision.Other("teleport").kind)
    }
    @Test fun newerEntryRevisionWins() {
        val a = ChatEntry("e", 3, 1, ChatEntryRole.AGENT, ChatEntryKind.PROSE, "old", tsMs = 1)
        val b = a.copy(rev = 4, text = "new")
        assertEquals(b, ChatEntry.newer(a, b)); assertEquals(b, ChatEntry.newer(b, a))
        assertEquals(a, ChatEntry.newer(a, a.copy(text = "same rev")))
    }
    @Test fun constantsMatchTheSwiftPackage() {
        assertEquals(10_485_760, ShellXLink.MAX_ATTACHMENT_BYTES); assertEquals(5, ShellXLink.MAX_ATTACHMENTS_PER_MESSAGE)
        assertEquals(5, ShellXLink.MAX_PENDING_UPLOADS); assertEquals(45_000, ShellXLink.MAX_ATTACHMENT_CHUNK_BYTES)
        assertEquals(300.seconds, ShellXLink.UNSENT_UPLOAD_LIFETIME); assertEquals(512, ShellXLink.MAX_WORKSPACE_TITLE_BYTES)
        assertEquals(4096, ChatEntry.MAX_TEXT_BYTES); assertEquals(8192, PendingItem.MAX_PREVIEW_BYTES)
        assertEquals(listOf("attachments", "workspaces", "workspace_control", "agent_close", "terminal_close"),
            listOf(ShellXLink.ATTACHMENTS_FEATURE, ShellXLink.WORKSPACES_FEATURE, ShellXLink.WORKSPACE_CONTROL_FEATURE,
                ShellXLink.AGENT_CLOSE_FEATURE, ShellXLink.TERMINAL_CLOSE_FEATURE))
    }
}
```

- [ ] **Step 3: Run the tests.** Run `gw :link-core:test`. Expected: red, with compile errors "Unresolved reference: toHex" and "Unresolved reference: PermissionMode".
- [ ] **Step 4: Implement the four `core/` files.** Use the Interfaces above.
- [ ] **Step 5: Lock the new libraries, then run the tests again.** 3A's locked runtime classpaths refuse an artefact their `gradle.lockfile` does not name ("… which is not part of the dependency lock state").
  - Run `shellx-android/scripts/dev.sh lock`. It rewrites the lockfiles of `link-core`, `link-account`, `shellx-android/core` and `shellx-android/app`.
  - Run `bash scripts/shellx/check-android-license.sh`. For every `violation` line, apply 3A's allowlist procedure (3A Task 3 Step 6) and rerun until it prints `check-android-license: ok`. Expect kotlinx-coroutines and kotlinx-serialization (covered by `org.jetbrains.kotlinx:*`), `org.bouncycastle:bcprov-jdk18on` (`Bouncy-Castle`), and `com.squareup.okhttp3` / `com.squareup.okio` artefacts (`Apache-2.0`).
  - Run `gw :link-core:test`. Expected: PASS.
- [ ] **Step 6: Mark ledger row `6.2-15` done and commit.** In `docs/superpowers/ledgers/shellx-android-parity.md`, set row `6.2-15` (attachments 5 × 10 MiB, `ShellXLink.kt`) to `done (3B)`.

```bash
git add shellx-link/kotlin/gradle/libs.versions.toml shellx-link/kotlin/build.gradle.kts shellx-link/kotlin/link-core/build.gradle.kts shellx-link/kotlin/link-account/build.gradle.kts shellx-link/kotlin/link-core/src \
  shellx-link/kotlin/link-core/gradle.lockfile shellx-link/kotlin/link-account/gradle.lockfile \
  shellx-android/core/gradle.lockfile shellx-android/app/gradle.lockfile scripts/shellx/android-license-allowlist.txt \
  docs/superpowers/ledgers/shellx-android-parity.md
git commit -m "feat(shellx-link): Kotlin build, Link model types and byte helpers"
```

---

### Task 2: Message codec, checked against `messages.json`

**Files:**
- Create: `core/LinkMessage.kt`, `core/JsonFields.kt`, `core/LinkCodec.kt`
- Test: `core-test/Vectors.kt`, `core-test/VectorMessages.kt`, `core-test/LinkCodecVectorTest.kt`, `core-test/LinkCodecTest.kt`

Reference: `shellx-link/Sources/ShellXLinkCore/Messages/LinkCodec.swift`, `LinkMessage.swift`, and `Tests/ShellXLinkCoreTests/LinkCodecTests.swift`.

**Interfaces:**
- Consumes: Task 1 model types and `Bytes.kt`.
- Produces:

```kotlin
sealed interface LinkMessage {
    /** The one answer to a client call (PROTOCOL.md §3). */
    sealed interface Answer : LinkMessage { val callId: String }
    // the 41 classes below, as data classes nested here
}
object LinkCodec {
    const val MAX_FRAME_BYTES = 65_519
    const val MAX_CALL_ID_BYTES = 64
    fun encode(message: LinkMessage): ByteArray      // throws LinkCodecException
    fun decode(frame: ByteArray): LinkMessage        // throws LinkCodecException
}
sealed class LinkCodecException(message: String) : Exception(message) {
    class FrameTooLarge : LinkCodecException("frame_too_large")
    data class BadJson(val callId: String?) : LinkCodecException("bad_json")  // the frame's call_id when valid
    class WrongVersion : LinkCodecException("wrong_version")
    class CannotEncodeUnknown : LinkCodecException("cannot_encode_unknown")
}
```

  The 41 cases (PROTOCOL.md §8). `A` marks an `Answer`. Each JSON key is the snake_case form of its property, and properties are encoded in the order listed.

  | `LinkMessage.` class | wire `t` | `message.case` |
  | --- | --- | --- |
  | `Hello(clientVersion: String, deviceName: String)` | `hello` | `hello` |
  | `Welcome(protocolVersion: Int, hostVersion: String, machineName: String, features: List<String> = emptyList())` | `welcome` | `welcome` |
  | `Error(code: String, message: String, callId: String? = null)` | `error` | `error` |
  | `SnapshotGet(callId: String)` | `agent.snapshot.get` | `snapshot_get` |
  | `Snapshot(callId, revision: Long, pending: List<PendingItem>)` A | `agent.snapshot` | `snapshot` |
  | `Changed(revision: Long, added: List<PendingItem>, resolved: List<String>)` | `agent.changed` | `changed` |
  | `Reply(callId, requestId: String, decision: LinkDecision)` | `agent.reply` | `reply` |
  | `ReplyResult(callId, requestId: String, outcome: ReplyOutcome)` A | `agent.reply.result` | `reply_result` |
  | `Ping(nonce: ULong)` / `Pong(nonce: ULong)` | `ping` / `pong` | `ping` / `pong` |
  | `SessionsGet(callId)` | `agent.sessions.get` | `sessions_get` |
  | `Sessions(callId, revision: Long, sessions: List<AgentSession>)` A | `agent.sessions` | `sessions` |
  | `SessionsChanged(revision: Long, upserted: List<AgentSession>, removed: List<String>)` | `agent.sessions.changed` | `sessions_changed` |
  | `ChatHistoryGet(callId, sessionId: String, beforeSeq: Long? = null, limit: Int)` | `chat.history.get` | `chat_history_get` |
  | `ChatHistory(callId, sessionId: String, entries: List<ChatEntry>, hasMore: Boolean)` A | `chat.history` | `chat_history` |
  | `ChatEntries(sessionId: String, entries: List<ChatEntry>)` | `chat.entries` | `chat_entries` |
  | `ChatReset(sessionId: String)` | `chat.reset` | `chat_reset` |
  | `ChatSend(callId, sessionId: String, text: String, attachments: List<String> = emptyList())` | `chat.send` | `chat_send` |
  | `ChatSendResult(callId, outcome: ChatSendOutcome)` A | `chat.send.result` | `chat_send_result` |
  | `ChatInterrupt(callId, sessionId: String, hard: Boolean)` | `chat.interrupt` | `chat_interrupt` |
  | `ChatInterruptResult(callId, outcome: ChatInterruptOutcome)` A | `chat.interrupt.result` | `chat_interrupt_result` |
  | `AttachBegin(callId, kind: AttachmentKind, name: String, size: Int)` | `attach.begin` | `attach_begin` |
  | `AttachReady(callId, attachmentId: String)` A | `attach.ready` | `attach_ready` |
  | `AttachChunk(callId, attachmentId: String, offset: Int, data: ByteArray)` | `attach.chunk` | `attach_chunk` |
  | `AttachChunkResult(callId, attachmentId: String, received: Int)` A | `attach.chunk.result` | `attach_chunk_result` |
  | `AttachEnd(callId, attachmentId: String, sha256: ByteArray)` | `attach.end` | `attach_end` |
  | `AttachEndResult(callId, attachmentId: String)` A | `attach.end.result` | `attach_end_result` |
  | `WorkspacesGet(callId)` | `workspace.list.get` | `workspaces_get` |
  | `Workspaces(callId, revision: Long, workspaces: List<LinkWorkspace>)` A | `workspace.list` | `workspaces` |
  | `WorkspacesChanged(revision: Long, upserted: List<LinkWorkspace>, removed: List<String>)` | `workspace.changed` | `workspaces_changed` |
  | `WorkspaceCreate(callId)` | `workspace.create` | `workspace_create` |
  | `WorkspaceCreateResult(callId, outcome: WorkspaceControlOutcome, workspaceId: String? = null)` A | `workspace.create.result` | `workspace_create_result` |
  | `WorkspaceRename(callId, workspaceId: String, title: String)` | `workspace.rename` | `workspace_rename` |
  | `WorkspaceRenameResult(callId, outcome: WorkspaceControlOutcome)` A | `workspace.rename.result` | `workspace_rename_result` |
  | `WorkspaceClose(callId, workspaceId: String)` | `workspace.close` | `workspace_close` |
  | `WorkspaceCloseResult(callId, outcome: WorkspaceControlOutcome)` A | `workspace.close.result` | `workspace_close_result` |
  | `AgentClose(callId, sessionId: String)` | `agent.close` | `agent_close` |
  | `AgentCloseResult(callId, outcome: WorkspaceControlOutcome)` A | `agent.close.result` | `agent_close_result` |
  | `TerminalClose(callId, workspaceId: String, terminalId: String)` | `terminal.close` | `terminal_close` |
  | `TerminalCloseResult(callId, outcome: WorkspaceControlOutcome)` A | `terminal.close.result` | `terminal_close_result` |
  | `Unknown(type: String, callId: String? = null)` (decode only) | any other | `unknown` |

  `callId` is always `String` (`override val` in an `Answer`). `AttachChunk`, `AttachEnd` and `ChatAttachment` (Task 9) follow the `ByteArray` rule in Global Constraints. `AttachEnd.sha256` is the 32-byte digest; on the wire it is 64 lowercase hex characters. `AttachChunk.data` is raw bytes; on the wire it is standard padded base64.

- [ ] **Step 1: Write the vector loader and the vector test.**

```kotlin
// core-test/Vectors.kt
object Vectors {
    /** Contracts §5: read in place, relative to the module directory. */
    fun file(relative: String): File = File(relative).also { check(it.isFile) { "missing vector file ${it.absolutePath}" } }
    fun json(relative: String): JsonObject = Json.parseToJsonElement(file(relative).readText()).jsonObject
    val messages: JsonObject get() = json("../../spec/vectors/messages.json")
    fun hex(text: String): ByteArray = hexToBytesOrNull(text) ?: error("bad hex")
    /** Contracts §6: cases plan 3G adds. Skipped here if 2A has put them in messages.json. */
    val TERMINAL_VIEW_CASES = setOf("terminal_view_open", "terminal_view_open_result", "terminal_view_frame",
        "terminal_view_input", "terminal_view_resize", "terminal_view_resync", "terminal_view_close",
        "terminal_view_ended", "terminal_create", "terminal_create_result")
    fun isTerminalViewFrame(t: String?) =
        t != null && (t.startsWith("terminal.view.") || t == "terminal.create" || t == "terminal.create.result")
}
```

  `core-test/VectorMessages.kt` provides `object VectorMessages { val SENDABLE_CASES: Set<String>; fun fromVector(m: JsonObject): LinkMessage }`. `SENDABLE_CASES` is the 40 case names of the table, all except `unknown`. `fromVector` builds the expected message by hand, by `m["case"]`, through the table:
  - every other key is a property's snake_case name;
  - nested model objects are built key by key with the model constructors;
  - `decision` maps by its `kind`: `permission` → `Permission(PermissionMode(mode))`, `question` → `Question(selections)`, `exit_plan` → `ExitPlan(ExitPlanMode(mode), feedback)`, anything else → `Other(kind)`;
  - `attach_chunk.data` is decoded with `java.util.Base64.getDecoder()`, and `attach_end.sha256` with `Vectors.hex`;
  - `nonce` is read as `content.toULong()`;
  - an absent optional key is `null`, or an empty list for `features` and `attachments`.

  It never calls `LinkCodec`.

```kotlin
class LinkCodecVectorTest {
    private val file = Vectors.messages
    private fun entries(section: String) = file.getValue(section).jsonArray.map { it.jsonObject }
    private fun JsonObject.text(key: String) = getValue(key).jsonPrimitive.content
    private fun frame(element: JsonElement) = Json.encodeToString(JsonElement.serializer(), element).encodeToByteArray()

    @Test fun vectorsDecodeAndEncodeBack() {
        val seen = mutableSetOf<String>()
        for (v in entries("vectors")) {
            val case = v.getValue("message").jsonObject.text("case")
            if (case in Vectors.TERMINAL_VIEW_CASES) continue
            val name = v.text("name"); seen += case
            val expected = VectorMessages.fromVector(v.getValue("message").jsonObject)
            assertEquals(expected, LinkCodec.decode(frame(v.getValue("json"))), name)
            assertEquals(v.getValue("json"), Json.parseToJsonElement(LinkCodec.encode(expected).decodeToString()), name)
        }
        assertEquals(VectorMessages.SENDABLE_CASES, seen)
    }
    @Test fun decodeOnlyVectors() {
        val seen = mutableSetOf<String>()
        for (v in entries("decode_only")) {
            val case = v.getValue("message").jsonObject.text("case")
            if (case in Vectors.TERMINAL_VIEW_CASES) continue      // 2A appends terminal entries here too
            seen += case
            assertEquals(VectorMessages.fromVector(v.getValue("message").jsonObject), LinkCodec.decode(frame(v.getValue("json"))), v.text("name"))
        }
        assertTrue("unknown" in seen)
    }
    @Test fun decodeErrorVectors() {
        for (v in entries("decode_errors")) {
            val name = v.text("name"); val json = v["json"]?.jsonObject
            if (Vectors.isTerminalViewFrame(json?.get("t")?.jsonPrimitive?.contentOrNull)) continue
            val bytes = v["json_text"]?.jsonPrimitive?.content?.encodeToByteArray() ?: frame(json!!)
            val error = assertFailsWith<LinkCodecException>(name) { LinkCodec.decode(bytes) }
            when (v.text("error")) {
                "wrong_version" -> assertIs<LinkCodecException.WrongVersion>(error, name)
                "frame_too_large" -> assertIs<LinkCodecException.FrameTooLarge>(error, name)
                "bad_json" -> assertEquals(LinkCodecException.BadJson(v["call_id"]?.jsonPrimitive?.content), error, name)
                else -> fail("unknown error name in $name")
            }
        }
    }
    @Test fun boundaryFrames() {
        val b = file.getValue("boundary_frames").jsonObject
        val cases = b.getValue("cases").jsonArray.map { it.jsonObject }
        assertTrue(cases.size >= 4)
        for (c in cases) {
            val name = c.text("name")
            val filler = c.getValue("filler").jsonArray.joinToString("") { it.jsonObject.text("text").repeat(it.jsonObject.getValue("count").jsonPrimitive.int) }
            val text = b.text("prefix") + filler + b.text("suffix")
            assertEquals(c.getValue("bytes").jsonPrimitive.int, text.utf8Size, name)
            c["chars"]?.let { assertEquals(it.jsonPrimitive.int, text.codePointCount(0, text.length), name) }
            val message = LinkMessage.Error(code = "x", message = filler)
            when (c.text("result")) {
                "ok" -> { assertEquals(message, LinkCodec.decode(text.encodeToByteArray()), name); assertEquals(text.utf8Size, LinkCodec.encode(message).size, name) }
                "frame_too_large" -> {
                    assertFailsWith<LinkCodecException.FrameTooLarge>(name) { LinkCodec.decode(text.encodeToByteArray()) }
                    assertFailsWith<LinkCodecException.FrameTooLarge>(name) { LinkCodec.encode(message) }
                }
                else -> fail("unknown result in $name")
            }
        }
    }
}
```

- [ ] **Step 2: Write the unit tests.** These mirror `LinkCodecTests.swift`, plus Kotlin strictness. Each line below is one `@Test`; `d(text)` means `LinkCodec.decode(text.encodeToByteArray())`.

```kotlin
class LinkCodecTest {
    // unknownTypeKeepsOnlyAValidCallId
    //   d("""{"v":1,"t":"future.call","call_id":"c1","x":{}}""") == Unknown("future.call", "c1")
    //   each of `""`, 65 × "c", `7`, `null`, `["c1"]` as call_id → Unknown("future.call", null)
    // badJsonCarriesTheFramesValidCallId
    //   agent.reply without request_id, call_id c1 → BadJson("c1"); without call_id → BadJson(null)
    //   agent.snapshot.get with call_id "" or 65 bytes → BadJson(null); 64 × "c" decodes
    // garbageIsBadJsonWithoutCallId
    //   "", "nope", "[1]", """{"v":"1","t":"ping"}""", bytes [0x7b, 0xff, 0x7d] → BadJson(null)
    // integersAreStrictTokens (PROTOCOL.md §3)
    //   agent.changed with revision 1.0 or 1e3 → BadJson(null)
    //   ping with nonce -1, 18446744073709551616 or "5" → BadJson(null)
    //   ping with nonce 18446744073709551615 → Ping(ULong.MAX_VALUE)
    // stringsAndBoolsAreTyped
    //   chat.reset with session_id 7 → BadJson(null)
    //   chat.interrupt with call_id c1 and hard "true" → BadJson("c1")
    // nullOptionalIsAbsentNullRequiredIsBadJson
    //   error with call_id null → Error("x", "m", null); chat.reset with session_id null → BadJson(null)
    // chunkDataMustBeCanonicalBase64
    //   attach.chunk call_id c1 with data in "%%%", "QQ", "QQ=", "Q Q==", "QQ==\n", "-_8=", "QR==", 7 → BadJson("c1")
    //   data "QQ==" and "" decode (the empty chunk is a host rule)
    // endDigestMustBe64LowercaseHex
    //   attach.end call_id c1 with sha256 63 or 65 chars, upper case, "zz"×32, "" → BadJson("c1"); "ab"×32 decodes
    // encodingValidatesCallIdsAndDigest
    //   encode(SnapshotGet("")) and SnapshotGet("c".repeat(65)) → BadJson(null)
    //   Error("x", "m", "") → BadJson(null)
    //   AttachEnd("c1", "a1", ByteArray(31)) → BadJson(null)
    //   Unknown("x") → CannotEncodeUnknown
    // encodingOmitsEmptyAndAbsentOptionals
    //   encode(Welcome(1, "h", "m")) has no "features" key
    //   ChatSend("c1", "s", "hi") has no "attachments"
    //   WorkspaceCreateResult("c1", REFUSED) has no "workspace_id"
    //   no encoded text contains "null"
    // frameAtTheLimitIsAccepted
    //   item(p) = PendingItem("r", PendingKind.PERMISSION, "claude", "w", "t", toolName = "Bash", toolInputPreview = p, createdAtMs = 1)
    //   binary search the longest "a".repeat(n) preview for which Snapshot("c1", 1, listOf(item(…))) encodes
    //   its frame is exactly 65 519 bytes and decodes to the same message
    //   a 70 000-byte preview → FrameTooLarge; decode(ByteArray(70_000) { 0x20 }) → FrameTooLarge
    // fullChunkFitsAFrame
    //   AttachChunk(64 × "i", 64 × "i", 10_485_760, ByteArray(45_000) { it.toByte() }) encodes to ≤ 65 519 bytes
    //   and round-trips equal
    // vietnameseTextCountsBytes
    //   Error("x", "ệ".repeat(30_000)) (90 000 bytes) → FrameTooLarge
}
```

  Write each line as a real test with these exact inputs and expected values.

- [ ] **Step 3: Run the tests.** Run `gw :link-core:test --tests 'com.shellx.link.core.LinkCodec*'`. Expected: red, "Unresolved reference: LinkCodec".
- [ ] **Step 4: Implement `LinkMessage.kt`, `JsonFields.kt` and `LinkCodec.kt`.**

  **Strict readers** (`JsonFields.kt`, internal). Each throws a private `FieldError`.
  - `str`: a `JsonPrimitive` with `isString`.
  - `optStr`: absent or `JsonNull` → `null`, otherwise `str`.
  - `long` / `int`: a non-string primitive whose `content` matches `-?(0|[1-9][0-9]*)` and fits the type (`toLongOrNull` / `toIntOrNull`).
  - `uLong`: matches `0|[1-9][0-9]*` and passes `toULongOrNull()`.
  - `bool`: a non-string primitive whose `content` is `true` or `false`.
  - `array`, `obj`, with `opt…` forms that treat `JsonNull` as absent.
  - `validCallIdOrNull(e: JsonElement?)`: the string when it is 1–64 UTF-8 bytes, otherwise `null`.
  - `callId(o)`: like `str("call_id")`, but `FieldError` unless 1–64 bytes.

  `JsonNull` is a `JsonPrimitive` with content `"null"`, so the `isString` and content checks above reject it.

  **Encode rules:**
  1. `Unknown` → `CannotEncodeUnknown`.
  2. Every `callId` (including a non-null `Error.callId`) must be 1–64 UTF-8 bytes, and `AttachEnd.sha256` 32 bytes; otherwise `BadJson(null)`.
  3. Build a `JsonObject` with `"v": 1`, `"t"`, then the properties in table order. Leave out a `null` optional, and leave out `features` and `attachments` when empty.
     - `nonce` is `JsonUnquotedLiteral(nonce.toString())`, with `@OptIn(ExperimentalSerializationApi::class)`.
     - Open enums are written as `wire`.
     - `LinkDecision` is `{"kind"}` plus `mode`, `selections`, or `mode` and `feedback`; `Other` writes `kind` only.
     - Nested objects use the same rules, with properties in constructor order.
  4. `Json.encodeToString(JsonObject.serializer(), obj)`. If the UTF-8 size is above 65 519 → `FrameTooLarge`.

  **Decode rules:**
  1. `size > 65 519` → `FrameTooLarge`.
  2. Decode with `decodeToString(throwOnInvalidSequence = true)` and `Json.parseToJsonElement`. If the result is not an object, `t` is not a string, or `v` is not an integer token → `BadJson(null)`.
  3. If `v`'s content is not `"1"` → `WrongVersion`.
  4. If `t` is not in the table → `Unknown(t, validCallIdOrNull(o["call_id"]))`, whatever the other fields hold.
  5. Otherwise build the message with the strict readers. Any `FieldError`, base64 or hex failure, including in nested objects → `BadJson(validCallIdOrNull(o["call_id"]))`. Unknown fields are ignored.

- [ ] **Step 5: Run the tests again.** Run `gw :link-core:test`. Expected: PASS. The vector test covers 40 sendable cases plus `unknown`.
- [ ] **Step 6: Commit.**

```bash
git add shellx-link/kotlin/link-core/src
git commit -m "feat(shellx-link): Kotlin Link message codec checked against the shared vectors"
```

---

### Task 3: Noise_XX_25519_ChaChaPoly_SHA256, checked against `noise_xx.json`

**Files:**
- Create: `core/NoiseKeys.kt`, `core/NoiseCipherState.kt`, `core/NoiseHandshake.kt`
- Modify: `core-test/Vectors.kt` (add `val noise get() = json("../../vectors/noise_xx.json")`)
- Test: `core-test/NoiseVectorTest.kt`, `core-test/NoiseTest.kt`

Reference: `shellx-link/Sources/ShellXLinkCore/Noise/*.swift`, `Tests/ShellXLinkCoreTests/NoiseTests.swift`.

**Interfaces:**
- Consumes: `sha256`, `hmacSha256`, `toHex` (Task 1).
- Produces:

```kotlin
enum class NoiseRole { INITIATOR, RESPONDER }
sealed class NoiseException(message: String) : Exception(message) {
    class UntrustedPeer : NoiseException("untrusted_peer")
    class DecryptFailed : NoiseException("decrypt_failed")
    class BadMessage : NoiseException("bad_message")
    class NonceExhausted : NoiseException("nonce_exhausted")
    class NonEmptyHandshakePayload : NoiseException("non_empty_handshake_payload")   // thrown by SecureChannel (Task 7)
}
class NoiseStaticKey private constructor(/* 32-byte private, 32-byte public */) {
    val rawPrivate: ByteArray          // a copy
    val publicKey: ByteArray           // a copy
    internal fun diffieHellman(remotePublic: ByteArray): ByteArray   // BadMessage on a wrong length or an all-zero result
    override fun toString(): String    // "NoiseStaticKey(<redacted>)"
    companion object {
        fun generate(random: SecureRandom = SecureRandom()): NoiseStaticKey
        fun fromPrivate(rawPrivate: ByteArray): NoiseStaticKey       // IllegalArgumentException unless 32 bytes
    }
}
class NoiseHandshake internal constructor(role: NoiseRole, local: NoiseStaticKey,
        trusts: (ByteArray) -> Boolean, ephemeralForTesting: NoiseStaticKey?) {
    constructor(role: NoiseRole, local: NoiseStaticKey, trusts: (ByteArray) -> Boolean = { true })
    val isComplete: Boolean
    val handshakeHash: ByteArray
    val remoteStatic: ByteArray?       // authenticated only once isComplete; null after any failure
    fun writeMessage(payload: ByteArray = ByteArray(0)): ByteArray
    fun readMessage(message: ByteArray): ByteArray
    fun split(): NoiseTransport        // once, after message 3; else BadMessage
    companion object {
        const val PROTOCOL_NAME = "Noise_XX_25519_ChaChaPoly_SHA256"
        val PROLOGUE: ByteArray get() = "shellx-link/1".encodeToByteArray()   // a fresh copy per read
    }
}
class NoiseTransport internal constructor(send: CipherState, receive: CipherState) {
    fun encrypt(plaintext: ByteArray): ByteArray     // @Synchronized; BadMessage when plaintext + 16 > 65 535
    fun decrypt(ciphertext: ByteArray): ByteArray    // @Synchronized; BadMessage when > 65 535; DecryptFailed keeps the nonce
    companion object { const val MAX_MESSAGE_BYTES = 65_535; const val TAG_BYTES = 16 }
}
internal class CipherState(key: ByteArray?, nonce: ULong = 0u) {  // the nonce parameter lets the exhaustion test start near 2^64
    val hasKey: Boolean
    fun encrypt(ad: ByteArray, plaintext: ByteArray): ByteArray    // no key: returns plaintext
    fun decrypt(ad: ByteArray, ciphertext: ByteArray): ByteArray   // no key: returns ciphertext
}
```

- [ ] **Step 1: Write the failing tests.**

```kotlin
class NoiseVectorTest {
    @Test fun matchesSnowVectors() {
        val v = Vectors.noise
        fun JsonObject.hex(key: String) = Vectors.hex(getValue(key).jsonPrimitive.content)
        fun party(name: String) = v.getValue(name).jsonObject
        assertEquals(NoiseHandshake.PROTOCOL_NAME, v.getValue("protocol").jsonPrimitive.content)
        assertContentEquals(NoiseHandshake.PROLOGUE, v.hex("prologue"))
        val keys = listOf("initiator", "responder").associateWith { p ->
            NoiseStaticKey.fromPrivate(party(p).hex("static_private")) to NoiseStaticKey.fromPrivate(party(p).hex("ephemeral_private")) }
        for ((p, pair) in keys) {
            assertContentEquals(party(p).hex("static_public"), pair.first.publicKey)
            assertContentEquals(party(p).hex("ephemeral_public"), pair.second.publicKey)
        }
        val initiator = NoiseHandshake(NoiseRole.INITIATOR, keys.getValue("initiator").first, { true }, keys.getValue("initiator").second)
        val responder = NoiseHandshake(NoiseRole.RESPONDER, keys.getValue("responder").first, { true }, keys.getValue("responder").second)
        val steps = v.getValue("handshake").jsonArray.map { it.jsonObject }
        assertEquals(3, steps.size)
        steps.forEachIndexed { i, step ->
            val initiatorSends = i % 2 == 0
            assertEquals(if (initiatorSends) "initiator" else "responder", step.getValue("sender").jsonPrimitive.content)
            val (writer, reader) = if (initiatorSends) initiator to responder else responder to initiator
            val message = writer.writeMessage(step.hex("payload"))
            assertEquals(step.getValue("ciphertext").jsonPrimitive.content, message.toHex(), "handshake message ${i + 1}")
            assertContentEquals(step.hex("payload"), reader.readMessage(message))
        }
        assertTrue(initiator.isComplete && responder.isComplete)
        assertContentEquals(party("responder").hex("static_public"), initiator.remoteStatic)
        assertContentEquals(party("initiator").hex("static_public"), responder.remoteStatic)
        assertEquals(v.getValue("handshake_hash").jsonPrimitive.content, initiator.handshakeHash.toHex())
        assertEquals(v.getValue("handshake_hash").jsonPrimitive.content, responder.handshakeHash.toHex())
        val iT = initiator.split(); val rT = responder.split()
        val transport = v.getValue("transport").jsonObject
        for ((key, pair) in listOf("initiator_to_responder" to (iT to rT), "responder_to_initiator" to (rT to iT)))
            for (m in transport.getValue(key).jsonArray.map { it.jsonObject }) {
                assertEquals(m.getValue("ciphertext").jsonPrimitive.content, pair.first.encrypt(m.hex("payload")).toHex())
                assertContentEquals(m.hex("payload"), pair.second.decrypt(m.hex("ciphertext")))
            }
    }
}
```

  `NoiseTest` mirrors `NoiseTests.swift`. `handshake(i, r)` runs XX with payloads `""`, `"r"`, `"i"` and checks each payload.
  - `roundTripWithRandomKeys`:
    - keys are 32 bytes, and two generated keys differ;
    - `fromPrivate(k.rawPrivate).publicKey` equals `k.publicKey`;
    - each side's `remoteStatic` is the other's public key, and both hashes are equal;
    - `"hello mac"` and `"hello phone"` survive both directions;
    - a second `split()` throws `BadMessage`.
  - `untrustedPeerIsRejectedAndForgotten`:
    - with an initiator `trusts = { seen += it; false }`, reading message 2 throws `UntrustedPeer`;
    - `seen == [r.publicKey]`, `!isComplete`, `remoteStatic == null`, and the next `writeMessage()` throws `BadMessage`;
    - a responder that distrusts throws `UntrustedPeer` at message 3, has `remoteStatic == null`, and `split()` throws.
  - `tamperedMessagesFail`:
    - flipping bit 0, 7 or the last bit of a transport ciphertext throws `DecryptFailed`, and afterwards the genuine ciphertext still decrypts;
    - `message2[40] ^= 1` throws `DecryptFailed` with `remoteStatic == null`;
    - flipping message 2's last byte throws `DecryptFailed`, leaves `remoteStatic == null` and `!isComplete`.
  - `nonceCountsPerFrameAndCapsFrameSize`:
    - two encryptions of `"same"` differ, and each is `+16` bytes;
    - decrypting the second first throws `DecryptFailed`; then first and second decrypt in order; replaying the first throws;
    - `encrypt(ByteArray(65_519))` works, and `ByteArray(65_520)` throws `BadMessage`.
  - `exhaustedNonceIsRefused`: `CipherState(ByteArray(32), ULong.MAX_VALUE - 1u).encrypt(ByteArray(0), "x".encodeToByteArray())` works once, then throws `NonceExhausted`.
  - `fromPrivateRejectsWrongLength`: 31 bytes → `IllegalArgumentException`.
  - `toStringHidesThePrivateKey`: `toString()` contains neither the private key's hex nor its base64.

- [ ] **Step 2: Run the tests.** Run `gw :link-core:test --tests 'com.shellx.link.core.Noise*'`. Expected: red, "Unresolved reference: NoiseHandshake".
- [ ] **Step 3: Implement.**
  - **X25519:**
    - generate with `X25519PrivateKeyParameters(random)`, or build from raw bytes with `X25519PrivateKeyParameters(raw, 0)`;
    - get the public key with `.generatePublicKey().encoded`;
    - for DH, `X25519Agreement().apply { init(priv) }.calculateAgreement(X25519PublicKeyParameters(remote, 0), out, 0)`. Its `IllegalStateException` (all-zero result) → `BadMessage`.
  - **ChaChaPoly:** `ChaCha20Poly1305()` with `AEADParameters(KeyParameter(key), 128, nonce12, ad)`. The output is ciphertext followed by the 16-byte tag. `InvalidCipherTextException` → `DecryptFailed`.
  - **Algorithm** (Noise rev 34 §5, as `NoiseHandshake.swift` and `NoiseCipherState.swift` implement it):

```text
init      h = PROTOCOL_NAME bytes (exactly 32, no hashing); ck = h; no key; MixHash(PROLOGUE)
MixHash   h = SHA256(h || data)
HKDF      t = HMAC(ck, ikm); o1 = HMAC(t, 0x01); o2 = HMAC(t, o1 || 0x02) → (o1, o2)
MixKey    (ck, k) = HKDF(ck, ikm); n = 0
nonce     12 bytes = 00 00 00 00 || n as 8-byte little-endian; n == 2^64-1 → NonceExhausted; n += 1 only after success
Encrypt/DecryptAndHash   with a key: AEAD with ad = h, else pass through; then MixHash(ciphertext)
messages  1: e        2: e, ee, s, es        3: s, se        then payload = EncryptAndHash(payload)
e         write: take ephemeralForTesting or generate; append pub; MixHash(pub).  read: re = next 32 bytes; MixHash(re)
s         write: append EncryptAndHash(local.pub).  read: rs = DecryptAndHash(next 32 + (hasKey ? 16 : 0) bytes); trusts(rs) or UntrustedPeer
ee        MixKey(DH(e, re))
es        initiator MixKey(DH(e, rs)); responder MixKey(DH(s, re))
se        initiator MixKey(DH(s, re)); responder MixKey(DH(e, rs))
split     (k1, k2) = HKDF(ck, empty); initiator sends k1 receives k2; responder the reverse
turns     initiator writes 1 and 3, reads 2; wrong turn, a 4th message, or > 65 535 bytes → BadMessage
failure   any error marks the handshake failed, clears remoteStatic and the ephemeral; later calls throw BadMessage;
          errors that are not NoiseException become BadMessage
```

- [ ] **Step 4: Run the tests again.** Run `gw :link-core:test`. Expected: PASS.
- [ ] **Step 5: Commit.**

```bash
git add shellx-link/kotlin/link-core/src
git commit -m "feat(shellx-link): Kotlin Noise XX handshake and transport checked against snow vectors"
```

---

### Task 4: Pairing offer, checked against `pairing.json`

**Files:**
- Create: `core/PairingOffer.kt`
- Modify: `core-test/Vectors.kt` (add `val pairing get() = json("../../spec/vectors/pairing.json")`)
- Test: `core-test/PairingOfferTest.kt`

Reference: `shellx-link/Sources/ShellXLinkCore/Pairing/PairingOffer.swift`, `Tests/ShellXLinkCoreTests/PairingOfferTests.swift`, PROTOCOL.md §9.

**Interfaces:**
- Produces:

```kotlin
data class PairingOffer(val machineId: String, val linkSlot: String, val hostKey: ByteArray,
        val code: ByteArray, val machineName: String) {
    /** `shellx-link://pair?v=1&m=…&s=…&k=…&c=…&n=…` */
    val uri: String
    /** HMAC-SHA256(code, "shellx-link-pair/1" 0x00 machineId 0x00 linkSlot 0x00 hostKey clientKey) */
    fun proof(clientKey: ByteArray): ByteArray
    override fun toString(): String    // "PairingOffer(machine=…, slot=…, <redacted>)": never the code
    companion object {
        val LIFETIME: Duration = 300.seconds
        fun parse(uri: String): PairingOffer                       // throws PairingOfferException
        fun make(machineId: String, linkSlot: String, hostKey: ByteArray, machineName: String,
                 random: SecureRandom = SecureRandom()): PairingOffer   // 16-byte random code (test and demo Macs)
    }
}
sealed class PairingOfferException(message: String) : Exception(message) {
    class BadUri : PairingOfferException("bad_uri")
    class UnsupportedVersion : PairingOfferException("unsupported_version")
    data class BadField(val field: String) : PairingOfferException("bad_field")
}
```

- [ ] **Step 1: Write the failing tests.** These port `PairingOfferTests.swift`. Load the vector like this:

```kotlin
val v = Vectors.pairing
fun text(key: String) = v.getValue(key).jsonPrimitive.content
fun b64u(key: String) = base64UrlToBytesOrNull(text(key))!!
val vectorOffer = PairingOffer(text("machine_id"), text("link_slot"), b64u("host_key_b64url"), b64u("code_b64url"), text("machine_name"))
val client = b64u("client_key_b64url")
val good = vectorOffer.uri
```

  The tests:
  - `uriRoundTrips`:
    - `uri` starts with `"shellx-link://pair?v=1&m=6f1c2b7e-0d4a-4c1e-9a53-3b8e5d2f7a10&s=slot-test-1&k="`, has no `+`, and ends with `"&n=Phu%27s%20Mac"`;
    - `parse(uri) == vectorOffer`;
    - `make(…, machineName = "Mac é ü & =")` round-trips with a 16-byte code, and two `make` codes differ;
    - `LIFETIME == 300.seconds`.
  - `vietnameseMachineNameRoundTrips`: `make(…, "MacBook của Phú").uri` parses back to the same name.
  - `proofMatchesTheVector`: `proof(client).toHex() == proof_hex` and `proof(client).toBase64Url() == proof_b64url`.
  - `proofIsBoundToHostKeySlotAndMachine`: the proof differs after `copy(hostKey = host with byte 0 ^ 1)`, after `copy(linkSlot = "attacker-slot")`, after `copy(machineId = "00000000-0000-4000-8000-000000000000")`, and for a client key with byte 0 flipped.
  - `parseRejectsStrictFieldClasses`: every replacement in `testParseRejectsStrictFieldClasses` gives the same error, for example:
    - `m=a_b`, `m=a%2Fb`, 65 × `a`, `m=` → `BadField("m")`;
    - `s=a.b`, `s=a%20b`, 65 × `a` → `BadField("s")`;
    - a `+` in `k`, `%2F` in `k`, `k` + `%3D` → `BadField("k")`;
    - `c=…%2B` → `BadField("c")`;
    - `n=`, 101 × `a`, `%0A`, `%00`, `%7F`, `%E2%80%AA`, `%E2%80%AE`, `%E2%81%A6`, `%E2%81%A9` → `BadField("n")`;
    - 100 × `a` and `n=%E2%80%8F%20ok` parse;
    - `pair/x?`, `pair/?`, `//pair:80?`, `//user@pair?`, `good + "#frag"` → `BadUri`;
    - `good + "&n=Other"` → `BadField("n")`; a repeated `k` → `BadField("k")`.
  - `parseRejectsBadFields`:
    - `"https://example.com/pair?v=1"` and `"not a uri"` → `BadUri`;
    - `v=2` → `UnsupportedVersion`;
    - a 31-byte `k` → `BadField("k")`; no `c` → `BadField("c")`; no `s` → `BadField("s")`.
  - `toStringHidesTheCode`: `toString()` does not contain `"AAECAwQFBgcICQoLDA0ODw"`.

- [ ] **Step 2: Run the tests.** Run `gw :link-core:test --tests 'com.shellx.link.core.PairingOfferTest'`. Expected: red, "Unresolved reference: PairingOffer".
- [ ] **Step 3: Implement.** `equals`/`hashCode` compare the two keys by content.

  **Parse** (with `java.net.URI`):
  1. `URI(uri)`; a `URISyntaxException` → `BadUri`.
  2. Require scheme `shellx-link`, `rawAuthority == "pair"` (this rejects userinfo and port), an empty `rawPath` and no fragment; otherwise `BadUri`.
  3. Split `rawQuery` on `&`, then each item at its first `=`. A missing `=` gives the value `""`. Percent-decode name and value to bytes, then decode strict UTF-8; an invalid value → `BadField(name)`. Never turn `+` into a space. A repeated name → `BadField(name)`.
  4. A missing `v` → `BadField("v")`; `v != "1"` → `UnsupportedVersion`.
  5. `m` matches `[A-Za-z0-9-]{1,64}`, and `s` matches `[A-Za-z0-9_-]{1,64}`.
  6. `k` and `c` pass `base64UrlToBytesOrNull` and decode to 32 and 16 bytes.
  7. `n` is non-empty and ≤ 100 code points, with no `Character.CONTROL` and nothing in U+202A–U+202E or U+2066–U+2069.

  **`uri`:** percent-encode `m`, `s` and `n` by UTF-8 byte, keeping only `A-Za-z0-9-._~`, with upper-case hex. Write `k` and `c` with `toBase64Url()`.

- [ ] **Step 4: Run the tests again.** Run `gw :link-core:test`. Expected: PASS.
- [ ] **Step 5: Commit.**

```bash
git add shellx-link/kotlin/link-core/src
git commit -m "feat(shellx-link): Kotlin pairing offer parse and proof"
```

---

### Task 5: Relay control messages, tickets and URL policy

**Files:**
- Create: `core/RelayControl.kt`, `core/RelayTicket.kt`, `core/RelayEndpoint.kt`
- Create: `shellx-link/kotlin/link-core/src/test/resources/relay-control-samples.jsonl`, exactly the 10 lines below, written by hand in the key order of `RelayControl.swift` (Global Constraints: never copy a file from `cmux-tui/`)
- Test: `core-test/RelayControlTest.kt`, `core-test/RelayTicketTest.kt`, `core-test/RelayEndpointTest.kt`

```text
{"type":"register","protocol":5,"slot":"slot-k1","ticket":"t-register"}
{"type":"registered","lease_seconds":45}
{"type":"connect","protocol":5,"slot":"slot-k1","ticket":"t-connect","lane":"lane-k1","generation":3}
{"type":"allocated","circuit":"circuit-k1","lane":"lane-k1","generation":3,"join_ticket":"t-client-join"}
{"type":"incoming","circuit":"circuit-k1","lane":"lane-k1","generation":3,"join_ticket":"t-daemon-join"}
{"type":"join","protocol":5,"slot":"slot-k1","circuit":"circuit-k1","lane":"lane-k1","generation":3,"ticket":"t-client-join","role":"client"}
{"type":"ready","circuit":"circuit-k1","lane":"lane-k1","generation":3}
{"type":"ping","nonce":7}
{"type":"pong","nonce":7}
{"type":"error","code":"slot-offline","message":"the host is offline","retryable":true}
```

Reference: `shellx-link/Sources/ShellXLinkRelay/RelayControl.swift`, `Tests/ShellXLinkRelayTests/RelayEndpointTests.swift`, `RelayTicketTests.swift`; `relay/src/v2/tickets.ts`.

**Interfaces:**
- Consumes: the `JsonFields.kt` readers (Task 2), `base64UrlToBytesOrNull` (Task 1).
- Produces:

```kotlin
sealed class RelayException(message: String) : Exception(message) {
    class Closed : RelayException("closed")
    data class Server(val code: String, val retryable: Boolean) : RelayException(code)
    data class ProtocolViolation(val detail: String) : RelayException(detail)
    data class InsecureTransport(val scheme: String) : RelayException("insecure_transport")
    class TimedOut : RelayException("timed_out")
}
object RelayProtocol {
    const val VERSION = 5                                   // cmux-tui/crates/cmux-remote-protocol/src/frame.rs:6
    val CONTROL_TIMEOUT: Duration = 10.seconds
    val AUTHENTICATION_CODES = setOf("unauthorized", "invalid-ticket", "ticket-expired", "registration-expired")
}
enum class RelayRole(val wire: String) { DAEMON("daemon"), CLIENT("client") }
sealed interface RelayControl {
    data class Register(val protocol: Int, val slot: String, val ticket: String) : RelayControl
    data class Registered(val leaseSeconds: Long) : RelayControl
    data class Connect(val protocol: Int, val slot: String, val ticket: String, val lane: String, val generation: ULong) : RelayControl
    data class Allocated(val circuit: String, val lane: String, val generation: ULong, val joinTicket: String) : RelayControl
    data class Incoming(val circuit: String, val lane: String, val generation: ULong, val joinTicket: String) : RelayControl
    data class Join(val protocol: Int, val slot: String, val circuit: String, val lane: String,
                    val generation: ULong, val ticket: String, val role: RelayRole) : RelayControl
    data class Ready(val circuit: String, val lane: String, val generation: ULong) : RelayControl
    data class Ping(val nonce: ULong) : RelayControl
    data class Pong(val nonce: ULong) : RelayControl
    data class Error(val code: String, val message: String, val retryable: Boolean) : RelayControl
    fun encodeText(): String
    companion object { fun decode(text: String): RelayControl }   // anything else → ProtocolViolation("invalid relay control message")
}
data class RelayTicket(val ticket: String, val expiresAtUnix: Long) {
    val claims: RelayTicketClaims?     // middle segment of `v2.<base64url JSON>.<sig>`; signature not checked
    override fun toString(): String    // "RelayTicket(expires=<n>, <redacted>)"
}
data class RelayTicketClaims(val slot: String, val permission: String, val role: String,
    val expiresAtUnix: Long, val issuedAtUnix: Long? = null)
object RelayTransportPolicy {
    fun isLoopback(host: String?): Boolean         // localhost, 127.0.0.0/8, ::1 (brackets allowed), case-insensitive
    fun requireHttps(url: URI)                     // https; http only to loopback → else InsecureTransport("http"); no scheme/host or other scheme → ProtocolViolation
}
object RelayEndpoint {
    fun control(url: URI): URI                     // ws/relay+ws/http → ws (loopback only), wss/relay+wss/https → wss; empty or "/" path → /v1/relay; query and fragment dropped
    fun circuit(control: URI, circuit: String): URI  // path under /v1/slots/ → /v1/circuits/<percent-encoded circuit>; else control
}
internal object RelayLane { fun random(random: SecureRandom = SecureRandom()): String }  // 24 random bytes, toBase64Url() (32 chars)
```

  **Wire keys**, in encode order: `type` first, then the fields in the order of each class above. JSON names are `protocol`, `slot`, `ticket`, `lease_seconds`, `lane`, `generation`, `circuit`, `join_ticket`, `role`, `nonce`, `code`, `message`, `retryable`. Type strings are the lower-case class names.

  **Decode limits:** `protocol` must be 0–255, `lease_seconds` 0–4 294 967 295, `generation` and `nonce` uint64, `role` `daemon` or `client`.

  **Redaction:** `toString()` of `Register`, `Connect`, `Join`, `Allocated` and `Incoming` prints `<redacted>` for `ticket` and `joinTicket`.

- [ ] **Step 1: Write the failing tests.**

```kotlin
class RelayControlTest {
    private fun samples() = javaClass.getResource("/relay-control-samples.jsonl")!!.readText().lines().filter { it.isNotEmpty() }
    @Test fun sampleLinesDecodeAndEncodeByteForByte() {
        val lines = samples(); assertEquals(10, lines.size)
        for (line in lines) assertEquals(line, RelayControl.decode(line).encodeText(), line)
        assertEquals(RelayControl.Register(5, "slot-k1", "t-register"), RelayControl.decode(lines[0]))
        assertEquals(RelayControl.Join(5, "slot-k1", "circuit-k1", "lane-k1", 3u, "t-client-join", RelayRole.CLIENT), RelayControl.decode(lines[5]))
        assertEquals(RelayControl.Error("slot-offline", "the host is offline", true), RelayControl.decode(lines[9]))
    }
    @Test fun uint64FieldsKeepTheirFullRange() {
        assertEquals(RelayControl.Ping(ULong.MAX_VALUE), RelayControl.decode("""{"type":"ping","nonce":18446744073709551615}"""))
        assertEquals("""{"type":"pong","nonce":18446744073709551615}""", RelayControl.Pong(ULong.MAX_VALUE).encodeText())
    }
    @Test fun anythingElseIsAProtocolViolation() {
        for (bad in listOf("""{"type":"teleport"}""", """{"type":"ping"}""", """{"type":"register","protocol":256,"slot":"s","ticket":"t"}""",
                """{"type":"ready","circuit":"c","lane":"l","generation":-1}""", """{"type":"error","code":"x","message":"m","retryable":"yes"}""", "nope"))
            assertIs<RelayException.ProtocolViolation>(assertFailsWith<RelayException> { RelayControl.decode(bad) }, bad)
    }
    @Test fun ticketsNeverPrint() {
        for (c in listOf(RelayControl.Register(5, "s", "secret-ticket"), RelayControl.Connect(5, "s", "secret-ticket", "l", 0u),
                RelayControl.Join(5, "s", "c", "l", 0u, "secret-ticket", RelayRole.CLIENT), RelayControl.Allocated("c", "l", 0u, "secret-ticket"),
                RelayControl.Incoming("c", "l", 0u, "secret-ticket")))
            assertFalse("secret-ticket" in c.toString(), c::class.simpleName)
    }
}
```

  `RelayTicketTest` ports `RelayTicketTests.swift`. A ticket here is `"v2." + claimsJson.toBase64Url() + ".c2ln"`.
  - `claimsParse`: claims `{"slot":"slot-a","permission":"register","role":"daemon","expires_at_unix":1090,"issued_at_unix":1000}` give `RelayTicketClaims("slot-a", "register", "daemon", 1090, 1000)`, and without `issued_at_unix` the last field is `null`.
  - `claimsNullForMalformed`: `""`, `"garbage"`, `"v2.only"`, `"v2..sig"`, `"v1.<valid>.sig"`, `"v2.<b64u(not json)>.sig"`, `"v2.<b64u({"slot":"s"})>.sig"` and `"v2.!!!.sig"` all give `claims == null`.
  - `ticketNeverPrints`: `toString()` contains neither the ticket nor its signature, but does contain `"1900000000"`.

  `RelayEndpointTest` ports `RelayEndpointTests.swift`:
  - `ws://relay.example.com`, `http://relay.example.com/v2/relay`, `relay+ws://relay.example.com`, `ws://10.0.0.5:8080`, `ws://192.168.1.2`, `ws://[2001:db8::1]/`, `ws://localhost.example.com` and `ws://127.0.0.1.example.com` → `InsecureTransport`, and `ws://relay.example.com` → `InsecureTransport("ws")`;
  - `ws://localhost:1/x`, `ws://LOCALHOST`, `http://127.0.0.1:9`, `relay+ws://127.9.8.7` and `ws://[::1]:8080/v1/relay` → scheme `ws`, and `ws://127.0.0.1:9` → path `/v1/relay`;
  - `wss://relay.example.com`, `https://relay.example.com` and `relay+wss://relay.example.com` → `wss`, and `https://relay.example.com/v2/relay` keeps path `/v2/relay`;
  - `circuit(URI("wss://r.example/v1/slots/abc"), "c/1 x")` → `wss://r.example/v1/circuits/c%2F1%20x`, while `circuit(URI("wss://r.example/v2/relay"), "c1")` → unchanged;
  - `requireHttps`: `http://api.example.test` → `InsecureTransport("http")`; `http://127.0.0.1:8080`, `http://localhost:8080` and `https://api.example.test` pass; `ftp://x.test` → `ProtocolViolation`;
  - `isLoopback`: `127.9.8.7`, `LOCALHOST`, `[::1]` → true; `127.0.0.1.example.com`, `127.0.0.256`, `10.0.0.5`, `null` → false.

- [ ] **Step 2: Run the tests.** Run `gw :link-core:test --tests 'com.shellx.link.core.Relay*'`. Expected: red, "Unresolved reference: RelayControl".
- [ ] **Step 3: Implement.** Decode with `Json.parseToJsonElement` and the strict readers, and encode with `buildJsonObject` (uint64 values as `JsonUnquotedLiteral`).
  - **Claims:** split on `.`; require exactly 3 parts, `parts[0] == "v2"` and a non-empty `parts[1]`. Decode `parts[1]` with `java.util.Base64.getUrlDecoder()` (padding optional), then read `slot`, `permission` and `role` as strings, `expires_at_unix` as a long and optional `issued_at_unix`. Any failure → `null`.
  - **`control()`:** build the result as `URI("$scheme://${url.rawAuthority}$path")`.
- [ ] **Step 4: Run the tests again.** Run `gw :link-core:test`. Expected: PASS.
- [ ] **Step 5: Commit.**

```bash
git add shellx-link/kotlin/link-core/src
git commit -m "feat(shellx-link): Kotlin relay control messages, tickets and URL policy"
```

---

### Task 6: Relay sockets, circuits and the client connector

**Files:**
- Create: `core/RelaySocket.kt`, `core/RelayCircuit.kt`, `core/RelayClientConnector.kt`, `core/InMemoryCircuit.kt`
- Test: `core-test/ScriptedRelaySockets.kt`, `core-test/RelayClientConnectorTest.kt`, `core-test/WebSocketRelayCircuitTest.kt`, `core-test/InMemoryCircuitTest.kt`

Reference: `shellx-link/Sources/ShellXLinkRelay/RelayCircuit.swift`, `RelayClientConnector.swift`, `Sources/ShellXLinkSession/Testing/InMemoryCircuit.swift`, `Tests/ShellXLinkSessionTests/InMemoryCircuitTests.swift`.

**Interfaces:**
- Consumes: `RelayControl`, `RelayEndpoint`, `RelayLane`, `RelayProtocol`, `RelayTicket`, `RelayException` (Task 5).
- Produces:

```kotlin
sealed interface RelaySocketMessage {
    data class Text(val text: String) : RelaySocketMessage
    class Binary(val bytes: ByteArray) : RelaySocketMessage
}
/** One WebSocket to the relay. Cancelling a pending receive() closes the socket. */
interface RelaySocket {
    suspend fun sendText(text: String)          // RelayException.Closed when closed
    suspend fun sendBinary(bytes: ByteArray)    // RelayException.Closed when closed
    suspend fun receive(): RelaySocketMessage   // Closed after a close; the transport's IOException after a failure
    fun close()                                 // idempotent
}
fun interface RelaySocketFactory { fun open(url: URI, bearer: String?): RelaySocket }

/** An ordered binary pipe: one send arrives as one receive. Receive from one coroutine at a time. */
interface RelayCircuit {
    suspend fun send(data: ByteArray)           // RelayException.Closed once ended
    suspend fun receive(): ByteArray            // RelayException.Closed once ended; cancelling a pending receive closes the circuit
    fun close()                                 // ends it for both sides; idempotent
}
internal class WebSocketRelayCircuit(socket: RelaySocket) : RelayCircuit
object RelayCircuitJoin {
    suspend fun join(sockets: RelaySocketFactory, endpoint: URI, slot: String, role: RelayRole, circuit: String,
                     lane: String, generation: ULong, ticket: String,
                     controlTimeout: Duration = RelayProtocol.CONTROL_TIMEOUT): RelayCircuit
}
object RelayClientConnector {
    val DEFAULT_SLOT_OFFLINE_RETRIES: List<Duration> = listOf(500.milliseconds, 1.seconds, 2.seconds)
    suspend fun connect(relayUrl: URI, slot: String, ticket: RelayTicket, sockets: RelaySocketFactory,
                        slotOfflineRetries: List<Duration> = DEFAULT_SLOT_OFFLINE_RETRIES,
                        controlTimeout: Duration = RelayProtocol.CONTROL_TIMEOUT): RelayCircuit
}
fun inMemoryCircuitPair(): Pair<RelayCircuit, RelayCircuit>
```

  **`WebSocketRelayCircuit`:**
  - `send` → `sendBinary`; any non-cancellation failure → `Closed`.
  - `receive` loops:
    - `Binary` → returned.
    - `Text` → `RelayControl.decode`:
      - `Ping(n)` → `sendText(Pong(n).encodeText())`, then go on;
      - `Pong` → go on;
      - `Error` → `close()`, then `Closed` when `code == "peer-disconnected"`, otherwise `Server(code, retryable)`;
      - any other type, or a decode failure → `close()` and `ProtocolViolation("relay sent unexpected circuit control")`.
    - A socket `IOException` or `Closed` → `Closed`.

  **`RelayCircuitJoin.join`:**
  1. `socket = sockets.open(RelayEndpoint.circuit(endpoint, circuit), bearer = ticket)`.
  2. `sendText(Join(VERSION, slot, circuit, lane, generation, ticket, role))`.
  3. Within `controlTimeout`, read control messages:
     - `Ready` with the same circuit, lane and generation → done;
     - `Error` → `Server`;
     - `Ping` → `Pong`;
     - anything else → ignored;
     - `Binary` → `ProtocolViolation("relay sent binary data before the circuit was ready")`.
  4. Timeout → `TimedOut`. On any failure, close the socket and rethrow.
  5. Return `WebSocketRelayCircuit(socket)`.

  **`connect`:**
  1. `endpoint = RelayEndpoint.control(relayUrl)`, `lane = RelayLane.random()`, `generation = 0u`.
  2. Open the control socket with `bearer = ticket.ticket` and send `Connect(VERSION, slot, ticket.ticket, lane, 0u)`.
  3. Within `controlTimeout`, wait for `Allocated` with the same lane and generation 0. `Error` → `Server`, `Ping` → `Pong`, anything else is ignored, and `Binary` → `ProtocolViolation`.
  4. Always close the control socket. Then `join(role = CLIENT, ticket = allocated.joinTicket)`.
  5. On `Server("slot-offline", true)`, wait the next delay in `slotOfflineRetries` and retry with the same ticket. Rethrow when the delays are used up.
  6. An `IOException` from a socket passes through unchanged.

  **`inMemoryCircuitPair`** keeps the Swift rules:
  - frames arrive in order;
  - `close()` on either end ends both: pending and later `receive()` and `send()` throw `Closed`;
  - frames the peer sent before it closed are still delivered first;
  - the closing end drops its own unread frames;
  - cancelling a pending `receive()` closes the circuit.

- [ ] **Step 1: Write the test double and the failing tests.** `ScriptedRelaySockets` is a test double that implements `RelaySocketFactory`:
  - it records every `open(url, bearer)` as an `Opened(url, bearer, sent: MutableList<String>, closed: Boolean)`;
  - each opened socket asks `respond(index, sentControl): List<RelaySocketMessage>` for its replies;
  - `push(index, message)` injects a frame;
  - `receive()` follows the cancel-closes rule.

```kotlin
class RelayClientConnectorTest {
    // connectAllocatesThenJoins: control socket answers Ping(9) then Allocated("c-1", <lane>, 0u, "jt-1"); circuit socket answers Ready("c-1", <lane>, 0u).
    //   opened[0]: url wss://relay.example.test/v2/relay, bearer = ticket, closed = true
    //   opened[1]: url wss://relay.example.test/v2/relay, bearer "jt-1"
    //   Connect sent: protocol 5, slot "slot-1", ticket, generation 0u, lane matches [A-Za-z0-9_-]{32}
    //   Pong(9) sent before the join
    //   Join sent: protocol 5, slot "slot-1", circuit "c-1", same lane, generation 0u, ticket "jt-1", role CLIENT
    //   circuit.send([1]) reaches opened[1] as Binary; push(1, Binary([2])) → circuit.receive() == [2]
    // allocationForAnotherLaneIsIgnored: Allocated with lane "x" first, then the right one → connects
    // slotOfflineIsRetriedWithTheSameTicket: Error("slot-offline", "", true) twice, then allocated
    //   retries [10.milliseconds, 10.milliseconds] → connects; 3 control sockets, all with the same bearer
    // slotOfflineAfterTheRetriesIsReported: slotOfflineRetries = emptyList() → Server("slot-offline", true)
    // joinErrorIsReportedAndTheSocketClosed: Join answered Error("invalid-ticket", "", false)
    //   → Server("invalid-ticket", false); opened[1].closed
    // silenceTimesOut: controlTimeout = 100.milliseconds, no answer → RelayException.TimedOut; opened[0].closed
    // binaryBeforeAllocationIsAViolation → ProtocolViolation
}
class WebSocketRelayCircuitTest {
    // relayPingIsAnsweredAndNotDelivered: push Text(ping 4), Binary([7]) → receive() == [7]; Pong(4) was sent
    // peerDisconnectedIsAPlainClose: Text(error "peer-disconnected") → Closed; socket closed
    // otherRelayErrorIsServer: Text(error "capacity", retryable true) → Server("capacity", true)
    // unexpectedControlIsAViolation: Text(registered) → ProtocolViolation; socket closed
    // socketFailuresBecomeClosed: receive throws IOException → Closed; sendBinary throws → Closed
}
class InMemoryCircuitTest {   // ports InMemoryCircuitTests.swift
    // framesArriveInOrder: a sends [1], [2], [3] → b receives them in that order
    // closeEndsPendingReceiveOnBothEnds: pending receives on a and b; a.close() → both throw Closed
    // sendAfterCloseThrows: b.close(); a.send([1]) and b.send([1]) → Closed
    // framesSentBeforePeerClosedStillArrive: a sends [1], [2] then a.close() → b receives [1], [2], then Closed
    // cancellingAPendingReceiveClosesTheCircuit: cancel a job blocked in a.receive() → b.receive() throws Closed
}
```

  Write each comment as a `@Test` with those exact values, wrapped in `runBlocking` and `within`.

- [ ] **Step 2: Run the tests.** Run `gw :link-core:test --tests 'com.shellx.link.core.*Circuit*' --tests 'com.shellx.link.core.RelayClientConnectorTest'`. Expected: red, "Unresolved reference: RelayClientConnector".
- [ ] **Step 3: Implement the four files.** Follow the rules above. Timeouts use `withTimeoutOrNull`, never `withTimeout`. In-memory circuit: two `Channel<ByteArray>(UNLIMITED)`, plus a shared closed flag checked before each send and each receive.
- [ ] **Step 4: Run the tests again.** Run `gw :link-core:test`. Expected: PASS.
- [ ] **Step 5: Commit.**

```bash
git add shellx-link/kotlin/link-core/src
git commit -m "feat(shellx-link): Kotlin relay sockets, circuits and client connector"
```

---

### Task 7: Secure channel (Noise over a circuit)

**Files:**
- Create: `core/SecureChannel.kt`
- Test: `core-test/SecureChannelTest.kt`

Reference: `shellx-link/Sources/ShellXLinkSession/SecureChannel.swift`; the handshake tests in `Tests/ShellXLinkSessionTests/LinkSessionTests.swift`.

**Interfaces:**
- Consumes: `NoiseHandshake`, `NoiseTransport`, `NoiseException` (Task 3); `LinkCodec` (Task 2); `RelayCircuit`, `inMemoryCircuitPair` (Task 6).
- Produces:

```kotlin
class SecureChannel private constructor(/* circuit, transport, peerKey */) {
    val peerKey: ByteArray                              // authenticated by the completed handshake
    suspend fun send(message: LinkMessage)              // LinkCodecException: nothing sent, channel usable
    internal suspend fun sendFrame(frame: ByteArray)    // tests send frames LinkCodec cannot produce
    suspend fun receive(): LinkMessage                  // LinkCodecException: frame dropped, channel usable;
                                                        // DecryptFailed: circuit closed; relay errors pass through
    fun close()
    companion object {
        /** XX with empty payloads (PROTOCOL.md §2). The client is the initiator. */
        suspend fun open(circuit: RelayCircuit, role: NoiseRole, key: NoiseStaticKey,
                         trusts: (ByteArray) -> Boolean): SecureChannel
    }
}
```

  **`open`:** build `NoiseHandshake(role, key)` with its default `trusts = { true }`.
  - **Initiator:** send message 1 (empty); receive and read message 2; require an empty payload, else `NonEmptyHandshakePayload`; require `trusts(remoteStatic)`, else `UntrustedPeer`, and this check happens before message 3 is sent; then send message 3 (empty).
  - **Responder:** read message 1 (it must be empty); send message 2; read message 3 (it must be empty); then require `trusts`.
  - On any failure, including cancellation, close the circuit and rethrow. Finish with `split()`.

  **`send`:** take a fair `Mutex`, then do both steps inside one `withContext(NonCancellable)` block: encrypt, and hand the ciphertext to `circuit.send`. A cancellation can then only land before the lock (nothing spent) or after the send, never between them, so a frame whose nonce was spent is always sent and a cancelled caller can never desync the cipher.

- [ ] **Step 1: Write the failing tests.**
  - `handshakeCarriesMessagesBothWays`: over `inMemoryCircuitPair()`, the responder in `async`; then `peerKey`s are each other's public keys, and a `Hello` goes out while a `Welcome(1, "h", "m", listOf("attachments"))` comes back, both equal.
  - `initiatorRejectsAWrongHostKeyBeforeMessage3`: a raw responder `NoiseHandshake` with an impostor key answers message 1. `open(trusts = { it.contentEquals(expected.publicKey) })` throws `NoiseException.UntrustedPeer`. The responder's next `receive()` then throws `RelayException.Closed`: message 3 was never sent.
  - `nonEmptyHandshakePayloadAborts`: a raw initiator writes message 1 with payload `"hi"`. The responder `open` throws `NonEmptyHandshakePayload`, and the raw side's `receive()` throws `Closed`.
  - `undecodableFrameKeepsTheChannel`: `sendFrame("""{"v":1,"t":"ping"}""")` makes the receiver throw `BadJson(null)`. The next `send(Ping(7u))` arrives as `Ping(7u)`.
  - `tamperedFrameClosesTheCircuit`: a wrapping circuit flips one bit of the first transport frame. `receive()` throws `DecryptFailed`, and the sender's next `send` throws `Closed`.
  - `concurrentSendsAllDecrypt`: 200 parallel `send(Ping(i.toULong()))` from `Dispatchers.Default`; the receiver gets 200 messages, without error, whose nonces are exactly `0..199`.

- [ ] **Step 2: Run the tests.** Run `gw :link-core:test --tests 'com.shellx.link.core.SecureChannelTest'`. Expected: red, "Unresolved reference: SecureChannel".
- [ ] **Step 3: Implement.** Use `kotlinx.coroutines.sync.Mutex` and `withContext(NonCancellable)` as described.
- [ ] **Step 4: Run the tests again.** Run `gw :link-core:test`. Expected: PASS.
- [ ] **Step 5: Commit.**

```bash
git add shellx-link/kotlin/link-core/src
git commit -m "feat(shellx-link): Kotlin secure channel over a relay circuit"
```

---

### Task 8: LinkSession and LinkClient: hello, calls, pushes, liveness

**Files:**
- Create: `core/LinkSession.kt`, `core/Liveness.kt`, `core/LinkClient.kt`
- Test: `core-test/TestHosts.kt`, `core-test/LinkClientTest.kt`, `core-test/LinkClientCallsTest.kt`

Reference: `shellx-link/Sources/ShellXLinkSession/LinkClient.swift`, `Liveness.swift`; the client tests in `Tests/ShellXLinkSessionTests/LinkSessionTests.swift`.

**Interfaces:**
- Consumes: `SecureChannel` (Task 7), `RelayCircuit` (Task 6), `LinkMessage` (Task 2).
- Produces (3C consumes these; contracts "Contract additions"):

```kotlin
data class LinkTimings(val pingInterval: Duration, val idleTimeout: Duration, val requestTimeout: Duration = 10.seconds) {
    companion object { val STANDARD = LinkTimings(pingInterval = 20.seconds, idleTimeout = 45.seconds) }
}
object LinkLog {
    /** Gets event names and protocol error codes only, never content, names, ids, keys, tickets or tokens. */
    @Volatile var sink: (String) -> Unit = {}
}
data class PendingSnapshot(val revision: Long, val pending: List<PendingItem>)
data class PendingChange(val revision: Long, val added: List<PendingItem>, val resolved: List<String>)
data class SessionList(val revision: Long, val sessions: List<AgentSession>)
data class SessionChange(val revision: Long, val upserted: List<AgentSession>, val removed: List<String>)
data class WorkspaceList(val revision: Long, val workspaces: List<LinkWorkspace>)
data class WorkspaceChange(val revision: Long, val upserted: List<LinkWorkspace>, val removed: List<String>)
data class ChatHistoryPage(val entries: List<ChatEntry>, val hasMore: Boolean)
data class WorkspaceCreated(val outcome: WorkspaceControlOutcome, val workspaceId: String?)
sealed interface ChatPush {
    val sessionId: String
    val entries: List<ChatEntry>                                        // empty for Reset
    data class Upsert(override val sessionId: String, override val entries: List<ChatEntry>) : ChatPush
    data class Reset(override val sessionId: String) : ChatPush
}
sealed class LinkClientException(message: String) : Exception(message) {
    data class ProtocolMismatch(val detail: String) : LinkClientException("protocol_mismatch")
    data class Rejected(val code: String, val detail: String) : LinkClientException("rejected")
    class SessionClosed : LinkClientException("session_closed")
    class TimedOut : LinkClientException("timed_out")
    data class Remote(val code: String, val detail: String) : LinkClientException("remote")
    class UnexpectedAnswer : LinkClientException("unexpected_answer")
}
/** One established Link session with one host (PROTOCOL.md §7). 3C fakes it for tests and the demo. */
interface LinkSession {
    val hostFeatures: Set<String>                                       // welcome.features; unknown strings kept
    /** Each push in arrival order. Single consumer. Completes normally when the session ends. */
    val changes: Flow<PendingChange>
    val sessionChanges: Flow<SessionChange>
    val workspaceChanges: Flow<WorkspaceChange>
    val chatEntries: Flow<ChatPush>
    suspend fun snapshot(): PendingSnapshot
    suspend fun reply(requestId: String, decision: LinkDecision): ReplyOutcome
    suspend fun sessions(): SessionList
    suspend fun chatHistory(sessionId: String, beforeSeq: Long?, limit: Int): ChatHistoryPage
    suspend fun chatSend(sessionId: String, text: String, attachments: List<String> = emptyList()): ChatSendOutcome
    suspend fun chatInterrupt(sessionId: String, hard: Boolean): ChatInterruptOutcome
    suspend fun workspaces(): WorkspaceList
    suspend fun createWorkspace(): WorkspaceCreated
    suspend fun renameWorkspace(workspaceId: String, title: String): WorkspaceControlOutcome
    suspend fun closeWorkspace(workspaceId: String): WorkspaceControlOutcome
    suspend fun closeAgent(sessionId: String): WorkspaceControlOutcome
    suspend fun closeTerminal(workspaceId: String, terminalId: String): WorkspaceControlOutcome
    /** Ends the session: pending calls throw SessionClosed, every Flow completes, the circuit closes. Idempotent. */
    fun close()
}
class LinkClient private constructor(/* … */) : LinkSession {
    companion object {
        /** Handshake trusting only [hostKey], then hello/welcome. */
        suspend fun connect(circuit: RelayCircuit, key: NoiseStaticKey, hostKey: ByteArray, clientVersion: String,
                            deviceName: String, timings: LinkTimings = LinkTimings.STANDARD): LinkClient
    }
    /** Sends make(callId) and returns the one answer that carries callId. */
    internal suspend fun call(make: (callId: String) -> LinkMessage): LinkMessage
}
```

  **Errors of every call:**
  - `Remote(code, detail)` when the host answered with an `error` that carries this `call_id` (`unsupported`, `too_large`, `bad_request`, `not_found`);
  - `TimedOut` after `requestTimeout`; the session stays usable and a late answer is dropped;
  - `SessionClosed`, or the session's end error, when the session ends first;
  - `UnexpectedAnswer` when the answer has another type;
  - a `LinkCodecException` when the request cannot be encoded (nothing is sent).

  A call made after the session ended throws the end error at once. Nothing closes a client that is dropped: callers must `close()` it.

  **`connect`:**
  1. Wrap the circuit in an internal `WatchedCircuit`. It records `System.nanoTime()` at creation and after every received frame. Its watchdog wakes every `idleTimeout / 5` and closes the inner circuit once `idleTimeout` has passed with nothing received (`LinkLog`: `"closing a silent session"`). The watchdog runs from before the handshake.
  2. `SecureChannel.open(watched, INITIATOR, key) { it.contentEquals(hostKey) }`.
  3. Send `Hello(clientVersion, deviceName)`.
  4. Read until `Welcome`:
     - `WrongVersion` → `ProtocolMismatch("the host sent another protocol version")`;
     - any other `LinkCodecException` → skip;
     - `Welcome` with `protocolVersion != 1` → `ProtocolMismatch("the host speaks protocol <n>")`;
     - `Error("protocol_mismatch", m)` → `ProtocolMismatch(m)`;
     - any other `Error(c, m)` → `Rejected(c, m)`;
     - anything else → ignored.
  5. Start the reader and the pinger in the client's own `CoroutineScope(SupervisorJob() + Dispatchers.Default)`.

  On any failure, cancel that scope, close the circuit and rethrow.

  **The pinger** starts from a random `ULong` and sends `Ping(++nonce)` (wrapping) every `pingInterval`. It stops at the first send failure.

  **Reader dispatch**, one frame at a time:

  | Received | Action |
  | --- | --- |
  | any `LinkMessage.Answer` | remove the waiter for its `callId` and complete it; no waiter → drop |
  | `Changed` / `SessionsChanged` / `WorkspacesChanged` | send `PendingChange` / `SessionChange` / `WorkspaceChange` to its `Channel(UNLIMITED)` |
  | `ChatEntries` / `ChatReset` | send `ChatPush.Upsert` / `ChatPush.Reset` to the chat channel |
  | `Ping(n)` | `send(Pong(n))`, ignoring a send failure |
  | `Error("protocol_mismatch", m, _)` | `end(ProtocolMismatch(m))` |
  | `Error(c, m, id)` with a waiter for `id` | fail that waiter with `Remote(c, m)` |
  | other `Error` | `LinkLog` `"host reported error <code>"` |
  | anything else (`Pong`, `Unknown`, `Hello`, `Welcome`, client-only types) | ignore |
  | `LinkCodecException.WrongVersion` | `end(ProtocolMismatch("the host sent another protocol version"))` |
  | any other `LinkCodecException` | `LinkLog` `"client dropped an undecodable frame"`, continue |
  | any other failure | `end(SessionClosed())` |

  **`call`:**
  1. Under a non-suspending `synchronized` section: check the end error, take `callId = "c<n>"` (n = 1, 2, …), and register a `CompletableDeferred`.
  2. `channel.send(make(callId))`. A non-codec failure → `SessionClosed`.
  3. `withTimeoutOrNull(requestTimeout) { deferred.await() } ?: throw TimedOut()`.
  4. In `finally`, remove the waiter.

  Complete deferreds outside the lock.

  **`end(error)`** runs once:
  1. Record the error.
  2. Fail every waiter with it.
  3. Close the four channels (the Flows are `receiveAsFlow()` over them).
  4. Cancel the pinger and the watchdog, close the channel, and cancel the scope last.

- [ ] **Step 1: Write the host helper.**

```kotlin
// core-test/TestHosts.kt
class HostRig(val features: List<String> = emptyList(), val timings: LinkTimings = LinkTimings.STANDARD) {
    val hostKey = NoiseStaticKey.generate(); val clientKey = NoiseStaticKey.generate()
    private val ends = inMemoryCircuitPair(); val clientEnd = ends.first; val hostEnd = ends.second
    /** Responder handshake only, trusting anyone: for tests that script what comes before Welcome. */
    suspend fun handshake(): SecureChannel
    /** handshake(), then reads Hello and answers Welcome(1, "test-host", "Test Mac", features). */
    suspend fun host(): Pair<SecureChannel, LinkMessage.Hello>
    suspend fun client(): LinkClient = LinkClient.connect(clientEnd, clientKey, hostKey.publicKey, "test-client", "Test Phone", timings)
}
// A test runs `val host = async { rig.host() }; val client = rig.client(); val (ch, hello) = host.await()`,
// then scripts `ch` inline: `val call = async { client.snapshot() }; val get = ch.receive() as LinkMessage.SnapshotGet; ch.send(...)`.
```

- [ ] **Step 2: Write the failing tests** in `LinkClientTest`. The value after → is the assertion; `RF` marks a Review Focus test.
  - `helloCarriesVersionAndNameAndFeaturesAreKept`: `hello == Hello("test-client", "Test Phone")`; `features = ["attachments", "teleport"]` gives `hostFeatures == setOf("attachments", "teleport")`.
  - `welcomeErrorsFailTheConnect` (host side via `rig.handshake()`, then reads `Hello` itself):
    - host answers `Error("protocol_mismatch", "update the app")` → `ProtocolMismatch("update the app")`;
    - `Error("bad_request", "nope")` → `Rejected("bad_request", "nope")`;
    - `Welcome(2, …)` → `ProtocolMismatch("the host speaks protocol 2")`;
    - after each, the host's `receive()` throws `Closed`.
  - `wrongHostKeyFailsBeforeMessage3`: a raw impostor responder → connect throws `NoiseException.UntrustedPeer`, and the impostor's next `hostEnd.receive()` throws `Closed`.
  - `framesBeforeWelcomeAreIgnored`: via `rig.handshake()`, after reading `Hello` and before `Welcome` the host sends `sendFrame("""{"v":1,"t":"agent.changed","revision":1}""")` and `Changed(1, [], [])` → connect succeeds.
  - `callIdsAreUniqueAndAnswersMatch`: two `reply("r1", …)` calls → two distinct call ids of 1–64 bytes, each answered with its own id → `[DELIVERED, DELIVERED]`.
  - `lateAnswerOfATimedOutCallIsDropped`: `requestTimeout = 300.milliseconds`; the host holds call 1's id, waits for call 2, then answers call 1 `DELIVERED` and call 2 `ALREADY_HANDLED` → the first call throws `TimedOut` and the retry returns `ALREADY_HANDLED`.
  - `remoteErrorFailsOnlyThatCall`: `Error("bad_request", "nope", replyId)` → `Remote("bad_request", "nope")`; the next `snapshot()` answered `Snapshot(id, 3, [])` → revision 3.
  - `answerOfAnotherTypeIsUnexpectedAnswer`: `SnapshotGet` answered with `ChatSendResult(id, SUBMITTED)` → `UnexpectedAnswer`.
  - `clientOnlyFramesNeverAnswerACall`: the host sends `AttachBegin`, `AttachChunk` and `AttachEnd` with the pending id, then `AttachReady(id, "a1")` → `call { AttachBegin(it, FILE, "x", 1) }` returns `AttachReady(id, "a1")`.
  - `pushesReachTheirFlowsInOrder`:
    - host sends `Changed(1, [item], [])`, `SessionsChanged(1, [s], [])`, `WorkspacesChanged(1, [w], [])`, `ChatEntries("s-1", [e])`, `ChatReset("s-1")`, `Changed(2, [], ["r1"])`;
    - `changes.take(2).toList()` revisions `[1, 2]`;
    - `chatEntries.take(2).toList() == [Upsert("s-1", [e]), Reset("s-1")]`;
    - the session and workspace changes equal what was sent.
  - `undecodableFrameIsDroppedAndTheNextArrives`: `sendFrame("""{"v":1,"t":"agent.changed","revision":1}""")` then `Changed(2, …)` → `changes.first().revision == 2`.
  - `protocolMismatchEndsTheSession`: with a pending `snapshot()`, `Error("protocol_mismatch", "update")` → the call throws `ProtocolMismatch("update")`, `changes.toList()` completes, and a new call throws `ProtocolMismatch`. Same with `sendFrame("""{"v":2,"t":"ping","nonce":1}""")` → `ProtocolMismatch("the host sent another protocol version")`.
  - `hostPingWithAnyUint64NonceIsEchoed` (RF 4): `Ping(ULong.MAX_VALUE)` → host receives `Pong(ULong.MAX_VALUE)`; `Ping(9_223_372_036_854_775_808u)` → `Pong` of the same value.
  - `clientPingsEveryIntervalWithConsecutiveNonces`: `pingInterval = 50.milliseconds` → within 1 s the host receives ≥ 3 `Ping`s, each nonce the previous `+ 1u` (wrapping).
  - `closeFailsPendingCallsAndCompletesEveryFlow`: with a pending `snapshot()`, `close()` → the call throws `SessionClosed`; all four Flows `toList()` complete; `snapshot()` throws `SessionClosed`; the host's `receive()` throws `Closed`.
  - `cancelledCallerLeavesTheSessionUsable` (RF 1): `val job = launch { client.snapshot() }`; the host receives the `SnapshotGet`; `job.cancelAndJoin()`; the host answers the cancelled id, then the next `snapshot()` is answered → revision 5; the late answer is dropped.
  - `cancellingManyCallersNeverBreaksTheCipherStream` (RF 1):
    - 100 `launch(Dispatchers.Default) { client.reply("r$i", Permission(ONCE)) }`, and every odd job is cancelled at once;
    - the host decrypts every frame it receives (no `DecryptFailed`) and answers each `Reply`;
    - then `snapshot()` still works and the host saw no decrypt error.
  - `silentHostIsClosedByTheWatchdog` (RF 2): timings `50ms / 300ms / 5s`; the host finishes `Welcome` and then reads nothing and sends nothing → a pending `snapshot()` throws `SessionClosed` after ≥ 250 ms and < 3 s, and `changes.toList()`, `sessionChanges.toList()`, `workspaceChanges.toList()` and `chatEntries.toList()` all complete.

  In `LinkClientCallsTest`, write `everyCallSendsItsRequestAndUnpacksItsAnswer`. The host records each request and answers it by type:

  | Request | Answer |
  | --- | --- |
  | `SnapshotGet` | `Snapshot(id, 7, [item])` |
  | `Reply` | `ReplyResult(id, requestId, DELIVERED)` |
  | `SessionsGet` | `Sessions(id, 4, [s])` |
  | `ChatHistoryGet` | `ChatHistory(id, sid, [e], true)` |
  | `ChatSend` | `ChatSendResult(id, SUBMITTED)` |
  | `ChatInterrupt` | `ChatInterruptResult(id, SENT)` |
  | `WorkspacesGet` | `Workspaces(id, 6, [w])` |
  | `WorkspaceCreate` | `WorkspaceCreateResult(id, OK, "ws-3")` |
  | `WorkspaceRename` | `WorkspaceRenameResult(id, OK)` |
  | `WorkspaceClose` | `WorkspaceCloseResult(id, REFUSED)` |
  | `AgentClose` | `AgentCloseResult(id, NOT_FOUND)` |
  | `TerminalClose` | `TerminalCloseResult(id, OK)` |

  The test checks every return value:

```kotlin
assertEquals(PendingSnapshot(7, listOf(item)), client.snapshot())
assertEquals(ReplyOutcome.DELIVERED, client.reply("req-1", LinkDecision.Question(listOf("Postgres"))))
assertEquals(SessionList(4, listOf(s)), client.sessions())
assertEquals(ChatHistoryPage(listOf(e), true), client.chatHistory("s-1", 40, 20))
assertEquals(ChatSendOutcome.SUBMITTED, client.chatSend("s-1", "fix", listOf("a1")))
assertEquals(ChatInterruptOutcome.SENT, client.chatInterrupt("s-1", hard = true))
assertEquals(WorkspaceList(6, listOf(w)), client.workspaces())
assertEquals(WorkspaceCreated(WorkspaceControlOutcome.OK, "ws-3"), client.createWorkspace())
assertEquals(WorkspaceControlOutcome.OK, client.renameWorkspace("ws-2", "Docs — v2"))
assertEquals(WorkspaceControlOutcome.REFUSED, client.closeWorkspace("ws-2"))
assertEquals(WorkspaceControlOutcome.NOT_FOUND, client.closeAgent("sess-1"))
assertEquals(WorkspaceControlOutcome.OK, client.closeTerminal("ws-1", "t-1"))
// and the recorded requests carry the arguments, call ids aside:
//   ChatHistoryGet("s-1", 40, 20), ChatSend("s-1", "fix", ["a1"]), ChatInterrupt("s-1", true),
//   WorkspaceRename("ws-2", "Docs — v2"), TerminalClose("ws-1", "t-1"), Reply("req-1", Question(["Postgres"]))
```

- [ ] **Step 3: Run the tests.** Run `gw :link-core:test --tests 'com.shellx.link.core.LinkClient*'`. Expected: red, "Unresolved reference: LinkClient".
- [ ] **Step 4: Implement `LinkSession.kt`, `Liveness.kt` and `LinkClient.kt`.** Use the tables above. `WatchedCircuit` and the pinger are `internal` in `Liveness.kt`, with `LinkTimings` and `LinkLog`.
- [ ] **Step 5: Run the tests again.** Run `gw :link-core:test`. Expected: PASS. Run it twice more to catch flakiness; all three runs must pass.
- [ ] **Step 6: Commit.**

```bash
git add shellx-link/kotlin/link-core/src
git commit -m "feat(shellx-link): Kotlin LinkClient session with calls, pushes and liveness"
```

---

### Task 9: Attachment uploads

**Files:**
- Modify: `core/LinkSession.kt` (add the two methods and `ChatAttachment`, `MessageUploadException`), `core/LinkClient.kt`
- Test: `core-test/FakeAttachHost.kt`, `core-test/LinkClientAttachmentTest.kt`

Reference: `LinkClient.swift` (`uploadAttachment`, `upload`, `chatSend(uploading:)`, the upload turn), PROTOCOL.md §5 "Attachments", and the client tests in `Tests/ShellXLinkSessionTests/AttachmentSessionTests.swift`.

**Interfaces:**
- Consumes: `LinkClient.call`, `sha256` and the `ShellXLink` constants.
- Produces, added to `LinkSession` and implemented by `LinkClient`:

```kotlin
data class ChatAttachment(val kind: AttachmentKind, val name: String, val data: ByteArray)   // ByteArray rule; toString without bytes
class MessageUploadException(override val cause: Exception) : Exception("message_upload", cause)   // never wraps CancellationException
interface LinkSession {
    // … Task 8 members …
    /** attach.begin, chunks of ≤ 45 000 bytes each after the previous result, attach.end with SHA-256; returns the host's id.
     *  progress(bytesSentSoFar) after each chunk result. Call only when hostFeatures contains ATTACHMENTS_FEATURE. */
    suspend fun uploadAttachment(kind: AttachmentKind, name: String, data: ByteArray, progress: (Int) -> Unit = {}): String
    /** Uploads [uploading] in order, then chat.send with their ids: one message, holding the upload turn from the first
     *  attach.begin until the chat.send is answered. An upload failure → MessageUploadException(cause): nothing was typed. */
    suspend fun chatSend(sessionId: String, text: String, uploading: List<ChatAttachment>, progress: (Int) -> Unit = {}): ChatSendOutcome
}
```

  **The upload turn:** one fair `kotlinx.coroutines.sync.Mutex` per client.
  - `uploadAttachment` locks it for its whole upload.
  - The message form of `chatSend` locks it from before its first `attach.begin` until its `chat.send` is answered or fails.
  - Inside the lock, check the end error first. For a message, the end error is wrapped in `MessageUploadException`.
  - Cancellation while waiting for, or holding, the turn propagates as `CancellationException` and releases the turn.

  **One upload's checks:**
  - the answer to `attach.begin` must be `AttachReady`;
  - each chunk answer must be `AttachChunkResult` with the same id and `received == offset + chunk size`;
  - the end answer must be `AttachEndResult` with the same id;
  - anything else → `UnexpectedAnswer`.

  **Limits:** there are no client-side size or count checks. The host refuses with `too_large` or `bad_request`, as in Swift. 3C validates 5 × 10 MiB before calling.

- [ ] **Step 1: Write the fake host and the failing tests.** `FakeAttachHost(channel, stallSecondChunkOfFirstUpload = false, answerChatSend = true)` runs on a `HostRig` with `features = ["attachments"]` and keeps the host rules of PROTOCOL.md §5:
  - **`attach.begin`:** kind `image`/`file` and size `1..10_485_760` → `AttachReady(id, "U<n>")`, where n counts accepted begins. A larger size → `Error("too_large")`; a smaller size or another kind → `Error("bad_request")`.
  - **`attach.chunk`:** `offset == received` and data of 1–45 000 bytes within the size → `AttachChunkResult`; otherwise `bad_request`.
  - **`attach.end`:** all bytes received and the digest matches → `AttachEndResult`; otherwise `bad_request`.
  - **`chat.send` with ids:** all ids finished → it records `Sent(text, names, bytes)` and answers `SUBMITTED`; otherwise `bad_request`.
  - It records `events` in order (`"begin:U1"`, `"chunk:U1:0"`, `"end:U1"`, `"send:<text>"`).
  - With `stallSecondChunkOfFirstUpload`, it never answers chunk 2 of `U1`. With `answerChatSend = false`, it never answers `chat.send`.

```kotlin
class LinkClientAttachmentTest {
    // uploadSendsChunksInOrderWithTheDigest: 100 000 bytes (i % 251) → "U1"; chunks at offsets 0, 45 000, 90 000 of sizes
    //   45 000, 45 000, 10 000; the end digest is sha256(data); progress == [45_000, 90_000, 100_000]
    // uploadsRunOneAtATime: start upload A; once events has "begin:U1", start B → events has every U1 entry before "begin:U2";
    //   ids == ["U1", "U2"]
    // cancelledUploadReleasesTheTurn: stall; A shows progress [45_000]; start B; after 200 ms events has no "begin:U2";
    //   A.cancelAndJoin() (A ends with CancellationException); B returns "U2"
    // cancelledWaiterLeavesTheQueue: stall; A running, B and C waiting; cancel B; cancel A → C returns "U2"; events has no
    //   begin for B
    // failedUploadReleasesTheTurn: size 10_485_761 → Remote("too_large"); the next upload of 2 bytes → "U2", and
    //   chatSend("s1", "", listOf("U2")) → SUBMITTED
    // messageHoldsTheTurnUntilItsSendIsAnswered: answerChatSend = false; the message's "send:look" shows up; an upload
    //   started after it shows no begin within 200 ms; cancel the message → the upload returns "U2"
    // messageReportsProgressAndStopsAtARefusedUpload: [big 100 000, small.jpg 3 bytes] → SUBMITTED;
    //   progress == [45_000, 90_000, 100_000, 100_003]; sent names ["big", "small.jpg"];
    //   [fine 1 byte, empty 0 bytes] → MessageUploadException whose cause is Remote("bad_request"); still one Sent
    // twoMessagesOfFiveAttachmentsBothArriveWhole: two concurrent messages "one" and "two", 5 × 50 000 bytes each →
    //   both SUBMITTED; names by text: one → a0..a4, two → b0..b4
    // closingWithQueuedUploadsFailsThemAll (RF 3): stall; A running, B waiting, message M waiting; client.close() → A and B throw
    //   SessionClosed and M throws MessageUploadException(SessionClosed), all within 2 s
    // hostWithoutTheFeatureAnswersUnsupported: plain HostRig, host answers attach.begin with Error("unsupported", …, id)
    //   → uploadAttachment throws Remote("unsupported")
}
```

  Write each comment as a `@Test` with those values.

- [ ] **Step 2: Run the tests.** Run `gw :link-core:test --tests 'com.shellx.link.core.LinkClientAttachmentTest'`. Expected: red, "Unresolved reference: uploadAttachment".
- [ ] **Step 3: Implement.** Use the rules above.
- [ ] **Step 4: Run the tests again.** Run `gw :link-core:test` three times. Expected: PASS each time.
- [ ] **Step 5: Commit.**

```bash
git add shellx-link/kotlin/link-core/src
git commit -m "feat(shellx-link): Kotlin attachment uploads with one upload turn per client"
```

---

### Task 10: RelayApi transport, pairing, grants and tickets

**Files:**
- Create: `account/ApiModels.kt`, `account/HttpSupport.kt`, `account/RelayApi.kt`
- Test: `account-test/AccountTestSupport.kt`, `account-test/RelayApiTest.kt`

Reference: `shellx-link/Sources/ShellXLinkAccount/RelayAPI.swift`, `Tests/ShellXLinkAccountTests/RelayAPITests.swift`, `StubURLProtocol.swift` (`stubTicket`); `relay/src/v2/phones.ts`, `relay/src/v2/relay-tickets.ts`, `relay/src/http/errors.ts`.

**Interfaces:**
- Consumes: `PairingOffer`, `RelayTicket`, `RelayTransportPolicy`, `RelayException` (link-core).
- Produces:

```kotlin
data class AccountSession(val userId: String, val deviceId: String, val token: String) {
    override fun toString(): String    // "AccountSession(user=…, device=…, <redacted>)"
}
data class AccountSignIn(val session: AccountSession, val email: String)
sealed interface PhonePairingStatus {
    data object Pending : PhonePairingStatus
    data class Approved(val machineId: String, val name: String, val linkSlot: String) : PhonePairingStatus
    data object Denied : PhonePairingStatus
    data object Expired : PhonePairingStatus
}
data class PairedMachineListing(val grantId: String, val machineId: String, val name: String, val platform: String,
    val online: Boolean, val linkSlot: String, val fingerprint: String)
data class MintedTicket(val ticket: RelayTicket, val relayUrl: URI)
sealed class RelayApiException(message: String) : Exception(message) {
    data class Http(val status: Int, val code: String) : RelayApiException("http $status $code")   // code = error.code or "unknown"
    class BadResponse : RelayApiException("bad_response")
    class SlotMismatch : RelayApiException("slot_mismatch")
    class NotConnectTicket : RelayApiException("not_connect_ticket")
}
class RelayApi(baseUrl: String, client: OkHttpClient, private val clientVersion: String) {
    // init: RelayTransportPolicy.requireHttps(URI(baseUrl)) (URISyntaxException → RelayException.ProtocolViolation("URL is invalid"))
    val baseUrl: String
    suspend fun requestPairing(offer: PairingOffer, clientKey: ByteArray, token: String): String   // pairing id
    suspend fun pairingStatus(id: String, token: String): PhonePairingStatus
    suspend fun cancelPairing(id: String, token: String)
    suspend fun machines(token: String): List<PairedMachineListing>
    suspend fun mintConnectTicket(machineId: String, expectedSlot: String, token: String): MintedTicket
    suspend fun unpair(grantId: String, token: String)
}
internal suspend fun Call.await(): Response          // enqueue + suspendCancellableCoroutine; cancel() on cancellation
```

  | Method | Request | Success |
  | --- | --- | --- |
  | `requestPairing` | `POST /v2/phone-pairings {machine_id, client_key_b64, proof_b64}` (standard padded base64; proof = `offer.proof(clientKey)`) | `{pairing_id}`, which must be a safe segment |
  | `pairingStatus` | `GET /v2/phone-pairings/<id>` | `pending`, `denied`, `expired`, or `approved` with `machine {machine_id, name, link_slot}`; another status or a missing machine → `BadResponse` |
  | `cancelPairing` | `POST /v2/phone-pairings/<id>/deny`, empty body | any 2xx |
  | `machines` | `GET /v2/phone-grants` | `{grants: [{grant_id, machine_id, name, platform, online, link_slot, fingerprint}]}` |
  | `mintConnectTicket` | `POST /v2/relay/tickets {permission: "connect", lane: "link", target_machine_id}` | `{ticket, expires_at_unix, relay_url}`. Unparseable claims, or a `relay_url` without a host → `BadResponse`; `claims.permission != "connect"` → `NotConnectTicket`; `claims.slot != expectedSlot` → `SlotMismatch` (checked in that order) |
  | `unpair` | `DELETE /v2/phone-grants/<id>` | any 2xx |

  **Transport rules:**
  - The client is built as `client.newBuilder().followRedirects(false).followSslRedirects(false)`, with connect, read and write timeouts of 15 s.
  - URL = `baseHttpUrl.newBuilder().addPathSegments(path.removePrefix("/")).build()`; never string concatenation.
  - Headers: `X-ShellX-Version: <clientVersion>` and `Accept: application/json` always; `Authorization: Bearer <token>` when there is a token; `Content-Type: application/json` with a JSON body.
  - A POST without a body sends `ByteArray(0).toRequestBody(null)`.
  - Non-2xx, including 3xx → `Http(status, code)`, where `code` is the body's `error.code` string, or `"unknown"`.
  - A 2xx whose JSON is missing a field or has a wrong type → `BadResponse`.
  - An `IOException` passes through.
  - A path id must be 1–64 bytes of `[0-9A-Za-z_-]`, else `BadResponse` and no request is made.
  - JSON goes through an internal `ApiJson` with strict `str`, `long`, `bool`, `array` and `obj` readers that throw `BadResponse`.

- [ ] **Step 1: Write the failing tests.** `AccountTestSupport.kt` holds:
  - `ApiServer : AutoCloseable`, which starts `MockWebServer` on `InetAddress.getByName("127.0.0.1")` and offers `base = "http://127.0.0.1:${server.port}"`, `api(base)`, `reply(status, json?)`, `take(): RecordedRequest` (5 s timeout) and `RecordedRequest.json()`;
  - `stubTicket(slot, permission = "connect", role = "client")`, the claims form of `StubURLProtocol.swift`;
  - `within`.

```kotlin
class RelayApiTest {
    // Fixtures (as PhonePairingTests.swift): clientKey = ByteArray(32) { (0x20 + it).toByte() },
    //   hostKey = ByteArray(32) { (0x40 + it).toByte() },
    //   offer = PairingOffer.make("6f1c2b7e-0d4a-4c1e-9a53-3b8e5d2f7a10", "slot-1", hostKey, "Mac")
    // requestPairingPostsKeyAndProof: reply 201 {"pairing_id":"p-1"} → "p-1";
    //   request POST /v2/phone-pairings, Authorization "Bearer tok", body machine_id == offer.machineId,
    //   client_key_b64 == Base64.getEncoder().encodeToString(clientKey), proof_b64 == standard base64 of offer.proof(clientKey)
    // pairingStatusMapsEveryStatus: pending → Pending; denied → Denied; expired → Expired;
    //   approved + machine {machine_id m1, name Mac, link_slot slot-1} → Approved("m1", "Mac", "slot-1");
    //   approved without machine → BadResponse; "later" → BadResponse
    // cancelPairingPostsDeny: POST /v2/phone-pairings/p-1/deny, bearer, body size 0
    // unsafeIdsNeverReachThePath: pairingStatus("../x"), cancelPairing(""), unpair("a/b") → BadResponse; server.requestCount == 0
    // machinesAndUnpair: grants list → [PairedMachineListing("g1","m1","Mac","macos",true,"slot-1","ab:cd")];
    //   unpair("g1") → DELETE /v2/phone-grants/g1
    // mintChecksPermissionThenSlot: stubTicket("other-slot") → SlotMismatch; stubTicket("slot-1","register","daemon") →
    //   NotConnectTicket; ticket "garbage" → BadResponse; relay_url "not a url" → BadResponse;
    //   good → MintedTicket(RelayTicket(t, 1900000000), URI("wss://relay.example.test/v2/relay")) and body
    //   {"permission":"connect","lane":"link","target_machine_id":"m1"}
    // httpErrorsSurfaceTheirCode: 403 {"error":{"code":"not_granted","message":"no"}} → Http(403, "not_granted");
    //   502 with no body → Http(502, "unknown")
    // redirectIsNotFollowed: 302 Location "<base>/steal" → Http(302, "unknown"); server.requestCount == 1
    // plainHttpRefusedForRemoteHost: RelayApi("http://api.example.test", …) → RelayException.InsecureTransport("http");
    //   "http://127.0.0.1:8080", "http://localhost:8080", "https://api.example.test" construct
    // everyRequestCarriesTheVersionHeader: X-ShellX-Version "9.9.9" and Accept "application/json" on a machines() call
    // malformedSuccessBodyIsBadResponse: machines() answered 200 "{" or {"grants":[{"grant_id":1}]} → BadResponse
    // baseUrlPathAndTrailingSlashJoinOnce (RF 5): bases "<base>", "<base>/", "<base>/api", "<base>/api/" → machines()
    //   request paths "/v2/phone-grants", "/v2/phone-grants", "/api/v2/phone-grants", "/api/v2/phone-grants"
}
```

- [ ] **Step 2: Run the tests.** Run `gw :link-account:test --tests 'com.shellx.link.account.RelayApiTest'`. Expected: red, "Unresolved reference: RelayApi".
- [ ] **Step 3: Implement.** Use the table and transport rules above.
- [ ] **Step 4: Run the tests again.** Run `gw :link-account:test`. Expected: PASS.
- [ ] **Step 5: Commit.**

```bash
git add shellx-link/kotlin/link-account/src
git commit -m "feat(shellx-link): Kotlin RelayApi for pairing, grants and connect tickets"
```

---

### Task 11: RelayApi account routes: nonce, Google sign-in, account deletion, push token, logout

**Files:**
- Modify: `account/RelayApi.kt`
- Test: `account-test/RelayApiAccountTest.kt`

Reference: contracts §2 (relay routes, owned by 1A), §4 (Swift names), §5 (Kotlin names), §8 (push registration); `relay/src/routes/devices.ts:55-106`, `relay/src/routes/auth.ts:121-165`, `relay/src/auth/device.ts`, `Sources/ShellXLinkAccount/RelayAPI+Logout.swift`, `RelayAPI+PushToken.swift`.

**Interfaces:**
- Produces, on `RelayApi`:

```kotlin
suspend fun nonce(): String
suspend fun signInWithGoogle(idToken: String, nonce: String, deviceName: String, clientKey: ByteArray): AccountSignIn
suspend fun deleteAccount(idToken: String, nonce: String, token: String)
suspend fun setPushToken(fcmToken: String, token: String)
suspend fun unsetPushToken(token: String)
suspend fun logout(token: String)
```

  | Method | Request | Success |
  | --- | --- | --- |
  | `nonce` | `POST /v1/auth/nonce`, body `{}`, no bearer | `{nonce, expires_in}` → `nonce`; a missing or empty `nonce` → `BadResponse` |
  | `signInWithGoogle` | `POST /v1/auth/google {id_token, nonce, device: {kind: "mobile", name: deviceName, platform: "android", public_key: base64url(clientKey), no padding}}`, no bearer | `{user_id, device_id, token, email}` → `AccountSignIn(AccountSession(user_id, device_id, token), email)` |
  | `deleteAccount` | `DELETE /v1/account {id_token, nonce}`, bearer | any 2xx (204) |
  | `setPushToken` | `PUT /v1/devices/me/push-token {token: fcmToken, platform: "android"}` (no `apns_*` keys), bearer | any 2xx |
  | `unsetPushToken` | `DELETE /v1/devices/me/push-token`, no body, bearer | any 2xx |
  | `logout` | `POST /v1/auth/logout`, empty body, bearer | any 2xx |

  There is no `login`, no Apple method and no `linkGoogle` (contracts §5).

- [ ] **Step 1: Write the failing tests.**

```kotlin
class RelayApiAccountTest {
    // nonceIsAskedWithAnEmptyObject: 201 {"nonce":"n".repeat(43),"expires_in":600} → "n"×43; POST /v1/auth/nonce,
    //   body == {}, no Authorization; 201 {} → BadResponse
    // signInWithGoogleSendsTheAndroidDevice: 200 {user_id u1, device_id d1, token tok-secret, email a@b.c} →
    //   AccountSignIn(AccountSession("u1","d1","tok-secret"), "a@b.c"); toString of the session lacks "tok-secret";
    //   body id_token "id-1", nonce "n-1", device == {"kind":"mobile","name":"Pixel 9","platform":"android",
    //   "public_key":"ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8"} for key bytes 0x20..0x3f; no Authorization
    // signInErrorsSurface: 401 invalid_credentials, 409 switch_from_signed_in_device, 400 invalid_device, 429 rate_limited
    //   → Http(status, code) each
    // deleteAccountSendsTheFreshIdToken: 204 → ok; DELETE /v1/account, Authorization "Bearer tok", body {id_token, nonce};
    //   401 reauth_required → Http(401, "reauth_required")
    // setPushTokenPutsTheAndroidToken: 204; PUT /v1/devices/me/push-token; body exactly {"token":"fcm-1","platform":"android"}
    // unsetPushTokenDeletes: 204; DELETE /v1/devices/me/push-token, bearer, body size 0
    // logoutPostsBearer: 204; POST /v1/auth/logout, "Bearer tok"; 500 → Http(500, "unknown")
    // publicKeyUsesTheBase64UrlAlphabet: key FB FF BF + 29 zero bytes → device.public_key "-_-_" + "A"×39
}
```

- [ ] **Step 2: Run the tests.** Run `gw :link-account:test --tests 'com.shellx.link.account.RelayApiAccountTest'`. Expected: red, "Unresolved reference: nonce".
- [ ] **Step 3: Implement the six methods.** Use the table above and Task 10's transport. Base64url with `java.util.Base64.getUrlEncoder().withoutPadding()`.
- [ ] **Step 4: Run the tests again.** Run `gw :link-account:test`. Expected: PASS.
- [ ] **Step 5: Commit.**

```bash
git add shellx-link/kotlin/link-account/src
git commit -m "feat(shellx-link): Kotlin RelayApi sign-in, account deletion, push token and logout"
```

---

### Task 12: PhonePairing

**Files:**
- Create: `account/PhonePairing.kt`
- Test: `account-test/PhonePairingTest.kt`

Reference: `shellx-link/Sources/ShellXLinkAccount/PhonePairing.swift`, `Tests/ShellXLinkAccountTests/PhonePairingTests.swift`, PROTOCOL.md §9 "Rules".

**Interfaces:**
- Consumes: `RelayApi.requestPairing`, `pairingStatus` and `cancelPairing` (Task 10); `PairingOffer.parse` (Task 4).
- Produces:

```kotlin
/** A Mac this phone is paired with. hostKey comes from the QR offer, never from the relay. */
data class PairedMachine(val machineId: String, val name: String, val linkSlot: String, val hostKey: ByteArray)  // ByteArray rule
sealed class PhonePairingException(message: String) : Exception(message) {
    class Denied : PhonePairingException("denied")
    class Expired : PhonePairingException("expired")
}
object PhonePairing {
    suspend fun pair(offerUri: String, clientKey: ByteArray, api: RelayApi, token: String,
                     pollInterval: Duration = 2.seconds, timeout: Duration = PairingOffer.LIFETIME,
                     onRequested: (pairingId: String) -> Unit = {}): PairedMachine
}
```

  **`pair`:**
  1. Parse the offer. A `PairingOfferException` propagates and nothing reaches the relay.
  2. `requestPairing`, then `onRequested(id)`.
  3. Poll until a deadline of now + `timeout` (`TimeSource.Monotonic`):
     - `Pending` → keep polling;
     - `Denied` or `Expired` from the relay → throw `PhonePairingException.Denied` or `Expired`, with no cancel call;
     - `Approved` whose `machineId` and `linkSlot` both equal the offer's → return `PairedMachine(offer.machineId, offer.machineName, offer.linkSlot, offer.hostKey)`;
     - any other `Approved` → `RelayApiException.BadResponse`;
     - `IOException` or `Http` with status ≥ 500 → keep polling;
     - any other error → rethrow.
  4. Past the deadline → `Expired`. Otherwise `delay(pollInterval)` and poll again.

  On every failure the relay did not decide (including cancellation, a mismatch and the deadline), call `api.cancelPairing(id, token)` once, inside `withContext(NonCancellable)`, ignoring its errors. Then rethrow.

- [ ] **Step 1: Write the failing tests.** These port `PhonePairingTests.swift` onto a `MockWebServer` dispatcher:
  - `POST /v2/phone-pairings` → 201 `{"pairing_id":"p-1"}`;
  - `GET /v2/phone-pairings/p-1` → `pending` twice, then a final response the test chooses;
  - `POST …/p-1/deny` → 204, counted as `denyCalls`;
  - `pollInterval = 5.milliseconds`.

  Tests:
  - `pollsUntilApproved`: returns machine `6f1c2b7e-…`, slot `slot-1`, the offer's host key and name (not "Relay Name"); 3 GETs; POST body as in Task 10.
  - `deniedThrowsWithoutCancel`: final `denied` → `Denied`, `denyCalls == 0`.
  - `expiredThrows`: final `expired` → `Expired`.
  - `hostKeyComesFromTheOffer`: approval with the relay name "Relay Name" → `hostKey` equals the offer's.
  - `mismatchedApprovalCancelsOnce`: slot `evil-slot`, or another machine id → `BadResponse`, `denyCalls == 1`.
  - `clientDeadlineExpiresAndCancels`: always pending, `timeout = 60.milliseconds` → `Expired`, `denyCalls == 1`.
  - `cancellationCancelsThePairing`: `launch(Dispatchers.Default) { pair(…, pollInterval = 20.milliseconds) }`, `delay(80)`, `cancelAndJoin()` → `denyCalls == 1`.
  - `transientErrorsAreRetried`: 503 `relay_v2_unavailable`, then 502, then approved → success, `denyCalls == 0`.
  - `clientErrorAborts`: 404 `pairing_not_found` → `Http(404, "pairing_not_found")`, exactly 1 GET.
  - `reportsTheIdBeforeItPolls`: `onRequested` gets `"p-1"` while `server.requestCount == 1`.
  - `badOfferNeverReachesTheRelay`: `"https://example.com"` → `PairingOfferException.BadUri`, `requestCount == 0`.
  - `pairedMachineEqualityUsesKeyContent`: two `PairedMachine`s with equal key bytes are equal; `toString()` shows `<32 bytes>`.

- [ ] **Step 2: Run the tests.** Run `gw :link-account:test --tests 'com.shellx.link.account.PhonePairingTest'`. Expected: red, "Unresolved reference: PhonePairing".
- [ ] **Step 3: Implement.** Follow the rules above.
- [ ] **Step 4: Run the tests again.** Run `gw :link-account:test`. Expected: PASS.
- [ ] **Step 5: Commit.**

```bash
git add shellx-link/kotlin/link-account/src
git commit -m "feat(shellx-link): Kotlin phone pairing flow"
```

---

### Task 13: OkHttp relay sockets and LinkConnector

**Files:**
- Create: `account/OkHttpRelaySockets.kt`, `account/LinkConnector.kt`
- Modify: `account/RelayApi.kt` (add `val relaySockets: RelaySocketFactory = OkHttpRelaySockets(<the derived client>)`)
- Test: `account-test/FakeWebSocketRelay.kt`, `account-test/OkHttpRelaySocketsTest.kt`, `account-test/LinkConnectorTest.kt`

Reference: `shellx-link/Sources/ShellXLinkRelay/RelayCircuit.swift` (`RelaySocket`), `Sources/ShellXLinkAccount/LinkConnector.swift`.

**Interfaces:**
- Consumes: `RelaySocket`, `RelaySocketFactory`, `RelayClientConnector`, `LinkClient` (link-core); `RelayApi.mintConnectTicket` (Task 10).
- Produces:

```kotlin
class OkHttpRelaySockets(client: OkHttpClient) : RelaySocketFactory   // client.newBuilder().followRedirects(false).followSslRedirects(false)
object LinkConnector {
    /** Mints a connect ticket whose slot must be machine.linkSlot, opens a relay circuit (retrying slot-offline),
     *  and runs the handshake trusting only machine.hostKey. */
    suspend fun connect(machine: PairedMachine, key: NoiseStaticKey, api: RelayApi, token: String,
                        clientVersion: String, deviceName: String,
                        sockets: RelaySocketFactory = api.relaySockets): LinkClient
}
```

  What each failure surfaces as, so 3C's `LinkFailure` can map it as `LinkFailure.swift` does:

  | Cause | Exception |
  | --- | --- |
  | 401 | `RelayApiException.Http(401, …)` |
  | revoked grant | `Http(_, "not_granted")` or `Http(_, "machine_not_found")` |
  | host key changed | `NoiseException.UntrustedPeer` or `RelayApiException.SlotMismatch` |
  | needs update | `LinkClientException.ProtocolMismatch` |
  | everything else (offline) | `IOException`, `RelayException.*`, `LinkClientException.SessionClosed`/`TimedOut` |

  **The OkHttp socket.** `open(url, bearer)` sends a `Request` to `url.toString()` with `Authorization: Bearer <bearer>`, through `newWebSocket(request, listener)`. The listener feeds a `Channel(UNLIMITED)`:
  - text → `Text`;
  - bytes → `Binary(bytes.toByteArray())`;
  - `onClosing` → `webSocket.close(1000, null)`, then close the channel;
  - `onClosed` → close the channel;
  - `onFailure(t)` → `channel.close(t as? IOException ?: IOException(t))`.

  The socket methods:
  - `receive()` returns the next element. A normal close → `RelayException.Closed`. A failure rethrows its `IOException`. On `CancellationException` it calls `webSocket.cancel()` and rethrows.
  - `sendText` and `sendBinary` throw `Closed` when `send` returns false.
  - `close()` calls `webSocket.close(1000, null)` and closes the channel.

- [ ] **Step 1: Write the fake relay and the failing tests.** `FakeWebSocketRelay` is a `MockWebServer` (on 127.0.0.1) whose dispatcher handles three requests:
  - **`POST /v2/relay/tickets`** → `{ticket: stubTicket(slot), expires_at_unix: 1900000000, relay_url: "ws://127.0.0.1:<port>/v2/relay"}`. The slot is configurable.
  - **The first `GET /v2/relay` upgrade (the control socket):** on the text `connect` it answers `allocated` (circuit `"c-1"`, the same lane, generation 0, join ticket `"jt-1"`).
  - **The second upgrade (the circuit socket):** on the text `join` it answers `ready`, then bridges binary frames both ways to `inMemoryCircuitPair().first`.

  The test runs a host on `.second`: `SecureChannel.open(…, RESPONDER, hostKey) { true }`, reads `Hello`, then sends `Welcome(1, "test-host", "Test Mac", listOf("workspaces"))`. The fake records each upgrade's `Authorization` header and each text it received.

```kotlin
class OkHttpRelaySocketsTest {
    // Server side of each test: a MockWebServer on 127.0.0.1 enqueuing MockResponse.Builder().webSocketUpgrade(serverListener).build()
    // deliversTextAndBinaryWithTheBearer: an upgrade whose server listener sends "hello" then bytes [1,2,3] on open →
    //   receive() == Text("hello"), then Binary([1,2,3]); the recorded Authorization == "Bearer t1"
    // sendsReachTheServer: sendText("x"), sendBinary([9]) → the server listener got "x" and [9]
    // serverCloseIsClosed: server closes with 1000 → receive() throws RelayException.Closed; then sendText throws Closed
    // failureBeforeOpenIsIOException: open ws://127.0.0.1:<closed port>/v1/relay → receive() throws an IOException
}
class LinkConnectorTest {
    // connectsWithThePinnedKeyOverTheMintedRelay: machine (slot "slot-1", hostKey = host public key) →
    //   client.hostFeatures == setOf("workspaces"); ticket POST body target_machine_id = machine.machineId;
    //   control upgrade Authorization "Bearer <stub ticket>"; connect text has slot "slot-1" and protocol 5;
    //   circuit upgrade Authorization "Bearer jt-1"; join role "client"; hello == Hello("1.0.0", "Pixel 9")
    // anotherHostKeyIsUntrustedPeer: machine.hostKey = another key → NoiseException.UntrustedPeer
    // ticketForAnotherSlotNeverOpensASocket: minted slot "other" → RelayApiException.SlotMismatch; zero upgrades
}
```

- [ ] **Step 2: Run the tests.** Run `gw :link-account:test --tests 'com.shellx.link.account.OkHttpRelaySocketsTest' --tests 'com.shellx.link.account.LinkConnectorTest'`. Expected: red, "Unresolved reference: OkHttpRelaySockets".
- [ ] **Step 3: Implement.** Follow the rules above. `LinkConnector.connect` makes three calls: `mintConnectTicket(machine.machineId, machine.linkSlot, token)`, then `RelayClientConnector.connect(minted.relayUrl, machine.linkSlot, minted.ticket, sockets)`, then `LinkClient.connect(circuit, key, machine.hostKey, clientVersion, deviceName)`.
- [ ] **Step 4: Run the tests again.** Run `gw :link-account:test`. Expected: PASS.
- [ ] **Step 5: Commit.**

```bash
git add shellx-link/kotlin/link-account/src
git commit -m "feat(shellx-link): Kotlin OkHttp relay sockets and LinkConnector"
```

---

### Task 14: Integration test against a real `cmux-relay` (gated by `CMUX_RELAY_BIN`)

**Files:**
- Test: `account-test/TestTicketMinter.kt`, `account-test/TestRelayHost.kt`, `account-test/RelayProcess.kt`, `account-test/RelayIntegrationTest.kt`

Reference: `shellx-link/Tests/ShellXLinkRelayTests/RelayIntegrationTests.swift`, `TestTicketMinter.swift`; `Sources/ShellXLinkRelay/RelayHostRegistration.swift` (`open`, `pump`, `accept`); `relay/src/v2/tickets.ts`.

**Interfaces (test code only):**
- Consumes: `OkHttpRelaySockets`, `RelayClientConnector`, `RelayCircuitJoin`, `RelayControl`, `RelayEndpoint`, `SecureChannel` and `LinkClient`.

```kotlin
class TestTicketMinter(secret: String) {
    companion object { const val ISSUER = "shellx-relay" }
    /** v2.<base64url(claims JSON)>.<base64url(HMAC-SHA256(secret, payload))>. Claims: version 2, issuer, permission,
     *  role (register → daemon, connect → client), slot, circuit/lane/generation null, issued_at_unix, expires_at_unix.
     *  payload = ["cmux-relay-ticket-v2","2",issuer,permission,role,slot,"","","",issued,expires].joinToString("\n") */
    fun mint(permission: String, slot: String, nowUnix: Long = System.currentTimeMillis() / 1000, lifetime: Long = 120): RelayTicket
}
class RelayProcess private constructor(val url: URI /* ws://127.0.0.1:<port>/v1/relay */) {
    fun stop()       // destroy(); waitFor(5 s), else destroyForcibly()
    companion object {
        /** `<binary> serve` with CMUX_RELAY_HMAC_SECRET, CMUX_RELAY_ISSUER=shellx-relay and CMUX_RELAY_BIND=127.0.0.1:<free port>;
         *  output discarded; healthy when GET http://127.0.0.1:<port>/healthz answers 200 within 10 s, else stop and fail. */
        fun start(binary: String, secret: String): RelayProcess
    }
}
class TestRelayHost(sockets: RelaySocketFactory, relayUrl: URI, slot: String, minter: TestTicketMinter) {
    /** Registers `slot`; for each Incoming, joins as DAEMON and runs onCircuit in its own coroutine; answers Ping with Pong. */
    fun start(scope: CoroutineScope, onCircuit: suspend (RelayCircuit) -> Unit): Job
}
```

  **Registration**, as `RelayHostRegistration.swift`'s `open` does it:
  1. Open the control endpoint with `bearer = ticket`.
  2. `sendText(Register(5, slot, ticket))`.
  3. Wait for `Registered`. An `Error` → `Server`.
  4. Loop:
     - `Incoming` → `RelayCircuitJoin.join(…, role = DAEMON, ticket = joinTicket)`;
     - `Ping` → `Pong`.

- [ ] **Step 1: Write the tests.** The test class is annotated with `@EnabledIfEnvironmentVariable(named = "CMUX_RELAY_BIN", matches = ".+")`. It uses secret `"0123456789abcdef0123456789abcdef"` and starts the relay before each test. `connectWhenOnline(slot)` retries `RelayClientConnector.connect(…, slotOfflineRetries = emptyList())` on `Server("slot-offline", true)` every 50 ms, for up to 10 s.
  - `clientAndHostExchangeBytes`: the host echoes → `send([1, 2])`, then `receive() == [1, 2]`.
  - `badTicketSurfacesServerError`: with the slot online, a connect ticket minted with secret `"fedcba9876543210fedcba9876543210"` → `Server("invalid-ticket", false)`.
  - `connectRetriesSlotOffline`: start `connect` (default retries) first; start the host 300 ms later → it connects and echoes `[9]`. Slot `"nobody"` with `slotOfflineRetries = emptyList()` → `Server("slot-offline", true)`.
  - `linkSessionRunsOverTheRealRelay`:
    - the host's `onCircuit` runs `SecureChannel.open(RESPONDER)`, then hello/welcome, then answers `SnapshotGet` with `Snapshot(id, 3, [])`;
    - the client runs `LinkClient.connect` over `connectWhenOnline("s1")`;
    - `snapshot().revision == 3`.

- [ ] **Step 2: Run without the binary.** Run `gw :link-account:test --tests 'com.shellx.link.account.RelayIntegrationTest'`. Expected: PASS, with the 4 tests reported as skipped (`build/test-results` shows `skipped="4"`).
- [ ] **Step 3: Run against the real relay.** Build the relay with `cargo build --manifest-path cmux-tui/Cargo.toml -p cmux-relay`. Then run `CMUX_RELAY_BIN="$(git rev-parse --show-toplevel)/cmux-tui/target/debug/cmux-relay" gw :link-account:test --tests 'com.shellx.link.account.RelayIntegrationTest'`. Expected: PASS, 4 tests run (`tests="4" skipped="0"`).
  - If a test fails, fix the library code it exposes: a test that fails here is a real bug.
  - If `cargo` is missing, record "integration not run: no cargo" for Task 15 and go on.
- [ ] **Step 4: Commit.**

```bash
git add shellx-link/kotlin/link-account/src/test
git commit -m "test(shellx-link): Kotlin Link client against a real cmux-relay"
```

---

### Task 15: Verify and hand off

**Files:** none new.

- [ ] **Step 1: Run the full suite.** Run `gw cleanTest test`. Expected: PASS.
  - Record the test counts per module from `shellx-link/kotlin/*/build/test-results/test/*.xml`.
  - If Task 14 Step 3 ran, repeat it now and expect 4 tests run.
- [ ] **Step 2: Run 3A's script.** Run `shellx-android/scripts/dev.sh test all`. Expected: `==> test all: passed`. Besides the link tests, this proves that `shellx-android`'s `:core`, `:app` and `build-release` still resolve their lockfiles and shrink with the new libraries.
  - If a lockfile is stale, repeat Task 1 Step 5 and commit the lockfiles.
  - If R8 in `build-release` stops on `Missing class … (referenced from: org.bouncycastle…)` or another library of this plan, add one `-dontwarn <package>.**` line per missing package to `shellx-android/app/proguard-rules.pro`, under a comment that names the library and why (3A's rule for that file), and commit it as `build(shellx-android): R8 rules for the Kotlin Link libraries`.
- [ ] **Step 3: Run the licence checks.**
  - Run `bash scripts/shellx/check-link-license.sh`. Expected: exit 0, no output. The Swift side is unchanged.
  - Run `bash scripts/shellx/check-android-license.sh`. Expected: `check-android-license: ok` (Task 1 Step 5 added the entries). If it rejects an artefact this plan added, add it with 3A's allowlist procedure (3A Task 3 Step 6), rerun, and commit with `git add scripts/shellx/android-license-allowlist.txt` and message `build(shellx): allow the Kotlin Link libraries`.
- [ ] **Step 4: Run the boundary greps.** Each command must print nothing.

```bash
grep -rnE 'HexFormat|java\.net\.http|readAllBytes|transferTo|ofVirtual|Redirect\.DISCARD|Security\.addProvider|"BC"' shellx-link/kotlin/link-core/src/main shellx-link/kotlin/link-account/src/main
grep -rn 'Manaflow' shellx-link/kotlin
grep -nE '\.\./\.\.' shellx-link/kotlin/link-core/build.gradle.kts shellx-link/kotlin/link-account/build.gradle.kts
git diff --stat develop -- shellx-link/Sources shellx-link/Tests shellx-link/spec shellx-link/vectors shellx-link/Package.swift
```

- [ ] **Step 5: Run the repository checks.** Run `python3 scripts/verify-local.py`. Expected: exit 0. Kotlin files are unknown inputs to it, so it runs the full static recipe. If a check fails, run the same command on `develop` in the primary checkout. A failure there too is pre-existing: report it and do not fix it on this branch.
- [ ] **Step 6: Review.** Run a review subagent on `git diff develop...HEAD`, following `skills/cmux-review/SKILL.md` (correctness first) through superpowers:requesting-code-review. Give it this plan and PROTOCOL.md. Fix each confirmed finding with a test first, then repeat Steps 1–5.
- [ ] **Step 7: Land on develop (contracts §1).**
  1. In the checkout that has `develop` checked out: `git pull --ff-only`.
  2. `git merge --no-ff feat/shellx-android-3b-link-kotlin -m "Merge branch 'feat/shellx-android-3b-link-kotlin' into develop"`.
  3. Run `gw test` there. Expected: PASS.
  4. `git push origin develop`.

  Never merge into `main`, never deploy, never publish. This plan changes no app, runtime or UI code. Remove the worktree afterwards (superpowers:finishing-a-development-branch).
- [ ] **Step 8: Report.** Include:
  - test counts;
  - whether the live-relay test ran;
  - whether the licence script needed allowlist entries;
  - the public API that 3C consumes (Task 8, Task 9, Task 10–13 Interfaces);
  - the "Spec notes" below, for the parity ledger owner.

---

## Spec notes

These are places where the spec, the brief or the contracts differ from the code. The code is the fact, and this plan follows the spec's intent.

- **Case count.** PROTOCOL.md §8 counts `unknown` among its "41 cases". There are 40 sendable cases plus `unknown`, not 41 plus `unknown`.
- **`terminal.json`.** S3 §7.1 lists it among the link-core vectors, but contracts §6 gives it to 3G (after 2A). The Task 2 test skips the contracts §6 names, in case 2A adds them to `messages.json`.
- **Integer strictness.** PROTOCOL.md §3 says integers have no fraction or exponent. Kotlin enforces that on every integer field. Swift's `JSONDecoder` accepts integral `1.0` outside `v`. No real host sends that.
- **The phone's machine list.** The brief lists `relay/src/v2/machines.ts`, but that file is desktop-only (`requireDesktop`). The phone's list is `GET /v2/phone-grants` (`relay/src/v2/phones.ts:189-215`), as Swift's `machines(token:)` uses.
- **Routes not yet on `develop`.** `POST /v1/auth/nonce`, `POST /v1/auth/google` and `DELETE /v1/account {id_token, nonce}` are not on `develop` yet (`relay/src/routes/account.ts` still takes `{password}`). 1A adds them. 3B tests them only against MockWebServer.
- **Relay control samples.** The relay's own fixture (`cmux-tui/crates/cmux-remote-protocol/tests/fixtures/relay-control-v1.jsonl`) is under the GPL and is not copied (S3 §5, `shellx-link/README.md`). Task 5 writes ten samples by hand in the Swift encoder's key order, with `"protocol":5`, the version the real relay requires (`cmux-tui/crates/cmux-remote-protocol/src/frame.rs:6`) and the connector sends.
- **Deliberate differences from the Swift reference** (for the parity ledger `docs/superpowers/ledgers/shellx-android-parity.md`, owned by later plans):
  - `SecureChannelError.nonEmptyHandshakePayload` became `NoiseException.NonEmptyHandshakePayload`.
  - A request whose frame cannot be encoded throws its `LinkCodecException`. Swift reports `sessionClosed`.
  - Cancellation propagates as `CancellationException` and is never wrapped in `MessageUploadException`. iOS maps a cancelled message to `uploadFailed`, while 3C lets cancellation propagate.
  - There is no `deinit`: a dropped `LinkClient` must be `close()`d.
  - Not ported (phone-side library): no `LinkHost`, `RelayHostRegistration`, host-only shrink helpers, password `login` or `verify(proof:)`.
  - `unsetPushToken` (`DELETE /v1/devices/me/push-token`, `relay/src/routes/devices.ts:101-106`, contracts §8) is new. Swift has no equivalent.

## Contract additions

These are cross-plan names that 3C relies on and that contracts §5 does not list yet. They are listed here for the contracts owner to add to §5 before 3C is planned. The executor of this plan does not edit the contracts file.

- Gradle coordinates `com.shellx.link:link-core` and `com.shellx.link:link-account` (group `com.shellx.link`), for `includeBuild("../shellx-link/kotlin")`.
- `com.shellx.link.core.LinkSession`, implemented by `LinkClient` (`LinkClient.connect(circuit, key, hostKey, clientVersion, deviceName, timings)`). Its Flows are `changes`, `sessionChanges`, `workspaceChanges` and `chatEntries`; the element and result types are `PendingChange`, `SessionChange`, `WorkspaceChange`, `ChatPush`, `PendingSnapshot`, `SessionList`, `WorkspaceList`, `ChatHistoryPage` and `WorkspaceCreated`. It also covers `ChatAttachment`, `LinkTimings`, `LinkLog.sink` and `inMemoryCircuitPair()`.
- Exceptions: `LinkClientException.{ProtocolMismatch, Rejected, SessionClosed, TimedOut, Remote, UnexpectedAnswer}`, `MessageUploadException`, `NoiseException.UntrustedPeer`, `RelayException.*`, `PairingOfferException.*`.
- `com.shellx.link.account`: `RelayApi(baseUrl, client: OkHttpClient, clientVersion)` with the Task 10 and Task 11 methods; `RelayApiException.{Http, BadResponse, SlotMismatch, NotConnectTicket}`; `PhonePairing.pair(…)`; `PhonePairingException.{Denied, Expired}`; `PairedMachine`; `PairedMachineListing`; `LinkConnector.connect(…)`; `OkHttpRelaySockets`.
