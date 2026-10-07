import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/mux/background_service_choice.dart';
import 'package:shellx_desktop/src/mux/daemon_launcher.dart';

/// The switch ("Giữ shell chạy khi đóng cửa sổ") and what a launch does
/// about a background service that is running anyway.
void main() {
  var probes = 0;
  var quits = 0;
  DaemonConnection? running;

  var lockFree = false;

  Future<bool> decide({required bool enabled}) => attachThisLaunch(
    enabled: enabled,
    daemonLockFree: () async => lockFree,
    findRunning: () async {
      probes++;
      return running;
    },
    quit: (client) async => quits++,
  );

  setUp(() {
    probes = 0;
    quits = 0;
    running = null;
    lockFree = false;
  });

  Future<Attached> service({int? sessions, int protocol = kMuxProtocol}) async {
    final (a, _) = MemoryMuxTransport.pair();
    return Attached(
      client: MuxClient(a),
      info: MuxPeerInfo(
        protocol: protocol,
        app: '1.5.0',
        instance: 'i',
        sessions: sessions,
      ),
    );
  }

  test(
    'on: attach, and nothing is probed (the launcher connects or starts)',
    () async {
      expect(await decide(enabled: true), isTrue);
      expect(probes, 0);
    },
  );

  test('off, nothing running: in-process (exactly today)', () async {
    expect(await decide(enabled: false), isFalse);
    expect(probes, 1);
    expect(quits, 0);
  });

  test(
    'off, a service with no sessions runs: it is quit, in-process',
    () async {
      running = await service(sessions: 0);
      expect(await decide(enabled: false), isFalse);
      expect(quits, 1);
    },
  );

  test('off, a service holds sessions: never stop shells unasked, never two '
      'hosts: this launch attaches', () async {
    running = await service(sessions: 3);
    expect(await decide(enabled: false), isTrue);
    expect(quits, 0);
  });

  test('off, a service of unknown count is not "empty"', () async {
    running = await service(sessions: null);
    expect(await decide(enabled: false), isTrue);
    expect(quits, 0);
  });

  test('off, an old-protocol service with no sessions is quit too', () async {
    final old = await service(sessions: 0, protocol: kMuxProtocol + 1);
    running = Incompatible(client: old.client, info: old.info);
    expect(await decide(enabled: false), isFalse);
    expect(quits, 1);
  });

  test(
    'off, an old-protocol service with sessions: attach (the launcher asks)',
    () async {
      final old = await service(sessions: 2, protocol: kMuxProtocol + 1);
      running = Incompatible(client: old.client, info: old.info);
      expect(await decide(enabled: false), isTrue);
      expect(quits, 0);
    },
  );

  test(
    'off and no service holds the lock: no connection is tried at all',
    () async {
      lockFree = true;
      expect(await decide(enabled: false), isFalse);
      expect(probes, 0);
    },
  );
}
