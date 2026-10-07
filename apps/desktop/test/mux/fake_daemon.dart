import 'dart:async';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/mux/daemon_launcher.dart';
import 'package:shellx_desktop/src/mux/daemon_state.dart';

import '../support/fake_local_sessions.dart';
import '../support/restore_fakes.dart';
import 'mux_test_support.dart';

/// A background service of the test: sessions behind a [MuxServer], and the
/// UI's [Attached] connection to it.
final class FakeDaemon {
  FakeDaemon(this.instance, {List<int> ids = const []}) {
    for (final id in ids) {
      sessions.add(
        sessions.summary(id, origin: SessionOrigin.desktop, cwd: '/w$id'),
        notify: false,
      );
    }
    server = MuxServer(
      sessions: sessions,
      secret: testSecret,
      self: MuxPeerInfo(
        protocol: kMuxProtocol,
        app: '1.6.0',
        instance: instance,
      ),
      onQuit: () async {
        quits++;
        await onQuit?.call();
      },
    )..serve(listener);
  }

  final String instance;

  /// What the service does when it is told to quit.
  FutureOr<void> Function()? onQuit;

  /// How many `daemon.quit` it received.
  int quits = 0;
  final sessions = FakeLocalSessions();
  final listener = TestListener();
  late final MuxServer server;
  late MuxConnection serverSide;

  Future<Attached> attach() async {
    final (client, daemonSide) = MemoryMuxTransport.pair();
    serverSide = daemonSide;
    listener.push(daemonSide);
    final peer = await clientHandshake(
      client,
      secret: testSecret,
      app: '1.6.0',
      role: 'ui',
    );
    return Attached(
      client: MuxClient(client, early: peer.early),
      info: peer,
    );
  }

  /// The service dies: its end of the link goes away.
  Future<void> die() => serverSide.close();
}

final class FakeConnector implements DaemonConnector {
  final queue = <Future<DaemonConnection> Function()>[];
  int connects = 0;

  /// What `RecordingFiles.layouts` held each time `connect` was called.
  final layoutsAtConnect = <int>[];
  late RecordingFiles files;

  @override
  Future<DaemonConnection> connect() {
    connects++;
    layoutsAtConnect.add(files.layouts.length);
    return queue.removeAt(0)();
  }

  @override
  Future<DaemonConnection> replaceIncompatible(Incompatible old) =>
      throw UnimplementedError();
}
