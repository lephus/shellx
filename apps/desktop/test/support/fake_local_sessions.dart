import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

/// Scriptable [LocalSessions]: tests add sessions (as if a phone opened
/// them), emit output and end shells.
final class FakeLocalSessions implements LocalSessions {
  final _changes = StreamController<void>.broadcast(sync: true);
  final summaries = <SessionSummary>[];
  final _notices = StreamController<SessionNotice>.broadcast();

  @override
  Stream<SessionNotice> get notices => _notices.stream;

  /// A notice from session [id], as the agent would emit it (A4).
  void notice(
    int id,
    SessionNoticeKind kind, {
    String? title,
    String? body,
    CompletedCommand? command,
    DateTime? at,
  }) => _notices.add(
    SessionNotice(
      sessionId: id,
      kind: kind,
      at: at ?? DateTime(2026, 10, 7, 9),
      title: title,
      body: body,
      command: command,
    ),
  );
  final views = <int, FakeSessionView>{};
  final opens = <(int, int)>[];

  /// The `cwd` of each [open] call, in order (null when none was given).
  final openCwds = <String?>[];

  /// The `tabId` of each [open] call (A7 D29).
  final openTabIds = <int?>[];

  /// Every [notify] call: (id, title, body).
  final notified = <(int, String?, String)>[];
  final closed = <int>[];
  int nextId = 100;

  /// When set, [open] throws it.
  Object? openError;

  /// When set, [open] waits for it.
  Completer<void>? openGate;

  /// [open] with one of these `cwd`s waits for its completer (one open
  /// held while others go through).
  final cwdGates = <String, Completer<void>>{};

  /// Runs once [open] made session `id`, before it returns.
  void Function(int id)? afterOpen;

  /// The backlog of the next sessions [open] makes (A5a: what the new
  /// shell printed before the view attached).
  String nextBacklog = '';

  /// [open] with one of these `cwd`s throws [SpawnFailedException].
  Set<String> failOpens = {};

  /// When true, [open] emits [changes] before it returns, as the real
  /// `SessionManager.open` does.
  bool notifyOnOpen = false;

  @override
  List<SessionSummary> get sessions => List.of(summaries);
  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<int> open({
    required int cols,
    required int rows,
    String? cwd,
    int? tabId,
  }) async {
    opens.add((cols, rows));
    openCwds.add(cwd);
    openTabIds.add(tabId);
    await openGate?.future;
    await cwdGates[cwd]?.future;
    final error = openError;
    if (error != null) throw error;
    if (failOpens.contains(cwd)) {
      throw const SpawnFailedException('No such file or directory');
    }
    final id = nextId++;
    add(
      summary(id, origin: SessionOrigin.desktop),
      notify: notifyOnOpen,
      backlog: nextBacklog,
    );
    afterOpen?.call(id);
    return id;
  }

  @override
  bool notify(int id, {String? title, required String body}) {
    notified.add((id, title, body));
    if (!summaries.any((s) => s.id == id)) return false;
    notice(id, SessionNoticeKind.message, title: title, body: body);
    return true;
  }

  SessionSummary summary(
    int id, {
    SessionOrigin origin = SessionOrigin.phone,
    String title = '',
    bool runningCommand = false,
    String? attachedMobileId,
    DriverSide? driver,
    String? cwd,
    String? gitBranch,
    List<int> ports = const [],
  }) => SessionSummary(
    id: id,
    index: summaries.length + 1,
    shell: 'zsh',
    createdAt: DateTime(2026, 10, 6),
    attachedMobileId: attachedMobileId,
    origin: origin,
    title: title,
    runningCommand: runningCommand,
    driver:
        driver ??
        (origin == SessionOrigin.phone ? DriverSide.phone : DriverSide.desktop),
    cwd: cwd,
    gitBranch: gitBranch,
    ports: ports,
  );

  void add(SessionSummary summary, {bool notify = true, String backlog = ''}) {
    summaries.add(summary);
    views[summary.id] = FakeSessionView(summary.id, backlog);
    if (notify) _changes.add(null);
  }

  /// Session [id] starts or stops running a command (A1 D15); fires
  /// [changes].
  void setRunning(int id, bool running) {
    final s = summaries.firstWhere((s) => s.id == id);
    replace(
      SessionSummary(
        id: s.id,
        index: s.index,
        shell: s.shell,
        createdAt: s.createdAt,
        attachedMobileId: s.attachedMobileId,
        origin: s.origin,
        title: s.title,
        runningCommand: running,
        driver: s.driver,
        cwd: s.cwd,
        gitBranch: s.gitBranch,
        ports: s.ports,
      ),
    );
  }

  void replace(SessionSummary summary) {
    final i = summaries.indexWhere((s) => s.id == summary.id);
    summaries[i] = summary;
    _changes.add(null);
  }

  @override
  LocalSessionView view(int id) {
    final view = views[id];
    if (view == null) throw StateError('No session $id');
    view.viewed++;
    return view;
  }

  /// Every `watchPorts` call, in order (A2 D8).
  final watched = <bool>[];

  @override
  void watchPorts(bool visible) => watched.add(visible);

  @override
  void close(int id) {
    closed.add(id);
    summaries.removeWhere((s) => s.id == id);
    _changes.add(null);
    views[id]?.end(-15, onRequest: true);
  }
}

final class FakeSessionView implements LocalSessionView {
  FakeSessionView(this.id, String backlogText)
    : backlog = Uint8List.fromList(utf8.encode(backlogText));

  @override
  final int id;
  @override
  final Uint8List backlog;
  final outputController = StreamController<Uint8List>();
  final driverController = StreamController<DriverSide>.broadcast(sync: true);
  final _exit = Completer<int>();
  final writes = <String>[];
  final replies = <String>[];
  final resizes = <(int, int)>[];
  int viewed = 0;
  bool disposed = false;
  bool _onRequest = false;

  void emit(String text) =>
      outputController.add(Uint8List.fromList(utf8.encode(text)));

  void end(int code, {bool onRequest = false}) {
    if (_exit.isCompleted) return;
    _onRequest = onRequest;
    _exit.complete(code);
    unawaited(outputController.close());
  }

  @override
  Stream<Uint8List> get output => outputController.stream;
  @override
  Stream<DriverSide> get driver => driverController.stream;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  bool get closedOnRequest => _onRequest;
  @override
  void write(Uint8List data) => writes.add(utf8.decode(data));
  @override
  void reply(Uint8List data) => replies.add(utf8.decode(data));
  @override
  void resize(int cols, int rows) => resizes.add((cols, rows));
  @override
  void dispose() => disposed = true;
}
