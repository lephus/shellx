import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'pages/change_password_page.dart';
import 'pages/confirm_page.dart';
import 'pages/login_page.dart';
import 'pages/onboarding_page.dart';
import 'pages/pairing_page.dart';
import 'window_router.dart';

/// Root widget. The one window renders whatever the [WindowRouter] has open.
class ShellxDesktopApp extends StatelessWidget {
  const ShellxDesktopApp({super.key, required this.locale});

  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2563EB),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF2563EB),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const WindowContent(),
    );
  }
}

class WindowContent extends ConsumerWidget {
  const WindowContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final window = ref.watch(windowRouterProvider);
    final confirm = window.confirm;
    final Widget page = confirm != null
        ? ConfirmPage(key: ValueKey(confirm), request: confirm)
        : switch (window.route) {
            LoginRoute() => const LoginPage(),
            OnboardingRoute() => const OnboardingPage(),
            PairingRoute() => const PairingPage(),
            ChangePasswordRoute() => const ChangePasswordPage(),
            null => const SizedBox.shrink(),
          };
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            ref.read(windowRouterProvider.notifier).close(),
      },
      child: Focus(autofocus: true, child: Scaffold(body: page)),
    );
  }
}
