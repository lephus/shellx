import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'dialogs/route_dialog.dart';
import 'terminal/terminal_workspace_page.dart';
import 'theme/shellx_desktop_theme.dart';
import 'window_router.dart';

/// Root widget: the terminal window (A1 D9), dark only (UI §1).
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
      theme: buildDesktopTheme(),
      themeMode: ThemeMode.dark,
      home: const WindowContent(),
    );
  }
}

/// The terminal workspace, with the open route or confirm as a dialog over
/// it (UI §4).
class WindowContent extends ConsumerStatefulWidget {
  const WindowContent({super.key});

  @override
  ConsumerState<WindowContent> createState() => _WindowContentState();
}

class _WindowContentState extends ConsumerState<WindowContent> {
  final _workspace = GlobalKey<TerminalWorkspacePageState>();

  /// Counts dialog opens (closed → open), so a dialog opened while the last
  /// one still fades out (sign out → login) gets its own key and element.
  int _opens = 0;
  bool _wasOpen = false;

  @override
  Widget build(BuildContext context) {
    final window = ref.watch(windowRouterProvider);
    if (window.dialogOpen && !_wasOpen) _opens++;
    _wasOpen = window.dialogOpen;
    // UI §3.6: the terminal regains focus after any dialog closes.
    ref.listen(windowRouterProvider.select((w) => w.dialogOpen), (_, open) {
      if (!open) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _workspace.currentState?.focusTerminal(),
        );
      }
    });
    // The window-level Escape binding is gone on purpose: Escape belongs to
    // the shell (vim); dialogs bind it themselves.
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: ExcludeFocus(
              excluding: window.dialogOpen,
              child: TerminalWorkspacePage(key: _workspace),
            ),
          ),
          // UI §1.5: the dialog (with its scrim) fades in with `base` and
          // out with `exit`; one dialog replacing another switches at once.
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: ShellxMotion.of(context, ShellxMotion.base),
              reverseDuration: ShellxMotion.of(context, ShellxMotion.exit),
              switchInCurve: ShellxMotion.baseCurve,
              switchOutCurve: ShellxMotion.exitCurve,
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                children: [...previous, ?current],
              ),
              child: window.dialogOpen
                  ? RouteDialogHost(
                      key: ValueKey(('dialogHost', _opens)),
                      state: window,
                    )
                  : const SizedBox.shrink(key: ValueKey('none')),
            ),
          ),
        ],
      ),
    );
  }
}
