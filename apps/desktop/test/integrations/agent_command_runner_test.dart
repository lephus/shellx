import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/integrations/agent_command_runner.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';

final t0 = DateTime.utc(2026, 10, 8, 9);

/// A process that records what it is given and ends when told to.
final class FakeProcess implements Process {
  FakeProcess() {
    _stdinBytes.stream.listen(stdinBytes.addAll);
    stdin = IOSink(_stdinBytes);
  }

  final _stdinBytes = StreamController<List<int>>();
  final stdinBytes = <int>[];
  final _exit = Completer<int>();
  final stdoutCtl = StreamController<List<int>>();
  final stderrCtl = StreamController<List<int>>();
  bool killed = false;

  String get stdinText => utf8.decode(stdinBytes);

  void finish([int code = 0]) {
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  late final IOSink stdin;

  @override
  Stream<List<int>> get stdout => stdoutCtl.stream;

  @override
  Stream<List<int>> get stderr => stderrCtl.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => 4242;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    finish(-9);
    return true;
  }
}

typedef Started = ({
  String exe,
  List<String> args,
  String? cwd,
  Map<String, String>? env,
  bool parentEnv,
  bool shell,
  FakeProcess proc,
});

AgentCommandEvent ev({
  int pane = 3,
  String event = 'needs_input',
  String? message = 'Allow?',
}) => AgentCommandEvent(
  event: event,
  agent: 'claude',
  pane: pane,
  tab: 1,
  status: event,
  message: message,
);

void main() {
  group('splitCommand', () {
    List<String>? s(String text) => splitCommand(text, home: '/Users/me');

    test('words, quotes and escapes', () {
      expect(s('a b  c'), ['a', 'b', 'c']);
      expect(s("'a b' \"c d\""), ['a b', 'c d']);
      expect(s(r'a\ b'), ['a b']);
      expect(s(r'"a\"b"'), ['a"b']);
      expect(s(r'"a\\b"'), [r'a\b']);
      expect(s(r"'a\b'"), [r'a\b']); // single quotes keep everything
      expect(s('a"b c"d'), ['ab cd']);
      expect(s('""'), ['']);
      expect(s("  lead\ttab  "), ['lead', 'tab']);
    });

    test('only a leading ~/ is the home directory', () {
      expect(s('~/bin/on-agent --fast'), ['/Users/me/bin/on-agent', '--fast']);
      expect(s('~'), ['~']);
      expect(s('~user/x'), ['~user/x']);
      expect(s('"~/x"'), ['~/x']);
      expect(s("'~/x'"), ['~/x']);
      expect(s('a ~/x'), ['a', '/Users/me/x']);
      expect(s('a~/x'), ['a~/x']);
    });

    test('no variables, substitutions, globs or operators', () {
      expect(s(r'$HOME $(id) `id` *.sh ? [a] {a,b}'), [
        r'$HOME',
        r'$(id)',
        '`id`',
        '*.sh',
        '?',
        '[a]',
        '{a,b}',
      ]);
      expect(s('a | b && c ; d > e < f &'), [
        'a',
        '|',
        'b',
        '&&',
        'c',
        ';',
        'd',
        '>',
        'e',
        '<',
        'f',
        '&',
      ]);
    });

    test('empty, unbalanced, dangling, control characters: refused', () {
      for (final bad in [
        '',
        '   ',
        '"abc',
        "'abc",
        r'abc\',
        'a\nb',
        'a\rb',
        'a\u0000b',
        'a\u0007b',
        'a\u007fb',
      ]) {
        expect(s(bad), isNull, reason: bad.codeUnits.toString());
      }
    });

    test('no home: a leading ~/ stays as typed', () {
      expect(splitCommand('~/x', home: ''), ['~/x']);
    });
  });

  group('Windows', () {
    test('only .exe or powershell -File; never a .cmd or .bat', () {
      bool ok(List<String> a) => argvAllowed(a, windows: true);
      expect(ok([r'C:\tools\on-agent.exe', '--fast']), isTrue);
      expect(ok([r'C:\TOOLS\ON.EXE']), isTrue);
      expect(ok(['powershell', '-File', r'C:\x.ps1']), isTrue);
      expect(ok(['powershell.exe', '-File', r'C:\x.ps1']), isTrue);
      expect(ok(['pwsh', '-File', 'x.ps1']), isTrue);
      expect(ok(['powershell', '-Command', 'calc']), isFalse);
      expect(ok(['powershell']), isFalse);
      expect(ok([r'C:\x.cmd']), isFalse);
      expect(ok([r'C:\x.bat']), isFalse);
      expect(ok(['on-agent']), isFalse);
      expect(ok([]), isFalse);
      expect(argvAllowed(['anything'], windows: false), isTrue);
      expect(argvAllowed([], windows: false), isFalse);
      expect(argvAllowed([''], windows: false), isFalse);
    });
  });

  group('hash', () {
    test('sha256 hex of the string', () {
      // sha256("abc")
      expect(
        commandHash('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(commandHash('abc '), isNot(commandHash('abc')));
    });
  });

  group('AgentCommandEvent', () {
    test('one JSON line, no workspace, path or branch; env switches', () {
      final e = ev(message: 'hi');
      expect(jsonDecode(e.jsonLine()), {
        'v': 1,
        'event': 'needs_input',
        'agent': 'claude',
        'pane': 3,
        'tab': 1,
        'status': 'needs_input',
        'message': 'hi',
      });
      expect(e.jsonLine(), isNot(contains('\n')));
      expect(
        jsonDecode(ev(message: null).jsonLine()),
        isNot(contains('message')),
      );
      expect(e.env(), {
        'SHELLX_EVENT': 'needs_input',
        'SHELLX_AGENT': 'claude',
        'SHELLX_PANE': '3',
        'SHELLX_TAB': '1',
        'SHELLX_STATUS': 'needs_input',
      });
    });

    test('a message with a newline is still one line', () {
      expect(ev(message: 'a\nb').jsonLine(), isNot(contains('\n')));
    });

    test('toString hides everything', () {
      expect(ev().toString(), '…');
    });
  });

  group('runner', () {
    late List<Started> started;
    late String cmd;
    late Set<String> approvedHashes;
    late List<String> notApproved;
    late int couldNotRun;
    late Object? startError;
    late Map<String, String> parentEnv;

    AgentCommandRunner make(FakeAsync fa, {bool windows = false}) {
      return AgentCommandRunner(
        command: () => cmd,
        approved: approvedHashes.contains,
        home: '/Users/me',
        environment: parentEnv,
        windows: windows,
        now: fa.getClock(t0).now,
        onNotApproved: notApproved.add,
        onCouldNotRun: () => couldNotRun++,
        start:
            (
              exe,
              args, {
              workingDirectory,
              environment,
              includeParentEnvironment = true,
              runInShell = false,
            }) async {
              final error = startError;
              if (error != null) throw error;
              final p = FakeProcess();
              started.add((
                exe: exe,
                args: args,
                cwd: workingDirectory,
                env: environment,
                parentEnv: includeParentEnvironment,
                shell: runInShell,
                proc: p,
              ));
              return p;
            },
      );
    }

    setUp(() {
      started = [];
      cmd = '~/bin/on-agent --fast';
      approvedHashes = {commandHash(cmd)};
      notApproved = [];
      couldNotRun = 0;
      startError = null;
      parentEnv = {
        'PATH': '/usr/bin',
        'HOME': '/Users/me',
        'USER': 'me',
        'LOGNAME': 'me',
        'LANG': 'en_US.UTF-8',
        'TMPDIR': '/tmp',
        'SystemRoot': r'C:\Windows',
        'SHELLX_CLI_TOKEN': 'secret-token',
        'SHELLX_SOCKET': '/tmp/sock',
        'SHELLX_PANE_ID': '7',
        'AWS_SECRET_ACCESS_KEY': 'nope',
        'GH_TOKEN': 'nope',
      };
    });

    test('an approved command starts: argv, no shell, home, stdin line', () {
      fakeAsync((fa) {
        final r = make(fa);
        r.emit(ev(message: 'hi'));
        fa.flushMicrotasks();
        final s = started.single;
        expect(s.exe, '/Users/me/bin/on-agent');
        expect(s.args, ['--fast']);
        expect(s.shell, isFalse);
        expect(s.parentEnv, isFalse);
        expect(s.cwd, '/Users/me');
        expect(jsonDecode(s.proc.stdinText.trim())['event'], 'needs_input');
        expect(s.proc.stdinText.endsWith('\n'), isTrue);
        expect('\n'.allMatches(s.proc.stdinText), hasLength(1));
        r.dispose();
      });
    });

    test('the environment is exactly the allowed names and the 5 switches', () {
      fakeAsync((fa) {
        final r = make(fa);
        r.emit(ev());
        fa.flushMicrotasks();
        final env = started.single.env!;
        expect(env.keys.toSet(), {
          'PATH',
          'HOME',
          'USER',
          'LOGNAME',
          'LANG',
          'TMPDIR',
          'SystemRoot',
          'SHELLX_EVENT',
          'SHELLX_AGENT',
          'SHELLX_PANE',
          'SHELLX_TAB',
          'SHELLX_STATUS',
        });
        expect(env['SHELLX_EVENT'], 'needs_input');
        expect(env['PATH'], '/usr/bin');
        for (final k in env.keys) {
          expect(k, isNot(contains('TOKEN')));
          expect(k, isNot('SHELLX_SOCKET'));
          expect(k, isNot('SHELLX_PANE_ID'));
        }
        r.dispose();
      });
    });

    test('names that are not set are not invented', () {
      fakeAsync((fa) {
        parentEnv = {'PATH': '/bin', 'SHELLX_CLI_TOKEN': 'x'};
        final r = make(fa);
        r.emit(ev());
        fa.flushMicrotasks();
        expect(started.single.env!.keys.toSet(), {
          'PATH',
          'SHELLX_EVENT',
          'SHELLX_AGENT',
          'SHELLX_PANE',
          'SHELLX_TAB',
          'SHELLX_STATUS',
        });
        r.dispose();
      });
    });

    test('output is read and thrown away', () {
      fakeAsync((fa) {
        final r = make(fa);
        r.emit(ev());
        fa.flushMicrotasks();
        expect(started.single.proc.stdoutCtl.hasListener, isTrue);
        expect(started.single.proc.stderrCtl.hasListener, isTrue);
        r.dispose();
      });
    });

    test('10 s: the process is killed; a quick one is left alone', () {
      fakeAsync((fa) {
        final r = make(fa);
        r.emit(ev(pane: 1));
        r.emit(ev(pane: 2));
        fa.flushMicrotasks();
        started[1].proc.finish(0);
        fa.elapse(const Duration(seconds: 9, milliseconds: 900));
        expect(started[0].proc.killed, isFalse);
        fa.elapse(const Duration(milliseconds: 200));
        expect(started[0].proc.killed, isTrue);
        expect(started[1].proc.killed, isFalse);
        expect(fa.nonPeriodicTimerCount, 0);
        r.dispose();
      });
    });

    test('4 at a time, a queue of 16 that drops the oldest', () {
      fakeAsync((fa) {
        final r = make(fa);
        for (var pane = 0; pane < 30; pane++) {
          r.emit(ev(pane: pane));
        }
        fa.flushMicrotasks();
        expect(started, hasLength(4));
        // Finish them all, one after another, until nothing is left.
        var done = 0;
        while (done < started.length) {
          started[done].proc.finish();
          fa.flushMicrotasks();
          done++;
          expect(
            started.length - done,
            lessThanOrEqualTo(4),
            reason: 'running at once',
          );
        }
        final panes = started
            .map((s) => int.parse(s.env!['SHELLX_PANE']!))
            .toList();
        // 4 ran at once; of the other 26 the 16 newest waited.
        expect(panes.take(4), [0, 1, 2, 3]);
        expect(panes.skip(4), [for (var p = 14; p < 30; p++) p]);
        r.dispose();
      });
    });

    test('one a second for the same pane and event', () {
      fakeAsync((fa) {
        final r = make(fa);
        r.emit(ev());
        r.emit(ev());
        r.emit(ev(event: 'done'));
        r.emit(ev(pane: 9));
        fa.flushMicrotasks();
        expect(started, hasLength(3));
        fa.elapse(const Duration(milliseconds: 1100));
        r.emit(ev());
        fa.flushMicrotasks();
        expect(started, hasLength(4));
        r.dispose();
      });
    });

    test('not approved: nothing starts, one notice, the exact string', () {
      fakeAsync((fa) {
        approvedHashes = {};
        final r = make(fa);
        for (var i = 0; i < 5; i++) {
          r.emit(ev(pane: i));
        }
        fa.flushMicrotasks();
        expect(started, isEmpty);
        expect(notApproved, ['~/bin/on-agent --fast']);
        r.dispose();
      });
    });

    test('the approval is asked of the hash only', () {
      fakeAsync((fa) {
        final asked = <String>[];
        final r = AgentCommandRunner(
          command: () => cmd,
          approved: (h) {
            asked.add(h);
            return false;
          },
          home: '/h',
          environment: parentEnv,
          windows: false,
          now: fa.getClock(t0).now,
          onNotApproved: (_) {},
          onCouldNotRun: () {},
          start:
              (
                _,
                _, {
                workingDirectory,
                environment,
                includeParentEnvironment = true,
                runInShell = false,
              }) => throw StateError('never'),
        );
        r.emit(ev());
        expect(asked, [commandHash(cmd)]);
        expect(asked.single, isNot(contains('on-agent')));
        r.dispose();
      });
    });

    test('a changed string asks again, and runs only once allowed', () {
      fakeAsync((fa) {
        final r = make(fa);
        r.emit(ev());
        fa.flushMicrotasks();
        expect(started, hasLength(1));
        cmd = '~/bin/on-agent --fast --evil';
        fa.elapse(const Duration(seconds: 2));
        r.emit(ev());
        fa.flushMicrotasks();
        expect(started, hasLength(1));
        expect(notApproved, ['~/bin/on-agent --fast --evil']);
        approvedHashes.add(commandHash(cmd));
        fa.elapse(const Duration(seconds: 2));
        r.emit(ev());
        fa.flushMicrotasks();
        expect(started, hasLength(2));
        expect(started.last.args, ['--fast', '--evil']);
        // One space more is a different string too.
        cmd = '~/bin/on-agent --fast --evil ';
        fa.elapse(const Duration(seconds: 2));
        r.emit(ev());
        fa.flushMicrotasks();
        expect(started, hasLength(2));
        expect(notApproved, hasLength(2));
        r.dispose();
      });
    });

    test('no command set: nothing starts and nothing is said', () {
      fakeAsync((fa) {
        cmd = '';
        final r = make(fa);
        r.emit(ev());
        fa.flushMicrotasks();
        expect(started, isEmpty);
        expect(notApproved, isEmpty);
        expect(couldNotRun, 0);
        r.dispose();
      });
    });

    test('a command that cannot start: one notice a session, no retry', () {
      fakeAsync((fa) {
        startError = const ProcessException('x', [], 'no such file');
        final r = make(fa);
        r.emit(ev(pane: 1));
        r.emit(ev(pane: 2));
        fa.flushMicrotasks();
        fa.elapse(const Duration(seconds: 3));
        r.emit(ev(pane: 1));
        fa.flushMicrotasks();
        expect(couldNotRun, 1);
        expect(started, isEmpty);
        r.dispose();
      });
    });

    test('a string that does not split is a command that cannot run', () {
      fakeAsync((fa) {
        cmd = '"unbalanced';
        approvedHashes = {commandHash(cmd)};
        final r = make(fa);
        r.emit(ev());
        fa.flushMicrotasks();
        expect(started, isEmpty);
        expect(couldNotRun, 1);
        r.dispose();
      });
    });

    test('Windows: a .cmd is refused as a command that cannot run', () {
      fakeAsync((fa) {
        cmd = r'C:\tools\on-agent.cmd';
        approvedHashes = {commandHash(cmd)};
        final r = make(fa, windows: true);
        r.emit(ev());
        fa.flushMicrotasks();
        expect(started, isEmpty);
        expect(couldNotRun, 1);
        r.dispose();
      });
    });

    test('dispose kills what is running and drops the queue', () {
      fakeAsync((fa) {
        final r = make(fa);
        for (var pane = 0; pane < 8; pane++) {
          r.emit(ev(pane: pane));
        }
        fa.flushMicrotasks();
        r.dispose();
        fa.flushMicrotasks();
        expect(started, hasLength(4));
        expect(started.every((s) => s.proc.killed), isTrue);
        expect(fa.nonPeriodicTimerCount, 0);
      });
    });

    test('privacy: the command, the message and the ids never reach a log', () {
      final lines = <String>[];
      final old = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => lines.add(m ?? '');
      addTearDown(() => debugPrint = old);
      fakeAsync((fa) {
        startError = StateError('/Users/me/bin/on-agent secret');
        final r = make(fa);
        r.emit(ev(message: 'the secret message'));
        approvedHashes = {};
        fa.flushMicrotasks();
        cmd = 'other thing';
        r.emit(ev(pane: 99));
        fa.flushMicrotasks();
        r.dispose();
      });
      final all = lines.join('\n');
      expect(all, isNot(contains('on-agent')));
      expect(all, isNot(contains('secret')));
      expect(all, isNot(contains('other thing')));
    });

    test('toString of the runner hides the command', () {
      fakeAsync((fa) {
        final r = make(fa);
        expect(r.toString(), isNot(contains('on-agent')));
        r.dispose();
      });
    });
  });

  group('approvals in the settings store', () {
    test('only the hash is stored; the string is never written', () async {
      final store = InMemorySettingsStore();
      const command = '~/bin/on-agent --fast';
      expect(isCommandApproved(store, commandHash(command)), isFalse);
      await approveCommand(store, commandHash(command));
      expect(isCommandApproved(store, commandHash(command)), isTrue);
      expect(isCommandApproved(store, commandHash('$command x')), isFalse);
      final stored = store.strings[SettingKeys.agentCommandApproved]!;
      expect(stored, [commandHash(command)]);
      expect(stored.join(), isNot(contains('on-agent')));
      expect(
        store.strings.values.expand((v) => v).join(),
        isNot(contains('on-agent')),
      );
    });

    test('approving twice keeps one; the list is bounded', () async {
      final store = InMemorySettingsStore();
      await approveCommand(store, commandHash('a'));
      await approveCommand(store, commandHash('a'));
      expect(store.strings[SettingKeys.agentCommandApproved], hasLength(1));
      for (var i = 0; i < 40; i++) {
        await approveCommand(store, commandHash('c$i'));
      }
      expect(
        store.strings[SettingKeys.agentCommandApproved]!.length,
        lessThanOrEqualTo(20),
      );
      expect(isCommandApproved(store, commandHash('c39')), isTrue);
      expect(isCommandApproved(store, commandHash('a')), isFalse);
    });

    test('anything that is not a hash is not an approval', () {
      final store = InMemorySettingsStore()
        ..strings[SettingKeys.agentCommandApproved] = ['~/bin/on-agent', ''];
      expect(isCommandApproved(store, '~/bin/on-agent'), isFalse);
      expect(isCommandApproved(store, ''), isFalse);
    });
  });
}
