import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/agent/agent_runtime.dart'
    show PushNotificationsSetup;
import 'package:shellx_desktop/src/agent/daemon_ai.dart';
import 'package:shellx_desktop/src/agent/session_core.dart';
import 'package:shellx_desktop/src/ai/ai_phone.dart';
import 'package:shellx_desktop/src/ai/ai_runtimes.dart';
import 'package:shellx_desktop/src/ai/ai_startup.dart' show stopAi;
import 'package:shellx_desktop/src/mux/daemon_state.dart';

import '../cli/support/cli_container.dart';
import '../mux/mux_test_support.dart';
import '../support/ai_fakes.dart';
import '../support/ai_tabs.dart';
import '../support/fake_local_sessions.dart';
import '../support/fake_pty.dart';

const _phone = '33333333-3333-4333-8333-333333333333';
const _info = MuxPeerInfo(protocol: kMuxProtocol, app: 't', instance: 'i');

/// What one phone was sent, read the way the phone reads it.
final class _Phone {
  final got = <AiMessage>[];
  final lists = <SessionListResult>[];

  void take(OutboundMessage o) {
    if (o.mobileId != _phone) return;
    switch (o.message) {
      case final AiMessage m:
        got.add(m);
      case final SessionListResult m:
        lists.add(m);
      default:
        break;
    }
  }

  List<T> all<T extends AiMessage>() => got.whereType<T>().toList();

  AiListing listing() {
    final r = all<AiListResult>().last;
    return AiListing.fromJson(decodeBody(r.body)!, available: r.available);
  }

  AiResult? result(int rid) =>
      all<AiResult>().where((r) => r.rid == rid).lastOrNull;

  /// Its copy of [sid], from every body it was sent.
  AiMirror mirror(String sid) {
    final m = AiMirror();
    for (final message in got) {
      switch (message) {
        case AiSnapshot(sid: final s, :final body) when s == sid:
          m.apply(decodeBody(body)!, snapshot: true);
        case AiUpdate(sid: final s, :final body) when s == sid:
          m.apply(decodeBody(body)!, snapshot: false);
        default:
          break;
      }
    }
    return m;
  }

  /// What the agent wrote in [sid], as the phone shows it.
  String agentText(String sid) => [
    for (final item in mirror(sid).items)
      if (item case MirrorText(kind: MirrorTextKind.agent, :final text)) text,
  ].join('\n');
}

Future<void> _until(bool Function() test) async {
  for (var i = 0; i < 400 && !test(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(test(), isTrue, reason: 'condition not reached');
}

/// The process's sessions, as `main.dart` (in-process) or the background
/// service builds them. With [posts], its push notifications go there.
SessionCore _core({List<http.Request>? posts}) => SessionCore(
  ptyFactory: FakePtyFactory(),
  shellResolver: const FixedShellResolver(),
  homeDirectory: '/Users/phu',
  baseEnvironment: const {'HOME': '/Users/phu'},
  api: ShellxApi(
    baseUri: Uri.parse('https://relay.test'),
    httpClient: MockClient((request) async {
      posts?.add(request);
      return http.Response('{"sent":1}', 202);
    }),
  )..token = 'agent-token',
  notifications: posts == null
      ? null
      : PushNotificationsSetup(
          threshold: () => null,
          machineName: () => 'MacBook-Pro',
          locale: () => 'vi_VN',
        ),
);

/// A runtime's router (what a relay link delivers a phone's messages to).
SessionRouter _router(SessionCore core, _Phone phone) {
  final router = SessionRouter(
    shells: core.sessions,
    desktop: DesktopSessionManager(nextId: core.ids),
    desktopSharing: () => false,
    ai: core.ai,
  );
  router.outbound.listen(phone.take);
  addTearDown(router.dispose);
  return router;
}

/// A background service on [core] (what `daemon_main.dart` sets up), with
/// the window's link to it (what `daemon_state.dart` adopts).
Future<(MuxClient, DaemonLink)> _service(SessionCore core) async {
  final listener = TestListener();
  final server = MuxServer(
    sessions: core.sessions,
    secret: testSecret,
    self: _info,
    onQuit: () async {},
  )..serve(listener);
  addTearDown(server.close);
  installDaemonAi(server, core);
  final client = await attachClient(listener);
  return (
    client,
    DaemonLink(sessions: RemoteLocalSessions(client), info: _info),
  );
}

ProviderContainer _window(
  FakeScenario scenario, [
  List<Override> more = const [],
]) => cliContainer(
  FakeLocalSessions(),
  overrides: [...FakeAiRuntimes(scenario).overrides, ...more],
);

/// V2-2 D1, D11: how the window is wired to phones, in-process and through
/// the background service, end to end over the real hub, real runtimes on
/// fake agents, a real router and a real mux server.
void main() {
  test('in-process: a phone reaches a running AI tab through a router and '
      'the agent side\'s slot, and back; before the hub is plugged in AI is '
      'advertised but unavailable (V2-2 D1, D3)', () async {
    final c = _window(
      FakeScenario(
        turns: [
          [FakeSteps.text('Xin chào'), FakeSteps.stop('end_turn')],
        ],
      ),
    );
    final core = _core();
    final phone = _Phone();
    final router = _router(core, phone);
    final ai = openTestAiTab(c, cwd: testAiCwd, select: false);

    await router.handle(_phone, const SessionList(desktop: true));
    await router.handle(_phone, const AiList());
    expect(phone.lists.single.ai, kAiProtocol);
    expect(phone.all<AiListResult>().single.available, isFalse);

    startAiPhone(c, slot: core.ai); // what main.dart does in-process
    await router.handle(_phone, const AiList());
    final listing = phone.listing();
    expect(listing.available, isTrue);
    final sid = listing.sessions.single.sid;
    await router.handle(_phone, AiAttach(sid: sid));
    await _until(() => phone.mirror(sid).head?.phase == 'ready');
    await router.handle(_phone, AiPrompt(sid: sid, rid: 1, text: 'Chào'));
    await _until(() => phone.agentText(sid) == 'Xin chào');
    expect(phone.result(1)?.ok, isTrue);
    final desktop = c
        .read(aiRuntimesProvider.notifier)
        .existing(ai.ai!.id)!
        .state;
    expect(desktop.timeline.items.whereType<UserItem>().single.text, 'Chào');
  });

  for (final quit in [true, false]) {
    test(
      quit
          ? 'the window quits: its phones hear desktop_closed, then the slot '
                'answers unavailable, and the agents stop unseen'
          : 'the hub is disposed: its phones hear desktop_closed, then the '
                'slot answers unavailable',
      () async {
        final c = _window(const FakeScenario());
        final core = _core();
        final phone = _Phone();
        final router = _router(core, phone);
        openTestAiTab(c, cwd: testAiCwd, select: false);
        startAiPhone(c, slot: core.ai);
        await router.handle(_phone, const AiList());
        final sid = phone.listing().sessions.single.sid;
        await router.handle(_phone, AiAttach(sid: sid));
        await _until(() => phone.mirror(sid).head?.phase == 'ready');
        phone.got.clear();

        if (quit) {
          stopAiPhone(c); // what main.dart's quit does first
        } else {
          c.dispose();
        }
        expect(phone.got.map((m) => m.type), ['ai.list.result', 'ai.closed']);
        expect(phone.all<AiListResult>().single.available, isFalse);
        expect(phone.all<AiClosed>().single.sid, sid);
        expect(phone.all<AiClosed>().single.reason, 'desktop_closed');
        expect(core.ai.target, isNull);

        phone.got.clear();
        await router.handle(_phone, const AiList());
        await router.handle(_phone, AiAttach(sid: sid));
        expect(phone.all<AiListResult>().single.available, isFalse);
        expect(phone.all<AiClosed>().single.reason, 'unavailable');
        if (quit) {
          phone.got.clear();
          await stopAi(c);
          await pumpEventQueue();
          expect(phone.got, isEmpty, reason: 'no update of a stopping agent');
        }
      },
    );
  }

  test('background service: through the service to a running AI tab and '
      'back; one binding per link, so the same link again keeps the mirror; '
      'when the link ends its phones are gone from the window', () async {
    final pushes = <AiPush>[];
    final c = _window(
      FakeScenario(
        turns: [
          [FakeSteps.text('một'), FakeSteps.stop('end_turn')],
          [FakeSteps.text('hai'), FakeSteps.stop('end_turn')],
          [FakeSteps.permission('c1', 'Edit a.ts'), FakeSteps.stop('end_turn')],
        ],
      ),
      [aiPushSinkProvider.overrideWithValue(pushes.add)],
    );
    final service = _core();
    final phone = _Phone();
    service.ai.outbound.listen(phone.take);
    final (client, link) = await _service(service);
    c.read(daemonLinkProvider.notifier).set(link);
    final ai = openTestAiTab(c, cwd: testAiCwd, select: false);
    startAiPhone(c); // what main.dart does with the background service

    service.ai.handle(_phone, const AiList());
    await _until(() => phone.all<AiListResult>().any((r) => r.available));
    final sid = phone.listing().sessions.single.sid;
    service.ai.handle(_phone, AiAttach(sid: sid));
    await _until(() => phone.mirror(sid).head?.phase == 'ready');
    service.ai.handle(_phone, AiPrompt(sid: sid, rid: 1, text: 'Một'));
    await _until(() => phone.agentText(sid).contains('một'));

    // The same link, as another object: no second `ai.serve`, no phone lost.
    c
        .read(daemonLinkProvider.notifier)
        .set(DaemonLink(sessions: link.sessions, info: link.info));
    await pumpEventQueue();
    service.ai.handle(_phone, AiPrompt(sid: sid, rid: 2, text: 'Hai'));
    await _until(() => phone.agentText(sid).contains('hai'));
    expect([phone.result(1)?.ok, phone.result(2)?.ok], [true, true]);

    // The link ends: the service tells the phone, the window forgets it, so
    // nobody mirrors the session and its next question is pushed.
    await client.close();
    await _until(() => phone.all<AiClosed>().isNotEmpty);
    expect(phone.all<AiClosed>().single.reason, 'desktop_closed');
    final runtime = c.read(aiRuntimesProvider.notifier).existing(ai.ai!.id)!;
    unawaited(runtime.send([const TextBlock('ba')]));
    await _until(() => pushes.isNotEmpty);
    expect(pushes.single.kind, AiPushKind.needsInput);
    expect(pushes.single.sid, sid);
  });

  test('startAiPhone never throws: a hub that cannot be made leaves phones '
      'on "unavailable", and main.dart goes on to show the window', () async {
    final c = _window(const FakeScenario(), [
      aiPhoneHubProvider.overrideWith((ref) => throw StateError('no hub')),
    ]);
    final core = _core();
    final phone = _Phone();
    final router = _router(core, phone);
    expect(() => startAiPhone(c, slot: core.ai), returnsNormally);
    expect(() => startAiPhone(c), returnsNormally);
    expect(core.ai.target, isNull);
    await router.handle(_phone, const AiList());
    expect(phone.all<AiListResult>().single.available, isFalse);
  });

  group('pushes go out with the notifications of whoever holds the relay '
      'link (V2-2 D11)', () {
    final permission = FakeScenario(
      turns: [
        [
          FakeSteps.permission('c1', 'Sửa src/main.ts'),
          FakeSteps.stop('end_turn'),
        ],
      ],
    );

    /// A session of [c] that nobody shows starts to need the user; its sid.
    Future<String> needsInput(ProviderContainer c) async {
      final ai = openTestAiTab(c, cwd: testAiCwd, select: false);
      final runtime = c
          .read(aiRuntimesProvider.notifier)
          .runtimeFor(ai.ai!.id)!;
      await runtime.start();
      unawaited(runtime.send([const TextBlock('go')]));
      await _until(() => runtime.state.currentPermission != null);
      return c.read(aiPhoneHubProvider).sidOf(ai.ai!.id);
    }

    void expectPushed(List<http.Request> posts, String sid) {
      final post = posts.single;
      expect(post.url.path, '/v1/notifications');
      final body = jsonDecode(post.body) as Map<String, dynamic>;
      expect(body['title'], 'MacBook-Pro · Claude');
      expect(body['body'], 'Cần bạn trả lời: Sửa src/main.ts');
      expect(body['data'], {'kind': 'ai', 'ai_session': sid});
    }

    test('in-process: this process\'s own', () async {
      final posts = <http.Request>[];
      final core = _core(posts: posts);
      final c = _window(permission, [
        aiPushSinkFor(daemonMode: false, notifications: core.notifications),
      ]);
      startAiPhone(c, slot: core.ai);
      final sid = await needsInput(c);
      await _until(() => posts.isNotEmpty);
      await core.notifications!.sender.idle;
      expectPushed(posts, sid);
    });

    test('in-process with push notifications off: none', () async {
      final core = _core();
      final c = _window(permission, [
        aiPushSinkFor(daemonMode: false, notifications: core.notifications),
      ]);
      expect(c.read(aiPushSinkProvider), isNull);
    });

    test('background service: `ai.push` on the window\'s link, sent with the '
        'service\'s notifications', () async {
      final posts = <http.Request>[];
      final service = _core(posts: posts);
      final (_, link) = await _service(service);
      final c = _window(permission, [aiPushSinkFor(daemonMode: true)]);
      expect(c.read(aiPushSinkProvider), isNull, reason: 'no link yet');
      c.read(daemonLinkProvider.notifier).set(link);
      startAiPhone(c);
      await pumpEventQueue();
      final sid = await needsInput(c);
      await _until(() => posts.isNotEmpty);
      await service.notifications!.sender.idle;
      expectPushed(posts, sid);
    });
  });
}
