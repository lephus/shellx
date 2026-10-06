import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

final class _Probe implements PortProbe {
  Map<int, Set<int>> ports = {};
  Map<int, int> tree = {};
  int listeningCalls = 0;
  int parentCalls = 0;
  Duration delay = Duration.zero;
  Object? fail;

  @override
  Future<Map<int, Set<int>>> listening() async {
    listeningCalls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final error = fail;
    if (error != null) throw error;
    return {
      for (final e in ports.entries) e.key: {...e.value},
    };
  }

  @override
  Future<Map<int, int>> parents() async {
    parentCalls++;
    return Map.of(tree);
  }
}

void main() {
  late _Probe probe;
  late Map<int, int> shells; // session id → shell pid
  late List<Map<int, List<int>>> published;

  setUp(() {
    probe = _Probe()
      ..tree = {200: 100, 300: 200, 400: 1}
      ..ports = {
        300: {5173, 3000},
        400: {9999}, // not in any session's tree
      };
    shells = {1: 100};
    published = [];
  });

  PortWatcher watcher(FakeAsync async) => PortWatcher(
    probe: probe,
    shells: () => shells,
    onPorts: published.add,
    now: () => DateTime(2026, 10, 7).add(async.elapsed),
  );

  test('hidden: nothing is ever spawned (spec criterion 4)', () {
    fakeAsync((async) {
      watcher(async);
      async.elapse(const Duration(seconds: 30));
      expect(probe.listeningCalls, 0);
    });
  });

  test('visible without sessions: nothing is spawned', () {
    fakeAsync((async) {
      shells = {};
      watcher(async).setVisible(true);
      async.elapse(const Duration(seconds: 30));
      expect(probe.listeningCalls, 0);
    });
  });

  test('visible: scans at once, then 3 s after each scan; the process table '
      'is read only for an unclassified pid (D4, D5)', () {
    fakeAsync((async) {
      watcher(async).setVisible(true);
      async.elapse(Duration.zero);
      expect(published.last, {
        1: [3000, 5173],
      });
      expect((probe.listeningCalls, probe.parentCalls), (1, 1));
      async.elapse(const Duration(milliseconds: 2999));
      expect(probe.listeningCalls, 1);
      async.elapse(const Duration(milliseconds: 2));
      expect((probe.listeningCalls, probe.parentCalls), (2, 1));
      probe.ports[500] = {8080};
      probe.tree[500] = 100;
      async.elapse(const Duration(seconds: 3));
      expect(probe.parentCalls, 2);
      expect(published.last, {
        1: [3000, 5173, 8080],
      });
    });
  });

  test('a nested shell owns the ports of its own children', () {
    fakeAsync((async) {
      shells = {1: 100, 2: 200};
      watcher(async).setVisible(true);
      async.elapse(Duration.zero);
      expect(published.last, {
        2: [3000, 5173],
      });
    });
  });

  test('a server that stops listening disappears at the next scan', () {
    fakeAsync((async) {
      watcher(async).setVisible(true);
      async.elapse(Duration.zero);
      probe.ports.remove(300);
      async.elapse(const Duration(seconds: 3));
      expect(published.last, isEmpty);
    });
  });

  test('hiding stops scanning; showing again scans at once', () {
    fakeAsync((async) {
      final w = watcher(async)..setVisible(true);
      async.elapse(Duration.zero);
      w.setVisible(false);
      async.elapse(const Duration(seconds: 30));
      expect(probe.listeningCalls, 1);
      w.setVisible(true);
      async.elapse(Duration.zero);
      expect(probe.listeningCalls, 2);
    });
  });

  test('a scan slower than 1.5 s doubles the gap, up to 15 s (D5)', () {
    fakeAsync((async) {
      probe.delay = const Duration(seconds: 2);
      watcher(async).setVisible(true);
      async.elapse(const Duration(seconds: 2)); // first scan done at 2 s
      expect(probe.listeningCalls, 1);
      async.elapse(const Duration(milliseconds: 5900)); // 7.9 s
      expect(probe.listeningCalls, 1);
      async.elapse(const Duration(milliseconds: 200)); // 8.1 s: 2 + 6
      expect(probe.listeningCalls, 2);
    });
  });

  test('one failure keeps the ports, a second clears them and backs off '
      'to 15 s (D6)', () {
    fakeAsync((async) {
      watcher(async).setVisible(true);
      async.elapse(Duration.zero);
      expect(published, hasLength(1));
      probe.fail = const PortProbeException('lsof exited with code 2');
      async.elapse(const Duration(seconds: 3));
      expect(published, hasLength(1));
      async.elapse(const Duration(seconds: 15));
      expect(published.last, isEmpty);
      final calls = probe.listeningCalls;
      async.elapse(const Duration(seconds: 14));
      expect(probe.listeningCalls, calls);
    });
  });

  test('sessionsChanged reclassifies and restarts a watcher that stopped '
      'for lack of sessions', () {
    fakeAsync((async) {
      shells = {};
      final w = watcher(async)..setVisible(true);
      async.elapse(Duration.zero);
      expect(probe.listeningCalls, 0);
      shells = {1: 100};
      w.sessionsChanged();
      async.elapse(Duration.zero);
      expect(published.last, {
        1: [3000, 5173],
      });
      w.dispose();
      async.elapse(const Duration(seconds: 30));
      expect(probe.listeningCalls, 1);
    });
  });

  test('dispose during a scan: its result is never published', () {
    fakeAsync((async) {
      probe.delay = const Duration(seconds: 1);
      final w = watcher(async)..setVisible(true);
      async.elapse(const Duration(milliseconds: 500));
      expect(probe.listeningCalls, 1);
      w.dispose();
      async.elapse(const Duration(seconds: 30));
      expect(published, isEmpty);
      expect(probe.listeningCalls, 1);
    });
  });
}
