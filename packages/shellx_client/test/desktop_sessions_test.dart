import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/drive.dart';
import 'support/harness.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  late TestKeys keys;
  setUpAll(() async => keys = await TestKeys.generate());

  test('listSessions() is unchanged; includeDesktop adds desktop sessions '
      'and desktopSharing', () {
    fakeAsync((async) {
      final h = Harness(async, keys)..shareWindow(1);
      final machine = h.phoneMachine;
      expect(h.run(machine.listSessions()), isEmpty);
      expect(machine.desktopSharing, isNull);
      final all = h.run(machine.listSessions(includeDesktop: true));
      expect(all.single.kind, SessionKind.desktop);
      expect(all.single.app, 'Terminal');
      expect(machine.desktopSharing, isTrue);
    });
  });

  test('attach a desktop terminal: earlier output, typing, driver events', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final link = h.shareWindow(1, snapshot: 'before\r\n');
      final machine = h.phoneMachine;
      final id = h.run(machine.listSessions(includeDesktop: true)).single.id;
      final tab = h.run(machine.attach(id, cols: 50, rows: 20));
      final events = <TabEvent>[];
      tab.events.listen(events.add);
      settle(async);
      expect(tab.kind, SessionKind.desktop);
      expect(tab.app, 'Terminal');

      machine.input(id, _b('ls\r'));
      settle(async);
      expect(link.typed, 'ls\r');

      link.emit(const TermLocal());
      settle(async);
      expect(
        events.whereType<TabDriver>().map((e) => e.by),
        contains(DriverSide.desktop),
      );
    });
  });

  test('closeTab on a desktop tab detaches; the terminal stays', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final link = h.shareWindow(1);
      final machine = h.phoneMachine;
      final id = h.run(machine.listSessions(includeDesktop: true)).single.id;
      h.run(machine.attach(id, cols: 50, rows: 20));
      h.run(machine.closeTab(id));
      settle(async);
      expect(link.closed, isFalse);
      expect(link.sent.last, isA<AgentLocalSize>());
      expect(h.desktop.sessions.single.attachedMobileId, isNull);
    });
  });

  test('a desktop tab re-attaches after the phone reconnects, without '
      'listing again (Review Focus 1)', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final link = h.shareWindow(1);
      final machine = h.phoneMachine;
      final id = h.run(machine.listSessions(includeDesktop: true)).single.id;
      final tab = h.run(machine.attach(id, cols: 50, rows: 20));
      final text = StringBuffer();
      tab.events.listen((e) {
        if (e is TabOutput) text.write(e.text);
      });
      h.disconnectPhone();
      link.out('while away');
      settle(async);
      h.reconnectPhone();
      expect(tab.isAttached, isTrue);
      expect(text.toString(), contains('while away'));
      expect(h.desktop.sessions.single.attachedMobileId, phoneId);
    });
  });

  test('terminal_gone ends the tab; it is not re-attached', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final link = h.shareWindow(1);
      final machine = h.phoneMachine;
      final id = h.run(machine.listSessions(includeDesktop: true)).single.id;
      final tab = h.run(machine.attach(id, cols: 50, rows: 20));
      final events = <TabEvent>[];
      tab.events.listen(events.add);
      link.drop();
      async.elapse(const Duration(seconds: 31));
      expect(
        events.whereType<TabDetached>().single.reason,
        DetachReason.terminalGone,
      );
      expect(tab.isAttached, isFalse);
    });
  });
}
