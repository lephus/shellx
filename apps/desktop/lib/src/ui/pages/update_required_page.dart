import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart' show DragToMoveArea;

import '../../../l10n/app_localizations.dart';
import '../../agent/agent_controller.dart';
import '../../agent/desktop_services.dart';
import '../../agent/update_check.dart';
import '../../tray/tray_action.dart';
import '../../tray/tray_actions.dart';
import '../terminal/shortcut_labels.dart' show isMacDesktop;
import '../theme/shellx_desktop_theme.dart';

/// Contract §5 (force update): what the window shows instead of its content
/// while this build is below `min_agent` (WindowContent). Two ways on, and
/// no way around it: the download page (only a link [isTrustedDownloadUrl]
/// accepts; it may come from the background service) or Quit — the tray's
/// "Quit completely", so the background service with this build ends too.
/// macOS `[Quit] [Download]`, Windows `[Download] [Quit]` (as ConfirmPage).
class UpdateRequiredPage extends ConsumerWidget {
  const UpdateRequiredPage({super.key});

  Future<void> _download(WidgetRef ref, Uri url) async {
    try {
      await ref.read(desktopServicesProvider).urlOpener.open(url);
    } on Object catch (e) {
      debugPrint('ShellX: update page not opened: ${e.runtimeType}');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(agentControllerProvider.select((s) => s.update));
    if (notice == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final current = ref.watch(desktopServicesProvider).appVersion;
    final title = l10n.updateRequiredTitle;
    final download = FilledButton(
      key: const Key('updateRequired.download'),
      autofocus: true,
      onPressed: isTrustedDownloadUrl(notice.url)
          ? () => unawaited(_download(ref, notice.url))
          : null,
      child: Text(l10n.updateRequiredDownload),
    );
    final quit = OutlinedButton(
      key: const Key('updateRequired.quit'),
      // Never throws (failures become a notification).
      onPressed: () =>
          unawaited(ref.read(trayActionsProvider).handle(const QuitAll())),
      child: Text(l10n.updateRequiredQuit),
    );
    const gap = SizedBox(width: ShellxSpace.s8);
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: ColoredBox(
        key: const Key('updateRequired'),
        color: ShellxDesktopColors.bgTerminal,
        child: Stack(
          children: [
            // UI §2.1: the title bar is hidden on macOS; this band moves the
            // window, under the traffic lights.
            if (isMacDesktop)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: ShellxSizes.headerBandMac,
                child: DragToMoveArea(child: SizedBox.expand()),
              ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(ShellxSpace.s24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: ShellxSizes.dialogWidthOnboarding,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ExcludeSemantics(
                        child: Icon(
                          Icons.system_update_alt,
                          size: ShellxSizes.emptyIcon,
                          color: ShellxDesktopColors.warn,
                        ),
                      ),
                      const SizedBox(height: ShellxSpace.s12),
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: ShellxText.dialogTitle.copyWith(
                            color: ShellxDesktopColors.textTitle,
                          ),
                        ),
                      ),
                      const SizedBox(height: ShellxSpace.s8),
                      Text(
                        l10n.updateRequiredBody(current, notice.version),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: ShellxDesktopColors.textDialog2,
                        ),
                      ),
                      const SizedBox(height: ShellxSpace.s24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: isMacDesktop
                            ? [quit, gap, download]
                            : [download, gap, quit],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
