import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import '../pty/pty.dart';
import '../pty/session_environment.dart';
import '../pty/shell_resolver.dart';
import 'ring_buffer.dart';

/// An application message the agent must deliver to one phone.
final class OutboundMessage {
  const OutboundMessage(this.mobileId, this.message);
  final String mobileId;
  final AppMessage message;
}

/// Read-only view of a session for the tray menu.
final class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.index,
    required this.shell,
    required this.createdAt,
    required this.attachedMobileId,
  });
  final int id, index;
  final String shell;
  final DateTime createdAt;
  final String? attachedMobileId;
}

/// Emitted when a phone opens a new session (desktop notification).
final class SessionOpenedEvent {
  const SessionOpenedEvent(this.mobileId, this.sessionId);
  final String mobileId;
  final int sessionId;
}

const int _minDimension = 1;
const int _maxDimension = 1000;

/// Session ids start at a random value in [1, 2^31) (spec §6.4).
const int _idUpperBound = 1 << 31;
const Duration _outputDrainGrace = Duration(seconds: 2);

int _clampDimension(int value) => value.clamp(_minDimension, _maxDimension);

final class _Session {
  _Session({
    required this.id,
    required this.index,
    required this.shell,
    required this.createdAt,
    required this.pty,
    required this.buffer,
    required this.cols,
    required this.rows,
    required this.attachedMobileId,
  });

  final int id;
  final int index;
  final String shell;
  final DateTime createdAt;
  final Pty pty;
  final RingBuffer buffer;
  int cols;
  int rows;
  String? attachedMobileId;

  /// Phone that still gets `session.exited` after a `closed_by_host` detach.
  String? exitRecipient;

  /// Next stream position to send to the attached phone.
  int sent = 0;

  /// Highest position acknowledged by the attached phone.
  int acked = 0;

  StreamSubscription<Uint8List>? output;
}

/// Owns every terminal session of the agent (spec §6.5 and §7).
///
/// Session ids start at a random value in [1, 2^31) chosen per instance
/// ([random] defaults to `Random.secure()`) and then increase by one, so a
/// phone re-attaching after an agent restart cannot land on a new session
/// that reuses its old id (spec §6.4). `index` is still 1..n.
final class SessionManager {
  SessionManager({
    required PtyFactory ptyFactory,
    required ShellResolver shellResolver,
    required String homeDirectory,
    required Map<String, String> baseEnvironment,
    int maxSessions = 10,
    int bufferCapacity = 256 * 1024,
    int sendWindow = 256 * 1024,
    Random? random,
  }) : _ptyFactory = ptyFactory,
       _shellResolver = shellResolver,
       _homeDirectory = homeDirectory,
       _baseEnvironment = baseEnvironment,
       _maxSessions = maxSessions,
       _bufferCapacity = bufferCapacity,
       _sendWindow = sendWindow,
       _nextId = (random ?? Random.secure()).nextInt(_idUpperBound - 1) + 1;

  final PtyFactory _ptyFactory;
  final ShellResolver _shellResolver;
  final String _homeDirectory;
  final Map<String, String> _baseEnvironment;
  final int _maxSessions;
  final int _bufferCapacity;
  final int _sendWindow;

  final _outbound = StreamController<OutboundMessage>.broadcast(sync: true);
  final _changes = StreamController<void>.broadcast();
  final _opened = StreamController<SessionOpenedEvent>.broadcast();
  final _sessions = <int, _Session>{};
  int _nextId;
  int _pendingOpens = 0;

  /// Messages to deliver, in order. Synchronous broadcast stream.
  Stream<OutboundMessage> get outbound => _outbound.stream;

  /// Fires whenever the session list or an attachment changes.
  Stream<void> get changes => _changes.stream;

  Stream<SessionOpenedEvent> get opened => _opened.stream;

  List<SessionSummary> get sessions => [
    for (final s in _sessions.values)
      SessionSummary(
        id: s.id,
        index: s.index,
        shell: s.shell,
        createdAt: s.createdAt,
        attachedMobileId: s.attachedMobileId,
      ),
  ];

  /// Handles one decrypted message from phone [mobileId].
  Future<void> handle(String mobileId, AppMessage message) async {
    switch (message) {
      case SessionList():
        _send(
          mobileId,
          SessionListResult([
            for (final s in _sessions.values)
              SessionInfo(
                id: s.id,
                index: s.index,
                shell: s.shell,
                createdAt: s.createdAt.millisecondsSinceEpoch,
                attached: s.attachedMobileId != null,
              ),
          ]),
        );
      case SessionOpen(:final cols, :final rows):
        await _open(mobileId, cols, rows);
      case SessionAttach(:final id, :final cols, :final rows, :final lastSeq):
        _attach(mobileId, id, cols, rows, lastSeq);
      case InputMessage(:final id, :final data):
        _attachedTo(mobileId, id)?.pty.write(data);
      case ResizeMessage(:final id, :final cols, :final rows):
        final session = _attachedTo(mobileId, id);
        if (session != null) _resize(session, cols, rows);
      case AckMessage(:final id, :final seq):
        final session = _attachedTo(mobileId, id);
        if (session == null) return;
        session.acked = max(session.acked, min(seq, session.sent));
        _pump(session);
      case SessionClose(:final id):
        final session = _sessions[id];
        if (session == null) {
          _notFound(mobileId, id);
          return;
        }
        session.pty.kill();
      default:
        // pair.confirm is handled by AgentService; agent→phone types are
        // never accepted from a phone.
        break;
    }
  }

  /// The channel to [mobileId] is gone: its sessions become unattached
  /// (no message is sent).
  void mobileDisconnected(String mobileId) {
    var changed = false;
    for (final session in _sessions.values) {
      if (session.attachedMobileId == mobileId) {
        session.attachedMobileId = null;
        changed = true;
      }
      if (session.exitRecipient == mobileId) session.exitRecipient = null;
    }
    if (changed) _changes.add(null);
  }

  /// Kills every session attached to [mobileId] (used when revoking a phone).
  void closeSessionsAttachedTo(String mobileId) {
    for (final session in _sessions.values.toList()) {
      if (session.attachedMobileId == mobileId) session.pty.kill();
    }
  }

  /// Closes a session from the tray: `session.detached {closed_by_host}`
  /// now, `session.exited` once the shell is gone.
  void closeSession(int id) {
    final session = _sessions[id];
    if (session == null) return;
    final mobileId = session.attachedMobileId;
    if (mobileId != null) {
      _send(
        mobileId,
        SessionDetached(id: id, reason: DetachReason.closedByHost),
      );
      session.attachedMobileId = null;
      session.exitRecipient = mobileId;
      _changes.add(null);
    }
    session.pty.kill();
  }

  void closeAll() {
    for (final id in _sessions.keys.toList()) {
      closeSession(id);
    }
  }

  Future<void> _open(String mobileId, int cols, int rows) async {
    if (_sessions.length + _pendingOpens >= _maxSessions) {
      _send(
        mobileId,
        ErrorMessage(
          code: AppErrorCode.sessionLimit,
          message: 'This machine already has $_maxSessions open sessions.',
        ),
      );
      return;
    }
    final c = _clampDimension(cols);
    final r = _clampDimension(rows);
    _pendingOpens++;
    final ShellCommand command;
    final Pty pty;
    try {
      command = await _shellResolver.resolve();
      pty = _ptyFactory.spawn(
        command,
        workingDirectory: _homeDirectory,
        environment: buildSessionEnvironment(_baseEnvironment),
        cols: c,
        rows: r,
      );
    } catch (error) {
      _send(
        mobileId,
        ErrorMessage(code: AppErrorCode.spawnFailed, message: '$error'),
      );
      return;
    } finally {
      _pendingOpens--;
    }
    final session = _Session(
      id: _nextId++,
      index: _lowestFreeIndex(),
      shell: command.name,
      createdAt: DateTime.now(),
      pty: pty,
      buffer: RingBuffer(_bufferCapacity),
      cols: c,
      rows: r,
      attachedMobileId: mobileId,
    );
    _sessions[session.id] = session;
    _send(
      mobileId,
      SessionOpened(id: session.id, index: session.index, shell: session.shell),
    );
    _watch(session);
    _opened.add(SessionOpenedEvent(mobileId, session.id));
    _changes.add(null);
  }

  void _attach(String mobileId, int id, int cols, int rows, int lastSeq) {
    final session = _sessions[id];
    if (session == null) {
      _notFound(mobileId, id);
      return;
    }
    final previous = session.attachedMobileId;
    if (previous != null && previous != mobileId) {
      _send(previous, SessionDetached(id: id, reason: DetachReason.takenOver));
    }
    session.attachedMobileId = mobileId;
    session.exitRecipient = null;
    final buffer = session.buffer;
    if (lastSeq < buffer.start || lastSeq > buffer.end) {
      _send(mobileId, SessionReset(id: id));
      session.sent = buffer.start;
    } else {
      session.sent = lastSeq;
    }
    session.acked = session.sent;
    _pump(session);
    final c = _clampDimension(cols);
    final r = _clampDimension(rows);
    if (c == session.cols && r == session.rows) {
      // Same size: bounce the height so full-screen programs redraw.
      session.pty.resize(c, r > _minDimension ? r - 1 : r + 1);
      session.pty.resize(c, r);
    } else {
      session.cols = c;
      session.rows = r;
      session.pty.resize(c, r);
    }
    _send(mobileId, SessionAttached(id: id));
    if (previous != mobileId) _changes.add(null);
  }

  void _resize(_Session session, int cols, int rows) {
    final c = _clampDimension(cols);
    final r = _clampDimension(rows);
    if (c == session.cols && r == session.rows) return;
    session.cols = c;
    session.rows = r;
    session.pty.resize(c, r);
  }

  void _watch(_Session session) {
    final outputDone = Completer<void>();
    session.output = session.pty.output.listen(
      (data) {
        session.buffer.append(data);
        _pump(session);
      },
      onDone: outputDone.complete,
      onError: (Object _) {},
    );
    session.pty.exitCode.then((code) async {
      await outputDone.future.timeout(_outputDrainGrace, onTimeout: () {});
      _finish(session, code);
    }, onError: (Object _) => _finish(session, -1));
  }

  void _finish(_Session session, int exitCode) {
    if (!identical(_sessions[session.id], session)) return;
    _pump(session);
    final recipient = session.attachedMobileId ?? session.exitRecipient;
    _sessions.remove(session.id);
    session.output?.cancel();
    if (recipient != null) {
      _send(recipient, SessionExited(id: session.id, exitCode: exitCode));
    }
    _changes.add(null);
  }

  /// Sends buffered output to the attached phone while the send window
  /// allows. Data overwritten before it could be sent triggers a reset.
  void _pump(_Session session) {
    final mobileId = session.attachedMobileId;
    if (mobileId == null) return;
    final buffer = session.buffer;
    while (session.sent < buffer.end &&
        session.sent - session.acked < _sendWindow) {
      if (session.sent < buffer.start) {
        _send(mobileId, SessionReset(id: session.id));
        session.sent = buffer.start;
        session.acked = buffer.start;
        continue;
      }
      final room = _sendWindow - (session.sent - session.acked);
      final count = min(min(kMaxOutputChunk, buffer.end - session.sent), room);
      final data = buffer.read(session.sent, count);
      _send(
        mobileId,
        OutputMessage(id: session.id, seq: session.sent, data: data),
      );
      session.sent += count;
    }
  }

  _Session? _attachedTo(String mobileId, int id) {
    final session = _sessions[id];
    return session != null && session.attachedMobileId == mobileId
        ? session
        : null;
  }

  int _lowestFreeIndex() {
    final used = {for (final s in _sessions.values) s.index};
    var index = 1;
    while (used.contains(index)) {
      index++;
    }
    return index;
  }

  void _notFound(String mobileId, int id) {
    _send(
      mobileId,
      ErrorMessage(
        code: AppErrorCode.sessionNotFound,
        message: 'Session $id not found',
        id: id,
      ),
    );
  }

  void _send(String mobileId, AppMessage message) =>
      _outbound.add(OutboundMessage(mobileId, message));
}
