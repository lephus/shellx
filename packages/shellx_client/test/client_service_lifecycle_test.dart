import 'package:fake_async/fake_async.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:test/test.dart';

import 'support/drive.dart';
import 'support/harness.dart';

void main() {
  late TestKeys keys;
  setUpAll(() async => keys = await TestKeys.generate());

  test('overlapping start() calls subscribe once; the channel works', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      h.phone.stop();
      settle(async);

      final first = h.phone.start();
      final second = h.phone.start();
      h.run(first);
      h.run(second);
      settle(async);

      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final recorder = TabRecorder(tab);
      h.pty.emit('hello');
      settle(async);
      expect(recorder.text, 'hello');
      expect(tab.isAttached, isTrue);
      expect(h.phoneMachine.state, isA<MachineReady>());
    });
  });

  test(
    'stop() while start() loads the pins wins; start() afterwards works',
    () {
      fakeAsync((async) {
        final h = Harness(async, keys);
        h.phone.stop();
        settle(async);

        final starting = h.phone.start(); // Suspended reading the pins.
        h.phone.stop();
        h.run(starting);
        async.elapse(const Duration(seconds: 3));
        expect(h.relay.isOnline(phoneId), isFalse);
        expect(h.phone.isOnline(agentId), isFalse);

        h.run(h.phone.start());
        settle(async);
        expect(h.relay.isOnline(phoneId), isTrue);
        expect(h.phone.isOnline(agentId), isTrue);
        h.run(h.phoneMachine.connect());
        expect(h.phoneMachine.state, isA<MachineReady>());
      });
    },
  );

  test('start, stop, start before the pins load: the last start wins and '
      'subscribes once', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      h.phone.stop();
      settle(async);

      final first = h.phone.start();
      h.phone.stop();
      final second = h.phone.start();
      h.run(first);
      h.run(second);
      settle(async);
      expect(h.relay.isOnline(phoneId), isTrue);

      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final recorder = TabRecorder(tab);
      h.pty.emit('hello');
      settle(async);
      expect(recorder.text, 'hello');
      expect(h.phoneMachine.state, isA<MachineReady>());
    });
  });
}
