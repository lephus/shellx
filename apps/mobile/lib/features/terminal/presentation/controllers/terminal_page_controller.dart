import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_tab_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';
import 'package:shellx_mobile/features/terminal/presentation/terminal_metrics.dart';

/// Why the terminal page closed itself; the machine list reacts (design "Khi có sự cố").
enum TerminalExit {
  /// HS2 `untrusted`, or the machine is no longer pinned: the pin is gone; the list offers
  /// "Quét mã" (spec §12).
  untrusted,

  /// HS2 `proto_unsupported`: "Cần cập nhật app" (spec §12).
  updateRequired,
}

/// The terminal page of one machine (spec §9.2 #4). The tabs live in the machine's
/// [TerminalWorkspace], which outlives the page; failures show a floating notice with the spec
/// §12 text.
///
/// Once the page is leaving ([closing]) the workspace may already be disposed, so the controller
/// writes none of the signals the page's widgets read, and the page renders nothing of the
/// workspace (signals_core 6.3.1 prints a warning and returns a stale value when a disposed signal
/// is read, and a mounted `Watch` re-runs its builder as soon as a signal it read changes).
@injectable
class TerminalPageController extends Controller {
  TerminalPageController(@factoryParam this.agentId, this._registry, this._session, AppSettings settings)
    : _backend = _session.backend.peek(),
      _fontSize = signal(settings.fontSize.peek()) {
    final backend = _backend;
    _relayState = signal(backend?.relayState ?? RelayConnectionState.stopped);
    _relayStates = backend?.relayStates.listen(_onRelayState);
    // A sign-out (or another account) disposes every workspace of this backend ([WorkspaceRegistry]).
    _stopSessionWatch = _session.backend.subscribe((current) {
      if (!identical(current, backend)) _startClosing();
    });
    if (backend == null) {
      // Signed out before the page was built (a sign-out racing the tap on a machine): nothing to
      // connect to, like a machine that is not pinned. No exit: the session enforcer takes every
      // page to the login screen.
      _machineState = signal(const MachineIdle());
      _startClosing();
      return;
    }
    final TerminalWorkspace workspace;
    try {
      workspace = _registry.forMachine(agentId);
    } on StateError {
      // Not pinned any more — forgotten by an `untrusted` handshake the client ran on its own
      // (relay back, app resumed) while no terminal page was open. Nothing to connect to: leave
      // as untrusted, so the machine list offers to pair again.
      _machineState = signal(const MachineFailed(MachineConnectionFailure.untrusted));
      _startClosing();
      _exit.value = TerminalExit.untrusted;
      return;
    }
    _workspace = workspace;
    _machineState = signal(workspace.machine.state);
    _machineStates = workspace.machine.states.listen(_onMachineState);
  }

  static const Duration noticeDuration = Duration(seconds: 4);

  final String agentId;
  final WorkspaceRegistry _registry;
  final SessionHolder _session;

  final ShellxBackend? _backend;
  final Signal<double> _fontSize;
  final Signal<bool> _busy = signal(false);
  final Signal<String?> _notice = signal(null);
  final Signal<TerminalExit?> _exit = signal(null);
  final Signal<bool> _closing = signal(false);
  late final Signal<MachineConnectionState> _machineState;
  late final Signal<RelayConnectionState> _relayState;
  StreamSubscription<MachineConnectionState>? _machineStates;
  StreamSubscription<RelayConnectionState>? _relayStates;
  late final void Function() _stopSessionWatch;
  late final Computed<bool> _canOpen = computed(() => !_busy.value);
  TerminalWorkspace? _workspace;
  Timer? _noticeTimer;
  int _running = 0;
  bool _disposed = false;

  /// Set by the first untrusted/proto_unsupported failure, however it was found.
  bool _machineFailureHandled = false;

  /// Leaving or disposed: no more signal writes, no more machine operations.
  bool _closed = false;

  /// The page is leaving because the workspace is being dropped ([closing]); unlike [_closed],
  /// not set when the page is merely left: the workspace outlives the page.
  bool _dropped = false;

  /// The backend of the account this page was opened for. Throws [StateError] when the page was
  /// built signed out ([closing] is then true from the start).
  ShellxBackend get backend => _backend ?? (throw StateError('Not signed in'));

  /// The machine's tabs. Throws [StateError] when the machine was not pinned (or nobody was signed
  /// in) when the page opened ([closing] is then true from the start).
  TerminalWorkspace get workspace => _workspace ?? (throw StateError('The machine is not pinned'));

  /// Font size of this page (pinch or "Aa"); the default comes from Settings (spec §9.2 #5).
  ReadonlySignal<double> get fontSize => _fontSize;

  /// A machine operation is running (progress bar, `+` disabled).
  ReadonlySignal<bool> get busy => _busy;
  ReadonlySignal<bool> get canOpen => _canOpen;

  /// The floating notice (e.g. `session_limit`); cleared after [noticeDuration].
  ReadonlySignal<String?> get notice => _notice;

  /// Set when the page must close (the machine list then shows the matching screen).
  ReadonlySignal<TerminalExit?> get exit => _exit;

  /// The page is leaving (untrusted, proto_unsupported, not pinned, signed out) and must not
  /// read [workspace] any more: it may already be disposed.
  ReadonlySignal<bool> get closing => _closing;

  /// For the status line under the machine name.
  ReadonlySignal<MachineConnectionState> get machineState => _machineState;
  ReadonlySignal<RelayConnectionState> get relayState => _relayState;

  void setFontSize(double size) {
    if (_closed) return;
    _fontSize.value = AppSettings.clampFontSize(size);
  }

  /// First visit: connect and `session.list`; null on later visits or on error.
  Future<List<SessionInfo>?> prepare() => _run<List<SessionInfo>?>(() => workspace.prepare());

  Future<void> openNew(TerminalGrid grid) => _run(() => workspace.openNew(grid));

  Future<void> attach(SessionInfo session, TerminalGrid grid) => _run(() => workspace.attach(session, grid));

  /// "Gắn lại" on a taken-over tab. `reattach()` rethrows everything but `session_not_found`
  /// (e.g. `MachineConnectionException(agentOffline)`, thrown at once without a channel): those
  /// become the notice like any other request.
  Future<void> reattach(TerminalTabController tab) => _run(tab.reattach);

  Future<void> close(TerminalTabController tab) async {
    if (_closed) return;
    await workspace.close(tab);
  }

  /// "Mở phiên mới" on an ended or failed tab: the new session takes that tab's place. The
  /// workspace outlives the page, so the ended tab is removed even when the user left the page
  /// while the session was opening; only a dropped workspace is left alone.
  Future<void> replaceWithNew(TerminalTabController ended, TerminalGrid grid) async {
    final opened = await _run(() => workspace.openNew(grid));
    if (opened != null && !_dropped) await workspace.close(ended);
  }

  void sendKey(ExtraKey key) {
    if (_closed) return;
    final tab = workspace.activeTab.peek();
    if (tab != null) workspace.extraKeys.sendKey(key, tab.terminal.peek());
  }

  /// Bracketed when the program enabled it, CR line breaks (spec §9.4).
  void paste(String text) {
    if (text.isEmpty || _closed) return;
    workspace.activeTab.peek()?.terminal.peek().paste(text);
  }

  /// After 4001; a failure to restart (e.g. loading the pins) becomes the notice.
  void reconnectReplaced() => unawaited(_run(_session.reconnectReplaced));

  void dismissNotice() {
    _noticeTimer?.cancel();
    if (!_closed) _notice.value = null;
  }

  void _onRelayState(RelayConnectionState state) {
    if (!_disposed) _relayState.value = state;
  }

  /// The client re-handshakes on its own (relay back, app resumed); an `untrusted` or
  /// `proto_unsupported` found that way arrives only here, never through [_run].
  void _onMachineState(MachineConnectionState state) {
    if (_disposed) return;
    _machineState.value = state;
    if (state is! MachineFailed) return;
    // A stream callback: nothing may escape it as an unhandled error.
    try {
      _onMachineFailure(state.failure);
    } catch (error) {
      if (kDebugMode) debugPrint('TerminalPageController machine failure: ${error.runtimeType}');
    }
  }

  /// Runs a machine operation with the progress bar; failures become the notice.
  Future<T?> _run<T>(Future<T> Function() action) async {
    if (_closed) return null;
    T? result;
    _setBusy(++_running);
    await guard(() async {
      try {
        result = await action();
      } catch (error) {
        await _handleFailure(error);
        rethrow;
      }
    }, showError: false);
    _setBusy(--_running);
    return result;
  }

  void _setBusy(int running) {
    if (!_closed) _busy.value = running > 0;
  }

  Future<void> _handleFailure(Object error) async {
    final failure = switch (error) {
      MachineFailed(:final failure) || MachineConnectionException(:final failure) => failure,
      _ => null,
    };
    if (failure != null && _onMachineFailure(failure)) return;
    if (_closed) return; // Leaving: a failure of a request still in flight says nothing new.
    _show(errorFactory.fromException(error).title);
  }

  /// Spec §12: `untrusted` → the workspace is dropped and the page leaves with
  /// [TerminalExit.untrusted]; `proto_unsupported` → it leaves with [TerminalExit.updateRequired].
  /// Handled once, whichever way it arrives first (a request can meet the failure while the
  /// same failure also arrives on the machine's states). True when [failure] is one of these two.
  ///
  /// The machine is not unpaired from here: the agent already dropped its trust, and the client
  /// already forgot the pin and failed the machine. A DELETE of the pairing (retried on a slow
  /// network) could land after the user paired again and delete the new pairing.
  bool _onMachineFailure(MachineConnectionFailure failure) {
    final untrusted = failure == MachineConnectionFailure.untrusted;
    if (!untrusted && failure != MachineConnectionFailure.protocolUnsupported) return false;
    if (_machineFailureHandled) return true;
    _machineFailureHandled = true;
    // Before the workspace is disposed: from here on nothing on the page reads it.
    _startClosing();
    try {
      // The machine-level failure wins over the tabs' own `session_not_found` (spec §12).
      if (untrusted) _registry.remove(agentId);
    } finally {
      // The page leaves even if dropping the workspace failed.
      if (!_disposed) _exit.value = untrusted ? TerminalExit.untrusted : TerminalExit.updateRequired;
    }
    return true;
  }

  void _startClosing() {
    _dropped = true;
    if (_closed) return;
    _closed = true;
    _noticeTimer?.cancel();
    _closing.value = true;
  }

  void _show(String text) {
    if (_closed) return;
    _noticeTimer?.cancel();
    _notice.value = text;
    _noticeTimer = Timer(noticeDuration, dismissNotice);
  }

  void dispose() {
    _disposed = true;
    _closed = true;
    _noticeTimer?.cancel();
    _stopSessionWatch();
    // Cancelling takes effect at once; the futures only report cleanup (never awaited: fake_async).
    unawaited(_machineStates?.cancel());
    unawaited(_relayStates?.cancel());
    _canOpen.dispose();
    _fontSize.dispose();
    _busy.dispose();
    _notice.dispose();
    _exit.dispose();
    _closing.dispose();
    _machineState.dispose();
    _relayState.dispose();
  }
}
