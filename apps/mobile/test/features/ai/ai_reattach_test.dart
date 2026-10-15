import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_mobile/features/ai/domain/ai_drafts.dart';
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_session_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

import '../../support/fakes.dart';

const _sid = 'e.-1';

AiSessionInfo _info(String sid, {String? acp = 'sess-1', String agent = 'claude', String cwd = '/p'}) => AiSessionInfo(
  sid: sid,
  agentId: agent,
  agentName: 'Claude',
  title: 'Nút đăng xuất',
  state: AiRemoteState.idle,
  cwd: cwd,
  acpSessionId: acp,
);

/// V2-2b R3, B1, B22: the session page holds the computer's AI listing, and follows its session to the sid
/// it has after the computer restarted ShellX — exactly one match, within 30 s, nothing sent to it.
void main() {
  late FakeBackend backend;
  late FakeMachineSession machine;
  late FakeSessionHolder session;
  late WorkspaceRegistry registry;
  late AiDrafts drafts;

  setUp(() {
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    session = FakeSessionHolder(backend);
    registry = WorkspaceRegistry(session.backend);
    drafts = AiDrafts();
  });

  tearDown(() => registry.dispose());

  AiSessionController make() => AiSessionController(agentA, _sid, session, drafts, registry);

  /// A computer that speaks V2-2b and has listed session [_sid] as `sess-1` in `/p`.
  void known() {
    machine.ai
      ..protocolValue = 2
      ..emitListing(AiListing(sessions: [_info(_sid)]));
  }

  group('the listing (R3)', () {
    test('a page that came before any list of the computer asks for one, which tells the protocol, and holds '
        'the listing until it closes', () async {
      machine.ai.listedProtocol = 2;
      final controller = make();
      await pumpEventQueue();
      expect(machine.listCalls, 1);
      expect(machine.ai.protocol, 2);
      expect(machine.ai.watching, isTrue);
      controller.dispose();
      expect(machine.ai.watching, isFalse);
      expect(machine.ai.hasListingListener, isFalse);
    });

    test('a computer whose protocol is known is not listed again', () async {
      known();
      final controller = make();
      await pumpEventQueue();
      expect(machine.listCalls, 0);
      expect(machine.ai.watching, isTrue);
      controller.dispose();
    });

    test('a V2-2b feature is on only with protocol 2 and the listing naming it (B1)', () async {
      final controller = make();
      machine.ai
        ..protocolValue = 1
        ..emitListing(const AiListing(features: {AiFeature.config}));
      expect(controller.can(AiFeature.config), isFalse, reason: 'an older background service');
      machine.ai
        ..protocolValue = 2
        ..emitListing(const AiListing());
      expect(controller.can(AiFeature.config), isFalse, reason: 'an older window');
      machine.ai.emitListing(const AiListing(features: {AiFeature.config}));
      expect(controller.can(AiFeature.config), isTrue);
      controller.dispose();
    });

    test('a listing that names a feature arrives later: can() turns true and the page is told (version); after '
        'dispose nothing listens', () async {
      machine.ai.listedProtocol = 2;
      final controller = make();
      final made = controller.version.value;
      await pumpEventQueue();
      expect(controller.version.value, greaterThan(made), reason: 'the protocol, learned from the one list');
      expect(controller.can(AiFeature.config), isFalse);
      final known = controller.version.value;
      machine.ai.emitListing(const AiListing(features: {AiFeature.config}));
      expect(controller.can(AiFeature.config), isTrue);
      expect(controller.version.value, greaterThan(known));
      controller.dispose();
      expect(machine.ai.hasListingListener, isFalse);
    });
  });

  group('found again after the computer restarted ShellX (B22)', () {
    for (final reason in ['gone', 'desktop_closed']) {
      test('closed "$reason": the one session of the same agent session, agent and folder is followed, and the '
          'draft goes with it', () {
        known();
        final controller = make()..keepDraft('còn dở');
        machine.ai.session(_sid)
          ..sync()
          ..close(reason);
        expect(controller.sid, _sid);
        expect(controller.draft, isEmpty, reason: 'over, as long as it is not found again');
        machine.ai.emitListing(AiListing(sessions: [_info('k.-3')]));
        expect(controller.sid, 'k.-3');
        expect(controller.reattached.value, isTrue);
        expect(controller.linkState, AiLinkState.attaching);
        expect(machine.ai.session(_sid).detached, isTrue, reason: 'the old link is let go');
        machine.ai.session('k.-3').sync();
        expect(controller.linkState, AiLinkState.live);
        expect(controller.draft, 'còn dở');
        expect(drafts.of('$agentA/$_sid'), isEmpty);
        controller.dispose();
        expect(machine.ai.session('k.-3').detached, isTrue);
      });
    }

    test('a page that came from a notification knows the agent session from the header (acp)', () {
      machine.ai.protocolValue = 2;
      final controller = make();
      final ai = machine.ai.session(_sid);
      ai.desktop.setSession('sess-1');
      ai
        ..sync()
        ..close('gone');
      machine.ai.emitListing(AiListing(sessions: [_info('k.-3')]));
      expect(controller.sid, 'k.-3');
      controller.dispose();
    });

    test('none, or two, of the same agent session: the page stays closed', () {
      known();
      final controller = make();
      machine.ai.session(_sid)
        ..sync()
        ..close('gone');
      machine.ai.emitListing(
        AiListing(
          sessions: [
            _info('k.-3', cwd: '/elsewhere'),
            _info('k.-4', agent: 'codex'),
            _info('k.-5', acp: 'sess-2'),
            _info('k.-6', acp: null),
          ],
        ),
      );
      expect(controller.sid, _sid);
      machine.ai.emitListing(AiListing(sessions: [_info('k.-3'), _info('k.-4')]));
      expect(controller.sid, _sid, reason: 'two tabs on one agent session: which one is not known');
      expect(controller.linkState, AiLinkState.closed);
      expect(controller.reattached.value, isFalse);
      controller.dispose();
    });

    test('after 30 s it is not looked for any more', () {
      fakeAsync((async) {
        known();
        final controller = make();
        machine.ai.session(_sid)
          ..sync()
          ..close('desktop_closed');
        async.elapse(AiSessionController.findAgainFor + const Duration(seconds: 1));
        machine.ai.emitListing(AiListing(sessions: [_info('k.-3')]));
        expect(controller.sid, _sid);
        controller.dispose();
      });
    });

    for (final reason in ['unavailable', 'unreadable']) {
      test('closed "$reason" (it may pass): not looked for', () {
        known();
        final controller = make();
        machine.ai.session(_sid)
          ..sync()
          ..close(reason);
        machine.ai.emitListing(AiListing(sessions: [_info('k.-3')]));
        expect(controller.sid, _sid);
        controller.dispose();
      });
    }

    test('closed "unavailable", then "gone" once the computer was asked again (another run of ShellX): '
        'followed', () {
      known();
      final controller = make();
      final old = machine.ai.session(_sid)
        ..sync()
        ..close('unavailable');
      machine.ai.emitListing(AiListing(sessions: [_info('k.-3')]));
      expect(controller.sid, _sid, reason: 'it may pass');
      old.close('gone');
      expect(controller.sid, 'k.-3');
      controller.dispose();
    });

    test('the session found again is only followed: nothing is sent to it; "Đã nối lại" goes once the user '
        'sends', () async {
      known();
      final controller = make();
      machine.ai.session(_sid)
        ..sync()
        ..close('gone');
      machine.ai.emitListing(AiListing(sessions: [_info('k.-3')]));
      machine.ai.session('k.-3').sync();
      expect(machine.ai.prompts, isEmpty);
      expect(machine.ai.permissionAnswers, isEmpty);
      expect(machine.ai.askAnswers, isEmpty);
      expect(await controller.send('tiếp nhé'), isNull);
      expect(machine.ai.prompts, [('k.-3', 'tiếp nhé')]);
      expect(controller.reattached.value, isFalse);
      controller.dispose();
    });
  });
}
