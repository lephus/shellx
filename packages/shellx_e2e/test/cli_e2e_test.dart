@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

import 'support/term_window.dart';

/// The per-launch `SHELLX_CLI_TOKEN` of this host's ShellX shells.
const _token = 'e2e';

/// The tray hint every refused outside terminal gets (A7 amendment).
const _hint = 'Allow other terminals';

/// The window side of the host, as far as a pure-Dart package can have it.
///
/// The real `UiApi` is the desktop's `UiCommandHandler` (apps/desktop): it
/// needs Flutter, Riverpod and xterm, so it cannot run here. Its `ui.*`
/// answers are therefore scripted below, in the handler's shapes (ids as
/// numbers, `read` pages chained by `next`, `wait` results per mode); the
/// desktop's `test/cli/cli_binary_test.dart` runs this same binary against
/// the real handler. What is real: the `shellx` binary, the Unix socket,
/// the endpoint file, the handshake, `CliHost` (token, switch, "Allow other
/// terminals", events), and pane notices, which go to a real
/// [SessionManager] (its shell runs `shellx notify` itself).
final class ScriptedUi implements UiApi {
  ScriptedUi(this.sessions);

  final LocalSessions sessions;
  final requests = <MuxMessage>[];
  final appNotices = <(String?, String)>[];
  final events$ = StreamController<Map<String, Object?>>.broadcast();

  /// A test's own answer for a request type (else the defaults below).
  final answers =
      <String, FutureOr<Map<String, Object?>> Function(MuxMessage)>{};

  List<MuxMessage> sent(String type) =>
      requests.where((r) => r.type == type).toList();

  @override
  Future<Map<String, Object?>> handle(
    MuxMessage r, {
    Future<void>? cancelled,
    bool Function()? isGone,
  }) async {
    requests.add(r);
    final scripted = answers[r.type];
    if (scripted != null) return scripted(r);
    return switch (r.type) {
      CliType.uiLs => {
        'workspaces': [
          {
            'id': 'default',
            'name': 'Default',
            'current': true,
            'collapsed': false,
            'tabs': [
              {
                'id': 100,
                'title': 'build',
                'custom': false,
                'selected': true,
                'unread': 0,
                'running': false,
                'agent': false,
                'panes': [
                  {
                    'id': 100,
                    'kind': 'terminal',
                    'title': 'zsh',
                    'cwd': null,
                    'branch': null,
                    'ports': <int>[],
                    'running': false,
                    'exited': false,
                    'exitCode': null,
                    'focused': true,
                    'zoomed': false,
                    'phone': false,
                    'driver': 'desktop',
                    'agent': false,
                  },
                ],
              },
            ],
          },
        ],
        'selectedTab': 100,
        'focusedPane': 100,
      },
      CliType.uiTabNew => {'tab': 102, 'pane': 102},
      CliType.uiPaneSplit => {'pane': 101, 'tab': 100},
      CliType.uiFocus || CliType.uiClose || CliType.uiPaneSend => const {},
      _ => throw CliFailure(MuxError.unknownType, 'unknown request ${r.type}'),
    };
  }

  @override
  Stream<Map<String, Object?>> events() => events$.stream;

  @override
  Future<void> notifyApp({String? title, required String body}) async =>
      appNotices.add((title, body));

  @override
  bool notifyPane(int pane, {String? title, required String body}) =>
      sessions.notify(pane, title: title, body: body);
}

final class _Sh implements ShellResolver {
  const _Sh();
  @override
  Future<ShellCommand> resolve() async =>
      const ShellCommand(executable: '/bin/sh', arguments: [], name: 'sh');
}

/// Polls [condition] every 20 ms for at most [within].
Future<void> _until(
  bool Function() condition, {
  Duration within = const Duration(seconds: 5),
  String reason = '',
}) async {
  final sw = Stopwatch()..start();
  while (!condition()) {
    if (sw.elapsed > within) fail('timed out: $reason');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late Directory dir;
  late String shellx;
  late String endpoint;
  late SessionManager sessions;
  late CliHost host;
  late ScriptedUi ui;
  var enabled = true;
  var external = false;
  var hostRunning = false;

  setUpAll(() async {
    final bins = await buildTermBinaries();
    // Short: the socket path must fit in sun_path.
    dir = await Directory('/tmp').createTemp('ce');
    shellx = '${dir.path}/shellx';
    // The binary is `shellx` by its name (as the installed copy is).
    await Link(shellx).create(bins.shellxTerm);
    endpoint = '${dir.path}/mux/endpoint';
    sessions = SessionManager(
      ptyFactory: const ProcessPtyFactory(),
      shellResolver: const _Sh(),
      homeDirectory: dir.path,
      // What CliService gives every ShellX shell (Task 9), with the test's
      // endpoint; SessionManager adds SHELLX_PANE_ID / SHELLX_TAB_ID.
      baseEnvironment: {
        'PATH': '${dir.path}:/usr/bin:/bin',
        'HOME': dir.path,
        'SHELLX_ENDPOINT': endpoint,
        'SHELLX_CLI_TOKEN': _token,
        'PS1': r'$ ',
        'ENV': '',
        'HISTFILE': '/dev/null',
      },
    );
  });

  setUp(() async {
    ui = ScriptedUi(sessions);
    enabled = true;
    external = false;
    host = CliHost(
      transport: UnixMuxTransport(),
      address: '${dir.path}/mux.sock',
      endpointFile: MuxEndpointFile(endpoint),
      ui: ui,
      enabled: () => enabled,
      token: _token,
      allowExternal: () => external,
      appVersion: '1.7.0',
    );
    await host.start();
    hostRunning = true;
  });

  tearDown(() async {
    if (hostRunning) await host.stop();
    hostRunning = false;
    await ui.events$.close();
  });

  tearDownAll(() async {
    sessions.closeAll();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await dir.delete(recursive: true);
  });

  /// `shellx` as a ShellX shell runs it ([token] null: an outside terminal).
  Future<ProcessResult> sh(
    List<String> args, {
    String? token = _token,
    Map<String, String> env = const {},
  }) => Process.run(
    shellx,
    args,
    workingDirectory: dir.path,
    environment: {
      'SHELLX_ENDPOINT': endpoint,
      'HOME': dir.path,
      'SHELLX_CLI_TOKEN': ?token,
      ...env,
    },
    includeParentEnvironment: false,
  );

  Future<Process> start(String script, {String? token = _token}) =>
      Process.start(
        '/bin/sh',
        ['-c', script],
        environment: {
          'PATH': '${dir.path}:/usr/bin:/bin',
          'SHELLX_ENDPOINT': endpoint,
          'HOME': dir.path,
          'SHELLX_CLI_TOKEN': ?token,
        },
        includeParentEnvironment: false,
      );

  Matcher exits(int code, {String? stderr, Object? stdout}) =>
      isA<ProcessResult>()
          .having((r) => r.exitCode, 'exitCode', code)
          .having(
            (r) => r.stderr as String,
            'stderr',
            stderr == null ? anything : contains(stderr),
          )
          .having((r) => r.stdout as String, 'stdout', stdout ?? anything);

  group('a ShellX shell (SHELLX_CLI_TOKEN)', () {
    test('ls: --json with prefixed ids, --ids, the text tree', () async {
      final r = await sh(['ls', '--json']);
      expect(r, exits(0));
      final j = jsonDecode(r.stdout as String) as Map<String, dynamic>;
      expect(j['selectedTab'], 't100');
      expect(j['focusedPane'], 'p100');
      final ws = (j['workspaces'] as List).single as Map<String, dynamic>;
      expect(ws['id'], 'w:default');
      final tab = (ws['tabs'] as List).single as Map<String, dynamic>;
      expect(tab['id'], 't100');
      expect(((tab['panes'] as List).single as Map)['id'], 'p100');

      expect(await sh(['ls', '--ids']), exits(0, stdout: 't100\np100\n'));
      final tree = await sh(['ls']);
      expect(tree, exits(0));
      expect(tree.stdout, allOf(contains('t100'), contains('p100')));
    });

    test('new-tab, split, focus, close: the wire fields, only the new id '
        'printed', () async {
      await Directory('${dir.path}/sub').create();
      expect(
        await sh([
          'new-tab',
          '--cwd',
          'sub',
          '--cmd',
          'npm run dev',
          '--focus',
        ]),
        exits(0, stdout: 't102\n'),
      );
      final open = ui.sent(CliType.uiTabNew).single.fields;
      // D14: a relative --cwd is taken from the CLI's directory.
      expect(open['cwd'], allOf(startsWith('/'), endsWith('/sub')));
      expect((open['cmd'], open['focus']), ('npm run dev', true));

      expect(
        await sh(['split', '--down'], env: {'SHELLX_PANE_ID': '100'}),
        exits(0, stdout: 'p101\n'),
      );
      expect(await sh(['split', '--json']), exits(0));
      final splits = ui.sent(CliType.uiPaneSplit);
      // Inside a pane: @self; outside: @focused (the window resolves it).
      expect(splits[0].fields['pane'], 100);
      expect(splits[0].fields['direction'], 'down');
      expect(splits[1].fields['pane'], '@focused');

      expect(await sh(['focus', 't100']), exits(0, stdout: ''));
      expect(ui.sent(CliType.uiFocus).single.fields['tab'], 100);

      expect(await sh(['close', 'p101', '--force']), exits(0, stdout: ''));
      final close = ui.sent(CliType.uiClose).single.fields;
      expect((close['pane'], close['force']), (101, true));

      ui.answers[CliType.uiClose] = (_) => throw const CliFailure(
        CliError.runningCommand,
        'a command is running; use --force',
      );
      expect(await sh(['close', 'p101']), exits(6, stderr: 'running_command'));
    });

    test('send; read fetches every page; wait idle / exit / match', () async {
      expect(
        await sh(['send', 'p100', '--text', 'echo hi', '--enter']),
        exits(0, stdout: ''),
      );
      final send = ui.sent(CliType.uiPaneSend).single.fields;
      expect(
        (send['pane'], send['text'], send['enter']),
        (100, 'echo hi', true),
      );

      // D20: pages chained by `next`.
      ui.answers[CliType.uiPaneRead] = (r) => r.fields['offset'] == null
          ? {'text': 'line 1\n', 'next': 7}
          : {'text': 'line 2\n'};
      expect(
        await sh(['read', 'p100', '--lines', '2']),
        exits(0, stdout: 'line 1\nline 2\n'),
      );
      final reads = ui.sent(CliType.uiPaneRead);
      expect(reads.map((r) => r.fields['offset']), [null, 7]);
      expect(reads.first.fields['lines'], 2);
      final json = await sh(['read', 'p100', '--json']);
      expect(jsonDecode(json.stdout as String), {'text': 'line 1\nline 2\n'});

      ui.answers[CliType.uiPaneWait] = (r) => switch (r.fields['mode']) {
        'exit' => {'exitCode': 3},
        'match' => {'match': 'ready', 'line': 'ready in 4 ms'},
        _ => const {},
      };
      expect(
        await sh(['wait', 'p100', '--idle', '--quiet', '200']),
        exits(0, stdout: ''),
      );
      expect(await sh(['wait', 'p100', '--exit']), exits(0, stdout: '3\n'));
      expect(
        await sh(['wait', 'p100', '--match', 'ready', '--timeout', '5']),
        exits(0, stdout: 'ready in 4 ms\n'),
      );
      final waits = ui.sent(CliType.uiPaneWait).map((r) => r.fields).toList();
      expect((waits[0]['mode'], waits[0]['quietMs']), ('idle', 200));
      expect(waits[1]['mode'], 'exit');
      expect(
        (waits[2]['mode'], waits[2]['pattern'], waits[2]['timeoutMs']),
        ('match', 'ready', 5000),
      );

      // D21: the window's 1 s scan budget refuses a catastrophic pattern.
      ui.answers[CliType.uiPaneWait] = (_) =>
          throw const CliFailure(MuxError.badRequest, 'pattern is too slow');
      expect(
        await sh(['wait', 'p100', '--match', r'^(a+)+$']),
        exits(2, stderr: 'pattern is too slow'),
      );
      ui.answers[CliType.uiPaneWait] = (_) =>
          throw const CliFailure(CliError.timeout, 'timed out');
      expect(await sh(['wait', 'p100', '--idle', '--timeout', '1']), exits(5));
    });

    test('notify inside a real ShellX shell reaches its session '
        '(SHELLX_PANE_ID, D23 path 1)', () async {
      final id = await sessions.open(cols: 80, rows: 24);
      final view = sessions.view(id);
      final out = StringBuffer();
      final outSub = view.output.listen((b) => out.write(utf8.decode(b)));
      final notice = sessions.notices.firstWhere((n) => n.sessionId == id);
      // ProcessPtyFactory runs the shell on pipes: a line ends with LF.
      view.write(
        Uint8List.fromList(
          utf8.encode('shellx notify --title Build xong; echo "rc=\$?"\n'),
        ),
      );
      final n = await notice.timeout(
        const Duration(seconds: 10),
        onTimeout: () => fail('no notice; the shell printed: $out'),
      );
      expect(
        (n.kind, n.title, n.body),
        (SessionNoticeKind.message, 'Build', 'xong'),
      );
      await _until(() => out.toString().contains('rc=0'), reason: 'rc=0');
      expect(ui.appNotices, isEmpty);
      await outSub.cancel();
      view.dispose();
      sessions.close(id);
    });

    test('notify without a pane: the window notification (D23 path 3); a '
        'pane that does not exist → exit 4', () async {
      expect(await sh(['notify', '--title', 'CI', 'done']), exits(0));
      expect(ui.appNotices, [('CI', 'done')]);
      expect(
        await sh(['notify', '--pane', 'p999999', 'x']),
        exits(4, stderr: 'not_found'),
      );
    });

    test(
      'events --for N prints the events it asked for, then exits 0',
      () async {
        final p = await start(
          r'shellx events --for 1.5 --kinds notice,tab.opened',
        );
        final lines = p.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .toList();
        final err = p.stderr.transform(utf8.decoder).join();
        await _until(() => ui.events$.hasListener, reason: 'subscribed');
        ui.events$
          ..add({'kind': 'pane.focused', 'pane': 100, 'tab': 100})
          ..add({'kind': 'tab.opened', 'tab': 5, 'workspace': 'default'});
        expect(
          await p.exitCode.timeout(const Duration(seconds: 5)),
          0,
          reason: await err,
        );
        final got = [for (final l in await lines) jsonDecode(l)];
        expect(got, hasLength(1));
        expect(got.single, containsPair('kind', 'tab.opened'));
        expect(got.single, containsPair('tab', 't5'));
      },
    );

    test('events --follow | head -1 ends once head has gone and frees the '
        'host', () async {
      final p = await start('shellx events --follow | head -1');
      final out = p.stdout.transform(utf8.decoder).join();
      await _until(() => ui.events$.hasListener, reason: 'subscribed');
      expect(host.clientCount, 1);
      ui.events$.add({'kind': 'tab.selected', 'tab': 7});
      final sw = Stopwatch()..start();
      // `head` leaves after one line; shellx notices within about 1 s
      // even though no further event comes (review I1).
      expect(await p.exitCode.timeout(const Duration(seconds: 5)), 0);
      expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
      expect(jsonDecode((await out).trim()), {
        'kind': 'tab.selected',
        'tab': 't7',
      });
      await _until(() => host.clientCount == 0, reason: 'client freed');
      expect(ui.events$.hasListener, isFalse);
    });
  });

  group('refused or not reached', () {
    test('the switch off → exit 6 cli_disabled; notify still works '
        '(D26)', () async {
      enabled = false;
      expect(
        await sh(['send', 'p100', '--text', 'x']),
        exits(6, stderr: 'cli_disabled'),
      );
      expect(await sh(['ls']), exits(6, stderr: 'cli_disabled'));
      expect(await sh(['notify', 'still', 'here']), exits(0));
      expect(ui.sent(CliType.uiPaneSend), isEmpty);
    });

    test('wrong secret → exit 3; stale endpoint (nobody listens) → exit 3 '
        'at once; no endpoint → exit 3', () async {
      final ep = File(endpoint);
      final good = await ep.readAsString();
      final forged = good.replaceFirst(
        RegExp('secret=[0-9a-f]{64}'),
        'secret=${'0' * 64}',
      );
      expect(forged, isNot(good));
      await ep.writeAsString(forged);
      expect(await sh(['ls']), exits(3));
      await ep.writeAsString(good);
      expect(await sh(['ls']), exits(0));

      await host.stop();
      hostRunning = false;
      // A crash or power-off leaves the file; the socket is gone.
      await ep.writeAsString(good);
      await Process.run('/bin/chmod', ['600', endpoint]);
      final sw = Stopwatch()..start();
      expect(await sh(['ls']), exits(3, stderr: 'not_running'));
      expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
      await ep.delete();
      expect(await sh(['ls']), exits(3, stderr: 'ShellX is not running'));
    });

    for (final (who, token) in [('no token', null), ('a wrong token', 'x')]) {
      test('$who (an outside terminal): api.version and a pane-less notify '
          'only; everything else → exit 6 with the tray hint', () async {
        expect(await sh(['notify', 'from', 'cron'], token: token), exits(0));
        expect(ui.appNotices, [(null, 'from cron')]);
        for (final args in [
          ['ls'],
          ['send', 'p100', '--text', 'x'],
          ['split', '--pane', 'p100'],
          ['notify', '--pane', 'p100', 'x'],
          ['events'],
        ]) {
          expect(
            await sh(args, token: token),
            exits(6, stderr: _hint),
            reason: args.join(' '),
          );
        }
        // Nothing reached the window.
        expect(ui.requests, isEmpty);
      });
    }

    test('"Allow other terminals" on → full access without a token; '
        'unticked + recheck → a running events --follow is refused at '
        'once', () async {
      external = true;
      expect(
        await sh(['ls', '--ids'], token: null),
        exits(0, stdout: 't100\np100\n'),
      );
      expect(
        await sh(['split', '--pane', 'p100'], token: null),
        exits(0, stdout: 'p101\n'),
      );

      final p = await start('shellx events --follow', token: null);
      final out = p.stdout.transform(utf8.decoder).join();
      final err = p.stderr.transform(utf8.decoder).join();
      await _until(() => ui.events$.hasListener, reason: 'subscribed');
      external = false;
      final sw = Stopwatch()..start();
      host.recheck();
      expect(await p.exitCode.timeout(const Duration(seconds: 5)), 6);
      expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
      // events is always JSON: the refusal is on stdout.
      expect(
        '${await out}${await err}',
        allOf(contains('forbidden'), contains(_hint)),
      );
      expect(await sh(['ls'], token: null), exits(6, stderr: _hint));
    });
  });

  test('D40: per-command time of shellx ls (debug build; target ≈ 50 ms '
      'release, gate 250 ms)', () async {
    // Warm the file cache and the host.
    await sh(['ls']);
    final ms = <int>[];
    for (var i = 0; i < 20; i++) {
      final sw = Stopwatch()..start();
      final r = await sh(['ls']);
      ms.add(sw.elapsedMilliseconds);
      expect(r.exitCode, 0);
    }
    ms.sort();
    final median = ms[ms.length ~/ 2];
    // Recorded in the ledger (A7 D40).
    print('D40 shellx ls: median $median ms, max ${ms.last} ms (20 runs)');
    expect(median, lessThan(250));
  });
}
