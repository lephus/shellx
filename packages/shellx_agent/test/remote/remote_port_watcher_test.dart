import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  final devbox = SshTarget.parse('devbox')!;
  final other = SshTarget.parse('other')!;
  const out =
      '#ps\n 10 1\n 11 10\n 20 1\n#ss\n'
      'LISTEN 0 1 127.0.0.1:8000 0.0.0.0:* users:(("p",pid=11,fd=3))\n';

  late List<List<String>> calls;
  late CommandResult Function(List<String>) answer;
  late List<Map<int, List<int>>> published;
  late Map<int, RemoteShell> shells;

  RemotePortWatcher watcher() => RemotePortWatcher(
    control: SshControl(
      sshPath: '/usr/bin/ssh',
      controlDirectory: '/tmp/sx',
      run: (exe, args, {timeout = const Duration(seconds: 5)}) async {
        calls.add(args);
        return answer(args);
      },
    ),
    shells: () => shells,
    onPorts: published.add,
  );

  setUp(() {
    calls = [];
    published = [];
    answer = (_) => const CommandResult(0, out, '');
    shells = {
      1: RemoteShell(target: devbox, pid: 10),
      2: RemoteShell(target: devbox, pid: 20),
      3: RemoteShell(target: other, pid: 10),
    };
  });

  test(
    'one probe per host while visible, every 5 s; ports per session (D18)',
    () {
      fakeAsync((async) {
        final w = watcher();
        w.sessionsChanged();
        async.flushTimers(flushPeriodicTimers: false);
        expect(calls, isEmpty); // hidden: nothing
        w.setVisible(true);
        async.elapse(Duration.zero);
        expect(calls, hasLength(2));
        expect(
          published,
          containsAll([
            {
              1: [8000],
              2: <int>[],
            },
            {
              3: [8000],
            },
          ]),
        );
        async.elapse(const Duration(seconds: 5));
        expect(calls, hasLength(4));
        w.setVisible(false);
        async.elapse(const Duration(seconds: 30));
        expect(calls, hasLength(4));
        w.dispose();
      });
    },
  );

  test('3 failures → every 60 s; success → 5 s again', () {
    fakeAsync((async) {
      shells = {1: RemoteShell(target: devbox, pid: 10)};
      answer = (_) => const CommandResult(-1, '', '', timedOut: true);
      final w = watcher()..setVisible(true);
      async.elapse(const Duration(seconds: 11)); // t=0, 5, 10; next at 70
      expect(calls, hasLength(3));
      async.elapse(const Duration(seconds: 58)); // t=69
      expect(calls, hasLength(3));
      answer = (_) => const CommandResult(0, out, '');
      async.elapse(const Duration(seconds: 1));
      expect(calls, hasLength(4));
      async.elapse(const Duration(seconds: 5));
      expect(calls, hasLength(5));
      w.dispose();
    });
  });

  test('needs sign-in (255) stops probing that host until it says hello', () {
    fakeAsync((async) {
      shells = {1: RemoteShell(target: devbox, pid: 10)};
      answer = (_) => const CommandResult(255, '', 'Permission denied');
      final logs = <String>[];
      final w = RemotePortWatcher(
        control: SshControl(
          sshPath: '/usr/bin/ssh',
          run: (exe, args, {timeout = const Duration(seconds: 5)}) async {
            calls.add(args);
            return answer(args);
          },
        ),
        shells: () => shells,
        onPorts: published.add,
        log: logs.add,
      )..setVisible(true);
      async.elapse(const Duration(seconds: 30));
      expect(calls, hasLength(1));
      expect(published.last, {1: <int>[]});
      expect(logs.join(), isNot(contains('devbox')));
      answer = (_) => const CommandResult(0, out, '');
      w.resume(devbox);
      async.elapse(Duration.zero);
      expect(calls, hasLength(2));
      w.dispose();
    });
  });

  test('a stopped host is retried every 5 minutes while visible', () {
    fakeAsync((async) {
      shells = {1: RemoteShell(target: devbox, pid: 10)};
      answer = (_) => const CommandResult(255, '', 'Permission denied');
      final w = watcher()..setVisible(true);
      async.elapse(const Duration(minutes: 4, seconds: 59));
      expect(calls, hasLength(1));
      async.elapse(const Duration(seconds: 1));
      expect(calls, hasLength(2));
      answer = (_) => const CommandResult(0, out, '');
      async.elapse(const Duration(minutes: 5));
      expect(calls, hasLength(3));
      expect(published.last, {
        1: [8000],
      });
      async.elapse(const Duration(seconds: 5)); // back to the 5 s rhythm
      expect(calls, hasLength(4));
      w.dispose();
    });
  });

  test('hiding stops the stopped-host retry; showing resumes it', () {
    fakeAsync((async) {
      shells = {1: RemoteShell(target: devbox, pid: 10)};
      answer = (_) => const CommandResult(255, '', '');
      final w = watcher()..setVisible(true);
      async.elapse(Duration.zero);
      w.setVisible(false);
      async.elapse(const Duration(minutes: 10));
      expect(calls, hasLength(1));
      w.setVisible(true);
      async.elapse(const Duration(minutes: 5));
      expect(calls, hasLength(2));
      w.dispose();
    });
  });

  test('a host removed while its probe is in flight publishes nothing', () {
    fakeAsync((async) {
      shells = {1: RemoteShell(target: devbox, pid: 10)};
      final gate = Completer<CommandResult>();
      final w = RemotePortWatcher(
        control: SshControl(
          sshPath: '/usr/bin/ssh',
          controlDirectory: '/tmp/sx',
          run: (exe, args, {timeout = const Duration(seconds: 5)}) {
            calls.add(args);
            return gate.future;
          },
        ),
        shells: () => shells,
        onPorts: published.add,
      )..setVisible(true);
      async.elapse(Duration.zero);
      expect(calls, hasLength(1));
      shells = {};
      w.sessionsChanged();
      gate.complete(const CommandResult(0, out, ''));
      async.elapse(const Duration(seconds: 30));
      expect(published, isEmpty);
      expect(calls, hasLength(1));
      w.dispose();
    });
  });

  test('hide then show during a probe: one probe at a time, ports kept', () {
    fakeAsync((async) {
      shells = {1: RemoteShell(target: devbox, pid: 10)};
      final gate = Completer<CommandResult>();
      var first = true;
      final w = RemotePortWatcher(
        control: SshControl(
          sshPath: '/usr/bin/ssh',
          controlDirectory: '/tmp/sx',
          run: (exe, args, {timeout = const Duration(seconds: 5)}) {
            calls.add(args);
            if (first) {
              first = false;
              return gate.future;
            }
            return Future.value(const CommandResult(0, out, ''));
          },
        ),
        shells: () => shells,
        onPorts: published.add,
      )..setVisible(true);
      async.elapse(Duration.zero);
      w.setVisible(false);
      w.setVisible(true);
      async.elapse(const Duration(seconds: 1));
      expect(calls, hasLength(1)); // still the one in flight
      gate.complete(const CommandResult(0, out, ''));
      async.elapse(const Duration(seconds: 5));
      expect(calls, hasLength(2));
      w.dispose();
    });
  });

  test('a failed probe keeps the old ports (nothing published)', () {
    fakeAsync((async) {
      shells = {1: RemoteShell(target: devbox, pid: 10)};
      final w = watcher()..setVisible(true);
      async.elapse(Duration.zero);
      expect(published, hasLength(1));
      answer = (_) => const CommandResult(1, '', 'boom');
      async.elapse(const Duration(seconds: 5));
      expect(calls, hasLength(2));
      expect(published, hasLength(1));
      w.dispose();
    });
  });

  test('probes do not reuse a master and have a connect timeout', () {
    fakeAsync((async) {
      watcher().setVisible(true);
      async.elapse(Duration.zero);
      expect(calls, everyElement(contains('ControlMaster=no')));
      expect(
        calls,
        everyElement(
          predicate<List<String>>(
            (a) => a.any((x) => x.startsWith('ConnectTimeout=')),
          ),
        ),
      );
    });
  });

  test('every probe is BatchMode', () {
    fakeAsync((async) {
      watcher().setVisible(true);
      async.elapse(Duration.zero);
      expect(calls, everyElement(contains('BatchMode=yes')));
    });
  });
}
