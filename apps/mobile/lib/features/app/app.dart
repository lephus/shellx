import 'dart:async';

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:toastification/toastification.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/app/update_enforcer.dart';
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';
import 'package:shellx_mobile/features/lock/presentation/lock_gate.dart';
import 'package:shellx_mobile/features/notifications/presentation/push_controller.dart';
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

  /// Optional: a launch that stopped before it was registered runs without push.
  final PushController? push = getIt.isRegistered<PushController>() ? getIt<PushController>() : null;

  /// Optional like [push]: without it the version is checked at launch only.
  final UpdateEnforcer? updates = getIt.isRegistered<UpdateEnforcer>() ? getIt<UpdateEnforcer>() : null;

  @override
  void initState() {
    super.initState();
    // Push spec §6: after the first frame, so a notification that launched the app can navigate.
    WidgetsBinding.instance.addPostFrameCallback((_) => push?.start());
  }

  void _onForeground() {
    session.onForeground();
    // Contract §5: the version gate again (throttled), over whatever page is open.
    final updates = this.updates;
    if (updates != null) unawaited(updates.onForeground());
    // The permission may have been changed in the system settings meanwhile.
    final push = this.push;
    if (push != null) unawaited(push.refreshPermission());
  }

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
            onForeground: _onForeground,
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
