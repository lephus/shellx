import 'dart:async';
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

  test(
    'saveBeforeExit answers only after the save finished (A5a D18)',
    () async {
      final done = Completer<void>();
      var saved = false;
      listenForAppChannel(
        onReopen: () {},
        onQuitRequested: () {},
        onSaveBeforeExit: () async {
          await done.future;
          saved = true;
        },
      );
      var answered = false;
      final reply = send('saveBeforeExit').then((_) => answered = true);
      await pumpEventQueue();
      expect((saved, answered), (false, false));
      done.complete();
      await reply;
      expect((saved, answered), (true, true));
    },
  );

  test('exitCancelled reaches its handler; without handlers both calls '
      'are answered', () async {
    var cancelled = 0;
    listenForAppChannel(
      onReopen: () {},
      onQuitRequested: () {},
      onExitCancelled: () => cancelled++,
    );
    await send('exitCancelled');
    expect(cancelled, 1);
    listenForAppChannel(onReopen: () {}, onQuitRequested: () {});
    await send('saveBeforeExit');
    await send('exitCancelled');
    await send('quitAfterSave');
  });

  test('quitAfterSave (Windows Restart Manager) reaches its handler', () async {
    var quits = 0;
    listenForAppChannel(
      onReopen: () {},
      onQuitRequested: () {},
      onQuitAfterSave: () => quits++,
    );
    await send('quitAfterSave');
    expect(quits, 1);
  });

  test('AppDelegate.swift: power-off waits (at most 3 s) for saveBeforeExit; '
      'a terminate that did not happen resumes saving', () {
    final swift = File('macos/Runner/AppDelegate.swift').readAsStringSync();
    final terminate = swift.substring(
      swift.indexOf('func applicationShouldTerminate(_'),
      swift.indexOf('enum AppChannel'),
    );
    expect(terminate, contains('AppChannel.saveBeforeExit'));
    expect(terminate, contains('.terminateLater'));
    expect(terminate, contains('reply(toApplicationShouldTerminate: true)'));
    expect(terminate, contains('.now() + 3'));
    expect(terminate, contains('AppChannel.exitCancelled()'));
    expect(swift, contains('invokeMethod("saveBeforeExit"'));
    expect(swift, contains('invokeMethod("exitCancelled"'));
  });

  test('flutter_window.cpp: WM_QUERYENDSESSION asks Dart to save; '
      'WM_ENDSESSION waits for it, or resumes when cancelled', () {
    final cpp = File('windows/runner/flutter_window.cpp').readAsStringSync();
    expect(cpp, contains('"pro.shellx.desktop/app"'));
    expect(cpp, contains('case WM_QUERYENDSESSION:'));
    expect(cpp, contains('"saveBeforeExit"'));
    expect(cpp, contains('WaitForSave()'));
    expect(cpp, contains('case WM_ENDSESSION:'));
    expect(cpp, contains('InvokeMethod("exitCancelled"'));
    // Restart Manager: once saved, quit through Dart's Quit (D18 amended).
    expect(cpp, contains('ENDSESSION_CLOSEAPP'));
    expect(cpp, contains('InvokeMethod("quitAfterSave"'));
    final header = File('windows/runner/flutter_window.h').readAsStringSync();
    expect(header, contains('app_channel_'));
  });

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

  test('quitAllRequested (the app menu item, ⌥⌘Q) reaches its handler; '
      'without one it is answered', () async {
    var all = 0;
    listenForAppChannel(
      onReopen: () {},
      onQuitRequested: () {},
      onQuitAllRequested: () => all++,
    );
    await send('quitAllRequested');
    expect(all, 1);
    listenForAppChannel(onReopen: () {}, onQuitRequested: () {});
    await send('quitAllRequested');
  });

  test(
    'setQuitAllTitle sends the localised menu title once, to the app',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(appChannel, (call) async {
        calls.add(call);
        return null;
      });
      await setQuitAllTitle('Thoát hoàn toàn');
      expect(calls.single.method, 'setQuitAllTitle');
      expect(calls.single.arguments, 'Thoát hoàn toàn');
    },
  );

  test('AppDelegate.swift: ⌥⌘Q "Quit Completely" follows Quit in the app '
      'menu, UI only, and goes to Dart', () {
    final swift = File('macos/Runner/AppDelegate.swift').readAsStringSync();
    expect(swift, contains('setQuitAllTitle'));
    expect(swift, contains('.command, .option'));
    expect(swift, contains('quitAllRequested'));
    expect(swift, contains('#selector(NSApplication.terminate(_:))'));
  });
}
