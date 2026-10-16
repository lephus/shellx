import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/machines/domain/machine_entry.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

/// A machine whose AI listing is held: the workspace's hold, and the feed of its listings.
typedef _Held = ({void Function() release, StreamSubscription<AiListing> feed});

/// What a machine's card says of its AI sessions ("✦ 2 phiên AI · 1 cần bạn").
typedef MachineAiLine = ({int sessions, int waiting});

/// V2-2b B21: the AI line of each machine on the list. While the list shows (its page is up, nothing pushed over
/// it, the app in the foreground) and the relay is connected, it holds the AI listing of the online paired
/// machines, at most [cap] of them, the one used last first (the list's own order): a channel to each (one
/// handshake), one `session.list` when the computer's AI support is not known yet — on the machine itself, not
/// its workspace, so the terminal page still shows its picker on the first visit — then the workspace's listing
/// hold (shared with the pages that show the same list). It lets every one go when the list stops showing, the
/// app leaves the foreground, the relay drops or the machine goes offline or is no longer paired. A machine that
/// cannot be reached shows no line and says nothing; pulling the list down tries it again ([refresh]).
@injectable
class MachineAiLines extends Controller {
  MachineAiLines(this._session, this._registry) {
    _relay = _session.backend.peek()?.relayStates.listen((_) => unawaited(_sync()));
  }

  /// B21: each held machine costs a handshake and listing updates while the list shows.
  static const int cap = 6;

  final SessionHolder _session;
  final WorkspaceRegistry _registry;
  StreamSubscription<RelayConnectionState>? _relay;
  final _held = <String, _Held>{};
  final _probing = <String>{};
  final _failed = <String>{};
  List<MachineEntry> _machines = const [];
  var _visible = false;
  var _foreground = true;
  var _disposed = false;
  final Signal<Map<String, AiListing>> _listings = signal(const {});

  /// The listing of [agentId] while it is held; null otherwise.
  AiListing? listing(String agentId) => _listings.value[agentId];

  /// The line of [agentId]'s card; null when there is none to show (not held, no AI window, no session).
  /// Reactive: a `Watch` that reads it follows the listing.
  MachineAiLine? line(String agentId) {
    final listing = _listings.value[agentId];
    if (listing == null || !listing.available || listing.sessions.isEmpty) return null;
    return (sessions: listing.sessions.length, waiting: listing.needsInput);
  }

  /// The machines the list shows now, in its order (online first, the one used last at the top).
  void setMachines(List<MachineEntry> machines) {
    _machines = machines;
    unawaited(_sync());
  }

  /// The list is on screen (false while a page is pushed over it, or once it is left).
  void setVisible(bool visible) {
    _visible = visible;
    unawaited(_sync());
  }

  /// The app is in the foreground (false in the background: the relay is suspended then anyway).
  void setForeground(bool foreground) {
    _foreground = foreground;
    unawaited(_sync());
  }

  /// Pull to refresh: the machines that failed are tried again. Completes when every try is over.
  Future<void> refresh() {
    _failed.clear();
    return _sync();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_relay?.cancel());
    for (final agentId in [..._held.keys]) {
      _release(agentId);
    }
    _listings.dispose();
  }

  /// The machines to hold now: none unless the list shows, the app is in the foreground and the relay connected.
  Set<String> _wanted() {
    final backend = _session.backend.peek();
    if (_disposed || backend == null || !_visible || !_foreground) return const {};
    if (backend.relayState != RelayConnectionState.connected) return const {};
    return {
      for (final machine in _machines)
        if (machine.online && machine.paired) machine.id,
    }.take(cap).toSet();
  }

  Future<void> _sync() async {
    if (_disposed) return;
    final wanted = _wanted();
    for (final agentId in [..._held.keys]) {
      if (!wanted.contains(agentId)) _release(agentId);
    }
    final backend = _session.backend.peek();
    if (backend == null) return;
    await Future.wait([
      for (final agentId in wanted)
        if (!_held.containsKey(agentId) && !_probing.contains(agentId) && !_failed.contains(agentId))
          _probe(backend, agentId),
    ]);
  }

  Future<void> _probe(ShellxBackend backend, String agentId) async {
    _probing.add(agentId);
    try {
      final machine = backend.machine(agentId);
      await machine.connect();
      // Teaches the client whether the computer has AI for phones (`ai` of `session.list.result`).
      if (machine.ai.supported == null) await machine.listSessions();
      if (machine.ai.supported != true) return; // an older computer: no line
      // The list may have stopped showing, or the machine gone, during the handshake.
      if (!_wanted().contains(agentId) || !identical(_session.backend.peek(), backend)) return;
      final workspace = _registry.forMachine(agentId);
      final release = workspace.holdAiListing();
      final feed = machine.ai.listings.listen((listing) => _put(agentId, listing));
      _held[agentId] = (release: release, feed: feed);
      final current = workspace.aiListing;
      if (current != null) _put(agentId, current);
    } catch (error) {
      // B21: a machine that cannot be reached shows nothing on the list, and says nothing.
      _failed.add(agentId);
      if (kDebugMode) debugPrint('MachineAiLines error: ${error.runtimeType}');
    } finally {
      _probing.remove(agentId);
    }
  }

  void _put(String agentId, AiListing listing) {
    if (_disposed || (!_held.containsKey(agentId) && !_probing.contains(agentId))) return;
    _listings.value = {..._listings.peek(), agentId: listing};
  }

  void _release(String agentId) {
    final held = _held.remove(agentId);
    if (held == null) return;
    held.release();
    unawaited(held.feed.cancel());
    if (_disposed) return;
    _listings.value = {..._listings.peek()}..remove(agentId);
  }
}
