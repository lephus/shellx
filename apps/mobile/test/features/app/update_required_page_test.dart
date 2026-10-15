import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/app/update_required_page.dart';
import 'package:shellx_mobile/shared/shared.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fake_relay_http.dart';

void main() {
  late FakeExternalLinks links;
  late FakePopupHandler popups;
  late FakeRelayHttp relay;
  late VersionGate gate;

  setUp(() {
    links = FakeExternalLinks();
    popups = FakePopupHandler();
    relay = FakeRelayHttp();
    gate = VersionGate(
      ShellxApi(baseUri: Uri.parse('http://127.0.0.1:8787'), httpClient: relay.client),
      PackageInfo(appName: 'ShellX', packageName: 'com.shellx.prod', version: '1.0.0', buildNumber: '1'),
    );
    getIt
      ..registerSingleton<ExternalLinks>(links)
      ..registerSingleton<PopupHandler>(popups)
      ..registerSingleton<VersionGate>(gate);
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('shows the title and body', (tester) async {
    await tester.pumpWidget(localized(const UpdateRequiredPage()));
    expect(find.text('Cần cập nhật app'), findsOneWidget);
    expect(find.text('Phiên bản này không còn kết nối được với máy của bạn. Cập nhật để dùng tiếp.'), findsOneWidget);
    // Opened for a machine's proto_unsupported: no version of the app to name.
    expect(find.textContaining('Cần phiên bản'), findsNothing);
  });

  testWidgets('names the version it needs while the app is too old', (tester) async {
    relay.minMobile = '1.2.0';
    await gate.check();
    await tester.pumpWidget(localized(const UpdateRequiredPage()));
    expect(find.text('Cần phiên bản 1.2.0 trở lên.'), findsOneWidget);

    await tester.pumpWidget(localized(const UpdateRequiredPage(), locale: en));
    await tester.pumpAndSettle();
    expect(find.text('Requires version 1.2.0 or newer.'), findsOneWidget);
  });

  group('back (contract §5)', () {
    Widget routed() => routedApp(
      open: () => const UpdateRequiredRoute(),
      routes: [AutoRoute(page: UpdateRequiredRoute.page)],
    );

    testWidgets('no way back while the app is too old: neither system back nor the swipe', (tester) async {
      relay.minMobile = '2.0.0';
      await gate.check();
      await tester.pumpWidget(routed());
      await tester.pumpAndSettle();
      await openPushed(tester);
      expect(find.byType(UpdateRequiredPage), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(UpdateRequiredPage), findsOneWidget);

      expect(ModalRoute.of(tester.element(find.byType(UpdateRequiredPage)))!.popGestureEnabled, isFalse);
      await tester.timedDragFrom(const Offset(4, 300), const Offset(500, 0), const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.byType(UpdateRequiredPage), findsOneWidget);
    });

    testWidgets('opened for a machine\'s proto_unsupported, back closes it as usual', (tester) async {
      await gate.check();
      await tester.pumpWidget(routed());
      await tester.pumpAndSettle();
      await openPushed(tester);
      expect(find.byType(UpdateRequiredPage), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(UpdateRequiredPage), findsNothing);
      expect(find.text('open'), findsOneWidget);

      // The same swipe as above.
      await openPushed(tester);
      await tester.timedDragFrom(const Offset(4, 300), const Offset(500, 0), const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.byType(UpdateRequiredPage), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });
  });

  testWidgets(
    'the button opens the matching store for this platform',
    variant: const TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android}),
    (tester) async {
      final ios = debugDefaultTargetPlatformOverride == TargetPlatform.iOS;
      await tester.pumpWidget(localized(const UpdateRequiredPage()));
      await tester.tap(find.text(ios ? 'Mở App Store' : 'Mở Google Play'));
      await tester.pump();
      expect(links.opened, [ios ? AppConfig.appStorePage : AppConfig.playStorePage]);
    },
  );

  testWidgets('a store that cannot be opened shows the error toast, never an unhandled error', (tester) async {
    links.error = PlatformException(code: 'ACTIVITY_NOT_FOUND');
    await tester.pumpWidget(localized(const UpdateRequiredPage()));
    await tester.tap(find.byType(AppButton));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(popups.errors, ['Đã có lỗi xảy ra (PlatformException).']);

    links
      ..error = null
      ..openResult = false;
    await tester.tap(find.byType(AppButton));
    await tester.pump();
    expect(popups.errors, hasLength(2));
  });
}
