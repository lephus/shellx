import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/shared/shared.dart';

const Locale vi = Locale('vi');
const Locale en = Locale('en');

/// [home] inside the base design system (`context.colors`, `context.typo`) and a [MaterialApp]
/// with the ShellX strings, in Vietnamese unless [locale] says otherwise.
Widget localized(Widget home, {Locale locale = vi, TransitionBuilder? builder}) => _designSystem(
  MaterialApp(
    locale: locale,
    builder: builder,
    localizationsDelegates: _delegates,
    supportedLocales: S.delegate.supportedLocales,
    theme: ThemeDataFactory.create(Brightness.light),
    home: home,
  ),
);

/// An auto_route app for page tests. Its start page has an "open" button that pushes [open] and
/// adds what the pushed page pops with to [results]; [routes] holds the pages under test
/// ([XRoute.page]) and stand-ins ([stubRoute]).
Widget routedApp({
  required PageRouteInfo Function() open,
  List<AutoRoute> routes = const [],
  List<Object?>? results,
  Locale locale = vi,
}) {
  final router = _TestRouter([
    AutoRoute(page: PageInfo('HostRoute', builder: (_) => _Host(open, results)), initial: true),
    ...routes,
  ]);
  final config = router.config();
  return _designSystem(
    MaterialApp.router(
      locale: locale,
      localizationsDelegates: _delegates,
      supportedLocales: S.delegate.supportedLocales,
      theme: ThemeDataFactory.create(Brightness.light),
      routerConfig: config,
    ),
  );
}

/// A route named [name] (e.g. `TerminalRoute.name`) that only shows "[name] stub" with a back
/// button, and records the arguments it was pushed with in [pushed].
AutoRoute stubRoute(String name, {List<Object?>? pushed}) => AutoRoute(
  page: PageInfo(
    name,
    builder: (data) {
      pushed?.add(data.args);
      return Scaffold(appBar: AppBar(title: Text('$name stub')));
    },
  ),
);

/// Taps the start page's "open" button of [routedApp] and settles.
Future<void> openPushed(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

class _TestRouter extends RootStackRouter {
  _TestRouter(this.routes);

  @override
  final List<AutoRoute> routes;
}

class _Host extends StatelessWidget {
  const _Host(this.open, this.results);

  final PageRouteInfo Function() open;
  final List<Object?>? results;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () async {
          final result = await context.router.push<Object?>(open());
          results?.add(result);
        },
        child: const Text('open'),
      ),
    ),
  );
}

const List<LocalizationsDelegate<dynamic>> _delegates = [
  S.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

Widget _designSystem(Widget child) => DesignSystem(
  typography: AppTypography.instance,
  appColors: Brightness.light.appColors,
  brightness: Brightness.light,
  child: child,
);
