@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/cli/cli_service.dart';
import 'package:shellx_desktop/src/cli/cli_settings.dart';
import 'package:shellx_desktop/src/mux/mux_paths.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart'
    show settingsStoreProvider;

import '../support/fake_local_sessions.dart';
import 'support/cli_container.dart';

void main() {
  late Directory dir;
  late MuxPaths paths;
  setUp(() async {
    // Short: the socket path must fit in sun_path.
    dir = await Directory('/tmp').createTemp('cs');
    paths = MuxPaths(
      muxDirectory: '${dir.path}/mux',
      tmpDirectory: dir.path,
      uid: 501,
      windows: false,
    );
  });
  tearDown(() => dir.delete(recursive: true));

  final token = 'f00d' * 16;

  Future<MuxConnection> connect({String? token}) async {
    final info = (await MuxEndpointFile(paths.endpoint).read())!;
    final conn = await UnixMuxTransport().connect(info.address);
    await clientHandshake(
      conn,
      secret: info.secret,
      app: 't',
      role: 'cli',
      token: token,
    );
    return conn;
  }

  Future<MuxMessage> ask(MuxConnection conn, String t, int q) {
    final f = conn.messages.firstWhere((m) => m.q == q);
    conn.send(MuxMessage(t, q: q));
    return f;
  }

  test('serves api.version over a real socket to a ShellX shell; the '
      'switch applies at once; stop removes the endpoint', () async {
    final c = cliContainer(
      FakeLocalSessions(),
      overrides: [cliMuxPathsProvider.overrideWithValue(paths)],
    );
    addTearDown(c.dispose);
    final svc = await CliService.start(
      c,
      appVersion: '1.7.0',
      token: token,
      installBinary: false,
    );
    addTearDown(svc.stop);
    expect(svc.address, paths.address);
    // D30: the directory is the user's alone.
    final mode = (await Process.run('/usr/bin/stat', [
      '-f',
      '%Lp',
      paths.muxDirectory,
    ])).stdout.toString().trim();
    expect(mode, '700');
    final conn = await connect(token: token);
    expect((await ask(conn, 'api.version', 1)).get<int>('api'), 1);
    expect((await ask(conn, 'ui.ls', 2)).type, isNot('error'));
    await c
        .read(settingsStoreProvider)
        .setBool(SettingKeys.cliControlEnabled, false);
    expect((await ask(conn, 'ui.ls', 3)).get<String>('code'), 'cli_disabled');
    await conn.close();
    await svc.stop();
    expect(File(paths.endpoint).existsSync(), isFalse);
  });

  test('amendment: without the token, a terminal is refused until "Allow '
      'other terminals" is ticked; unticking refuses it at once', () async {
    final c = cliContainer(
      FakeLocalSessions(),
      overrides: [cliMuxPathsProvider.overrideWithValue(paths)],
    );
    final svc = await CliService.start(
      c,
      appVersion: '1.7.0',
      token: token,
      installBinary: false,
    );
    addTearDown(svc.stop);

    final outside = await connect();
    // api.version keeps its rule.
    expect((await ask(outside, 'api.version', 1)).get<int>('api'), 1);
    final refused = await ask(outside, 'ui.ls', 2);
    expect(refused.get<String>('code'), 'forbidden');
    expect(refused.get<String>('message'), contains('Allow other terminals'));
    await outside.done.timeout(const Duration(seconds: 2));

    final wrong = await connect(token: 'bad' * 8);
    expect((await ask(wrong, 'ui.ls', 1)).get<String>('code'), 'forbidden');

    await c.read(cliSettingsProvider.notifier).setAllowExternal(true);
    expect(
      c
          .read(settingsStoreProvider)
          .getBool(SettingKeys.cliAllowExternal, defaultValue: false),
      isTrue,
    );
    final allowed = await connect();
    expect((await ask(allowed, 'ui.ls', 1)).type, isNot('error'));
    // A subscription while allowed, then untick: refused and closed now,
    // not at its next request (CliHost.recheck through the setting).
    expect(
      (await ask(allowed, 'cli.events.subscribe', 2)).type,
      isNot('error'),
    );
    final closed = allowed.done.timeout(const Duration(seconds: 2));
    await c.read(cliSettingsProvider.notifier).setAllowExternal(false);
    await closed;
  });

  test('the host holds the mux lock: another process cannot take it, so '
      'two hosts never serve one directory', () async {
    final c = cliContainer(
      FakeLocalSessions(),
      overrides: [cliMuxPathsProvider.overrideWithValue(paths)],
    );
    final svc = await CliService.start(
      c,
      appVersion: '1.7.0',
      token: token,
      installBinary: false,
    );
    expect(await _lockFromAnotherProcess(paths.lock), isFalse);
    await svc.stop();
    expect(await _lockFromAnotherProcess(paths.lock), isTrue);
  });
}

/// Tries to take [path]'s exclusive lock from a child Dart process.
Future<bool> _lockFromAnotherProcess(String path) async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) fail('FLUTTER_ROOT is not set');
  final script = File('${File(path).parent.parent.path}/probe.dart')
    ..writeAsStringSync("""
import 'dart:io';
void main(List<String> args) {
  final f = File(args.single).openSync(mode: FileMode.append);
  try {
    f.lockSync(FileLock.exclusive);
    stdout.write('locked');
  } on FileSystemException {
    stdout.write('busy');
  }
}
""");
  final r = await Process.run('$root/bin/cache/dart-sdk/bin/dart', [
    script.path,
    path,
  ]);
  script.deleteSync();
  expect(r.stdout, anyOf('locked', 'busy'), reason: '${r.stderr}');
  return r.stdout == 'locked';
}
