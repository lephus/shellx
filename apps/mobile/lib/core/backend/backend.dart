import 'dart:typed_data';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/auth/account_session.dart';

/// App-side view of one terminal tab ([ClientTab] in `shellx_client`).
///
/// `shellx_client` types are `final`, so the UI depends on these interfaces
/// and tests substitute fakes; `ClientBackend` adapts the real classes.
abstract interface class TabHandle {
  int get id;
  int get index;
  String get shell;

  /// [SessionKind.desktop] for a terminal window open on the computer (spec "chia sẻ terminal" §9.2).
  SessionKind get kind;

  /// Desktop terminals only: the terminal application and the window title when the tab was
  /// attached; may be empty.
  String get app;
  String get title;

  /// False after [TabDetached], [TabExited] or [TabError], and once the tab
  /// is closed.
  bool get isAttached;

  /// Broadcast. Events emitted before the first listener are replayed to it
  /// (the catch-up output of an attach arrives before `attach()` returns).
  /// Re-attaching the tab returns this same handle, so a listener keeps
  /// receiving; the stream ends when the tab is closed or the machine is
  /// unpaired. A [TabError] with `session_not_found` means the session is
  /// gone ("Phiên đã kết thúc").
  Stream<TabEvent> get events;
}

/// App-side view of the encrypted channel to one pinned machine
/// ([MachineClient]).
///
/// Whenever a channel is installed — the relay is back, the machine comes
/// online, after [ShellxBackend.resume], or any [connect] — the tabs still
/// attached re-attach with `last_seq`; a session that vanished meanwhile ends
/// its tab with `TabError(session_not_found)` (spec §9.4).
abstract interface class MachineSession {
  String get agentId;

  /// [MachineIdle] → [MachineConnecting] → [MachineReady] or
  /// [MachineFailed]. Only [MachineReady] falls back to [MachineIdle], when
  /// the channel is lost (relay down, machine offline,
  /// [ShellxBackend.suspend]); [MachineFailed] stays until the next
  /// handshake. The automatic resume runs that handshake itself (relay back,
  /// machine online), so the state can change without the UI calling
  /// [connect].
  MachineConnectionState get state;
  Stream<MachineConnectionState> get states;

  /// IK handshake with the pinned key; a no-op when ready, and concurrent
  /// calls share one handshake. On failure the state becomes
  /// [MachineFailed] and a [MachineConnectionException] with the same
  /// failure is thrown (never the state object). Losing the relay or the
  /// machine during the handshake fails it at once (`timeout` while the
  /// relay is not connected, `agentOffline` otherwise). While
  /// [ShellxBackend.pair] runs for this machine, the handshake waits for it.
  ///
  /// `untrusted` (spec §12): the pin is forgotten ([ShellxBackend.machine]
  /// then throws, [ShellxBackend.pinnedMachines] no longer lists it) and
  /// every attached tab ends with `TabError(session_not_found)` — the UI
  /// shows the machine-level "untrusted" text, not "session ended".
  Future<void> connect();

  /// Like every request: connects first (throwing as [connect] does), then
  /// throws `MachineConnectionException(agentOffline)` at once when there is
  /// no channel or it is lost before the answer, `timeout` when the machine
  /// does not answer in time. Always asks for the computer's terminal windows
  /// too (`desktop: true`, spec "chia sẻ terminal" §8): they come back with
  /// [SessionKind.desktop].
  Future<List<SessionInfo>> listSessions();

  /// The `desktop_sharing` of the last [listSessions] answer: null when the
  /// agent never reported it (an agent older than terminal sharing), else
  /// whether "Chia sẻ terminal" is on (spec §9.1 hints).
  bool? get desktopSharing;

  /// Throws [AppErrorException] (`session_limit`, `spawn_failed`) or
  /// [MachineConnectionException].
  Future<TabHandle> openSession({required int cols, required int rows});

  /// Attaches a session from [listSessions], or re-attaches a tab of this
  /// machine (same [TabHandle], `last_seq = received`). Throws
  /// [AppErrorException] with `session_not_found` when the session is gone
  /// (an existing tab also receives [TabError]), or
  /// [MachineConnectionException].
  Future<TabHandle> attach(int id, {required int cols, required int rows});

  /// The machine's tabs, ended ones included until [closeTab].
  List<TabHandle> get tabs;

  /// Keystrokes. Dropped while there is no channel (the UI shows it is
  /// reconnecting) or the tab is not attached; on a new channel, held (the
  /// newest 64 KiB) until the tab's re-attach is answered, then sent.
  void input(int id, Uint8List data);

  /// Ignored below 1×1; sent only while the tab is attached on a channel
  /// (the size is kept for the next re-attach).
  void resize(int id, int cols, int rows);

  /// V2-2: the machine's AI sessions.
  AiMachine get ai;

  /// Removes the tab and ends its [TabHandle.events]. An attached tab also
  /// closes its session on the machine: at once, or — without a channel —
  /// right after the next channel is installed. A desktop tab
  /// ([SessionKind.desktop]) only leaves the terminal (`session.detach`): the
  /// window keeps running on the computer. An ended tab is only removed here.
  Future<void> closeTab(int id);
}

/// App-side view of one mirrored AI session ([AiSessionLink] in `shellx_client`).
abstract interface class AiSessionHandle {
  String get sid;

  /// What the phone holds of the session; changes come on [changes].
  AiMirror get mirror;

  /// [AiLinkState.attaching] also lasts while the machine cannot be reached (offline, failed,
  /// untrusted): read [MachineSession.state] for that.
  AiLinkState get state;

  /// `gone`, `desktop_closed`, `unavailable`, `detached`, `unreadable` (the computer keeps sending
  /// what this version cannot read), or a newer word.
  String? get closedReason;
  Stream<void> get changes;

  /// Stops mirroring (the screen closed).
  void detach();

  /// "Tải thêm": older items.
  void loadEarlier();
}

/// App-side view of a machine's AI sessions ([MachineAi] in `shellx_client`). Every request
/// connects first; it throws [AiRequestException] (the computer said no, with its code) or
/// [MachineConnectionException].
///
/// A request in flight when its session closes fails with [AiRequestException] too (no `ai.result`
/// comes then): `not_found` for a tab that closed, `unavailable` when the window quit; a listing that
/// says no window serves AI ends every request in flight with `unavailable`. One in flight when the
/// channel is lost fails with [MachineConnectionException] (`agentOffline`) and is never sent again.
abstract interface class AiMachine {
  /// Learned only from the computer's answer to a list of its sessions: null before the first one;
  /// false for a computer without AI for phones. True does not mean a window serves AI yet: [listing]
  /// can still say `available: false`, which the phone shows as "no AI sessions now", not as an error.
  bool? get supported;
  AiListing? get listing;
  Stream<AiListing> get listings;

  /// V2-2b B1: the `ai` protocol the computer's relay process reported in its answer to a list of its
  /// sessions (2 or more: it forwards what V2-2b adds); null before such an answer.
  int? get protocol;

  /// V2-2b B1 (ruling R3): whether a V2-2b feature ([AiFeature]) can be used now — [protocol] is 2 or
  /// more and the last [listing] names it. A request of a feature that cannot be used fails at once with
  /// `AiRequestException('unsupported')`, sending nothing.
  bool can(String feature);

  /// V2-2b B22, B23: the last entry seen for session [sid] in a listing of this machine, in this run of the
  /// app; null when none was. What a session was (its agent's own id, agent and folder) once the computer
  /// restarted ShellX and gave it another sid.
  AiSessionInfo? seen(String sid);

  /// Keeps [listing] current while the app is connected: asks now (connecting first when there is no
  /// channel) and again on every new channel, and a lost channel is brought back even with no terminal
  /// tab open, until [unwatch]. It is one switch, not a count: whoever shares the list between screens
  /// counts them.
  Future<void> watch();

  /// The inverse of [watch], for the screen that watched when it goes away or stops showing the machine.
  /// Nobody wants the list any more, so a lost channel is not brought back for it and a new channel does
  /// not ask for it (an open session still wants the channel); otherwise every relay or presence event
  /// would make a handshake with every machine ever watched. It does nothing when nothing is watched.
  ///
  /// The computer keeps sending the changes of the list until the channel ends (it cannot be asked to
  /// stop) and they are still read; but a new channel does not carry them, so [listing] is only as
  /// current as the last time the list was watched.
  void unwatch();
  AiSessionHandle attach(String sid);

  /// [blobs]: images uploaded with [uploadImage] for this message (V2-2b B12); [files]: paths [files] offered and
  /// still mentioned in [text] (B13). Each list is sent only to a computer that takes it (`unsupported`
  /// otherwise, sending nothing).
  Future<void> prompt(String sid, String text, {List<int> blobs = const [], List<String> files = const []});

  /// V2-2b B12: a number for the next image this phone uploads (its own, never the same twice while the app runs).
  int newBlobId();

  /// V2-2b B12: sends [bytes] as image [blob] in parts, [onProgress] after each part the computer took ([sent] of
  /// [parts]). Throws like a request: [AiRequestException] (`unsupported`, `too_large`, `busy`…) or
  /// [MachineConnectionException]; nothing is sent again by itself.
  Future<void> uploadImage(int blob, String mime, Uint8List bytes, {void Function(int sent, int parts)? onProgress});

  /// V2-2b B13: the files of session [sid]'s folder matching [query], for `@` (at most 8, relative paths).
  Future<List<String>> files(String sid, String query);

  Future<void> answerPermission(String sid, int permission, String option);
  Future<void> answerAsk(String sid, int ask, ElicitationResponse response);
  Future<void> cancel(String sid);
  Future<void> forceStop(String sid);
  Future<void> unqueue(String sid, int queued);

  /// A new session; its sid.
  Future<String> open(String agent, String folder);

  /// V2-2b B17: a page of the earlier sessions of [sid]'s agent in its folder ([cursor]: the next page). Throws
  /// [AiRequestException] (`not_ready` while the agent does not run, `unsupported` when the computer cannot).
  Future<AiHistoryPage> history(String sid, {String? cursor});

  /// V2-2b B17: reopens the agent's earlier session [acp] in a new AI tab of [agent] in [folder] (a listing key);
  /// the new session's sid.
  Future<String> resume(String agent, String folder, String acp);

  /// V2-2b B18: runs session [sid], a tab without a folder, in [folder] (a listing key).
  Future<void> chooseFolder(String sid, String folder);

  /// V2-2b B11: the mode, model and thinking choices of [sid] this phone may make; `unsupported` when the
  /// computer cannot (R15).
  Future<AiConfigView> config(String sid);

  /// V2-2b B11: one choice of "Chế độ và model" (a choice's value, or a bool for a switch).
  Future<void> setConfig(String sid, String id, Object value);

  /// V2-2b B11: the mode of an agent with only modes.
  Future<void> setMode(String sid, String modeId);

  /// V2-2b B16: item [index] of [sid] in full, a slice at a time ([onPart] after each, 1-based; an error it
  /// throws ends the load). `too_big`: read it on the computer; `changing`: it kept changing while it loaded.
  Future<AiFullView> fullItem(String sid, int index, {void Function(int part, int parts)? onPart});

  /// V2-2b B19: the files changed since [turn] began (null: since the session's first turn), as the computer's
  /// Changes panel shows them.
  Future<AiChangesView> changes(String sid, {int? turn});

  /// V2-2b B19: the diff of [path] (one of [changes]' files): an `ai.diff` body — its region (`aiFileDiffOf`), or
  /// `{"binary": true}` / `{"missing": true}`.
  Future<Map<String, Object?>> diff(String sid, String path, {int? turn});

  /// V2-2b B19: puts the files changed since [turn] began back; how many went. When some changed after the turn the
  /// computer asks first: [AiRequestException] `confirm` whose body is an `AiRevertConfirm`; then [keep] `clean` or
  /// `all`. Sent once per call: a lost channel fails it and nothing sends it again.
  Future<int> revert(String sid, {int? turn, String? keep});
}

/// Everything the signed-in UI needs from `shellx_core` + `shellx_client`.
///
/// Never log what flows through it: tokens, keys, payloads, terminal output.
abstract interface class ShellxBackend {
  /// `revoked` (close 4002, or a 401 upgrade) and `replaced` (4001) are
  /// never retried automatically.
  RelayConnectionState get relayState;
  Stream<RelayConnectionState> get relayStates;

  /// Skip the reconnect backoff (`RelayConnection.reconnectNow`, effective
  /// only while `disconnected`).
  void reconnectNow();

  /// App went to the background: drop the relay connection and every machine
  /// channel (spec §12: the phone only retries while in the foreground).
  /// Machines and tabs survive. Safe to call repeatedly.
  Future<void> suspend();

  /// App is back: reconnect; `shellx_client` re-handshakes and re-attaches
  /// every attached tab with `last_seq` (spec §9.4). Safe to call
  /// repeatedly. Only acts after [suspend]: while the client runs (e.g. the
  /// relay is `replaced`) it does nothing, so [suspend] first to restart it.
  Future<void> resume();

  /// `GET /v1/devices` (spec §10.2); throws [ApiException].
  Future<List<RemoteDevice>> devices();

  /// Presence as last reported by the hub (spec §6.2 PRESENCE). When the
  /// relay leaves `connected`, every machine that was online gets an offline
  /// frame and stays offline here until the hub announces it again.
  bool isOnline(String agentId);
  Stream<PresenceFrame> get presence;

  /// Machines pinned for the signed-in user (spec §5.3 step 6), stored under
  /// `pinned_machines_<userId>` in the app's single secure store.
  Future<List<PinnedMachine>> pinnedMachines();

  /// Pairing initiator (spec §5.3); throws [PairingException] (`shellx_client`)
  /// or the [ApiException] of `GET /v1/devices`. On success the machine is
  /// pinned. Once the pairing handshake was sent, the machine's channel is
  /// dropped whether pairing succeeds or not, and its open tabs re-attach.
  Future<void> pair(PairingUri uri);

  /// The same [MachineSession] per [agentId] while it stays pinned. Throws
  /// [StateError] when [agentId] is not pinned — never paired, unpaired, or
  /// forgotten after an `untrusted` handshake.
  MachineSession machine(String agentId);

  /// Spec §5.5: drop the machine's channel and tabs (its sessions keep
  /// running on the computer), forget the pin, then delete the pairing
  /// record (3 attempts for network/5xx errors). May still throw
  /// [ApiException] after the pin is gone: show it and offer a retry —
  /// calling this again only repeats the delete. A [MachineSession] kept
  /// from before is dead either way: its tabs are closed and [connect] and
  /// requests throw [MachineConnectionException]; ask [machine] again after
  /// pairing again. A `pairing_removed` event from the relay never unpairs;
  /// only an `untrusted` handshake forgets a pin.
  Future<void> unpair(String agentId);

  /// `PUT /v1/devices/me/push-token` (push spec §5, §6): this phone's FCM token, so the relay
  /// can push the agents' notifications to it. Throws [ApiException] (a relay without push
  /// support answers 404), and [StateError] after [dispose].
  Future<void> registerPushToken(String token, PushPlatform platform);

  /// `DELETE /v1/devices/me/push-token`: notifications were turned off on this phone. Throws
  /// [ApiException], and [StateError] after [dispose].
  Future<void> deletePushToken();

  /// Stops the client and the relay connection for good (sign-out). After
  /// it, [suspend], [resume] and [reconnectNow] do nothing — the relay never
  /// dials again — and [devices], [pair], [unpair] and [registerPushToken] throw [StateError]:
  /// the shared [ShellxApi] may already hold the next account's token.
  Future<void> dispose();
}

/// Builds the backend of a signed-in account; `ClientBackendFactory` in production, a fake in tests.
abstract interface class BackendFactory {
  Future<ShellxBackend> create(AccountSession session, NoiseKeyPair identity);
}
