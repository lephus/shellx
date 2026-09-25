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

@RoutePage()
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  @override
  void initState() {
    initialize();
    super.initState();
  }

  Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    await configureDependencies();
    await guardLaunch(prepareLaunch);
    if (!mounted) return;
    navigatorKey.currentState?.pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const RootApp(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: brightness.appColors.background,
      ),
    );
  }

  Brightness get brightness {
    return AdaptiveTheme.of(context).mode.brightness;
  }
}
