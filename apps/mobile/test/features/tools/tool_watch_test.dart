import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

import '../../support/fakes.dart';

const _board = ToolInfo(id: 'k3f9za7q1m', name: 'Bảng việc', ws: 'shop-web', port: 4000, path: '/', group: 'ws:a');

/// What the computer said the first time.
const _before = ToolListing(tools: [_board]);

/// What it says later: the tool was turned off meanwhile.
const _after = ToolListing();

/// V2-4 criterion 1: the tool list is asked for by whoever shows it (the session picker), and let go
/// ([ToolMachine.unwatch]) when nothing holds it any more, the way the AI list is (`ai_watch_test.dart`):
/// otherwise every relay or presence event would make a handshake with every machine ever watched.
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

  FakeToolMachine tools() => machine.tools;

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

  group('what the picker is given', () {
    test('a computer without tools for phones is never watched, and the picker does not wait for it', () {
      fakeAsync((async) {
        for (final supported in [null, false]) {
          tools().supportedValue = supported;
          final release = workspace.holdToolListing();
          final picking = follow(async, workspace.pickable());
          expect(picking.done(), isTrue, reason: 'no time passes: no list can come ($supported)');
          release();
          final listing = picking.value()!;
          expect(listing.toolsSupported, supported);
          expect(listing.tools, isNull);
          expect(listing.toolUpdates, isNull);
          expect(listing.isEmpty, isTrue, reason: 'nothing to pick: + opens a session at once');
        }
        expect((tools().watchCalls, tools().unwatchCalls), (0, 0));
      });
    });

    test('a computer with tools always has something to pick, however empty its list', () async {
      tools()
        ..supportedValue = true
        ..listingValue = _after;
      final listing = await workspace.pickable();
      expect(listing.toolsSupported, isTrue);
      expect(listing.tools, same(_after));
      expect(listing.toolUpdates, isNotNull);
      expect(listing.isEmpty, isFalse, reason: 'the Tool group offers its hint');
    });

    test('the picker asks for the list and, when no page holds it, lets it go again', () async {
      tools()
        ..supportedValue = true
        ..listingValue = _before;
      final listing = await workspace.pickable();
      expect(listing.tools, same(_before));
      expect((tools().watchCalls, tools().unwatchCalls, tools().watching), (1, 1, false));
      expect(tools().hasListingListener, isFalse);
    });

    test('the picker waits three seconds for the first list, then offers none', () {
      fakeAsync((async) {
        tools().supportedValue = true; // no list yet: the picker waits for it
        final picking = follow(async, workspace.pickable());
        expect(picking.done(), isFalse);
        async.elapse(TerminalWorkspace.aiListingWait - const Duration(milliseconds: 1));
        expect(picking.done(), isFalse);
        async.elapse(const Duration(milliseconds: 1));
        expect(picking.done(), isTrue);
        final listing = picking.value()!;
        expect(listing.toolsSupported, isTrue);
        expect(listing.tools, isNull, reason: '"open ShellX on the computer" until it answers');
        expect(listing.toolUpdates, isNotNull, reason: 'and the answer shows when it comes');
        expect((tools().watchCalls, tools().unwatchCalls, tools().watching), (1, 1, false));
        expect(tools().hasListingListener, isFalse, reason: 'a wait that timed out listens to nothing');
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a list that comes while the picker waits ends the wait at once', () {
      fakeAsync((async) {
        tools().supportedValue = true;
        final picking = follow(async, workspace.pickable());
        expect(picking.done(), isFalse);
        tools().emitListing(_before);
        async.flushMicrotasks();
        expect(picking.done(), isTrue, reason: 'no time passes');
        expect(picking.value()!.tools, same(_before));
        expect(tools().hasListingListener, isFalse);
        expect(async.pendingTimers, isEmpty, reason: 'the wait is over: no time-out left running');
      });
    });

    test('a machine dropped while the picker waits: no list, at once', () {
      fakeAsync((async) {
        tools().supportedValue = true;
        final picking = follow(async, workspace.pickable());
        expect(picking.done(), isFalse);
        unawaited(tools().endListings());
        async.flushMicrotasks();
        expect(picking.done(), isTrue, reason: 'no time passes: nothing will come');
        expect(picking.value()!.tools, isNull);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a machine that cannot be reached: the failing watch() is no failure of the picker', () {
      fakeAsync((async) {
        tools()
          ..supportedValue = true
          ..connectFailure = MachineConnectionFailure.agentOffline;
        final picking = follow(async, workspace.pickable());
        async.elapse(TerminalWorkspace.aiListingWait);
        expect(picking.done(), isTrue);
        expect(picking.value()!.tools, isNull);
        expect((tools().watchCalls, tools().unwatchCalls), (1, 1));
      });
    });
  });

  group('who holds the list', () {
    test('a page that holds the list keeps it watched until the last holder lets go', () async {
      tools()
        ..supportedValue = true
        ..listingValue = _before;
      final first = workspace.holdToolListing();
      expect(tools().watchCalls, 1, reason: 'the computer is known to have tools: watched at once');
      final second = workspace.holdToolListing();
      expect(tools().watchCalls, 1, reason: 'one watch for both');

      await workspace.pickable(); // a picker comes and goes meanwhile
      expect((tools().watchCalls, tools().unwatchCalls), (1, 0));

      first();
      first(); // letting go twice is letting go once
      expect(tools().unwatchCalls, 0, reason: 'the other holder still wants it');
      second();
      expect((tools().watchCalls, tools().unwatchCalls, tools().watching), (1, 1, false));
    });

    test('held before the computer is known to have tools: the first picker starts the watch', () async {
      final release = workspace.holdToolListing();
      expect(tools().watchCalls, 0);
      // What the first list of the sessions tells:
      tools()
        ..supportedValue = true
        ..listingValue = _before;
      await workspace.pickable();
      expect((tools().watchCalls, tools().unwatchCalls), (1, 0), reason: 'the holder still wants it');
      release();
      expect((tools().unwatchCalls, tools().watching), (1, false));
    });

    test('disposing the workspace stops the watch; a holder letting go afterwards stops nothing twice', () {
      tools().supportedValue = true;
      final release = workspace.holdToolListing();
      expect(tools().watching, isTrue);
      registry.remove(agentA);
      expect((tools().unwatchCalls, tools().watching), (1, false));
      release();
      expect(tools().unwatchCalls, 1);
      // A dead workspace holds nothing.
      workspace.holdToolListing()();
      expect((tools().watchCalls, tools().unwatchCalls), (1, 1));
    });

    test('no listener of the list is left behind, however the watch ended', () {
      tools().supportedValue = true;
      expect(tools().hasListingListener, isFalse);
      final release = workspace.holdToolListing();
      expect(tools().hasListingListener, isTrue, reason: 'watched: the workspace hears the answers');
      release();
      expect(tools().hasListingListener, isFalse);

      workspace.holdToolListing();
      registry.remove(agentA); // the workspace is dropped with a holder still there
      expect(tools().hasListingListener, isFalse);
    });
  });

  group('what the client holds from an earlier watch', () {
    test('is current only while the list is watched, and again once the computer answers', () {
      tools()
        ..supportedValue = true
        ..listingValue = _before;
      expect(workspace.toolListing, same(_before), reason: 'nothing was watched yet: as the client has it');
      final first = workspace.holdToolListing();
      expect(workspace.toolListing, same(_before));
      first(); // the picker closed
      expect(tools().listing, same(_before), reason: 'the client still holds it');
      expect(workspace.toolListing, isNull, reason: 'but it may be old now');

      final second = workspace.holdToolListing(); // the next picker
      expect(workspace.toolListing, isNull, reason: 'until the computer answers');
      tools().emitListing(_after);
      expect(workspace.toolListing, same(_after));
      second();
    });

    test('the picker of a later visit waits for the computer rather than show the old list', () {
      fakeAsync((async) {
        tools()
          ..supportedValue = true
          ..listingValue = _before;
        workspace.holdToolListing()(); // an earlier visit: watched, then let go

        final picking = follow(async, workspace.pickable());
        expect(picking.done(), isFalse, reason: 'the old list is not offered');

        tools().emitListing(_after);
        async.flushMicrotasks();
        expect(picking.done(), isTrue);
        expect(picking.value()!.tools, same(_after));
      });
    });
  });
}
