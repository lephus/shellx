import 'dart:async';

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/app/launch.dart';

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

/// Dependency injection, then [prepareLaunch].
Future<void> startApp() async {
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
class AppLaunch extends StatefulWidget {
  const AppLaunch({super.key, required this.prepare});

  final Future<void> Function() prepare;

  @override
  State<AppLaunch> createState() => _AppLaunchState();
}

class _AppLaunchState extends State<AppLaunch> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    await widget.prepare();
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const RootApp();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(backgroundColor: AdaptiveTheme.of(context).mode.brightness.appColors.background),
    );
  }
}
