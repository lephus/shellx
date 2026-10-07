import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../config/config_controller.dart';
import '../../mux/daemon_state.dart' show daemonStateProvider;
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import 'shortcut_labels.dart';

/// UI §3: the focused state is a 2 px accent ring inside the radius.
const BorderSide _focusRing = BorderSide(
  color: ShellxDesktopColors.accent,
  width: ShellxSizes.focusRing,
);

const RoundedRectangleBorder _r6 = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r6)),
);

/// UI §3.3 primary button (32 high, min 80 wide, padding 0/14, label
/// bodyStrong; hover / pressed fills, focus ring for keyboard focus only).
class ShellxPrimaryButton extends StatelessWidget {
  const ShellxPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.focusNode,
  });
  final String label;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    focusNode: focusNode,
    style: ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(
        Size(ShellxSizes.buttonMinWidth, ShellxSizes.button),
      ),
      fixedSize: const WidgetStatePropertyAll(
        Size.fromHeight(ShellxSizes.button),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: ShellxSizes.buttonPaddingH),
      ),
      // Material reports `focused` only for keyboard focus (highlight mode
      // traditional), which is what UI §3 asks for; on the fill the ring
      // is drawn outside the button (S-9).
      shape: buttonShape(outsideRing: true),
      textStyle: WidgetStatePropertyAll(
        uiFont(ShellxText.bodyStrong, Theme.of(context).textTheme),
      ),
      elevation: const WidgetStatePropertyAll(0),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      animationDuration: ShellxMotion.of(context, ShellxMotion.fast),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? ShellxDesktopColors.onPrimary.withValues(
                alpha: ShellxDesktopColors.disabledOpacity,
              )
            : ShellxDesktopColors.onPrimary,
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? ShellxDesktopColors.primary.withValues(
                alpha: ShellxDesktopColors.disabledOpacity,
              )
            : states.contains(WidgetState.pressed)
            ? ShellxDesktopColors.primaryPressed
            : states.contains(WidgetState.hovered)
            ? ShellxDesktopColors.primaryHover
            : ShellxDesktopColors.primary,
      ),
    ),
    child: Text(label),
  );
}

/// UI §3.2 / §2.8 icon button: a [hitSize] square target around a
/// [visualSize] fill (hover `rowHover`, pressed `rowPressed`, focus ring
/// for keyboard focus only). While [busy] the glyph becomes a spinner and
/// presses are ignored, but the button stays focusable (never disabled).
class ShellxIconButton extends StatefulWidget {
  const ShellxIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.tooltip,
    this.busy = false,
    this.hitSize = ShellxSizes.iconHit,
    this.visualSize = ShellxSizes.iconVisual,
    this.glyphSize = ShellxSizes.icon,
    this.color = ShellxDesktopColors.textSecondary,
    this.hoverColor = ShellxDesktopColors.textPrimary,
    this.focusNode,
    this.selected,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onPressed;

  /// Shown after the theme's 500 ms wait (UI §3.5); left out of semantics,
  /// [semanticLabel] names the button.
  final InlineSpan? tooltip;
  final bool busy;
  final double hitSize;
  final double visualSize;
  final double glyphSize;
  final Color color;
  final Color hoverColor;
  final FocusNode? focusNode;

  /// A toggle's state (the sidebar bell while the panel is open, UI-A4
  /// §5.1): on → `rowSelected` fill and `toggled` semantics. Null: a plain
  /// button.
  final bool? selected;

  @override
  State<ShellxIconButton> createState() => _ShellxIconButtonState();
}

class _ShellxIconButtonState extends State<ShellxIconButton> {
  bool _hover = false;
  bool _pressed = false;
  bool _focus = false;

  void _activate() {
    if (!widget.busy) widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final glyphColor = _hover ? widget.hoverColor : widget.color;
    Widget button = FocusableActionDetector(
      focusNode: widget.focusNode,
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (value) => setState(() => _focus = value),
      onShowHoverHighlight: (value) => setState(() => _hover = value),
      child: Semantics(
        button: true,
        // Busy: announced as unavailable, since presses are ignored (UI §3.2).
        enabled: !widget.busy,
        toggled: widget.selected,
        label: widget.semanticLabel,
        onTap: widget.busy ? null : _activate,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _activate,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: SizedBox.square(
            dimension: widget.hitSize,
            child: Center(
              child: AnimatedContainer(
                duration: ShellxMotion.of(context, ShellxMotion.fast),
                curve: ShellxMotion.fastCurve,
                width: widget.visualSize,
                height: widget.visualSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _pressed && !widget.busy
                      ? ShellxDesktopColors.rowPressed
                      : _hover
                      ? ShellxDesktopColors.rowHover
                      : widget.selected ?? false
                      ? ShellxDesktopColors.rowSelected
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(ShellxRadius.r6),
                  border: _focus ? Border.fromBorderSide(_focusRing) : null,
                ),
                child: widget.busy
                    ? SizedBox.square(
                        dimension: ShellxSizes.spinner,
                        child: CircularProgressIndicator(
                          strokeWidth: ShellxSizes.spinnerStroke,
                          color: widget.color,
                        ),
                      )
                    : Icon(
                        widget.icon,
                        size: widget.glyphSize,
                        color: glyphColor,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    final tooltip = widget.tooltip;
    if (tooltip != null) {
      button = Tooltip(
        richMessage: tooltip,
        excludeFromSemantics: true,
        child: button,
      );
    }
    return button;
  }
}

/// UI §3.5: "label  shortcut" with the shortcut part in `caption`
/// `textSecondary`. [message] is the translated string builder that places
/// the shortcut (e.g. `l10n.terminalNewTabTooltip`); an unbound action
/// ([shortcut] null) shows the label alone (A9 D29).
InlineSpan shortcutTooltip(
  String Function(String shortcut) message,
  String? shortcut,
) {
  final full = withShortcut(message, shortcut);
  if (shortcut == null) return TextSpan(text: full);
  final at = full.lastIndexOf(shortcut);
  if (at < 0) return TextSpan(text: full);
  return TextSpan(
    children: [
      TextSpan(text: full.substring(0, at)),
      TextSpan(
        text: shortcut,
        style: ShellxText.caption.copyWith(
          color: ShellxDesktopColors.textSecondary,
        ),
      ),
      TextSpan(text: full.substring(at + shortcut.length)),
    ],
  );
}

/// UI §2.2 overlay scrollbar (also the terminal's, UI §2.3): thickness 6,
/// radius 3, 2 px from the edge, `scrollThumb` / `scrollThumbHover`; shows
/// while scrolling (and, with [showOnHover], while the pointer is over the
/// child), fades after 800 ms with the `fast` fade. Never takes width.
class ShellxScrollbar extends StatefulWidget {
  const ShellxScrollbar({
    super.key,
    required this.controller,
    required this.child,
    this.showOnHover = false,
    this.alwaysVisible = false,
    this.crossAxisMargin = ShellxSizes.scrollbarMargin,
  });

  final ScrollController controller;

  /// From the edge to the thumb. The sidebar passes 0, so the 6 px thumb
  /// sits in the list's 6 px right gutter, clear of the rows (V12).
  final double crossAxisMargin;
  final Widget child;
  final bool showOnHover;

  /// The thumb stays while the content overflows (a dialog body, so it is
  /// clear that more is below).
  final bool alwaysVisible;

  @override
  State<ShellxScrollbar> createState() => _ShellxScrollbarState();
}

class _ShellxScrollbarState extends State<ShellxScrollbar> {
  bool _pointerInside = false;

  @override
  Widget build(BuildContext context) {
    final scrollbar = _HoverThumbScrollbar(
      controller: widget.controller,
      thumbVisibility:
          widget.alwaysVisible || (widget.showOnHover && _pointerInside),
      fadeDuration: ShellxMotion.of(context, ShellxMotion.fast),
      crossAxisMargin: widget.crossAxisMargin,
      child: widget.child,
    );
    if (!widget.showOnHover) return scrollbar;
    return MouseRegion(
      onEnter: (_) => setState(() => _pointerInside = true),
      onExit: (_) => setState(() => _pointerInside = false),
      child: scrollbar,
    );
  }
}

class _HoverThumbScrollbar extends RawScrollbar {
  const _HoverThumbScrollbar({
    required super.child,
    required ScrollController super.controller,
    required bool super.thumbVisibility,
    required super.fadeDuration,
    required super.crossAxisMargin,
  }) : super(
         thickness: ShellxSizes.scrollbarThickness,
         radius: const Radius.circular(ShellxSizes.scrollbarRadius),
         padding: EdgeInsets.zero,
         thumbColor: ShellxDesktopColors.scrollThumb,
         timeToFade: ShellxMotion.scrollbarFade,
       );

  @override
  RawScrollbarState<_HoverThumbScrollbar> createState() =>
      _HoverThumbScrollbarState();
}

class _HoverThumbScrollbarState
    extends RawScrollbarState<_HoverThumbScrollbar> {
  bool _thumbHovered = false;

  @override
  void handleHover(PointerHoverEvent event) {
    super.handleHover(event);
    final over = isPointerOverThumb(event.position, event.kind);
    if (over != _thumbHovered) setState(() => _thumbHovered = over);
  }

  @override
  void handleHoverExit(PointerExitEvent event) {
    super.handleHoverExit(event);
    if (_thumbHovered) setState(() => _thumbHovered = false);
  }

  @override
  void updateScrollbarPainter() {
    super.updateScrollbarPainter();
    scrollbarPainter.color = _thumbHovered
        ? ShellxDesktopColors.scrollThumbHover
        : ShellxDesktopColors.scrollThumb;
  }
}

/// UI §2.4 / UI-A5 §4: the strips over the terminal area (signed out,
/// abnormal end): `rowSelected` with a `line` bottom border.
const BoxDecoration stripDecoration = BoxDecoration(
  color: ShellxDesktopColors.rowSelected,
  border: Border(bottom: BorderSide(color: ShellxDesktopColors.line)),
);

/// The strips' insets: 12 before the icon or text, 8 after the button.
const EdgeInsets stripPadding = EdgeInsets.only(
  left: ShellxSpace.s12,
  right: ShellxSpace.s8,
);

/// The text button at the end of a strip ("Sign in", "Close"): 28 high,
/// accent bodyStrong, hover / pressed fills, focus ring for keyboard
/// focus only.
ButtonStyle stripTextButtonStyle(BuildContext context) => ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(0, ShellxSizes.textButton)),
  fixedSize: const WidgetStatePropertyAll(
    Size.fromHeight(ShellxSizes.textButton),
  ),
  padding: const WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: ShellxSizes.textButtonPaddingH),
  ),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  shape: const WidgetStatePropertyAll(_r6),
  textStyle: WidgetStatePropertyAll(
    uiFont(ShellxText.bodyStrong, Theme.of(context).textTheme),
  ),
  foregroundColor: const WidgetStatePropertyAll(ShellxDesktopColors.accent),
  animationDuration: ShellxMotion.of(context, ShellxMotion.fast),
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  backgroundColor: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.pressed)
        ? ShellxDesktopColors.rowPressed
        : states.contains(WidgetState.hovered)
        ? ShellxDesktopColors.rowHover
        : Colors.transparent,
  ),
  side: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.focused) ? _focusRing : null,
  ),
);

/// UI §2.4: a layout row at the top of the pane (it may resize the terminal:
/// it is rare and shows before phones attach).
class SignedOutStrip extends StatelessWidget {
  const SignedOutStrip({super.key, required this.onSignIn, this.focusNode});
  final VoidCallback onSignIn;

  /// F6 lands here (UI §3.6 region 3).
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      key: const Key('pane.signedOutStrip'),
      height: ShellxSizes.signedOutStrip,
      decoration: stripDecoration,
      padding: stripPadding,
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: ShellxSizes.icon,
            color: ShellxDesktopColors.textSecondary,
          ),
          const SizedBox(width: ShellxSpace.s8),
          Expanded(
            child: Text(
              l10n.terminalSignedOutStrip,
              style: ShellxText.body.copyWith(
                color: ShellxDesktopColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            key: const Key('pane.signIn'),
            focusNode: focusNode,
            onPressed: onSignIn,
            style: stripTextButtonStyle(context),
            child: Text(l10n.terminalSignedOutAction),
          ),
        ],
      ),
    );
  }
}

/// The phone mark (UI §3.1 phone origin, §2.5 pill): the notch and home
/// bar read as a phone at 14 px, where `smartphone` is a plain rectangle.
const IconData kPhoneIcon = Icons.phone_iphone_outlined;

/// UI §2.5: clicks reach the terminal, except on the [iconOnly] pill, which
/// takes the pointer so its tooltip can show; never resizes the terminal. Announced once when it appears. [compact] (a narrow pane)
/// uses the short copy, so the instruction is never the part cut off.
class DriverPill extends StatelessWidget {
  const DriverPill({super.key, this.compact = false, this.iconOnly = false});
  final bool compact;

  /// Final ruling S-4: a pane too narrow for the instruction shows the
  /// phone mark alone; the words move to its tooltip and its label, so
  /// the instruction is never the part cut off.
  final bool iconOnly;

  static final _decoration = BoxDecoration(
    color: ShellxDesktopColors.warnBg,
    borderRadius: BorderRadius.circular(ShellxRadius.pill),
    border: Border.all(color: ShellxDesktopColors.warnBorder),
    boxShadow: ShellxShadows.e1,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (iconOnly) {
      // Hit-testable (unlike the pill with words) for its tooltip; 28 px
      // of the corner is all it takes from the terminal.
      return Tooltip(
        message: l10n.terminalDriverPhone,
        excludeFromSemantics: true,
        child: Semantics(
          liveRegion: true,
          label: l10n.terminalDriverPhone,
          child: Container(
            key: const Key('pane.driverPill'),
            width: ShellxSizes.driverPill,
            height: ShellxSizes.driverPill,
            decoration: _decoration,
            child: const Center(
              child: Icon(
                kPhoneIcon,
                size: ShellxSizes.mark,
                color: ShellxDesktopColors.warn,
              ),
            ),
          ),
        ),
      );
    }
    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        child: Container(
          key: const Key('pane.driverPill'),
          // 28 high for one line; with the 12 px insets of its slot at most
          // min(560, pane − 24) wide.
          constraints: const BoxConstraints(
            minHeight: ShellxSizes.driverPill,
            maxWidth: ShellxSizes.pillMaxWidth,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: ShellxSpace.s12,
            vertical: (ShellxSizes.driverPill - ShellxSizes.rowTextLine) / 2,
          ),
          decoration: _decoration,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ExcludeSemantics(
                child: Icon(
                  kPhoneIcon,
                  size: ShellxSizes.mark,
                  color: ShellxDesktopColors.warn,
                ),
              ),
              const SizedBox(width: ShellxSpace.s6),
              Flexible(
                child: Text(
                  compact
                      ? l10n.terminalDriverPhoneShort
                      : l10n.terminalDriverPhone,
                  style: ShellxText.body.copyWith(
                    color: ShellxDesktopColors.warn,
                  ),
                  // Narrow: a second line rather than a cut instruction
                  // (large text sizes).
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// UI §2.8 error toast: visible 6 s (the timer runs even with reduced
/// motion), paused while hovered or while its close button has the
/// keyboard, one at a time (a new notice replaces the old one and restarts
/// the timer).
class NoticeToast extends StatefulWidget {
  const NoticeToast({
    super.key,
    required this.notice,
    required this.onDismiss,
    this.onReturnFocus,
    this.onAction,
  });
  final TabNotice notice;
  final VoidCallback onDismiss;

  /// The "Show" button of a problems notice (A9 UI §3.1); null: none.
  final VoidCallback? onAction;

  /// Called after a dismissal while the close button had the keyboard, so
  /// the focus does not vanish with the toast.
  final VoidCallback? onReturnFocus;

  @override
  State<NoticeToast> createState() => _NoticeToastState();
}

class _NoticeToastState extends State<NoticeToast> {
  final _closeFocus = FocusNode(debugLabel: 'toast close');
  Timer? _timer;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _closeFocus.addListener(_onFocus);
    _start();
  }

  @override
  void didUpdateWidget(NoticeToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.notice, widget.notice)) _start();
  }

  bool get _warningsOnly {
    final notice = widget.notice;
    return notice is ConfigProblemsNotice && !notice.hasErrors;
  }

  bool get _paused => _hovered || _closeFocus.hasFocus;

  /// UI-A1 §2.8: the neutral variant (reserved in A1) for information.
  bool get _neutral =>
      widget.notice is ConfigReloadedNotice ||
      widget.notice is ConfigGhosttyNotice ||
      _warningsOnly ||
      widget.notice is WorkspaceDeletedNotice ||
      widget.notice is NoUnreadNotice ||
      widget.notice is NoTerminalForCommandNotice ||
      widget.notice is PaneNoRoomNotice ||
      (widget.notice is InputNotice &&
          const {
            InputNoticeKind.dropSsh,
            InputNoticeKind.imageSsh,
          }.contains((widget.notice as InputNotice).kind)) ||
      widget.notice is RestorePanesFailedNotice ||
      widget.notice is CliSkillsCopiedNotice ||
      widget.notice is CliPathInstalledNotice ||
      widget.notice is SshRecentClearedNotice;

  /// A fresh 6 s (4 s when neutral), unless the pointer or the keyboard is
  /// on the toast.
  void _start() {
    _timer?.cancel();
    _timer = _paused
        ? null
        : Timer(
            _neutral
                ? ShellxMotion.toastVisible
                : ShellxMotion.toastVisibleError,
            widget.onDismiss,
          );
  }

  void _onFocus() => _paused ? _timer?.cancel() : _start();

  void _close() {
    final hadFocus = _closeFocus.hasFocus;
    widget.onDismiss();
    if (hadFocus) widget.onReturnFocus?.call();
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Replaced by a newer notice while the keyboard was on this one.
    if (_closeFocus.hasFocus) {
      final returnFocus = widget.onReturnFocus;
      if (returnFocus != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => returnFocus());
      }
    }
    _closeFocus.dispose();
    super.dispose();
  }

  String _text(AppLocalizations l10n) => switch (widget.notice) {
    SessionLimitNotice(:final max) => l10n.terminalSessionLimit(max),
    SpawnFailedNotice(:final kind) => l10n.terminalSpawnFailed(kind.name),
    WorkspaceDeletedNotice(:final name, :final movedTo) =>
      l10n.workspaceDeleted(name, movedTo),
    PortOpenFailedNotice() => l10n.portOpenFailed,
    NoUnreadNotice() => l10n.noUnreadNotifications,
    NoTerminalForCommandNotice() => l10n.userCommandNoTerminal,
    ConfigOpenFailedNotice(:final path) => l10n.configOpenFailed(path),
    ConfigWriteFailedNotice(:final path) => l10n.configWriteFailed(path),
    ConfigProblemsNotice(:final count) => l10n.configProblemsToast(count),
    ConfigReloadedNotice() => l10n.configReloaded,
    ConfigGhosttyNotice() => l10n.configGhosttyNotice,
    PaneNoRoomNotice() => l10n.paneSplitNoRoom,
    PasteTooLargeNotice() => l10n.pasteTooLarge,
    InputNotice(:final kind) => switch (kind) {
      InputNoticeKind.dropSsh => l10n.dropSsh,
      InputNoticeKind.dropRefused => l10n.dropRefused,
      InputNoticeKind.dropTooMany => l10n.dropTooMany,
      InputNoticeKind.imageSsh => l10n.pasteImageSsh,
      InputNoticeKind.imageTooLarge => l10n.pasteImageTooLarge,
      InputNoticeKind.imageFailed => l10n.pasteImageFailed,
    },
    RestorePanesFailedNotice(:final count) => l10n.restorePanesFailed(count),
    DaemonQuitFailedNotice() => l10n.daemonQuitFailed,
    LinkOpenFailedNotice() => l10n.linkOpenFailed,
    CliSkillsCopiedNotice() => l10n.cliSkillsCopied,
    CliPathInstalledNotice() => l10n.cliPathInstalled,
    CliPathFailedNotice(:final path) => l10n.cliPathFailed(path),
    CliPathNotOnPathNotice(:final hint) => l10n.cliPathNotOnPath(
      hint.file,
      hint.line,
    ),
    CliPathRemoveFailedNotice(:final path) => l10n.cliPathRemoveFailed(path),
    SshUnavailableNotice() =>
      defaultTargetPlatform == TargetPlatform.windows
          ? l10n.sshUnavailableWindows
          : l10n.sshUnavailable,
    TmuxUnavailableNotice() => l10n.tmuxUnavailableLocal,
    SshRecentClearedNotice() => l10n.sshRecentCleared,
    RemotePortForwardFailedNotice(:final port) => l10n.remotePortForwardFailed(
      port,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final foreground = _neutral
        ? ShellxDesktopColors.textPrimary
        : ShellxDesktopColors.noticeText;
    return MouseRegion(
      onEnter: (_) {
        _hovered = true;
        _timer?.cancel();
      },
      onExit: (_) {
        _hovered = false;
        _start();
      },
      child: Semantics(
        liveRegion: true,
        container: true,
        child: Container(
          key: const Key('pane.toast'),
          constraints: const BoxConstraints(
            maxWidth: ShellxSizes.toastMaxWidth,
            minHeight: ShellxSizes.toastMinHeight,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: ShellxSpace.s12,
            vertical: ShellxSpace.s8,
          ),
          decoration: BoxDecoration(
            color: _neutral
                ? ShellxDesktopColors.rowSelected
                : ShellxDesktopColors.noticeBg,
            borderRadius: BorderRadius.circular(ShellxRadius.r8),
            border: Border.all(
              color: _neutral
                  ? ShellxDesktopColors.border
                  : ShellxDesktopColors.noticeBorder,
            ),
            boxShadow: ShellxShadows.e1,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Icon(
                  _neutral ? Icons.info_outline : Icons.error_outline,
                  size: ShellxSizes.icon,
                  color: foreground,
                ),
              ),
              const SizedBox(width: ShellxSpace.s8),
              Flexible(
                child: Text(
                  _text(l10n),
                  style: ShellxText.body.copyWith(color: foreground),
                ),
              ),
              const SizedBox(width: ShellxSpace.s8),
              if (widget.notice is ConfigProblemsNotice &&
                  widget.onAction != null)
                _ShowButton(
                  label: l10n.configProblemsShow,
                  neutral: _neutral,
                  color: foreground,
                  onPressed: () {
                    widget.onAction!();
                    _close();
                  },
                ),
              ShellxIconButton(
                key: const Key('pane.toast.close'),
                icon: Icons.close,
                semanticLabel: l10n.toastDismiss,
                tooltip: TextSpan(text: l10n.toastDismiss),
                onPressed: _close,
                focusNode: _closeFocus,
                hitSize: ShellxSizes.toastClose,
                visualSize: ShellxSizes.toastClose,
                glyphSize: ShellxSizes.toastCloseGlyph,
                color: foreground,
                hoverColor: foreground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// UI-A9 §3.1: the toast's text button (hit 28, padding 0/8); neutral →
/// accent w600, error → the notice colour underlined.
class _ShowButton extends StatelessWidget {
  const _ShowButton({
    required this.label,
    required this.neutral,
    required this.color,
    required this.onPressed,
  });
  final String label;
  final bool neutral;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    key: const Key('pane.toast.action'),
    onPressed: onPressed,
    style: ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 28)),
      fixedSize: const WidgetStatePropertyAll(Size.fromHeight(28)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: ShellxSpace.s8),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: buttonShape(outsideRing: false),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    child: Text(
      label,
      style: ShellxText.body.copyWith(
        color: neutral ? ShellxDesktopColors.accent : color,
        fontWeight: neutral ? FontWeight.w600 : null,
        decoration: neutral ? null : TextDecoration.underline,
        decorationColor: color,
      ),
    ),
  );
}

/// UI §2.7: shown in the pane when there is no tab.
class EmptyTerminalState extends ConsumerWidget {
  const EmptyTerminalState({super.key, required this.onOpen, this.buttonFocus});
  final VoidCallback onOpen;

  /// "Open new tab" gets the keyboard when the last tab closes.
  final FocusNode? buttonFocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The caption follows a reload (A9 D29).
    ref.watch(shellxConfigProvider.select((s) => s.bindings));
    final shortcut = newTabShortcutLabel();
    final l10n = AppLocalizations.of(context);
    // A5b UI-A5 §7.4: no service yet, so nothing to open a tab in.
    final waiting = ref.watch(daemonStateProvider.select((s) => s.waiting));
    return Center(
      key: const Key('pane.empty'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(ShellxSpace.s16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: ShellxSizes.emptyMaxWidth,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ExcludeSemantics(
                child: Icon(
                  Icons.terminal,
                  size: ShellxSizes.emptyIcon,
                  color: ShellxDesktopColors.textSecondary,
                ),
              ),
              const SizedBox(height: ShellxSpace.s12),
              Semantics(
                header: true,
                child: Text(
                  l10n.terminalEmptyTitle,
                  textAlign: TextAlign.center,
                  style: ShellxText.emptyTitle.copyWith(
                    color: ShellxDesktopColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: ShellxSpace.s6),
              Text(
                waiting ? l10n.daemonUnavailableEmpty : l10n.terminalEmptyBody,
                textAlign: TextAlign.center,
                style: ShellxText.body.copyWith(
                  color: ShellxDesktopColors.textSecondary,
                ),
              ),
              if (!waiting) ...[
                const SizedBox(height: ShellxSpace.s16),
                ShellxPrimaryButton(
                  key: const Key('pane.empty.open'),
                  label: l10n.terminalEmptyAction,
                  onPressed: onOpen,
                  focusNode: buttonFocus,
                ),
              ],
              const SizedBox(height: ShellxSpace.s8),
              if (shortcut != null && !waiting)
                ExcludeSemantics(
                  child: Text(
                    shortcut,
                    style: ShellxText.caption.copyWith(
                      color: ShellxDesktopColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Right of the sidebar ([ShellxSizes.sidebarWidth] + 6), vertically
/// centred on the row, kept inside the window.
Offset besideSidebar(TooltipPositionContext context) {
  final overlay = context.overlaySize;
  final size = context.tooltipSize;
  final double x = (ShellxSizes.sidebarWidth + ShellxSpace.s6).clamp(
    0.0,
    max(0.0, overlay.width - size.width - ShellxSpace.s8),
  );
  final double y = (context.target.dy - size.height / 2).clamp(
    0.0,
    max(0.0, overlay.height - size.height),
  );
  return Offset(x, y);
}
