import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/app/update_required_page.dart';
import 'package:shellx_mobile/shared/shared.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';

void main() {
  late FakeExternalLinks links;
  late FakePopupHandler popups;

  setUp(() {
    links = FakeExternalLinks();
    popups = FakePopupHandler();
    getIt
      ..registerSingleton<ExternalLinks>(links)
      ..registerSingleton<PopupHandler>(popups);
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('shows the title and body', (tester) async {
    await tester.pumpWidget(localized(const UpdateRequiredPage()));
    expect(find.text('Cần cập nhật app'), findsOneWidget);
    expect(find.text('Phiên bản này không còn kết nối được với máy của bạn. Cập nhật để dùng tiếp.'), findsOneWidget);
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
