import 'dart:async';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import '../session/agent_sessions.dart';
import '../session/session_stream.dart';
import 'osc_title.dart';
import 'term_link.dart';
import 'term_messages.dart';

/// Read-only view of a desktop terminal for the tray (P4).
final class DesktopSessionSummary {
  const DesktopSessionSummary({
    required this.id,
    required this.index,
    required this.app,
    required this.title,
    required this.shell,
    required this.createdAt,
    required this.attachedMobileId,
    required this.connected,
  });
  final int id, index;
  final String app, title, shell;
  final DateTime createdAt;
  final String? attachedMobileId;

  /// False while waiting (≤ 30 s) for `shellx-term` to reconnect.
  final bool connected;
}

/// A phone attached to a desktop terminal (for P4's desktop notification).
final class DesktopPhoneAttached {
  const DesktopPhoneAttached(this.mobileId, this.sessionId);
  final String mobileId;
  final int sessionId;
}

enum _Driver { desktop, phone }

const int _minDimension = 1;
const int _maxDimension = 1000;
int _clamp(int value) => value.clamp(_minDimension, _maxDimension);

final class _Session {
  _Session({
    required this.id,
    required this.index,
    required this.info,
    required this.stream,
  });

  final int id;
  final int index;
  TermInfo info;
  final SessionStream stream;

  TermLink? link;
  StreamSubscription<TermToAgent>? subscription;

  /// Collects a snapshot until `last: true`; null when none is arriving.
  BytesBuilder? snapshot;

  /// The current link's snapshot is complete: `out`, `local`, `exit` and
  /// phone input are accepted.
  bool live = false;

  Timer? graceTimer;
  Timer? drainTimer;
  final titles = OscTitleParser();
  String title = '';
  _Driver driver = _Driver.desktop;

  /// The attached phone's size; 0 before any phone attached.
  int cols = 0, rows = 0;

  /// `exit` received: hidden, not attachable, draining to the phone.
  bool closing = false;
  int exitCode = -1;

  String? get attachedMobileId => stream.attachedMobileId;
}

/// Every desktop terminal shared through `shellx-term` (spec §7.1). Each
/// authenticated [TermLink] becomes a `desktop` session; a window that
/// reconnects (same `term_id`) within [reconnectGrace] keeps its session.
///
/// This class can detach phones and drop links, but it has **no way to end
/// a terminal** (spec §7.2, T13): the window belongs to the user.
final class DesktopSessionManager {
  DesktopSessionManager({
    required int Function() nextId,
    int maxSessions = 32,
    int bufferCapacity = 256 * 1024,
    int sendWindow = 256 * 1024,
    Duration reconnectGrace = const Duration(seconds: 30),
    Duration drainTimeout = const Duration(seconds: 30),
  }) : _nextId = nextId,
       _maxSessions = maxSessions,
       _bufferCapacity = bufferCapacity,
       _sendWindow = sendWindow,
       _grace = reconnectGrace,
       _drainTimeout = drainTimeout;

  final int Function() _nextId;
  final int _maxSessions;
  final int _bufferCapacity;
  final int _sendWindow;
  final Duration _grace;
  final Duration _drainTimeout;

  final _outbound = StreamController<OutboundMessage>.broadcast(sync: true);
  final _changes = StreamController<void>.broadcast();
  final _attached = StreamController<DesktopPhoneAttached>.broadcast();
  final _sessions = <int, _Session>{};
  final _byTerm = <String, _Session>{};

  /// Messages to deliver, in order. A synchronous broadcast stream, like
  /// `SessionManager`'s and `SessionRouter`'s: a listener must not call
  /// back into this manager synchronously from its callback (adding to the
  /// stream while one of its listeners runs throws "Cannot fire new
  /// event").
  Stream<OutboundMessage> get outbound => _outbound.stream;
  Stream<void> get changes => _changes.stream;
  Stream<DesktopPhoneAttached> get phoneAttached => _attached.stream;

  List<DesktopSessionSummary> get sessions => [
    for (final s in _sessions.values)
      if (!s.closing)
        DesktopSessionSummary(
          id: s.id,
          index: s.index,
          app: s.info.app,
          title: s.title,
          shell: s.info.shell,
          createdAt: DateTime.fromMillisecondsSinceEpoch(s.info.startedAt),
          attachedMobileId: s.attachedMobileId,
          connected: s.link != null,
        ),
  ];

  List<SessionInfo> get sessionInfos => [
    for (final s in _sessions.values)
      if (!s.closing)
        SessionInfo(
          id: s.id,
          index: s.index,
          shell: s.info.shell,
          createdAt: s.info.startedAt,
          attached: s.attachedMobileId != null,
          kind: SessionKind.desktop,
          app: s.info.app,
          title: s.title,
        ),
  ];

  bool owns(int id) => _sessions.containsKey(id);

  /// `TermServer`'s check at `auth` (spec §7.8 step 3): a window that
  /// already has a session (it is reconnecting) is always admitted.
  bool canAdmit(TermInfo info) =>
      _byTerm.containsKey(info.key) || _sessions.length < _maxSessions;

  void addLink(TermLink link) {
    var session = _byTerm[link.info.key];
    if (session == null) {
      if (_sessions.length >= _maxSessions) {
        link.close();
        return;
      }
      final id = _nextId();
      session = _Session(
        id: id,
        index: _lowestFreeIndex(),
        info: link.info,
        stream: SessionStream(
          id: id,
          capacity: _bufferCapacity,
          sendWindow: _sendWindow,
          send: _send,
        ),
      );
      _sessions[id] = session;
      _byTerm[link.info.key] = session;
    } else {
      _dropLink(session); // A half-open old connection loses (spec §7.8).
      session.graceTimer?.cancel();
      session.graceTimer = null;
      session.info = link.info;
    }
    final s = session;
    s.link = link;
    s.live = false;
    s.snapshot = BytesBuilder(copy: false);
    s.subscription = link.messages.listen(
      (message) => _onMessage(s, link, message),
      onDone: () => _linkLost(s, link),
    );
    _changes.add(null);
  }

  // ---- phone side -------------------------------------------------------

  void attach(String mobileId, int id, int cols, int rows, int lastSeq) {
    final s = _sessions[id];
    if (s == null || s.closing) {
      _notFound(mobileId, id);
      return;
    }
    final previous = s.stream.attach(mobileId, lastSeq);
    _drive(s, _clamp(cols), _clamp(rows));
    _send(mobileId, SessionAttached(id: id));
    if (previous != mobileId) {
      _changes.add(null);
      _attached.add(DesktopPhoneAttached(mobileId, id));
    }
  }

  /// Dropped while the terminal is reconnecting (spec §7.8: not queued).
  void input(String mobileId, int id, Uint8List data) {
    final s = _attachedTo(mobileId, id);
    if (s == null || !s.live) return;
    if (s.driver == _Driver.desktop) _drive(s, s.cols, s.rows);
    s.link!.send(AgentIn(data: data));
  }

  void resize(String mobileId, int id, int cols, int rows) {
    final s = _attachedTo(mobileId, id);
    if (s != null) _drive(s, _clamp(cols), _clamp(rows));
  }

  void ack(String mobileId, int id, int seq) {
    final s = _attachedTo(mobileId, id);
    if (s == null) return;
    s.stream.ack(seq);
    _pump(s);
  }

  /// `session.detach` (or `session.close`) from the phone: it leaves, the
  /// terminal stays. Never answered.
  void detach(String mobileId, int id) {
    final s = _attachedTo(mobileId, id);
    if (s == null) return;
    _phoneLeft(s);
    _changes.add(null);
  }

  void mobileDisconnected(String mobileId) {
    var changed = false;
    for (final s in _sessions.values.toList()) {
      if (s.attachedMobileId != mobileId) continue;
      _phoneLeft(s);
      changed = true;
    }
    if (changed) _changes.add(null);
  }

  // ---- host side --------------------------------------------------------

  /// Tray "Disconnect phone", or the phone's access going away: the phone
  /// gets `session.detached {closed_by_host}`; the terminal keeps running.
  /// A session draining after its terminal exited is left alone (like
  /// `SessionManager.closeSession`): the drain finishes and the phone gets
  /// `session.exited`.
  void disconnectPhone(int id) {
    final s = _sessions[id];
    final mobileId = s?.attachedMobileId;
    if (s == null || s.closing || mobileId == null) return;
    _send(mobileId, SessionDetached(id: id, reason: DetachReason.closedByHost));
    _phoneLeft(s);
    _changes.add(null);
  }

  void disconnectPhonesAttachedTo(String mobileId) {
    for (final s in _sessions.values.toList()) {
      if (s.attachedMobileId == mobileId) disconnectPhone(s.id);
    }
  }

  void disconnectAllPhones() {
    for (final id in _sessions.keys.toList()) {
      disconnectPhone(id);
    }
  }

  /// Sharing switched off (`TerminalSharing.stop`): every session goes now,
  /// without the 30 s wait; attached phones get `closed_by_host`; links
  /// close. Windows keep running and keep retrying (spec §7.9).
  void clear() {
    for (final s in _sessions.values.toList()) {
      final mobileId = s.attachedMobileId;
      if (mobileId != null) {
        _send(
          mobileId,
          SessionDetached(id: s.id, reason: DetachReason.closedByHost),
        );
      }
      s.stream.attachedMobileId = null;
      _remove(s);
    }
  }

  // ---- link side --------------------------------------------------------

  void _onMessage(_Session s, TermLink link, TermToAgent message) {
    if (!identical(s.link, link)) return;
    switch (message) {
      case TermSnapshot(:final data, :final last):
        final builder = s.snapshot;
        if (builder == null || builder.length + data.length > _bufferCapacity) {
          return _protocolError(s);
        }
        builder.add(data);
        if (!last) return;
        final bytes = builder.takeBytes();
        s.snapshot = null;
        s.live = true;
        s.stream.restartWith(bytes);
        s.titles.reset();
        final title = s.titles.feed(bytes);
        if (title != null) s.title = title;
        _pump(s);
        if (s.attachedMobileId != null && s.driver == _Driver.phone) {
          // shellx-term went back to its window size when the link dropped.
          link.send(AgentResize(cols: s.cols, rows: s.rows));
        }
        _changes.add(null);
      case TermOut(:final data):
        if (!s.live) return _protocolError(s);
        s.stream.append(data);
        final title = s.titles.feed(data);
        if (title != null && title != s.title) {
          s.title = title;
          _changes.add(null);
        }
        _pump(s);
      case TermLocal():
        if (!s.live) return _protocolError(s);
        s.driver = _Driver.desktop;
        final mobileId = s.attachedMobileId;
        if (mobileId != null) {
          _send(mobileId, SessionDriver(id: s.id, by: DriverSide.desktop));
        }
      case TermExit(:final code):
        if (!s.live) return _protocolError(s);
        _exited(s, code);
      case TermSize():
        break; // The PTY follows the driver; nothing to do (spec §5.5).
      case TermHello() || TermAuth():
        _protocolError(s);
    }
  }

  void _linkLost(_Session s, TermLink link) {
    if (!identical(s.link, link)) return;
    s.subscription = null;
    s.link = null;
    if (s.closing) return;
    _startGrace(s);
    _changes.add(null);
  }

  void _protocolError(_Session s) {
    _dropLink(s);
    _startGrace(s);
    _changes.add(null);
  }

  void _startGrace(_Session s) {
    s.live = false;
    s.snapshot = null;
    s.graceTimer?.cancel();
    s.graceTimer = Timer(_grace, () {
      if (!identical(_sessions[s.id], s)) return;
      final mobileId = s.attachedMobileId;
      _remove(s);
      if (mobileId != null) {
        _send(
          mobileId,
          SessionDetached(id: s.id, reason: DetachReason.terminalGone),
        );
      }
    });
  }

  void _exited(_Session s, int code) {
    s.closing = true;
    s.exitCode = code;
    if (identical(_byTerm[s.info.key], s)) _byTerm.remove(s.info.key);
    _dropLink(s);
    _pump(s); // may already finish (and remove) the session.
    if (!identical(_sessions[s.id], s)) return;
    if (s.attachedMobileId == null) {
      _finish(s);
      return;
    }
    s.drainTimer = Timer(_drainTimeout, () => _finish(s));
    _changes.add(null);
  }

  void _finish(_Session s) {
    if (!identical(_sessions[s.id], s)) return;
    final mobileId = s.attachedMobileId;
    _remove(s);
    if (mobileId != null) {
      _send(mobileId, SessionExited(id: s.id, exitCode: s.exitCode));
    }
  }

  void _remove(_Session s) {
    s.graceTimer?.cancel();
    s.drainTimer?.cancel();
    _dropLink(s);
    _sessions.remove(s.id);
    if (identical(_byTerm[s.info.key], s)) _byTerm.remove(s.info.key);
    _changes.add(null);
  }

  /// Without a link nothing is live: phone input and resizes are dropped
  /// (also while an exited session drains to the phone).
  void _dropLink(_Session s) {
    s.live = false;
    unawaited(s.subscription?.cancel());
    s.subscription = null;
    s.link?.close();
    s.link = null;
  }

  // ---- helpers ----------------------------------------------------------

  /// The phone drives: tell `shellx-term` its size when it was not driving
  /// or the size changed (spec §7.3). While reconnecting, the size is kept
  /// and sent after the next snapshot.
  void _drive(_Session s, int cols, int rows) {
    final mobileId = s.attachedMobileId;
    if (mobileId == null) return;
    final changed = cols != s.cols || rows != s.rows;
    if (!changed && s.driver == _Driver.phone) return;
    s.cols = cols;
    s.rows = rows;
    s.driver = _Driver.phone;
    if (s.live) s.link!.send(AgentResize(cols: cols, rows: rows));
    _send(mobileId, SessionDriver(id: s.id, by: DriverSide.phone));
  }

  void _phoneLeft(_Session s) {
    s.stream.attachedMobileId = null;
    if (s.driver == _Driver.phone) {
      s.driver = _Driver.desktop;
      if (s.live) s.link!.send(const AgentLocalSize());
    }
    if (s.closing) _finish(s);
  }

  void _pump(_Session s) {
    if (s.attachedMobileId == null) return;
    s.stream.pump();
    if (s.closing && s.stream.drained) _finish(s);
  }

  _Session? _attachedTo(String mobileId, int id) {
    final s = _sessions[id];
    return s != null && s.attachedMobileId == mobileId ? s : null;
  }

  int _lowestFreeIndex() {
    final used = {for (final s in _sessions.values) s.index};
    var index = 1;
    while (used.contains(index)) {
      index++;
    }
    return index;
  }

  void _notFound(String mobileId, int id) => _send(
    mobileId,
    ErrorMessage(
      code: AppErrorCode.sessionNotFound,
      message: 'Session $id not found',
      id: id,
    ),
  );

  void _send(String mobileId, AppMessage message) =>
      _outbound.add(OutboundMessage(mobileId, message));
}
