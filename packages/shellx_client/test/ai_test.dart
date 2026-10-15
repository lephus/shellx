import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:test/test.dart';

import 'support/drive.dart';
import 'support/harness.dart';

final _t0 = DateTime.utc(2026, 10, 14, 9);

/// A runtime on a plain state (see shellx_agent's ai_rig).
final class _Control implements AiControl {
  _Control(this.state);
  @override
  final AiSessionState state;
  final prompts = <String>[];
  final answers = <(int, String)>[];

  @override
  Future<bool> send(AiPhonePrompt prompt) async {
    prompts.add(prompt.text);
    state.beginTurn([TextBlock(prompt.text)], _t0, source: PromptSource.phone);
    return true;
  }

  @override
  void cancel() {}
  @override
  Future<void> forceStop() async {}

  @override
  void answerPermission(int id, String optionId) {
    answers.add((id, optionId));
    state.resolvePermission(id, PermissionSelected(optionId));
  }

  @override
  void answerAsk(int id, ElicitationResponse response) {}

  @override
  Future<void> setConfig(String id, Object value) async {}

  @override
  Future<void> setMode(String modeId) async {}
}

final class _Source implements AiSessionSource {
  final state = AiSessionState(
    agentId: 'claude',
    agentName: 'Claude',
    cwd: '/p',
  )..setPhase(AgentPhase.ready);
  late final runtime = _Control(state);
  final _changes = StreamController<void>.broadcast(sync: true);

  @override
  Stream<void> get changes => _changes.stream;
  @override
  List<AiSessionEntry> get sessions => [
    AiSessionEntry(
      paneId: -1,
      agentId: 'claude',
      agentName: 'Claude',
      title: 'Phiên AI mới',
      cwd: '/p',
      state: state,
    ),
  ];
  @override
  List<AiAgentChoice> get agents => const [
    AiAgentChoice(id: 'claude', name: 'Claude'),
  ];
  @override
  List<AiFolderChoice> get folders => const [];
  @override
  String? get defaultAgent => 'claude';
  @override
  AiControl? control(int paneId, {bool start = false}) => runtime;
  @override
  Future<int?> open(String agentId, String folderKey) async => null;
  @override
  bool seenOnDesktop(int paneId) => false;
  @override
  Duration? get doneThreshold => null;
}

PermissionRequest _perm() => PermissionRequest.fromJson({
  'sessionId': 's',
  'toolCall': {'toolCallId': 'c1', 'title': 'Sửa src/main.ts'},
  'options': [
    {'optionId': 'allow', 'name': 'Yes', 'kind': 'allow_once'},
    {'optionId': 'reject', 'name': 'No', 'kind': 'reject_once'},
  ],
});

void _say(AiSessionState s, String text) => s.applyUpdate(
  SessionUpdate.fromJson({
    'sessionUpdate': 'agent_message_chunk',
    'content': {'type': 'text', 'text': text},
  }),
  _t0,
);

/// V2-2 end to end: a real phone client and a real agent over the fake
/// relay and the real encrypted channel.
void main() {
  late TestKeys keys;
  setUpAll(() async => keys = await TestKeys.generate());

  test('list, attach, stream, prompt and answer from the phone', () {
    fakeAsync((async) {
      final source = _Source();
      final hub = AiPhoneHub(source: source, epoch: 'ep');
      final h = Harness(async, keys, ai: hub);
      final ai = h.phoneMachine.ai;
      h.run(h.phoneMachine.listSessions(includeDesktop: true));
      expect(ai.supported, isTrue);
      h.run(ai.watch());
      settle(async);
      expect(ai.listing!.sessions.single.sid, 'ep.-1');

      final link = ai.attach('ep.-1');
      settle(async);
      expect(link.state, AiLinkState.live);
      h.run(ai.prompt('ep.-1', 'Thêm nút đăng xuất'));
      expect(source.runtime.prompts, ['Thêm nút đăng xuất']);
      for (var i = 0; i < 30; i++) {
        _say(source.state, 'phần $i. ');
        async.elapse(const Duration(milliseconds: 20));
      }
      settle(async, const Duration(milliseconds: 300));
      final text = (link.mirror.items.last as MirrorText).text;
      expect(text, startsWith('phần 0. '));
      expect(text, endsWith('phần 29. '));

      final p = source.state.addPermission(_perm(), _t0);
      settle(async, const Duration(milliseconds: 300));
      expect(link.mirror.head!.permission!.id, p.id);
      h.run(ai.answerPermission('ep.-1', p.id, 'allow'));
      expect(source.runtime.answers, [(p.id, 'allow')]);
      expect(
        () =>
            h.run(h.tabletMachine.ai.answerPermission('ep.-1', p.id, 'reject')),
        throwsA(
          isA<AiRequestException>().having((e) => e.code, 'code', 'stale'),
        ),
      );
      settle(async, const Duration(milliseconds: 300));
      expect(link.mirror.head!.permission, isNull);
    });
  });

  test('a lost channel resumes with what the phone holds', () {
    fakeAsync((async) {
      final source = _Source();
      final hub = AiPhoneHub(source: source, epoch: 'ep');
      final h = Harness(async, keys, ai: hub);
      final ai = h.phoneMachine.ai;
      source.state.beginTurn(const [TextBlock('go')], _t0);
      for (var i = 0; i < 20; i++) {
        _say(source.state, 'a$i ');
        source.state.applyUpdate(
          SessionUpdate.fromJson({
            'sessionUpdate': 'tool_call',
            'toolCallId': 't$i',
            'title': 'Read $i',
            'kind': 'read',
          }),
          _t0,
        );
      }
      final link = ai.attach('ep.-1');
      settle(async);
      expect(link.mirror.end, source.state.timeline.items.length);
      h.disconnectPhone();
      expect(link.state, AiLinkState.attaching);
      _say(source.state, 'after');
      h.reconnectPhone();
      settle(async, const Duration(seconds: 1));
      expect(link.state, AiLinkState.live);
      expect(link.mirror.end, source.state.timeline.items.length);
      expect((link.mirror.items.last as MirrorText).text, 'after');
    });
  });

  group('compatibility (mandatory)', () {
    test(
      'new phone, old desktop: no ai flag, nothing sent, terminals fine',
      () {
        fakeAsync((async) {
          final h = Harness(async, keys); // an agent without AI for phones
          final machine = h.phoneMachine;
          h.run(machine.listSessions(includeDesktop: true));
          expect(machine.ai.supported, isFalse);
          // Even when asked anyway, the old agent ignores it; the channel
          // stays and terminals keep working.
          expect(
            () => h.run(machine.ai.prompt('x.1', 'hi')),
            throwsA(isA<MachineConnectionException>()),
          );
          final tab = h.run(machine.openSession(cols: 80, rows: 24));
          final recorder = TabRecorder(tab);
          h.pty.emit('still here\r\n');
          settle(async);
          expect(recorder.text, contains('still here'));
        });
      },
    );

    test('old phone, new desktop: a phone that never asks gets no ai.*', () {
      fakeAsync((async) {
        final source = _Source();
        final hub = AiPhoneHub(source: source, epoch: 'ep');
        final toPhones = <OutboundMessage>[];
        hub.outbound.listen(toPhones.add);
        final h = Harness(async, keys, ai: hub);
        final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
        final recorder = TabRecorder(tab);
        source.state.beginTurn(const [TextBlock('go')], _t0);
        _say(source.state, 'streaming on the desktop');
        source.state.addPermission(_perm(), _t0);
        h.pty.emit('ok\r\n');
        settle(async, const Duration(seconds: 1));
        expect(toPhones, isEmpty);
        expect(recorder.text, contains('ok'));
      });
    });
  });
}
