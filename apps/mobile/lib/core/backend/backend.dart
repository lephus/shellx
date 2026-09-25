import 'dart:typed_data';

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

  /// [MachineIdle] → [MachineConnecting] → [MachineReady], or
  /// [MachineFailed]; back to [MachineIdle] when the channel is lost (relay
  /// down, machine offline, [ShellxBackend.suspend]).
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
  /// does not answer in time.
  Future<List<SessionInfo>> listSessions();

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

  /// Removes the tab and ends its [TabHandle.events]. An attached tab also
  /// closes its session on the machine: at once, or — without a channel —
  /// right after the next channel is installed. An ended tab is only removed
  /// here.
  Future<void> closeTab(int id);
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
  /// pinned; its channel is dropped and its tabs re-attach.
  Future<void> pair(PairingUri uri);

  /// The same [MachineSession] per [agentId] while it stays pinned. Throws
  /// [StateError] when [agentId] is not pinned — never paired, unpaired, or
  /// forgotten after an `untrusted` handshake.
  MachineSession machine(String agentId);

  /// Spec §5.5: drop the machine's channel and tabs (its sessions keep
  /// running on the computer), forget the pin, then delete the pairing
  /// record (3 attempts for network/5xx errors). May still throw
  /// [ApiException] after the pin is gone: show it and offer a retry —
  /// calling this again only repeats the delete. A `pairing_removed` event
  /// from the relay never unpairs; only an `untrusted` handshake forgets a pin.
  Future<void> unpair(String agentId);

  /// Stops the client and the relay connection for good (sign-out).
  Future<void> dispose();
}

/// Builds the backend of a signed-in account; `ClientBackendFactory` in production, a fake in tests.
abstract interface class BackendFactory {
  Future<ShellxBackend> create(AccountSession session, NoiseKeyPair identity);
}
