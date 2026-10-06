import 'dart:io';

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

  test('activateMacApp asks the native side to activate the app', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(appChannel, (call) async {
      calls.add(call.method);
      return null;
    });
    await activateMacApp();
    expect(calls, ['activate']);
  });

  test('AppDelegate.swift handles activate and un-minimizes on reopen', () {
    final swift = File('macos/Runner/AppDelegate.swift').readAsStringSync();
    expect(swift, contains('case "activate":'));
    expect(swift, contains('NSApp.activate(ignoringOtherApps: true)'));
    // A Dock click after ⌘M brings the window back (ruling C1).
    final reopen = swift.substring(
      swift.indexOf('applicationShouldHandleReopen'),
      swift.indexOf('AppChannel.reopen()'),
    );
    expect(reopen, contains('deminiaturize'));
  });

  test('the channel name matches AppDelegate.swift', () {
    expect(appChannel.name, 'pro.shellx.desktop/app');
  });
}
