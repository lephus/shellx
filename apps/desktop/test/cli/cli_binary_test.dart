@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shellx_desktop/src/cli/cli_service.dart';
import 'package:shellx_desktop/src/mux/mux_paths.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';
import 'support/cli_container.dart';

/// A7 D37c with the real window handler: the `shellx` binary against
/// [CliService] (real `CliHost`, real `UiCommandHandler`, the tab list and
/// its terminals) over a Unix socket. Only the shells are fake
/// ([FakeLocalSessions]): what a pane shows is emitted by the test. The
/// pure-Dart `packages/shellx_e2e/test/cli_e2e_test.dart` covers the host's
/// access rules and events with a scripted window.
///
/// Needs a built `shellx-term` (`dart test` in packages/shellx_e2e builds
/// it, or `cargo build` in term/, or SHELLX_TERM_BINARY). Skipped, saying
/// why, when there is none.
String? _findBinary() {
  final explicit = Platform.environment['SHELLX_TERM_BINARY'];
  if (explicit != null && File(explicit).existsSync()) return explicit;
  final target = p.normalize(
    p.join(Directory.current.path, '..', '..', 'term', 'target'),
  );
  // The newest build: an old one may predate the command line.
  final found = [
    for (final c in [
      p.join(target, 'debug', 'shellx-term'),
      p.join(target, 'release', 'shellx-term'),
    ])
      if (File(c).existsSync()) File(c),
  ]..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  return found.isEmpty ? null : found.first.path;
}

void main() {
  final binary = _findBinary();
  final skip = binary == null
      ? 'no built shellx-term (dart test in packages/shellx_e2e, or cargo '
            'build in term/)'
      : false;
  final token = 'c0de' * 16;

  late Directory dir;
  late String shellx;
  late MuxPaths paths;
  late FakeLocalSessions local;
  late CliService svc;
  late TerminalTabs tabs;

  setUp(() async {
    if (binary == null) return;
    // Short: the socket path must fit in sun_path.
    dir = await Directory('/tmp').createTemp('cb');
    shellx = '${dir.path}/shellx';
    await Link(shellx).create(binary);
    paths = MuxPaths(
      muxDirectory: '${dir.path}/mux',
      tmpDirectory: dir.path,
      uid: 501,
      windows: false,
    );
    local = FakeLocalSessions();
    final c = cliContainer(
      local,
      overrides: [cliMuxPathsProvider.overrideWithValue(paths)],
    );
    addTearDown(c.dispose);
    tabs = c.read(terminalTabsProvider.notifier);
    await tabs.openTab(); // the user's tab 100
    svc = await CliService.start(
      c,
      appVersion: '1.7.0',
      token: token,
      installBinary: false,
    );
  });

  tearDown(() async {
    if (binary == null) return;
    await svc.stop();
    await dir.delete(recursive: true);
  });

  Future<Process> start(List<String> args) => Process.start(
    shellx,
    args,
    environment: {
      'SHELLX_ENDPOINT': paths.endpoint,
      'SHELLX_CLI_TOKEN': token,
      'HOME': dir.path,
    },
    includeParentEnvironment: false,
  );

  Future<(int, String, String)> sh(List<String> args) async {
    final proc = await start(args);
    final out = proc.stdout.transform(utf8.decoder).join();
    final err = proc.stderr.transform(utf8.decoder).join();
    return (await proc.exitCode, await out, await err);
  }

  String written(int id) => local.views[id]!.writes.join();

  test('ls, new-tab, split, focus, close against the real tab list', () async {
    final (code, out, err) = await sh(['ls', '--json']);
    expect(code, 0, reason: err);
    final ls = jsonDecode(out) as Map<String, dynamic>;
    expect((ls['selectedTab'], ls['focusedPane']), ('t100', 'p100'));

    expect(await sh(['new-tab']), (0, 't101\n', ''));
    expect(await sh(['split', '--pane', 'p100', '--down']), (0, 'p102\n', ''));
    final state = tabs.state;
    expect(state.tabOfSession(101)?.id, 101);
    expect(state.tabOfSession(102)?.id, 100);
    // D15: the user's selection stays.
    expect(state.selectedId, 100);

    expect(await sh(['focus', 't101']), (0, '', ''));
    expect(tabs.state.selectedId, 101);
    expect(await sh(['close', 'p102', '--force']), (0, '', ''));
    expect(tabs.state.tabOfSession(102), isNull);
    final (missing, _, notFound) = await sh(['close', 'p102']);
    expect(missing, 4);
    expect(notFound, contains('not_found'));
  }, skip: skip);

  test('send types as a paste; read fetches 10,000 lines over every page '
      'in order', () async {
    expect(await sh(['send', 'p100', '--text', 'echo hi', '--enter']), (
      0,
      '',
      '',
    ));
    expect(written(100), 'echo hi\r');

    local.views[100]!.emit(
      [for (var i = 0; i < 10000; i++) 'line $i ${'x' * 20}'].join('\r\n'),
    );
    await pumpFeed();
    final sw = Stopwatch()..start();
    final (code, out, err) = await sh(['read', 'p100', '--lines', '10000']);
    sw.stop();
    expect(code, 0, reason: err);
    final lines = const LineSplitter().convert(out);
    expect(lines, hasLength(10000));
    expect(lines.first, 'line 0 ${'x' * 20}');
    expect(lines.last, 'line 9999 ${'x' * 20}');
    // Over 48 KiB: the CLI followed `next` across pages.
    expect(out.length, greaterThan(5 * 49152));
    // D40 (recorded in the ledger): the CLI's whole read, end to end.
    // ignore: avoid_print
    print('D40 shellx read --lines 10000: ${sw.elapsedMilliseconds} ms');

    final (screen, text, _) = await sh(['read', 'p100']);
    expect(screen, 0);
    expect(text.trimRight().split('\n').last, 'line 9999 ${'x' * 20}');
  }, skip: skip);

  test('wait: match on later output, exit code, idle, and a pattern that '
      'is too slow (exit 2)', () async {
    final matching = start(['wait', 'p100', '--match', r'ready in \d+']);
    final matchOut = (await matching).stdout.transform(utf8.decoder).join();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    local.views[100]!.emit('compiling\r\nready in 42 ms\r\n');
    expect(
      await (await matching).exitCode.timeout(const Duration(seconds: 5)),
      0,
    );
    expect(await matchOut, 'ready in 42 ms\n');

    await sh(['split', '--pane', 'p100']); // p101
    final exiting = start(['wait', 'p101', '--exit']);
    final exitOut = (await exiting).stdout.transform(utf8.decoder).join();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    local.views[101]!.end(3);
    expect(
      await (await exiting).exitCode.timeout(const Duration(seconds: 5)),
      0,
    );
    expect(await exitOut, '3\n');

    // A shell without hooks: idle after 2 s without output.
    final idle = Stopwatch()..start();
    expect(await sh(['wait', 'p100', '--idle', '--timeout', '10']), (
      0,
      '',
      '',
    ));
    expect(idle.elapsed, greaterThanOrEqualTo(const Duration(seconds: 2)));

    local.views[100]!.emit('${'a' * 40}b\r\n');
    await pumpFeed();
    final (slow, _, why) = await sh([
      'wait',
      'p100',
      '--match',
      r'^(a+)+$',
      '--timeout',
      '10',
    ]);
    expect(slow, 2);
    expect(why, contains('pattern is too slow'));

    final (timedOut, _, _) = await sh([
      'wait',
      'p100',
      '--match',
      'never',
      '--timeout',
      '0.5',
    ]);
    expect(timedOut, 5);
  }, skip: skip);

  test('notify inside a pane reaches its session', () async {
    final proc = await Process.start(
      shellx,
      ['notify', 'Build', 'xong'],
      environment: {
        'SHELLX_ENDPOINT': paths.endpoint,
        'SHELLX_CLI_TOKEN': token,
        'SHELLX_PANE_ID': '100',
        'HOME': dir.path,
      },
      includeParentEnvironment: false,
    );
    expect(await proc.exitCode, 0);
    expect(local.notified, [(100, null, 'Build xong')]);
  }, skip: skip);
}
