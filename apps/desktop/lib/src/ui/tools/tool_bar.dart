import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../tools/tool_entry.dart';
import '../../tools/tool_page.dart';
import '../terminal/shellx_menu.dart';
import '../theme/shellx_desktop_theme.dart';

/// D17: the tool bar's height (the AI pane's bar style).
const double kToolBarHeight = 32;

enum _More { edit, copy, closeDock }

/// D17: 🧩, the name, `host:port` with the D11 mark, "On {host}" when the
/// page left the tool's origin; then back, reload/stop, phone, expand,
/// open in browser, ⋯ and ×. Every button has a spoken label (D18).
class ToolBar extends StatelessWidget {
  const ToolBar({
    super.key,
    required this.tool,
    required this.state,
    required this.zoomed,
    required this.onBack,
    required this.onReload,
    required this.onStop,
    required this.onBackToTool,
    required this.onPhone,
    required this.onZoom,
    required this.onBrowser,
    required this.onEdit,
    required this.onCopyUrl,
    required this.onCloseDock,
    required this.onClose,
  });

  final ToolEntry tool;

  /// Null before the page exists.
  final ToolPageState? state;
  final bool zoomed;
  final VoidCallback onBack;
  final VoidCallback onReload;
  final VoidCallback onStop;
  final VoidCallback onBackToTool;
  final VoidCallback onPhone;
  final VoidCallback onZoom;
  final VoidCallback onBrowser;
  final VoidCallback onEdit;
  final VoidCallback onCopyUrl;
  final VoidCallback onCloseDock;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = state;
    final loading = s?.loading ?? false;
    final away = s != null && s.awayFrom(tool) ? s.url : null;
    Widget button(
      Key key,
      IconData glyph,
      String label,
      VoidCallback? onPressed, {
      bool on = false,
      String? tip,
    }) => IconButton(
      key: key,
      tooltip: tip ?? label,
      iconSize: 16,
      visualDensity: VisualDensity.compact,
      color: on
          ? ShellxDesktopColors.accent
          : ShellxDesktopColors.textSecondary,
      onPressed: onPressed,
      icon: Semantics(label: label, child: Icon(glyph)),
    );
    final mark = tool.isLocal ? l10n.toolLocal : l10n.toolRemote;
    final where = tool.unencrypted
        ? '${tool.hostPort} · $mark · ${l10n.toolUnencrypted}'
        : '${tool.hostPort} · $mark';
    return SizedBox(
      height: kToolBarHeight,
      child: Padding(
        padding: const EdgeInsets.only(
          left: ShellxSpace.s8,
          right: ShellxSpace.s4,
        ),
        child: Row(
          children: [
            const ExcludeSemantics(
              child: Icon(
                Icons.extension_outlined,
                size: 14,
                color: ShellxDesktopColors.accent,
              ),
            ),
            const SizedBox(width: ShellxSpace.s6),
            Flexible(
              child: Text(
                tool.name,
                key: const Key('tool.bar.name'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ShellxText.bodyStrong.copyWith(
                  color: ShellxDesktopColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: ShellxSpace.s8),
            Flexible(
              child: Text(
                where,
                key: const Key('tool.bar.mark'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ShellxText.caption.copyWith(
                  color: tool.unencrypted
                      ? ShellxDesktopColors.warn
                      : ShellxDesktopColors.textSecondary,
                ),
              ),
            ),
            if (away != null) ...[
              const SizedBox(width: ShellxSpace.s8),
              Flexible(
                child: Text(
                  l10n.toolAway(away.host),
                  key: const Key('tool.bar.away'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ShellxText.caption.copyWith(
                    color: ShellxDesktopColors.warn,
                  ),
                ),
              ),
              Flexible(
                child: TextButton(
                  key: const Key('tool.bar.backToTool'),
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: ShellxSpace.s6,
                    ),
                  ),
                  onPressed: onBackToTool,
                  child: Text(
                    l10n.toolBackToTool,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            const Spacer(),
            button(
              const Key('tool.bar.back'),
              Icons.arrow_back,
              l10n.toolBack,
              s != null && s.canGoBack ? onBack : null,
            ),
            if (loading)
              button(
                const Key('tool.bar.stop'),
                Icons.close,
                l10n.toolStop,
                onStop,
              )
            else
              button(
                const Key('tool.bar.reload'),
                Icons.refresh,
                l10n.toolReload,
                onReload,
              ),
            button(
              const Key('tool.bar.phone'),
              Icons.smartphone,
              tool.phoneOn ? l10n.toolPhoneOn : l10n.toolPhoneOff,
              tool.phoneAllowed ? onPhone : null,
              on: tool.phoneOn,
              tip: tool.phoneAllowed ? null : l10n.toolPhoneOnlyLocal,
            ),
            button(
              const Key('tool.bar.expand'),
              zoomed ? Icons.close_fullscreen : Icons.open_in_full,
              zoomed ? l10n.toolCollapse : l10n.toolExpand,
              onZoom,
              on: zoomed,
            ),
            button(
              const Key('tool.bar.browser'),
              Icons.open_in_new,
              l10n.toolOpenInBrowser,
              onBrowser,
            ),
            Builder(
              builder: (context) => button(
                const Key('tool.bar.more'),
                Icons.more_horiz,
                l10n.toolMore,
                () async {
                  final box = context.findRenderObject()! as RenderBox;
                  final choice = await showShellxMenu<_More>(
                    context: context,
                    at: box.localToGlobal(Offset(0, box.size.height)),
                    entries: [
                      ShellxMenuEntry(
                        key: const Key('tool.menu.edit'),
                        value: _More.edit,
                        label: l10n.toolEditMenu,
                      ),
                      ShellxMenuEntry(
                        key: const Key('tool.menu.copy'),
                        value: _More.copy,
                        label: l10n.toolCopyUrl,
                      ),
                      ShellxMenuEntry(
                        key: const Key('tool.menu.closeDock'),
                        value: _More.closeDock,
                        label: l10n.toolCloseDock,
                      ),
                    ],
                  );
                  switch (choice) {
                    case _More.edit:
                      onEdit();
                    case _More.copy:
                      onCopyUrl();
                    case _More.closeDock:
                      onCloseDock();
                    case null:
                      break;
                  }
                },
              ),
            ),
            button(
              const Key('tool.bar.close'),
              Icons.close,
              l10n.toolClose,
              onClose,
            ),
          ],
        ),
      ),
    );
  }
}
