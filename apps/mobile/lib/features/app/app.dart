import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:toastification/toastification.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';
import 'package:shellx_mobile/features/lock/presentation/lock_gate.dart';
import 'package:shellx_mobile/shared/shared.dart';

class RootApp extends StatefulWidget {
  const RootApp({
    super.key,
  });

  @override
  State<RootApp> createState() => _RootAppState();
}

class _RootAppState extends State<RootApp> {
  //
  final appRouter = getIt<AppRouter>();
  final lock = getIt<AppLockController>();
  final session = getIt<SessionHolder>();

  @override
  Widget build(BuildContext context) {
    final computedBrightness = brightness;
    return ToastificationWrapper(
      config: const ToastificationConfig(
        alignment: Alignment.topCenter,
        animationDuration: Duration(milliseconds: 300),
      ),
      child: DesignSystem(
        typography: AppTypography.instance,
        appColors: computedBrightness.appColors,
        brightness: computedBrightness,
        child: MaterialApp.router(
          onGenerateTitle: (context) => S.of(context).appTitle,
          showSemanticsDebugger: false,
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            S.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          debugShowCheckedModeBanner: false,
          routerConfig: appRouter.config(
            navigatorObservers: () => [AppRouteObserver()],
          ),
          theme: ThemeDataFactory.create(computedBrightness),
          // Spec §5.6: the lock covers every route and dialog. Spec §9.4/§12: the relay is
          // suspended in the background and reconnected right away when the app comes back.
          builder: (context, child) => LockGate(
            lock: lock,
            onBackground: session.onBackground,
            onForeground: session.onForeground,
            child: child!,
          ),
        ),
      ),
    );
  }

  Brightness get brightness {
    return AdaptiveTheme.of(context).mode.brightness;
  }
}
