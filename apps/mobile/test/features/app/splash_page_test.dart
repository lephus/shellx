import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/app/app.dart';
import 'package:shellx_mobile/features/app/splash_page.dart';

void main() {
  test('prepareLaunch throwing → splash still navigates: guardLaunch swallows the error', () async {
    // Must complete instead of propagating.
    await guardLaunch(() async => throw Exception('boom'));
  });

  test('guardLaunch still runs the action through to completion when it succeeds', () async {
    var ran = false;
    await guardLaunch(() async => ran = true);
    expect(ran, isTrue);
  });

  testWidgets('an app that cannot start at all shows "Retry" instead of a blank splash', (tester) async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    var starts = 0;
    await tester.pumpWidget(
      AdaptiveTheme(
        light: ThemeDataFactory.create(Brightness.light),
        dark: ThemeDataFactory.create(Brightness.dark),
        initial: AdaptiveThemeMode.light,
        // Nothing gets registered: the app's services are missing.
        builder: (light, dark) => AppLaunch(
          prepare: () async {
            starts++;
            throw PlatformException(code: 'channel-error');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(RootApp), findsNothing);
    expect(find.text('Something went wrong'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(starts, 2);
    expect(find.text('Retry'), findsOneWidget);
  });
}
