import 'dart:async';

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/app/launch.dart';
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

import 'app.dart';

/// Runs [action] (in production, always [prepareLaunch]) and swallows anything it throws: the
/// splash screen must never strand the user just because its launch hook failed. Kept as a
/// free function, not a [SplashPage] constructor parameter, so auto_route does not turn it into
/// a (non-serialisable) route argument.
Future<void> guardLaunch(Future<void> Function() action) async {
  try {
    await action();
  } catch (error) {
    if (kDebugMode) debugPrint('prepareLaunch error: ${error.runtimeType}');
  }
}

/// Dependency injection, then [prepareLaunch]. A retry after a failed start begins with an empty
/// container: the failed run may have registered part of it.
Future<void> startApp() async {
  await getIt.reset();
  await configureDependencies();
  await guardLaunch(prepareLaunch);
}

@RoutePage()
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) => const AppLaunch(prepare: startApp);
}

/// The splash background until [prepare] completes, then [RootApp] in its place.
///
/// [RootApp] replaces the splash's [MaterialApp] instead of being pushed onto its navigator: the
/// router's navigator must be the root one. `showDialog` opens on the root navigator, and a
/// navigator around the router would put dialogs outside the design system, the ShellX strings
/// and the lock screen.
///
/// A [prepare] that throws never leaves the splash blank. When the app's services are there, the
/// app opens anyway, locked if the lock is enabled (the login page otherwise, as nobody is signed
/// in); when they are not, the splash offers "Thử lại", which runs [prepare] again.
class AppLaunch extends StatefulWidget {
  const AppLaunch({super.key, required this.prepare});

  final Future<void> Function() prepare;

  @override
  State<AppLaunch> createState() => _AppLaunchState();
}

enum _LaunchState { starting, ready, failed }

class _AppLaunchState extends State<AppLaunch> {
  _LaunchState _state = _LaunchState.starting;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    var failed = false;
    try {
      await widget.prepare();
    } catch (error) {
      if (kDebugMode) debugPrint('Launch error: ${error.runtimeType}');
      failed = true;
    }
    if (!mounted) return;
    // The session enforcer is what leaves the login page after signing in (and returns to it
    // after a sign-out): without it the app would open but never navigate.
    final canRun =
        getIt.isRegistered<AppRouter>() &&
        getIt.isRegistered<AppLockController>() &&
        getIt.isRegistered<SessionHolder>() &&
        getIt.isRegistered<SessionEnforcer>();
    // The launch may have stopped before it locked the app: fail closed.
    if (failed && canRun) getIt<AppLockController>().lockOnLaunch();
    setState(() => _state = canRun ? _LaunchState.ready : _LaunchState.failed);
  }

  Future<void> _retry() async {
    setState(() => _state = _LaunchState.starting);
    await _start();
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _LaunchState.ready) return const RootApp();
    final brightness = AdaptiveTheme.of(context).mode.brightness;
    return DesignSystem(
      typography: AppTypography.instance,
      appColors: brightness.appColors,
      brightness: brightness,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          S.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        theme: ThemeDataFactory.create(brightness),
        home: Scaffold(
          backgroundColor: brightness.appColors.background,
          body: _state == _LaunchState.failed ? SafeArea(child: AppErrorWidget(retry: _retry)) : null,
        ),
      ),
    );
  }
}
