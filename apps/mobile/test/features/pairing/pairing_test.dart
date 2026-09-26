import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/pairing/domain/pairing_flow.dart';
import 'package:shellx_mobile/features/pairing/presentation/controllers/qr_scanner_controller.dart';
import 'package:shellx_mobile/features/pairing/presentation/pages/qr_scanner_page.dart';
import 'package:shellx_mobile/shared/shared.dart';

import '../../support/app_harness.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fakes.dart';

void main() {
  final validCode = PairingUri(
    agentDeviceId: agentA,
    agentPublicKey: Uint8List(32)..fillRange(0, 32, 7),
    secret: Uint8List(32)..fillRange(0, 32, 9),
  ).toUriString();
  late FakeBackend backend;

  setUp(() => backend = FakeBackend());

  group('pairFromQrCode', () {
    late ErrorText text;
    setUp(() async => text = ErrorText(await S.load(vi)));

    test('pairs with the scanned machine', () async {
      final outcome = await pairFromQrCode(validCode, backend, text);
      expect(outcome, isA<PairingSucceeded>().having((o) => o.agentId, 'agentId', agentA));
      expect(backend.paired.single.agentDeviceId, agentA);
    });

    test('a QR code that is not a pairing URI is "invalid or expired"', () async {
      final outcome = await pairFromQrCode('https://example.com', backend, text);
      expect(
        (outcome as PairingRejected).message,
        'Mã QR không hợp lệ hoặc đã hết hạn. Hãy tạo mã mới trên máy tính.',
      );
      expect(backend.paired, isEmpty);
    });

    final cases = {
      PairingFailure.notInAccount: 'Máy này không thuộc tài khoản của bạn. Hãy đăng nhập cùng tài khoản trên máy tính.',
      PairingFailure.invalidOrExpired: 'Mã QR không hợp lệ hoặc đã hết hạn. Hãy tạo mã mới trên máy tính.',
      PairingFailure.agentOffline: 'Máy tính đang offline. Hãy mở ShellX trên máy tính rồi thử lại.',
      PairingFailure.protocolUnsupported: 'Cần cập nhật app',
      PairingFailure.timeout: 'Máy tính không phản hồi. Hãy thử lại.',
    };
    for (final entry in cases.entries) {
      test('${entry.key} → spec message', () async {
        backend.pairError = PairingException(entry.key);
        final outcome = await pairFromQrCode(validCode, backend, text);
        expect((outcome as PairingRejected).message, entry.value);
      });
    }

    test('a rate-limited GET /v1/devices maps to "Thử lại sau ít phút."', () async {
      backend.pairError = const ApiException(status: 429, code: 'rate_limited', message: 'slow down');
      final outcome = await pairFromQrCode(validCode, backend, text);
      expect((outcome as PairingRejected).message, 'Thử lại sau ít phút.');
    });
  });

  group('QrScannerPage', () {
    late ValueChanged<String> scan;
    late List<Object?> results;
    late List<Object?> terminals;

    setUp(() {
      backend.deviceList = [agentDevice(agentA, 'MacBook Pro của Phú')];
      results = [];
      terminals = [];
      final session = FakeSessionHolder(backend);
      getIt
        ..registerSingleton<PopupHandler>(FakePopupHandler())
        ..registerFactory<QrScannerController>(() => QrScannerController(session));
    });

    tearDown(getIt.reset);

    Future<void> openScanner(WidgetTester tester) async {
      // Reduced motion stops the scan line, so pumpAndSettle can settle.
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pumpWidget(
        routedApp(
          open: () => QrScannerRoute(
            scannerBuilder: (context, onCode) {
              scan = onCode;
              return const ColoredBox(color: Colors.black);
            },
          ),
          routes: [
            AutoRoute(page: QrScannerRoute.page),
            stubRoute(TerminalRoute.name, pushed: terminals),
          ],
          results: results,
        ),
      );
      await tester.pumpAndSettle();
      await openPushed(tester);
    }

    testWidgets('the camera card says where the code is', (tester) async {
      await openScanner(tester);
      expect(find.text('Quét mã ghép nối'), findsOneWidget);
      expect(find.text('Mã nằm trên máy tính của bạn'), findsOneWidget);
      expect(find.text('Ghép nối điện thoại…'), findsOneWidget);
      await tester.tap(find.byTooltip('Đóng'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('success: "Đã ghép nối" with the machine; "Về danh sách máy" returns it', (tester) async {
      await openScanner(tester);
      scan(validCode);
      await tester.pumpAndSettle();
      expect(find.text('Đã ghép nối'), findsOneWidget);
      expect(find.textContaining('MacBook Pro của Phú đã tin cậy điện thoại này.'), findsOneWidget);

      await tester.tap(find.text('Về danh sách máy'));
      await tester.pumpAndSettle();
      expect(results, [agentA]);
    });

    testWidgets('success: "Mở terminal" opens the new machine', (tester) async {
      await openScanner(tester);
      scan(validCode);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mở terminal'));
      await tester.pumpAndSettle();
      final args = terminals.single as TerminalRouteArgs;
      expect((args.agentId, args.machineName), (agentA, 'MacBook Pro của Phú'));
    });

    testWidgets('a failure shows the sheet; scans wait for "Quét lại"; "Đóng" leaves', (tester) async {
      backend.pairError = const PairingException(PairingFailure.notInAccount);
      await openScanner(tester);

      scan(validCode);
      await tester.pumpAndSettle();
      expect(find.text('Không ghép nối được'), findsOneWidget);
      expect(
        find.text('Máy này không thuộc tài khoản của bạn. Hãy đăng nhập cùng tài khoản trên máy tính.'),
        findsOneWidget,
      );

      scan(validCode); // ignored while the sheet is shown
      await tester.pumpAndSettle();
      expect(backend.paired, isEmpty);

      await tester.tap(find.text('Quét lại'));
      await tester.pumpAndSettle();
      backend.pairError = null;
      scan(validCode);
      await tester.pumpAndSettle();
      expect(backend.paired, hasLength(1));
    });

    testWidgets('"Đóng" on the failure sheet closes the scanner', (tester) async {
      await openScanner(tester);
      scan('https://example.com');
      await tester.pumpAndSettle();
      expect(find.text('Mã QR không hợp lệ hoặc đã hết hạn. Hãy tạo mã mới trên máy tính.'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppButton, 'Đóng'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });

    // ---- Fix round 1 (task-15-fix1-findings.md) ----

    testWidgets(
      '(Critical) the name lookup finishing after the page closes writes nothing (no crash)',
      (tester) async {
        final gate = Completer<void>();
        backend.devicesGate = gate;
        await openScanner(tester);

        scan(validCode);
        await tester.pump();
        // Still resolving the machine name (`devices()` is gated): the pairing overlay is up.
        expect(find.text('Đang ghép nối…'), findsOneWidget);

        // Close the scanner (as "Đóng"/system back would) while that lookup is still in flight.
        tester.element(find.byType(QrScannerPage)).router.maybePop();
        await tester.pumpAndSettle();
        expect(find.text('open'), findsOneWidget);

        // The gated `devices()` call now resolves, after the controller (and its signal) is
        // disposed: this must not throw (SignalsWriteAfterDisposeError) or leak an unhandled error.
        gate.complete();
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'R2: devices() failing right after pairing still succeeds with "Máy không xác định"',
      (tester) async {
        backend.devicesError = const ApiException(status: 401, code: 'unauthorized', message: 'no token');
        await openScanner(tester);
        scan(validCode);
        await tester.pumpAndSettle();
        expect(find.text('Đã ghép nối'), findsOneWidget);
        expect(find.textContaining('Máy không xác định đã tin cậy điện thoại này.'), findsOneWidget);
        expect(find.text('Không ghép nối được'), findsNothing);
      },
    );
  });
}
