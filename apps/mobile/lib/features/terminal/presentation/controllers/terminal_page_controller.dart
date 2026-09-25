import 'dart:async';

import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_tab_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';
import 'package:shellx_mobile/features/terminal/presentation/terminal_metrics.dart';

/// Why the terminal page closed itself; the machine list reacts (design "Khi có sự cố").
enum TerminalExit {
  /// HS2 `untrusted`: the pin is dropped; the list offers "Quét mã" (spec §12).
  untrusted,

  /// HS2 `proto_unsupported`: "Cần cập nhật app" (spec §12).
  updateRequired,
}

/// The terminal page of one machine (spec §9.2 #4). The tabs live in the machine's
/// [TerminalWorkspace], which outlives the page; failures show a floating notice with the spec
/// §12 text.
@injectable
class TerminalPageController extends Controller {
  TerminalPageController(@factoryParam this.agentId, this._registry, this._session, AppSettings settings)
    : _fontSize = signal(settings.fontSize.peek()) {
    final machine = workspace.machine;
    _machineState = signal(machine.state);
    _machineStates = machine.states.listen((state) => _machineState.value = state);
    final backend = _session.requireBackend;
    _relayState = signal(backend.relayState);
    _relayStates = backend.relayStates.listen((state) => _relayState.value = state);
  }

  static const Duration noticeDuration = Duration(seconds: 4);

  final String agentId;
  final WorkspaceRegistry _registry;
  final SessionHolder _session;
  final Signal<double> _fontSize;
  final Signal<bool> _busy = signal(false);
  final Signal<String?> _notice = signal(null);
  final Signal<TerminalExit?> _exit = signal(null);
  late final Signal<MachineConnectionState> _machineState;
  late final Signal<RelayConnectionState> _relayState;
  late final StreamSubscription<MachineConnectionState> _machineStates;
  late final StreamSubscription<RelayConnectionState> _relayStates;
  late final Computed<bool> _canOpen = computed(() => !_busy.value);
  Timer? _noticeTimer;
  bool _disposed = false;

  late final TerminalWorkspace workspace = _registry.forMachine(agentId);

  ShellxBackend get backend => _session.requireBackend;

  /// Font size of this page (pinch or "Aa"); the default comes from Settings (spec §9.2 #5).
  ReadonlySignal<double> get fontSize => _fontSize;

  /// A machine operation is running (progress bar, `+` disabled).
  ReadonlySignal<bool> get busy => _busy;
  ReadonlySignal<bool> get canOpen => _canOpen;

  /// The floating notice (e.g. `session_limit`); cleared after [noticeDuration].
  ReadonlySignal<String?> get notice => _notice;

  /// Set when the page must close (the machine list then shows the matching screen).
  ReadonlySignal<TerminalExit?> get exit => _exit;

  /// For the status line under the machine name.
  ReadonlySignal<MachineConnectionState> get machineState => _machineState;
  ReadonlySignal<RelayConnectionState> get relayState => _relayState;

  void setFontSize(double size) => _fontSize.value = AppSettings.clampFontSize(size);

  /// First visit: connect and `session.list`; null on later visits or on error.
  Future<List<SessionInfo>?> prepare() => _run<List<SessionInfo>?>(workspace.prepare);

  Future<void> openNew(TerminalGrid grid) => _run(() => workspace.openNew(grid));

  Future<void> attach(SessionInfo session, TerminalGrid grid) => _run(() => workspace.attach(session, grid));

  Future<void> close(TerminalTabController tab) => workspace.close(tab);

  /// "Mở phiên mới" on an ended tab: the new session takes the ended tab's place.
  Future<void> replaceWithNew(TerminalTabController ended, TerminalGrid grid) async {
    final opened = await _run(() => workspace.openNew(grid));
    if (opened != null) await workspace.close(ended);
  }

  void sendKey(ExtraKey key) {
    final tab = workspace.activeTab.peek();
    if (tab != null) workspace.extraKeys.sendKey(key, tab.terminal.peek());
  }

  /// Bracketed when the program enabled it, CR line breaks (spec §9.4).
  void paste(String text) {
    if (text.isEmpty) return;
    workspace.activeTab.peek()?.terminal.peek().paste(text);
  }

  void reconnectReplaced() => unawaited(_session.reconnectReplaced());

  void dismissNotice() {
    _noticeTimer?.cancel();
    if (!_disposed) _notice.value = null;
  }

  /// Runs a machine operation with the progress bar; failures become the notice.
  Future<T?> _run<T>(Future<T> Function() action) async {
    T? result;
    _busy.value = true;
    await guard(() async {
      try {
        result = await action();
      } catch (error) {
        await _handleFailure(error);
        rethrow;
      }
    }, showError: false);
    if (!_disposed) _busy.value = false;
    return result;
  }

  Future<void> _handleFailure(Object error) async {
    final failure = switch (error) {
      MachineFailed(:final failure) || MachineConnectionException(:final failure) => failure,
      _ => null,
    };
    if (failure == MachineConnectionFailure.untrusted) {
      // Spec §12: the machine no longer trusts this phone → drop the pinned key.
      _registry.remove(agentId);
      try {
        await _session.requireBackend.unpair(agentId);
      } on Object {
        // The pin is gone locally even if the relay call failed.
      }
      if (!_disposed) _exit.value = TerminalExit.untrusted;
      return;
    }
    if (failure == MachineConnectionFailure.protocolUnsupported) {
      if (!_disposed) _exit.value = TerminalExit.updateRequired;
      return;
    }
    _show(errorFactory.fromException(error).title);
  }

  void _show(String text) {
    if (_disposed) return;
    _noticeTimer?.cancel();
    _notice.value = text;
    _noticeTimer = Timer(noticeDuration, dismissNotice);
  }

  void dispose() {
    _disposed = true;
    _noticeTimer?.cancel();
    unawaited(_machineStates.cancel());
    unawaited(_relayStates.cancel());
    _canOpen.dispose();
    _fontSize.dispose();
    _busy.dispose();
    _notice.dispose();
    _exit.dispose();
    _machineState.dispose();
    _relayState.dispose();
  }
}
