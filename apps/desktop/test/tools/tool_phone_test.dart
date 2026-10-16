import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/agent/daemon_tools.dart';
import 'package:shellx_desktop/src/agent/session_core.dart';
import 'package:shellx_desktop/src/mux/daemon_state.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/tools/tool_entry.dart';
import 'package:shellx_desktop/src/tools/tool_phone.dart';
import 'package:shellx_desktop/src/tools/tool_registry.dart';

import '../cli/support/cli_container.dart';
import '../mux/mux_test_support.dart';
import '../support/fake_local_sessions.dart';
import '../support/fake_pty.dart';

const _phone = '33333333-3333-4333-8333-333333333333';

/// V2-3's list as a test sets it.
final class _Tools extends ToolRegistry {
  _Tools(this._initial);
  final List<ToolEntry> _initial;

  @override
  List<ToolEntry> build() => _initial;

  void set(List<ToolEntry> tools) => state = tools;
}

const _board = ToolEntry(
  id: 'k3f9za7q1m',
  ws: kDefaultWorkspaceId,
  name: 'Bảng việc',
  url: 'http://localhost:4000/',
  phone: true,
);
const _grafana = ToolEntry(
  id: 'grafana001',
  ws: kDefaultWorkspaceId,
  name: 'Grafana',
  url: 'http://localhost:3000/',
);
const _remote = ToolEntry(
  id: 'remote0001',
  ws: kDefaultWorkspaceId,
  name: 'Staging',
  url: 'https://staging.example.com/',
  phone: true, // not allowed on a phone (V2-3 D15): never served
);

ProviderContainer _window(List<ToolEntry> tools) => cliContainer(
  FakeLocalSessions(),
  overrides: [toolRegistryProvider.overrideWith(() => _Tools(tools))],
);

SessionCore _core() => SessionCore(
  ptyFactory: FakePtyFactory(),
  shellResolver: const FixedShellResolver(),
  homeDirectory: '/Users/phu',
  baseEnvironment: const {'HOME': '/Users/phu'},
  api: ShellxApi(baseUri: Uri.parse('https://relay.test')),
);

List<String> _ids(Uint8List body) {
  final json = jsonDecode(utf8.decode(body)) as Map<String, Object?>;
  return [for (final t in json['tools']! as List) (t as Map)['id'] as String];
}

/// V2-4 E5, E15: the window's tools for phones, in-process and through the
/// background service (needs V2-3's `toolRegistryProvider`).
void main() {
  test('only tools on for the phone are served, with their workspace\'s '
      'name; the others are named off', () {
    final c = _window([_board, _grafana, _remote]);
    final body = c.read(phoneToolsBodyProvider);
    final json = jsonDecode(utf8.decode(body)) as Map<String, Object?>;
    expect(json['tools'], [
      {
        'id': 'k3f9za7q1m',
        'name': 'Bảng việc',
        'ws': 'Default',
        'group': kDefaultWorkspaceId,
        'url': 'http://localhost:4000/',
      },
    ]);
    expect(json['off'], ['grafana001', 'remote0001']);
  });

  // Task 15 minor (b): a workspace name is at most 64 characters, which can
  // be more UTF-16 units than a served tool's `ws` may hold (200): cut, never
  // inside a character, the tool is still served (not dropped by the
  // reader, in neither its tools nor its off list).
  test('a workspace name over 200 UTF-16 units is cut on a code point: the '
      'tool is still served', () {
    final c = _window(const []);
    final long = 'a${'🇻🇳' * 64}'; // kept: 'a' and 63 flags, 253 units
    final ws = c.read(sidebarWorkspacesProvider.notifier).createFor(name: long);
    (c.read(toolRegistryProvider.notifier) as _Tools).set([
      ToolEntry(
        id: _board.id,
        ws: ws,
        name: _board.name,
        url: _board.url,
        phone: true,
      ),
    ]);
    final body = c.read(phoneToolsBodyProvider);
    final json = jsonDecode(utf8.decode(body)) as Map<String, Object?>;
    final served = (json['tools']! as List).single as Map;
    final name = served['ws']! as String;
    expect(name.length, 199, reason: 'the 200th unit would split a flag');
    expect(long, startsWith(name));
    expect(utf8.decode(utf8.encode(name)), name, reason: 'no lone surrogate');
    expect(ToolCatalog.fromServeBody(body)!.tools.map((t) => t.id), [
      'k3f9za7q1m',
    ]);
  });

  // Task 15 minor (a): the list is rebuilt on every shell event; only a list
  // whose bytes changed is served (in-process) or sent (to the service).
  test('in-process: a rebuild of the list that changes nothing is not served '
      'again', () async {
    final c = _window([_board]);
    final core = _core();
    startToolPhone(c, slot: core.tools);
    final proxy = c.read(toolPhoneProxyProvider);
    final served = proxy.catalog;
    expect(served?.tools.map((t) => t.id), ['k3f9za7q1m']);
    (c.read(toolRegistryProvider.notifier) as _Tools).set([_board]);
    await pumpEventQueue();
    expect(identical(proxy.catalog, served), isTrue);
    (c.read(toolRegistryProvider.notifier) as _Tools).set([
      _board,
      _grafana.copyWith(phone: true),
    ]);
    await pumpEventQueue();
    expect(proxy.catalog?.tools.map((t) => t.id), ['k3f9za7q1m', 'grafana001']);
    stopToolPhone(c);
  });

  test('with the background service: a rebuild of the list that changes '
      'nothing is not sent again on the same link; a new link gets the list '
      'at once', () async {
    const info = MuxPeerInfo(
      protocol: kMuxProtocol,
      app: 't',
      caps: ['agent', 'cli', 'tools'],
    );
    DaemonLink link(List<String> sent) {
      final (raw, daemonSide) = MemoryMuxTransport.pair();
      daemonSide.messages.listen((m) => sent.add(m.type));
      return DaemonLink(
        sessions: RemoteLocalSessions(MuxClient(raw)),
        info: info,
      );
    }

    final c = _window([_board]);
    final first = <String>[];
    c.read(daemonLinkProvider.notifier).set(link(first));
    startToolPhone(c);
    await pumpEventQueue();
    expect(first.where((type) => type == MuxType.toolServe), hasLength(1));
    (c.read(toolRegistryProvider.notifier) as _Tools).set([_board]);
    await pumpEventQueue();
    expect(first.where((type) => type == MuxType.toolServe), hasLength(1));
    (c.read(toolRegistryProvider.notifier) as _Tools).set([
      _board,
      _grafana.copyWith(phone: true),
    ]);
    await pumpEventQueue();
    expect(first.where((type) => type == MuxType.toolServe), hasLength(2));
    final second = <String>[];
    c.read(daemonLinkProvider.notifier).set(link(second));
    await pumpEventQueue();
    expect(second.where((type) => type == MuxType.toolServe), hasLength(1));
  });

  test('in-process: the slot serves the window\'s list; a change is heard; '
      'quitting tells the phone and stops serving', () async {
    final c = _window([_board]);
    final core = _core();
    final heard = <ToolMessage>[];
    core.tools.outbound.listen((o) => heard.add(o.message as ToolMessage));
    expect(core.tools.serving, isFalse);
    startToolPhone(c, slot: core.tools);
    expect(core.tools.serving, isTrue);
    core.tools.handle(_phone, const ToolList());
    expect(_ids((heard.last as ToolListResult).body), ['k3f9za7q1m']);
    (c.read(toolRegistryProvider.notifier) as _Tools).set([
      _board.copyWith(phone: false),
    ]);
    await pumpEventQueue();
    expect(_ids((heard.last as ToolListResult).body), isEmpty);
    stopToolPhone(c);
    expect((heard.last as ToolListResult).available, isFalse);
    expect(core.tools.serving, isFalse);
  });

  test('with the background service: the list goes over the link to a '
      'service that has tools, again on every change; an older one gets '
      'nothing', () async {
    final core = _core();
    final listener = TestListener();
    final server = MuxServer(
      sessions: core.sessions,
      secret: testSecret,
      self: const MuxPeerInfo(
        protocol: kMuxProtocol,
        app: 't',
        instance: 'i',
        caps: ['agent', 'cli', 'tools'],
      ),
      onQuit: () async {},
    )..serve(listener);
    addTearDown(server.close);
    final proxy = installDaemonTools(server, core);
    addTearDown(proxy.close);
    final client = await attachClient(listener);
    final c = _window([_board]);
    c
        .read(daemonLinkProvider.notifier)
        .set(
          DaemonLink(
            sessions: RemoteLocalSessions(client),
            info: const MuxPeerInfo(
              protocol: kMuxProtocol,
              app: 't',
              caps: ['agent', 'cli', 'tools'],
            ),
          ),
        );
    startToolPhone(c); // no slot: the background service holds the relay
    await pumpEventQueue();
    expect(proxy.catalog?.tools.map((t) => t.id), ['k3f9za7q1m']);
    (c.read(toolRegistryProvider.notifier) as _Tools).set([
      _board,
      _grafana.copyWith(phone: true),
    ]);
    await pumpEventQueue();
    expect(proxy.catalog?.tools.map((t) => t.id), ['k3f9za7q1m', 'grafana001']);

    // An older service (no `tools` in its caps) is never sent the list.
    final older = _window([_board]);
    final sent = <String>[];
    final (raw, daemonSide) = MemoryMuxTransport.pair();
    daemonSide.messages.listen((m) => sent.add(m.type));
    older
        .read(daemonLinkProvider.notifier)
        .set(
          DaemonLink(
            sessions: RemoteLocalSessions(MuxClient(raw)),
            info: const MuxPeerInfo(
              protocol: kMuxProtocol,
              app: 't',
              caps: ['agent', 'cli'],
            ),
          ),
        );
    startToolPhone(older);
    await pumpEventQueue();
    expect(sent, isNot(contains(MuxType.toolServe)));
  });

  // Not in the plan's list: `main.dart` starts the tools before the first
  // connection to the service exists, so only the link listener ever sends
  // the list (the test above sets its link first).
  test('with the background service: the window starts before its link '
      'exists; the list goes when the link comes, and to the next link (a '
      'restarted service)', () async {
    final core = _core();
    final listener = TestListener();
    final server = MuxServer(
      sessions: core.sessions,
      secret: testSecret,
      self: const MuxPeerInfo(
        protocol: kMuxProtocol,
        app: 't',
        instance: 'i',
        caps: ['agent', 'cli', 'tools'],
      ),
      onQuit: () async {},
    )..serve(listener);
    addTearDown(server.close);
    final proxy = installDaemonTools(server, core);
    addTearDown(proxy.close);
    const info = MuxPeerInfo(
      protocol: kMuxProtocol,
      app: 't',
      caps: ['agent', 'cli', 'tools'],
    );
    final c = _window([_board]);
    startToolPhone(c); // as main.dart: before the first link exists
    await pumpEventQueue();
    expect(proxy.catalog, isNull);

    c
        .read(daemonLinkProvider.notifier)
        .set(
          DaemonLink(
            sessions: RemoteLocalSessions(await attachClient(listener)),
            info: info,
          ),
        );
    await pumpEventQueue();
    expect(proxy.catalog?.tools.map((t) => t.id), ['k3f9za7q1m']);

    // The service restarted: its new link gets the list at once.
    final sent = <String>[];
    final (raw, daemonSide) = MemoryMuxTransport.pair();
    daemonSide.messages.listen((m) => sent.add(m.type));
    c
        .read(daemonLinkProvider.notifier)
        .set(
          DaemonLink(sessions: RemoteLocalSessions(MuxClient(raw)), info: info),
        );
    await pumpEventQueue();
    expect(sent, contains(MuxType.toolServe));
  });
}
