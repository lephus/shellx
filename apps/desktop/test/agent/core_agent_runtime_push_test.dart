import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/agent/agent_runtime.dart';
import 'package:shellx_desktop/src/agent/notify_threshold.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';

import '../support/fakes.dart' as fakes show phone;

final class _Pty implements Pty {
  final _output = StreamController<Uint8List>.broadcast(sync: true);
  final _exit = Completer<int>();

  void emit(String text) => _output.add(Uint8List.fromList(utf8.encode(text)));

  @override
  Stream<Uint8List> get output => _output.stream;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  void write(Uint8List data) {}
  @override
  void resize(int cols, int rows) {}
  @override
  void kill() {
    if (!_exit.isCompleted) _exit.complete(0);
  }
}

final class _PtyFactory implements PtyFactory {
  final List<({ShellCommand command, Map<String, String> environment})>
  spawned = [];
  final List<_Pty> ptys = [];

  @override
  Pty spawn(
    ShellCommand command, {
    required String workingDirectory,
    required Map<String, String> environment,
    required int cols,
    required int rows,
  }) {
    spawned.add((command: command, environment: environment));
    final pty = _Pty();
    ptys.add(pty);
    return pty;
  }
}

final class _Zsh implements ShellResolver {
  @override
  Future<ShellCommand> resolve() async => const ShellCommand(
    executable: '/bin/zsh',
    arguments: ['-l'],
    name: 'zsh',
  );
}

const String esc = '\x1b';
const String bel = '\x07';
const String phone = '33333333-3333-4333-8333-333333333333';

void main() {
  late Directory hooks;
  late List<http.Request> posts;
  late InMemorySettingsStore settings;
  late _PtyFactory ptys;
  late DateTime now;
  var sentValue = 1;

  setUp(() {
    hooks = Directory.systemTemp.createTempSync('shellx-hooks-');
    posts = [];
    settings = InMemorySettingsStore();
    ptys = _PtyFactory();
    now = DateTime.utc(2026, 10, 5, 12);
    sentValue = 1;
  });

  tearDown(() => hooks.deleteSync(recursive: true));

  Future<CoreAgentRuntime> build({bool push = true}) async {
    final api = ShellxApi(
      baseUri: Uri.parse('https://relay.test'),
      httpClient: MockClient((request) async {
        posts.add(request);
        return http.Response('{"sent":$sentValue}', 202);
      }),
    )..token = 'agent-token';
    return CoreAgentRuntime(
      RuntimeParams(
        credentials: const AgentCredentials(
          token: 'agent-token',
          deviceId: '22222222-2222-4222-8222-222222222222',
          userId: '11111111-1111-4111-8111-111111111111',
          email: 'phu@example.com',
        ),
        identity: await NoiseKeyPair.generate(),
        trusted: TrustedStore(InMemoryKeyValueStore()),
        api: api,
      ),
      relayBaseUri: Uri.parse('https://relay.test'),
      appVersion: '1.0.0',
      ptyFactory: ptys,
      shellResolver: _Zsh(),
      homeDirectory: '/Users/phu',
      baseEnvironment: const {'HOME': '/Users/phu'},
      notifications: push
          ? PushNotificationsSetup(
              threshold: () => notifyThreshold(settings),
              machineName: () => 'MacBook-Pro',
              locale: () => 'vi_VN',
              hooksDirectory: hooks.path,
            )
          : null,
      connector: (uri, headers) async =>
          throw const SocketException('offline in tests'),
      now: () => now,
    );
  }

  Future<_Pty> openSession(CoreAgentRuntime runtime) async {
    await runtime.shellSessions.handle(
      phone,
      const SessionOpen(cols: 80, rows: 24),
    );
    return ptys.ptys.last;
  }

  Map<String, dynamic> body(http.Request request) =>
      jsonDecode(request.body) as Map<String, dynamic>;

  test(
    'a ShellX session starts zsh with the hook and its long command '
    'is pushed with the signed-in agent\'s token (push spec §4, §7)',
    () async {
      final runtime = await build();
      final pty = await openSession(runtime);
      final spawned = ptys.spawned.single;
      expect(spawned.environment['ZDOTDIR'], startsWith(hooks.path));

      pty.emit('$esc]633;E;npm test$bel$esc]133;C$bel');
      now = now.add(const Duration(minutes: 3, seconds: 12));
      pty.emit('$esc]133;D;1$bel');
      await runtime.notifications!.sender.idle;

      final post = posts.single;
      expect(post.url.path, '/v1/notifications');
      expect(post.headers['authorization'], 'Bearer agent-token');
      expect(body(post)['title'], 'MacBook-Pro · Phiên 1');
      expect(body(post)['body'], '✗ npm test · mã 1 · 3 phút 12 giây');
      runtime.closeAllSessions();
    },
  );

  test(
    'the threshold is read from the settings when the command ends',
    () async {
      final runtime = await build();
      final pty = await openSession(runtime);

      Future<void> command(Duration takes) async {
        pty.emit('$esc]133;C$bel');
        now = now.add(takes);
        pty.emit('$esc]133;D;0$bel');
        await runtime.notifications!.sender.idle;
      }

      await command(const Duration(seconds: 20)); // under the default 30 s
      expect(posts, isEmpty);
      await settings.setInt(SettingKeys.notifyThreshold, 10);
      await command(const Duration(seconds: 20));
      expect(posts, hasLength(1));
      await settings.setInt(SettingKeys.notifyThreshold, 0); // "Tắt"
      await command(const Duration(minutes: 10));
      expect(posts, hasLength(1));

      // Messages from programs do not depend on the threshold.
      pty.emit('$esc]777;notify;Build;xong$bel');
      await runtime.notifications!.sender.idle;
      expect(posts, hasLength(2));
      expect(body(posts.last)['title'], 'Build');
      runtime.closeAllSessions();
    },
  );

  test('paused after an unheard notification ({sent: 0}), a phone connecting '
      'lets the next one through', () async {
    sentValue = 0;
    final runtime = await build();
    final pty = await openSession(runtime);
    pty.emit('$esc]9;one$bel');
    await runtime.notifications!.sender.idle;
    pty.emit('$esc]9;two$bel');
    await runtime.notifications!.sender.idle;
    expect(posts, hasLength(1));

    sentValue = 1;
    runtime.onAgentEvent(const ActiveChannelsChanged(1));
    pty.emit('$esc]9;three$bel');
    await runtime.notifications!.sender.idle;
    expect(posts, hasLength(2));
    expect(body(posts.last)['body'], 'three');

    // A channel closing does not lift a new pause; a pairing does.
    sentValue = 0;
    pty.emit('$esc]9;four$bel');
    await runtime.notifications!.sender.idle;
    runtime.onAgentEvent(const ActiveChannelsChanged(0));
    pty.emit('$esc]9;five$bel');
    await runtime.notifications!.sender.idle;
    expect(posts, hasLength(3));
    runtime.onAgentEvent(MobilePaired(fakes.phone('m1', 'iPhone')));
    pty.emit('$esc]9;six$bel');
    await runtime.notifications!.sender.idle;
    expect(posts, hasLength(4));
    runtime.closeAllSessions();
  });

  test(
    'without the setup nothing is wired (the shell starts unchanged)',
    () async {
      final runtime = await build(push: false);
      final pty = await openSession(runtime);
      expect(runtime.notifications, isNull);
      expect(ptys.spawned.single.environment.containsKey('ZDOTDIR'), isFalse);
      pty.emit('$esc]9;hello$bel');
      await pumpEventQueue();
      expect(posts, isEmpty);
      runtime.closeAllSessions();
    },
  );
}
