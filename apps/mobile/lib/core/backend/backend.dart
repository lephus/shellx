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

  /// V2-4: the machine's personal web tools.
  ToolMachine get tools;

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
  Future<void> prompt(String sid, String text);
  Future<void> answerPermission(String sid, int permission, String option);
  Future<void> answerAsk(String sid, int ask, ElicitationResponse response);
  Future<void> cancel(String sid);
  Future<void> forceStop(String sid);
  Future<void> unqueue(String sid, int queued);

  /// A new session; its sid.
  Future<String> open(String agent, String folder);
}

/// App-side view of one open tool page ([ToolSession] in `shellx_client`, V2-4): while it is
/// started, the phone serves the tool on its own loopback (only to the page's web view: E11) and
/// carries every request to the computer. Never logs what it carries.
abstract interface class ToolPageSession {
  ToolPhase get phase;

  /// After every change of [phase].
  Stream<void> get changes;

  /// What the web view must do: load the entry URL, reload; what to tell the user.
  Stream<ToolPageEvent> get events;

  /// The tool's port on the computer.
  int get port;

  /// The port this phone serves it on (null while nothing is served); [alias] when it is not
  /// [port] (E3: the tool's port is taken on this phone).
  int? get servedPort;
  int? get alias;

  /// The origins this phone serves (`http://localhost:<port>`): the web view stays on them (E12).
  Set<String> get origins;

  /// Requests served since [resetRequests] (E20).
  int get requests;
  void resetRequests();

  /// Asks the computer and serves the tool.
  void start();

  /// "Về trang đầu".
  void home();

  /// The app went to the background (E13): nothing is served until [resume].
  Future<void> pause();
  void resume();

  /// The page was left: nothing is served, the computer is told.
  Future<void> close();
}

/// App-side view of a machine's tools ([MachineTools] in `shellx_client`, V2-4).
abstract interface class ToolMachine {
  /// From the computer's answer to a list of its sessions: null before the first one, false for a
  /// computer without tools for phones.
  bool? get supported;
  ToolListing? get listing;
  Stream<ToolListing> get listings;

  /// Keeps [listing] current (one switch, like [AiMachine.watch]).
  Future<void> watch();
  void unwatch();

  /// A page for [tool] that serves nothing until [ToolPageSession.start]; [texts] are the plain
  /// answers the phone's server gives itself, in the phone's language.
  ToolPageSession page(ToolInfo tool, ToolHostTexts texts);
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
