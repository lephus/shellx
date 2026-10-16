import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/shared/shared.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name}: the retry label and icon use onPrimary on primaryFill (AA)', (tester) async {
      final colors = brightness.appColors;
      await tester.pumpWidget(
        DesignSystem(
          typography: AppTypography.instance,
          appColors: colors,
          brightness: brightness,
          child: MaterialApp(
            locale: const Locale('vi'),
            localizationsDelegates: const [
              S.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: S.delegate.supportedLocales,
            theme: ThemeDataFactory.create(brightness),
            home: Scaffold(body: AppErrorWidget(retry: () async {})),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final label = tester.widget<Text>(find.text('Thử lại'));
      expect(label.style!.color, colors.onPrimary);
      expect(tester.widget<Icon>(find.byIcon(Icons.refresh)).color, colors.onPrimary);
      final ink = tester.widget<Ink>(find.descendant(of: find.byType(AppButton), matching: find.byType(Ink)));
      expect((ink.decoration! as BoxDecoration).color, colors.primaryFill);
    });
  }
}
