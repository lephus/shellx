import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/app_reopen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> send(String method) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    await messenger.handlePlatformMessage(
      appReopenChannel.name,
      appReopenChannel.codec.encodeMethodCall(MethodCall(method)),
      (_) {},
    );
  }

  tearDown(() => appReopenChannel.setMethodCallHandler(null));

  test('each reopen from AppDelegate calls the handler once', () async {
    var reopens = 0;
    listenForReopen(() => reopens++);
    await send('reopen');
    await send('reopen');
    expect(reopens, 2);
  });

  test('other calls are ignored', () async {
    var reopens = 0;
    listenForReopen(() => reopens++);
    await send('somethingElse');
    expect(reopens, 0);
  });

  test('the channel name matches AppDelegate.swift', () {
    expect(appReopenChannel.name, 'pro.shellx.desktop/app');
  });
}
