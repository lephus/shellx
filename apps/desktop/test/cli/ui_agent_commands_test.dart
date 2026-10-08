import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/cli/ui_command_handler.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';
import 'package:shellx_desktop/src/terminal/agent_status_notifier.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';
import 'support/cli_container.dart';

void main() {
  late ProviderContainer c;
  late FakeLocalSessions local;
  late UiCommandHandler h;

  Future<Map<String, Object?>> call(Map<String, Object?> fields) =>
      h.handle(MuxMessage('ui.agent.event', q: 1, fields: fields));

  Map<String, Object?> fieldsFor(
    int pane,
    String event, [
    Map<String, Object?> more = const {},
  ]) => {
    'pane': pane,
    'agent': 'claude',
    'event': event,
    'at': DateTime.now().millisecondsSinceEpoch,
    ...more,
  };

  Matcher badRequest() => throwsA(
    isA<CliFailure>()
        .having((e) => e.code, 'code', MuxError.badRequest)
        .having((e) => e.message, 'message', isNot(contains('SECRET'))),
  );

  setUp(() async {
    local = FakeLocalSessions();
    c = cliContainer(local);
    h = c.read(uiCommandHandlerProvider);
    await c.read(terminalTabsProvider.notifier).openTab(); // pane 100
  });

  test('ui.agent.event answers {} and records the state', () async {
    expect(await call(fieldsFor(100, 'running')), isEmpty);
    expect(c.read(agentStatusProvider)[100]!.state, AgentState.running);
  });

  test('a vanished or unknown pane is not an error', () async {
    expect(await call(fieldsFor(12, 'running')), isEmpty);
    expect(c.read(agentStatusProvider), isEmpty);
  });

  test('a bad request is bad_request and echoes nothing', () async {
    await expectLater(call(fieldsFor(100, 'SECRET')), badRequest());
    await expectLater(
      call(fieldsFor(100, 'idle', {'agent': 'SECRET'})),
      badRequest(),
    );
    await expectLater(
      call(fieldsFor(100, 'idle', {'pane': 'SECRET'})),
      badRequest(),
    );
    await expectLater(call({}), badRequest());
    expect(c.read(agentStatusProvider), isEmpty);
  });

  test('a hostile session id never reaches the record', () async {
    await call(fieldsFor(100, 'start', {'session': r'a; rm -rf ~'}));
    expect(c.read(agentStatusProvider)[100]!.session, isNull);
    await call(fieldsFor(100, 'running', {'session': 'good-1'}));
    expect(c.read(agentStatusProvider)[100]!.session, 'good-1');
  });

  test('ls --json: agent_name and agent_status only for a pane with a '
      'visible record; the A7 agent flag is untouched', () async {
    Future<Map<String, Object?>> only() async {
      final ls = await h.handle(const MuxMessage('ui.ls', q: 1));
      final tab =
          (((ls['workspaces']! as List).single as Map)['tabs']! as List).single
              as Map;
      return (tab['panes']! as List).single as Map<String, Object?>;
    }

    final before = await only();
    expect(before.containsKey('agent_status'), isFalse);
    expect(before.containsKey('agent_name'), isFalse);
    expect(before['agent'], isFalse);
    await call(fieldsFor(100, 'needs_input', {'message': 'SECRET'}));
    final after = await only();
    expect(after['agent_name'], 'claude');
    expect(after['agent_status'], 'needs_input');
    expect(after['agent'], isFalse);
    expect('$after', isNot(contains('SECRET')));
    await call(fieldsFor(100, 'end'));
    expect((await only()).containsKey('agent_status'), isFalse);
  });
}
