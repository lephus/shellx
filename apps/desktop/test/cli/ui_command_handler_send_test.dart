import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/cli/agent_marks.dart';
import 'package:shellx_desktop/src/cli/pane_text.dart';
import 'package:shellx_desktop/src/cli/ui_command_handler.dart';
import 'package:shellx_desktop/src/terminal/desktop_terminal.dart';
import 'package:shellx_desktop/src/terminal/pane_paste.dart';
import 'package:shellx_desktop/src/terminal/paste_sender.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';
import 'support/cli_container.dart';

void main() {
  late ProviderContainer c;
  late FakeLocalSessions local;
  late UiCommandHandler h;

  Future<Map<String, Object?>> call(String t, Map<String, Object?> f) =>
      h.handle(MuxMessage(t, q: 1, fields: f));
  String written(int id) => local.views[id]!.writes.join();
  Matcher fails(String code) =>
      throwsA(isA<CliFailure>().having((e) => e.code, 'code', code));

  setUp(() async {
    local = FakeLocalSessions();
    c = cliContainer(local);
    h = c.read(uiCommandHandlerProvider);
    await c.read(terminalTabsProvider.notifier).openTab(); // 100
  });

  group('send (D19)', () {
    test('text is a paste: controls stripped, LF → CR, Enter after', () async {
      await call('ui.pane.send', {
        'pane': 100,
        'text': 'echo a\necho \x1b[201~b',
        'enter': true,
      });
      expect(written(100), 'echo a\recho [201~b\r');
      expect(c.read(agentMarksProvider).panes.keys, contains(100));
    });

    test('a 48 KiB send (the CLI limit) arrives whole', () async {
      final text = 'abcdefgh' * 6144;
      await call('ui.pane.send', {'pane': 100, 'text': text});
      expect(written(100), text);
    });

    test('a send during a running paste queues after it, in order', () async {
      final tab = c.read(terminalTabsProvider).selected!;
      final sink = PanePasteSink(
        () => c.read(terminalTabsProvider),
        100,
        tab.focused.terminal,
      );
      final big = 'k' * 400000;
      final first = c.read(pasteSenderProvider).send(100, big, sink);
      await call('ui.pane.send', {'pane': 100, 'text': 'tail', 'enter': true});
      expect(await first, PasteOutcome.sent);
      expect(written(100), '${big}tail\r');
    });

    test('keys alone also wait for a running paste', () async {
      final tab = c.read(terminalTabsProvider).selected!;
      final sink = PanePasteSink(
        () => c.read(terminalTabsProvider),
        100,
        tab.focused.terminal,
      );
      final big = 'k' * 400000;
      unawaited(c.read(pasteSenderProvider).send(100, big, sink));
      await call('ui.pane.send', {
        'pane': 100,
        'keys': ['enter'],
      });
      expect(written(100), '$big\r');
    });

    test('PanePasteSink is not alive for a replaced terminal or an exited '
        'pane', () async {
      final tab = c.read(terminalTabsProvider).selected!;
      final terminal = tab.focused.terminal;
      PanePasteSink sink(DesktopTerminal t) =>
          PanePasteSink(() => c.read(terminalTabsProvider), 100, t);
      expect(sink(terminal).alive, isTrue);
      expect(sink(DesktopTerminal()).alive, isFalse);
      local.views[100]!.end(0);
      await pumpFeed();
      expect(sink(terminal).alive, isFalse);
    });

    test('final M4: a tab (t<id>) means its focused pane', () async {
      await call('ui.pane.send', {'pane': 't100', 'text': 'ls'});
      expect(written(100), 'ls');
    });

    test('bracketed paste when the shell asked for it', () async {
      local.views[100]!.emit('\x1b[?2004h');
      await pumpFeed();
      await call('ui.pane.send', {'pane': 100, 'text': 'ls'});
      expect(written(100), '\x1b[200~ls\x1b[201~');
    });

    test('keys', () async {
      await call('ui.pane.send', {
        'pane': 100,
        'keys': ['ctrl-c', 'up', 'enter', 'tab', 'esc', r'ctrl-\', 'ctrl-]'],
      });
      expect(written(100), '\x03\x1b[A\r\t\x1b\x1c\x1d');
      await expectLater(
        call('ui.pane.send', {
          'pane': 100,
          'keys': ['hyper-x'],
        }),
        fails('bad_request'),
      );
      await expectLater(
        call('ui.pane.send', {
          'pane': 100,
          'keys': [3],
        }),
        fails('bad_request'),
      );
    });

    test('cursor keys follow the application cursor mode', () async {
      local.views[100]!.emit('\x1b[?1h');
      await pumpFeed();
      await call('ui.pane.send', {
        'pane': 100,
        'keys': ['up'],
      });
      expect(written(100), '\x1bOA');
    });

    test('size limit (48 KiB of UTF-8), empty send, exited pane, browser '
        'pane', () async {
      await expectLater(
        call('ui.pane.send', {'pane': 100, 'text': 'x' * 49153}),
        fails('bad_request'),
      );
      // 24,577 characters, 49,154 bytes.
      await expectLater(
        call('ui.pane.send', {'pane': 100, 'text': 'é' * 24577}),
        throwsA(
          isA<CliFailure>().having(
            (e) => e.message,
            'message',
            'text is over 48 KiB',
          ),
        ),
      );
      await call('ui.pane.send', {'pane': 100, 'text': 'é' * 24576});
      await expectLater(
        call('ui.pane.send', {'pane': 100}),
        fails('bad_request'),
      );
      await expectLater(
        call('ui.pane.send', {'pane': -2, 'text': 'x'}),
        fails('bad_request'),
      );
      await expectLater(
        call('ui.pane.send', {'pane': 7, 'text': 'x'}),
        fails('not_found'),
      );
      local.views[100]!.end(1);
      await pumpFeed();
      await expectLater(
        call('ui.pane.send', {'pane': 100, 'text': 'x'}),
        fails('exited'),
      );
    });
  });

  group('A7 Task 7 review', () {
    test('I1: a pane output event fires once its text is in the terminal; '
        'a match on the second of two quick chunks succeeds', () async {
      final terminal = c
          .read(terminalTabsProvider)
          .tabOfSession(100)!
          .panes[100]!
          .terminal;
      final seen = <String>[];
      final sub = c
          .read(terminalTabsProvider.notifier)
          .paneOutputs
          .listen((_) => seen.add(screenText(terminal)));
      addTearDown(sub.cancel);
      final r = call('ui.pane.wait', {
        'pane': 100,
        'mode': 'match',
        'pattern': 'two',
        'fromNow': true,
      });
      await pumpFeed();
      local.views[100]!
        ..emit('one\r\n')
        ..emit('two\r\n');
      expect(await r.timeout(const Duration(seconds: 2)), {
        'match': 'two',
        'line': 'two',
      });
      expect(seen.last, contains('two'));
    });

    test('I2: send exit, the shell ends with 0, then wait --exit still '
        'answers', () async {
      await call('ui.pane.send', {'pane': 100, 'text': 'exit', 'enter': true});
      local.views[100]!.end(0);
      await pumpFeed();
      expect(c.read(terminalTabsProvider).tabOfSession(100), isNull);
      expect(await call('ui.pane.wait', {'pane': 100, 'mode': 'exit'}), {
        'exitCode': 0,
      });
      await expectLater(
        call('ui.pane.wait', {'pane': 100, 'mode': 'idle'}),
        fails('not_found'),
      );
      await expectLater(
        call('ui.pane.wait', {'pane': 999, 'mode': 'exit'}),
        fails('not_found'),
      );
    });

    test('I2: the wait --exit shortcut also takes the p<id> form', () async {
      await call('ui.pane.send', {
        'pane': 'p100',
        'text': 'exit',
        'enter': true,
      });
      local.views[100]!.end(0);
      await pumpFeed();
      expect(await call('ui.pane.wait', {'pane': 'p100', 'mode': 'exit'}), {
        'exitCode': 0,
      });
    });

    test('M6: an unknown key is not echoed back', () async {
      await expectLater(
        call('ui.pane.send', {
          'pane': 100,
          'keys': ['hyper-\x1b]0;x\x07'],
        }),
        throwsA(
          isA<CliFailure>().having(
            (e) => e.message,
            'message',
            isNot(contains('hyper')),
          ),
        ),
      );
    });

    test('M1: a catastrophic pattern never freezes the window; the wait '
        'fails fast with "pattern is too slow"', () async {
      local.views[100]!.emit('${'a' * 34}b\r\n');
      await pumpFeed();
      var ticks = 0;
      final tick = Timer.periodic(
        const Duration(milliseconds: 20),
        (_) => ticks++,
      );
      addTearDown(tick.cancel);
      final watch = Stopwatch()..start();
      await expectLater(
        call('ui.pane.wait', {
          'pane': 100,
          'mode': 'match',
          'pattern': r'(a+)+$',
          'timeoutMs': 60000,
        }),
        throwsA(
          isA<CliFailure>()
              .having((e) => e.code, 'code', 'bad_request')
              .having((e) => e.message, 'message', 'pattern is too slow'),
        ),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(ticks, greaterThan(20)); // the UI isolate kept running
    });

    test('M3: a client that leaves ends its wait with cancelled', () async {
      final left = Completer<void>();
      final r = h.handle(
        const MuxMessage(
          'ui.pane.wait',
          q: 1,
          fields: {'pane': 100, 'mode': 'idle'},
        ),
        cancelled: left.future,
      );
      left.complete();
      await expectLater(r, fails(CliError.cancelled));
    });
  });

  group('read (D20)', () {
    test('the screen by default; --lines, --ansi; bad lines', () async {
      local.views[100]!.emit('hello\r\n\x1b[1mworld\x1b[0m\r\n');
      await pumpFeed();
      final r = await call('ui.pane.read', {'pane': 100});
      expect(r['text'], 'hello\nworld\n');
      expect(r.containsKey('next'), isFalse);
      final last = await call('ui.pane.read', {
        'pane': 100,
        'lines': 1,
        'ansi': true,
      });
      expect(last['text'], '\x1b[0;1mworld\x1b[0m\n');
      await expectLater(
        call('ui.pane.read', {'pane': 100, 'lines': 0}),
        fails('bad_request'),
      );
      await expectLater(
        call('ui.pane.read', {'pane': 100, 'lines': 10001}),
        fails('bad_request'),
      );
      await expectLater(
        call('ui.pane.read', {'pane': 100, 'offset': -1}),
        fails('bad_request'),
      );
    });

    test('pages chain through offset', () async {
      final line = 'x' * 79;
      local.views[100]!.emit('${List.filled(1000, line).join('\r\n')}\r\n');
      await pumpFeed();
      final first = await call('ui.pane.read', {'pane': 100, 'lines': 1000});
      final next = first['next']! as int;
      final rest = await call('ui.pane.read', {
        'pane': 100,
        'lines': 1000,
        'offset': next,
      });
      expect(rest.containsKey('next'), isFalse);
      expect(
        '${first['text']}${rest['text']}',
        '${List.filled(1000, line).join('\n')}\n',
      );
    });
  });

  group('wait (D21)', () {
    test('a bad regex, an over-long pattern, a bad timeout or mode is '
        'bad_request', () async {
      await expectLater(
        call('ui.pane.wait', {
          'pane': 100,
          'mode': 'match',
          'pattern': '(',
          'timeoutMs': 1000,
        }),
        fails('bad_request'),
      );
      await expectLater(
        call('ui.pane.wait', {
          'pane': 100,
          'mode': 'match',
          'pattern': 'é' * 513,
        }),
        fails('bad_request'),
      );
      await expectLater(
        call('ui.pane.wait', {
          'pane': 100,
          'mode': 'idle',
          'timeoutMs': 3600001,
        }),
        fails('bad_request'),
      );
      await expectLater(
        call('ui.pane.wait', {'pane': 100, 'mode': 'later'}),
        fails('bad_request'),
      );
    });

    test('exit 0 removes the pane; wait exit still reports the code', () async {
      final r = call('ui.pane.wait', {'pane': 100, 'mode': 'exit'});
      await pumpFeed();
      local.views[100]!.end(0);
      expect(await r, {'exitCode': 0});
      expect(c.read(terminalTabsProvider).tabOfSession(100), isNull);
      expect(c.read(terminalTabsProvider.notifier).lastExitCode(100), 0);
    });

    test('final M2: a pane closed while waited on (or before) answers '
        'closed, never a bare null', () async {
      await c.read(terminalTabsProvider.notifier).openTab(); // 101
      final r = call('ui.pane.wait', {'pane': 101, 'mode': 'exit'});
      await pumpFeed();
      await call('ui.close', {'pane': 101, 'force': true});
      expect(await r, {'exitCode': null, 'closed': true});
      expect(await call('ui.pane.wait', {'pane': 101, 'mode': 'exit'}), {
        'exitCode': null,
        'closed': true,
      });
      // The tab's close (every pane) too.
      await c.read(terminalTabsProvider.notifier).openTab(); // 102
      c.read(terminalTabsProvider.notifier).close(102);
      expect(await call('ui.pane.wait', {'pane': 102, 'mode': 'exit'}), {
        'exitCode': null,
        'closed': true,
      });
    });

    test('an exited pane answers at once with its code', () async {
      local.views[100]!.end(4);
      await pumpFeed();
      expect(await call('ui.pane.wait', {'pane': 100, 'mode': 'exit'}), {
        'exitCode': 4,
      });
    });

    test('match sees output that arrives later', () async {
      final r = call('ui.pane.wait', {
        'pane': 100,
        'mode': 'match',
        'pattern': r'port \d+',
        'fromNow': true,
      });
      await pumpFeed();
      local.views[100]!.emit('listening on port 3000\r\n');
      expect(await r.timeout(const Duration(seconds: 2)), {
        'match': 'port 3000',
        'line': 'listening on port 3000',
      });
    });

    test('idle on a hooked shell: once its command ends and output is '
        'quiet', () async {
      local.setRunning(100, true);
      local.replace(
        local.summary(
          100,
          origin: SessionOrigin.desktop,
          cwd: '/w',
          runningCommand: true,
        ),
      );
      var done = false;
      final r = call('ui.pane.wait', {
        'pane': 100,
        'mode': 'idle',
        'quietMs': 50,
      }).then((v) => done = true);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(done, isFalse);
      local.setRunning(100, false);
      await r.timeout(const Duration(seconds: 2));
      expect(done, isTrue);
    });

    test('a client that leaves ends its wait', () async {
      final left = Completer<void>();
      final r = h.handle(
        const MuxMessage(
          'ui.pane.wait',
          q: 1,
          fields: {'pane': 100, 'mode': 'exit', 'timeoutMs': 3600000},
        ),
        cancelled: left.future,
      );
      left.complete();
      await expectLater(
        r.timeout(const Duration(milliseconds: 500)),
        fails('cancelled'),
      );
    });

    test('timeout', () async {
      await expectLater(
        call('ui.pane.wait', {'pane': 100, 'mode': 'exit', 'timeoutMs': 30}),
        fails('timeout'),
      );
    });
  });

  group('--cmd (D16)', () {
    test('typed once the new shell reports its cwd, with Enter', () async {
      final r = await call('ui.tab.new', {'cmd': 'npm run dev\nx'});
      final id = r['pane']! as int;
      await pumpFeed();
      expect(written(id), isEmpty);
      local.replace(
        local.summary(id, origin: SessionOrigin.desktop, cwd: '/w'),
      );
      await pumpEventQueue();
      expect(written(id), 'npm run dev\rx\r');
    });

    test(
      'a split with --cmd too; over 16 KiB of UTF-8 is bad_request',
      () async {
        final r = await call('ui.pane.split', {'pane': 100, 'cmd': 'ls'});
        final id = r['pane']! as int;
        local.replace(
          local.summary(id, origin: SessionOrigin.desktop, cwd: '/w'),
        );
        await pumpEventQueue();
        expect(written(id), 'ls\r');
        await expectLater(
          call('ui.tab.new', {'cmd': 'é' * 8193}),
          fails('bad_request'),
        );
        expect(local.opens, hasLength(2));
      },
    );
  });
}
