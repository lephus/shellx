import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('local_notifier');
  late List<String> calls;
  Completer<void>? holdClose;

  setUp(() {
    calls = [];
    holdClose = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'close') await holdClose?.future;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('a close(id) while the previous notification is going away '
      'stops the new one from showing (D15)', () async {
    final n = LocalSystemNotifier.forTest();
    await n.show(id: 'shellx.tab.1', title: 't', body: 'first');
    expect(calls, ['notify']);
    holdClose = Completer<void>();
    final second = n.show(id: 'shellx.tab.1', title: 't', body: 'second');
    await pumpEventQueue();
    expect(calls, ['notify', 'close']); // the first is going away
    final closing = n.close('shellx.tab.1'); // the tab was read meanwhile
    holdClose!.complete();
    await second;
    await closing;
    expect(calls.where((c) => c == 'notify'), hasLength(1));
  });

  test('a replacement shows after the previous one is removed', () async {
    final n = LocalSystemNotifier.forTest();
    await n.show(id: 'a', title: 't', body: '1');
    await n.show(id: 'a', title: 't', body: '2');
    expect(calls, ['notify', 'close', 'notify']);
    await n.close('a');
    expect(calls.last, 'close');
  });
}
