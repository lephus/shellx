import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_page_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

import '../../support/fakes.dart';

const _waiting = AiSessionInfo(
  sid: 'e.-1',
  agentId: 'claude',
  agentName: 'Claude',
  title: 'Nút đăng xuất',
  state: AiRemoteState.needsInput,
  waiting: 'Sửa src/main.ts',
);

const _agents = [AiAgentChoice(id: 'claude', name: 'Claude')];
const _folders = [AiFolderChoice(key: 'ws:a', name: 'shop-web', path: '/Users/me/shop-web')];

/// What the computer said the first time.
const _before = AiListing(sessions: [_waiting], agents: _agents, folders: _folders, defaultAgent: 'claude');

/// What it says later: the session was answered on the computer meanwhile.
const _after = AiListing(agents: _agents, folders: _folders, defaultAgent: 'claude');

/// V2-2: the AI list is asked for by whoever shows it, and let go (`AiMachine.unwatch`) when that
/// screen goes away; otherwise every relay or presence event would make a handshake with every
/// machine ever watched. The client's listing is only as current as the last watch, so a later
/// visit never shows the one an earlier visit left behind.
void main() {
  late FakeBackend backend;
  late FakeMachineSession machine;
  late FakeSessionHolder session;
  late WorkspaceRegistry registry;
  late TerminalWorkspace workspace;

  setUp(() {
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    session = FakeSessionHolder(backend);
    registry = WorkspaceRegistry(session.backend);
    workspace = registry.forMachine(agentA);
  });

  tearDown(() => registry.dispose());

  FakeAiMachine ai() => machine.ai;

  /// Starts [future] and lets everything that needs no time happen; whether it completed, and with
  /// what, shows in the record.
  ({bool Function() done, T? Function() value}) follow<T>(FakeAsync async, Future<T> future) {
    var done = false;
    T? value;
    unawaited(
      future.then((v) {
        done = true;
        value = v;
      }),
    );
    async.flushMicrotasks();
    return (done: () => done, value: () => value);
  }

  group('TerminalWorkspace', () {
    test('a computer without AI for phones is never watched, and the picker does not wait for it', () {
      fakeAsync((async) {
        for (final supported in [null, false]) {
          ai().supportedValue = supported;
          final release = workspace.holdAiListing();
          final picking = follow(async, workspace.pickable());
          expect(picking.done(), isTrue, reason: 'no time passes: no listing can come ($supported)');
          release();
          expect(picking.value()!.ai, isNull);
          expect(picking.value()!.aiSupported, supported);
        }
        expect((ai().watchCalls, ai().unwatchCalls), (0, 0));
      });
    });

    test('the picker waits three seconds for the first listing', () {
      expect(TerminalWorkspace.aiListingWait, const Duration(seconds: 3));
    });

    test('the picker asks for the list and, when no page holds it, lets it go again', () async {
      ai()
        ..supportedValue = true
        ..listingValue = _before;
      final listing = await workspace.pickable();
      expect(listing.ai, same(_before));
      expect((ai().watchCalls, ai().unwatchCalls, ai().watching), (1, 1, false));
    });

    test('a page that holds the list keeps it watched until the last page lets go', () async {
      ai()
        ..supportedValue = true
        ..listingValue = _before;
      final first = workspace.holdAiListing();
      expect(ai().watchCalls, 1, reason: 'the computer is known to have AI: watched at once');
      final second = workspace.holdAiListing();
      expect(ai().watchCalls, 1, reason: 'one watch for both');

      await workspace.pickable(); // a picker comes and goes meanwhile
      expect((ai().watchCalls, ai().unwatchCalls), (1, 0));

      first();
      first(); // letting go twice is letting go once
      expect(ai().unwatchCalls, 0, reason: 'the other page still shows it');
      second();
      expect((ai().watchCalls, ai().unwatchCalls, ai().watching), (1, 1, false));
    });

    test('held before the computer is known to have AI: the first picker starts the watch', () async {
      final release = workspace.holdAiListing();
      expect(ai().watchCalls, 0);
      // What the first list of the sessions tells:
      ai()
        ..supportedValue = true
        ..listingValue = _before;
      await workspace.pickable();
      expect((ai().watchCalls, ai().unwatchCalls), (1, 0), reason: 'the page still holds it');
      release();
      expect((ai().unwatchCalls, ai().watching), (1, false));
    });

    test('a page gone while the picker waits: the picker lets the list go when it is done', () {
      fakeAsync((async) {
        ai().supportedValue = true; // no listing yet: the picker waits for it
        final release = workspace.holdAiListing();
        final picking = follow(async, workspace.pickable());
        expect(picking.done(), isFalse);
        release();
        expect(ai().unwatchCalls, 0, reason: 'the picker still waits for the answer');

        ai().emitListing(_before);
        async.flushMicrotasks();
        expect(picking.done(), isTrue);
        expect(picking.value()!.ai, same(_before));
        expect((ai().watchCalls, ai().unwatchCalls, ai().watching), (1, 1, false));
        expect(ai().hasListingListener, isFalse);
        expect(async.pendingTimers, isEmpty, reason: 'the wait is over: no time-out left running');
      });
    });

    test('disposing the workspace stops the watch; a page letting go afterwards stops nothing twice', () {
      ai().supportedValue = true;
      final release = workspace.holdAiListing();
      expect(ai().watching, isTrue);
      registry.remove(agentA);
      expect((ai().unwatchCalls, ai().watching), (1, false));
      release();
      expect(ai().unwatchCalls, 1);
      // A dead workspace holds nothing.
      workspace.holdAiListing()();
      expect((ai().watchCalls, ai().unwatchCalls), (1, 1));
    });

    test('a session attached while the picker waits for the AI listing is left out of it', () {
      fakeAsync((async) {
        const running = SessionInfo(id: 7, index: 1, shell: 'zsh', createdAt: 1, attached: false);
        machine.sessions = [running];
        ai().supportedValue = true; // no listing yet: the picker waits for it
        final picking = follow(async, workspace.pickable());
        expect(picking.done(), isFalse);

        unawaited(workspace.attach(running, (cols: 80, rows: 24)));
        async.flushMicrotasks();
        ai().emitListing(_before);
        async.flushMicrotasks();
        expect(picking.value()!.sessions, isEmpty, reason: 'it is a tab by now');
      });
    });

    test('a machine dropped while the picker waits: no listing, at once', () {
      fakeAsync((async) {
        ai().supportedValue = true;
        final picking = follow(async, workspace.pickable());
        expect(picking.done(), isFalse);
        unawaited(ai().endListings());
        async.flushMicrotasks();
        expect(picking.done(), isTrue, reason: 'no time passes: nothing will come');
        expect(picking.value()!.ai, isNull);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a machine that cannot be reached: the failing watch() is no failure of the picker', () {
      fakeAsync((async) {
        ai()
          ..supportedValue = true
          ..connectFailure = MachineConnectionFailure.agentOffline;
        final picking = follow(async, workspace.pickable());
        async.elapse(TerminalWorkspace.aiListingWait);
        expect(picking.done(), isTrue);
        expect(picking.value()!.ai, isNull);
        expect((ai().watchCalls, ai().unwatchCalls), (1, 1));
      });
    });
  });

  group('what a screen that is gone leaves behind', () {
    test('no listener of the listing, however the watch ended', () {
      ai().supportedValue = true;
      expect(ai().hasListingListener, isFalse);
      final release = workspace.holdAiListing();
      expect(ai().hasListingListener, isTrue, reason: 'watched: the workspace hears the answers');
      release();
      expect(ai().hasListingListener, isFalse);

      workspace.holdAiListing();
      registry.remove(agentA); // the workspace is dropped with a page still holding
      expect(ai().hasListingListener, isFalse);
    });

    test('signing out stops the watch of every machine', () {
      ai()
        ..supportedValue = true
        ..listingValue = _before;
      workspace.holdAiListing();
      expect(ai().watching, isTrue);
      session.signOut();
      expect((ai().unwatchCalls, ai().watching), (1, false));
      expect(ai().hasListingListener, isFalse);
    });
  });

  group('what the client holds from an earlier watch', () {
    test('is current only while the list is watched, and again once the computer answers', () {
      ai()
        ..supportedValue = true
        ..listingValue = _before;
      expect(workspace.aiListing, same(_before), reason: 'nothing was watched yet: as the client has it');
      final first = workspace.holdAiListing();
      expect(workspace.aiListing, same(_before));
      first(); // the page left
      expect(ai().listing, same(_before), reason: 'the client still holds it');
      expect(workspace.aiListing, isNull, reason: 'but it may be old now');

      final second = workspace.holdAiListing(); // back
      expect(workspace.aiListing, isNull, reason: 'until the computer answers');
      ai().emitListing(_after);
      expect(workspace.aiListing, same(_after));
      second();
    });

    test('the picker of a later visit waits for the computer rather than show the old listing', () {
      fakeAsync((async) {
        ai()
          ..supportedValue = true
          ..listingValue = _before;
        workspace.holdAiListing()(); // an earlier visit: watched, then let go

        final release = workspace.holdAiListing();
        final picking = follow(async, workspace.pickable());
        expect(picking.done(), isFalse, reason: 'the old listing is not offered');

        ai().emitListing(_after);
        async.flushMicrotasks();
        expect(picking.done(), isTrue);
        expect(picking.value()!.ai, same(_after));
        release();
      });
    });

    test('and shows nothing, not the old listing, when the computer does not answer in time', () {
      fakeAsync((async) {
        ai()
          ..supportedValue = true
          ..listingValue = _before;
        workspace.holdAiListing()();

        final release = workspace.holdAiListing();
        final picking = follow(async, workspace.pickable());
        async.elapse(TerminalWorkspace.aiListingWait - const Duration(milliseconds: 1));
        expect(picking.done(), isFalse);
        async.elapse(const Duration(milliseconds: 1));
        expect(picking.done(), isTrue);
        expect(picking.value()!.ai, isNull);
        expect(picking.value()!.aiSupported, isTrue);
        release();
        expect(ai().hasListingListener, isFalse, reason: 'a wait that timed out listens to nothing');
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('the answer of the second watch makes the listing current for the pickers after it', () async {
      ai()
        ..supportedValue = true
        ..listingValue = _before;
      workspace.holdAiListing()();
      final release = workspace.holdAiListing();
      ai().emitListing(_after);
      expect((await workspace.pickable()).ai, same(_after), reason: 'no waiting: it is current');
      expect(ai().watchCalls, 2, reason: 'one watch per visit, not one per picker');
      release();
    });
  });

  group('TerminalPageController', () {
    TerminalPageController page() =>
        TerminalPageController(agentA, registry, session, AppSettings(InMemoryKeyValueStore()));

    test('a page holds the list while it exists and lets it go when it is disposed', () {
      ai()
        ..supportedValue = true
        ..listingValue = _before;
      final controller = page();
      expect(ai().watching, isTrue);
      expect(controller.aiListing.value, same(_before), reason: 'nothing was let go before: current');
      controller.dispose();
      expect((ai().watchCalls, ai().unwatchCalls, ai().watching), (1, 1, false));
    });

    test('a page that took the place of another for the same machine keeps the watch when the old one leaves', () {
      ai()
        ..supportedValue = true
        ..listingValue = _before;
      final old = page();
      final newer = page();
      expect(ai().watchCalls, 1);
      old.dispose();
      expect(ai().watching, isTrue, reason: 'the old page leaves after the new one is up (its transition runs)');
      newer.dispose();
      expect((ai().unwatchCalls, ai().watching), (1, false));
    });

    test('a later visit shows no badge from the listing of the earlier one, until the computer answers', () {
      ai()
        ..supportedValue = true
        ..listingValue = _before;
      page().dispose();
      final second = page();
      expect(second.aiListing.value, isNull);
      ai().emitListing(_after);
      expect(second.aiListing.value, same(_after));
      second.dispose();
    });

    test('a computer without AI for phones is not watched by the page', () {
      ai().supportedValue = false;
      page().dispose();
      expect((ai().watchCalls, ai().unwatchCalls), (0, 0));
    });

    test('a page that is gone leaves no listener of the listing behind', () {
      ai().supportedValue = true;
      final controller = page();
      expect(ai().hasListingListener, isTrue);
      controller.dispose();
      expect(ai().hasListingListener, isFalse, reason: 'neither the page\'s nor the workspace\'s');
    });

    test('disposing twice lets go once', () {
      ai().supportedValue = true;
      final controller = page();
      controller.dispose();
      controller.dispose();
      expect(ai().unwatchCalls, 1);
    });

    test('a listing that comes after the page is gone writes nothing', () {
      ai().supportedValue = true;
      page().dispose();
      expect(() => ai().emitListing(_before), returnsNormally);
    });
  });
}
