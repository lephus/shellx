import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import 'package:shellx_desktop/src/browser/engines/wk_webview_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('NSURLError codes map to error kinds (A6 D14)', () {
    expect(macErrorKind(-1004), BrowserLoadErrorKind.refused);
    expect(macErrorKind(-1003), BrowserLoadErrorKind.dns);
    expect(macErrorKind(-1006), BrowserLoadErrorKind.dns);
    expect(macErrorKind(-1001), BrowserLoadErrorKind.timeout);
    expect(macErrorKind(-1009), BrowserLoadErrorKind.unreachable);
    expect(macErrorKind(-1005), BrowserLoadErrorKind.unreachable);
    for (final c in [-1200, -1201, -1202, -1203, -1204, -1205, -1206]) {
      expect(macErrorKind(c), BrowserLoadErrorKind.certificate);
    }
    expect(macErrorKind(-999), isNull); // cancelled by a newer navigation
    expect(
      macErrorKind(0, processTerminated: true),
      BrowserLoadErrorKind.crashed,
    );
    expect(macErrorKind(-1100), BrowserLoadErrorKind.other);
    expect(isMacInterruptedLoad(102), isTrue);
    expect(isMacInterruptedLoad(-1004), isFalse);
  });

  test('BrowserNativeMac: outbound calls and inbound events', () async {
    const channel = MethodChannel('test/browser');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final native = BrowserNativeMac(channel);
    final events = <BrowserEngineEvent>[];
    native.attach(7, events.add);
    await native.setForwardedChords(7, ['meta+t']);
    await native.stop(7);
    await native.focus(7);
    await native.blur(7);
    await native.clearAll();
    expect(calls.map((c) => c.method), [
      'setForwardedChords',
      'stop',
      'focus',
      'blur',
      'clearWebsiteData',
    ]);
    expect(calls.first.arguments, {
      'id': 7,
      'chords': ['meta+t'],
    });

    Future<void> inbound(String method, Map<String, Object?> args) =>
        messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(MethodCall(method, args)),
          (_) {},
        );
    await inbound('shortcut', {'id': 7, 'chord': 'meta+t'});
    await inbound('pointerDown', {'id': 7});
    await inbound('shortcut', {'id': 99, 'chord': 'meta+t'}); // not ours
    expect(events, hasLength(2));
    expect((events[0] as ShortcutForwarded).chord, 'meta+t');
    expect(events[1], isA<ContentClicked>());
    native.detach(7);
    await inbound('pointerDown', {'id': 7});
    expect(events, hasLength(2));
  });
}
