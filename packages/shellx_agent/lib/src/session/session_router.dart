import 'dart:async';

import 'package:shellx_core/shellx_core.dart';

import '../term/desktop_session_manager.dart';
import 'agent_sessions.dart';
import 'session_manager.dart';

/// Shell sessions and desktop terminals behind one [AgentSessions] (spec
/// §7.7). Messages go to the manager that owns their session id (both draw
/// ids from one allocator); `session.list` is answered here.
///
/// A phone may attach a desktop terminal only after it sent
/// `session.list {desktop: true}` at least once since the agent started:
/// an old app never gets messages its decoder rejects (spec §7.9). The flag
/// survives channel losses (tabs re-attach without listing) and is dropped
/// on revoke.
///
/// A close from the host ends shell sessions; a phone's close ends only the
/// shell sessions a phone opened (one opened on this computer only loses
/// the phone, A1 D4). Desktop terminals only ever lose their phones (spec
/// §7.2).
final class SessionRouter implements AgentSessions {
  SessionRouter({
    required SessionManager shells,
    required DesktopSessionManager desktop,
    required bool Function() desktopSharing,
  }) : _shells = shells,
       _desktop = desktop,
       _desktopSharing = desktopSharing {
    shells.receivesDriver = _receivesDriver;
    _subscriptions.addAll([
      shells.outbound.listen(_outbound.add),
      desktop.outbound.listen(_outbound.add),
      shells.changes.listen(_changes.add),
      desktop.changes.listen(_changes.add),
    ]);
  }

  final _subscriptions = <StreamSubscription<Object?>>[];

  /// `session.driver` is only for phones that listed with `desktop: true`
  /// (their decoder knows it, spec §7.9) — for shell sessions too (A1 D6).
  bool _receivesDriver(String mobileId) => _desktopPhones.contains(mobileId);

  final SessionManager _shells;
  final DesktopSessionManager _desktop;
  final bool Function() _desktopSharing;
  final _outbound = StreamController<OutboundMessage>.broadcast(sync: true);
  final _changes = StreamController<void>.broadcast();
  final _desktopPhones = <String>{};

  /// Messages to deliver, in order. A synchronous broadcast stream, fed
  /// from the synchronous `outbound` streams of both managers: a listener
  /// must not call back into the router or either manager synchronously
  /// from its callback (adding to a manager's stream while one of its
  /// listeners runs throws "Cannot fire new event"). The router's own
  /// listeners only forward.
  @override
  Stream<OutboundMessage> get outbound => _outbound.stream;

  @override
  Stream<SessionOpenedEvent> get opened => _shells.opened;

  Stream<void> get changes => _changes.stream;

  @override
  Future<void> handle(String mobileId, AppMessage message) async {
    switch (message) {
      case SessionList(:final desktop):
        if (desktop) _desktopPhones.add(mobileId);
        _send(
          mobileId,
          SessionListResult([
            ..._shells.sessionInfos,
            if (desktop) ..._desktop.sessionInfos,
          ], desktopSharing: desktop ? _desktopSharing() : null),
        );
      case SessionAttach(:final id, :final cols, :final rows, :final lastSeq)
          when _desktop.owns(id):
        if (_desktopPhones.contains(mobileId)) {
          _desktop.attach(mobileId, id, cols, rows, lastSeq);
        } else {
          _send(
            mobileId,
            ErrorMessage(
              code: AppErrorCode.sessionNotFound,
              message: 'Session $id not found',
              id: id,
            ),
          );
        }
      case InputMessage(:final id, :final data) when _desktop.owns(id):
        _desktop.input(mobileId, id, data);
      case ResizeMessage(:final id, :final cols, :final rows)
          when _desktop.owns(id):
        _desktop.resize(mobileId, id, cols, rows);
      case AckMessage(:final id, :final seq) when _desktop.owns(id):
        _desktop.ack(mobileId, id, seq);
      case SessionClose(:final id) when _desktop.owns(id):
        _desktop.detach(mobileId, id);
      case SessionDetach(:final id):
        _desktop.detach(mobileId, id); // Unknown or shell id: ignored.
      default:
        await _shells.handle(mobileId, message);
    }
  }

  @override
  void mobileDisconnected(String mobileId) {
    _shells.mobileDisconnected(mobileId);
    _desktop.mobileDisconnected(mobileId);
  }

  @override
  void closeSessionsAttachedTo(String mobileId) {
    _desktopPhones.remove(mobileId);
    _shells.closeSessionsAttachedTo(mobileId);
    _desktop.disconnectPhonesAttachedTo(mobileId);
  }

  /// Tray: a shell session is closed; a desktop terminal only loses its
  /// phone.
  void closeSession(int id) {
    if (_desktop.owns(id)) {
      _desktop.disconnectPhone(id);
    } else {
      _shells.closeSession(id);
    }
  }

  /// Quit: shells end, desktop terminals only lose their phones.
  void closeAll() {
    _shells.closeAll();
    _desktop.disconnectAllPhones();
  }

  /// The runtime stops (A1 D7): every phone is let go, nothing is killed.
  void disconnectAllPhones() {
    _shells.disconnectAllPhones();
    _desktop.disconnectAllPhones();
  }

  /// The runtime is gone; the shell sessions live on (A1 D7) and must not
  /// keep forwarding into this router or asking its phone set.
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    if (_shells.receivesDriver == _receivesDriver) {
      _shells.receivesDriver = (_) => false;
    }
  }

  void _send(String mobileId, AppMessage message) =>
      _outbound.add(OutboundMessage(mobileId, message));
}
