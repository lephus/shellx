import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/app_reopen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> send(String method) => messenger.handlePlatformMessage(
    appChannel.name,
    appChannel.codec.encodeMethodCall(MethodCall(method)),
    (_) {},
  );

  tearDown(() {
    appChannel.setMethodCallHandler(null);
    messenger.setMockMethodCallHandler(appChannel, null);
  });

  test(
    'reopen and quitRequested from AppDelegate reach their handlers',
    () async {
      var reopens = 0;
      var quits = 0;
      listenForAppChannel(
        onReopen: () => reopens++,
        onQuitRequested: () => quits++,
      );
      await send('reopen');
      await send('reopen');
      await send('quitRequested');
      await send('somethingElse');
      expect((reopens, quits), (2, 1));
    },
  );

  test('setDockVisible calls the native side with a bool', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(appChannel, (call) async {
      calls.add(call);
      return null;
    });
    await setDockVisible(true);
    await setDockVisible(false);
    expect(
      [for (final c in calls) (c.method, c.arguments)],
      [('setDockVisible', true), ('setDockVisible', false)],
    );
  });

  test('the channel name matches AppDelegate.swift', () {
    expect(appChannel.name, 'pro.shellx.desktop/app');
  });
}
