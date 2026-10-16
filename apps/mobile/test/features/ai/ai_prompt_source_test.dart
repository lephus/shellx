import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_items.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';

/// V2-2b B24: under a prompt written on a phone, "từ điện thoại".
void main() {
  setUp(() {
    getIt
      ..registerSingleton<ExternalLinks>(FakeExternalLinks())
      ..registerSingleton<PopupHandler>(FakePopupHandler());
  });

  tearDown(() async => getIt.reset());

  Future<void> bubble(
    WidgetTester tester, {
    required bool fromPhone,
    Locale locale = vi,
  }) => tester.pumpWidget(
    localized(
      locale: locale,
      Scaffold(
        body: AiItemView(
          item: MirrorText(0, 1, 1, MirrorTextKind.user, 'Sửa lỗi', fromPhone: fromPhone),
          agentName: 'Claude',
        ),
      ),
    ),
  );

  testWidgets('a phone\'s prompt says so under it', (tester) async {
    await bubble(tester, fromPhone: true);
    expect(find.text('Sửa lỗi'), findsOneWidget);
    expect(find.byKey(const Key('ai.user.fromPhone')), findsOneWidget);
    expect(find.text('từ điện thoại'), findsOneWidget);
  });

  testWidgets('in English: "from phone"', (tester) async {
    await bubble(tester, fromPhone: true, locale: en);
    expect(find.text('from phone'), findsOneWidget);
  });

  testWidgets('the computer\'s prompt says nothing more', (tester) async {
    await bubble(tester, fromPhone: false);
    expect(find.text('Sửa lỗi'), findsOneWidget);
    expect(find.byKey(const Key('ai.user.fromPhone')), findsNothing);
  });
}
