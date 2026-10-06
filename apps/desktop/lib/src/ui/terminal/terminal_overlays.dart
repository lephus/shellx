import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
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
      shape: const WidgetStatePropertyAll(_r6),
      textStyle: const WidgetStatePropertyAll(ShellxText.bodyStrong),
      elevation: const WidgetStatePropertyAll(0),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      animationDuration: ShellxMotion.of(context, ShellxMotion.fast),
      // Material reports `focused` only for keyboard focus (highlight mode
      // traditional), which is what UI §3 asks for.
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused) ? _focusRing : null,
      ),
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
/// `textSecondary`. [full] is the translated string that contains
/// [shortcut] (e.g. `terminalNewTabTooltip`).
InlineSpan shortcutTooltip(String full, String shortcut) {
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
  });

  final ScrollController controller;
  final Widget child;
  final bool showOnHover;

  @override
  State<ShellxScrollbar> createState() => _ShellxScrollbarState();
}

class _ShellxScrollbarState extends State<ShellxScrollbar> {
  bool _pointerInside = false;

  @override
  Widget build(BuildContext context) {
    final scrollbar = _HoverThumbScrollbar(
      controller: widget.controller,
      thumbVisibility: widget.showOnHover && _pointerInside,
      fadeDuration: ShellxMotion.of(context, ShellxMotion.fast),
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
  }) : super(
         thickness: ShellxSizes.scrollbarThickness,
         radius: const Radius.circular(ShellxSizes.scrollbarRadius),
         crossAxisMargin: ShellxSizes.scrollbarMargin,
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

/// UI §2.4: a layout row at the top of the pane (it may resize the terminal:
/// it is rare and shows before phones attach).
class SignedOutStrip extends StatelessWidget {
  const SignedOutStrip({super.key, required this.onSignIn});
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      key: const Key('pane.signedOutStrip'),
      height: ShellxSizes.signedOutStrip,
      decoration: const BoxDecoration(
        color: ShellxDesktopColors.rowSelected,
        border: Border(bottom: BorderSide(color: ShellxDesktopColors.line)),
      ),
      padding: const EdgeInsets.only(
        left: ShellxSpace.s12,
        right: ShellxSpace.s8,
      ),
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
            onPressed: onSignIn,
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(
                Size(0, ShellxSizes.textButton),
              ),
              fixedSize: const WidgetStatePropertyAll(
                Size.fromHeight(ShellxSizes.textButton),
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(
                  horizontal: ShellxSizes.textButtonPaddingH,
                ),
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: const WidgetStatePropertyAll(_r6),
              textStyle: const WidgetStatePropertyAll(ShellxText.bodyStrong),
              foregroundColor: const WidgetStatePropertyAll(
                ShellxDesktopColors.accent,
              ),
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
                (states) =>
                    states.contains(WidgetState.focused) ? _focusRing : null,
              ),
            ),
            child: Text(l10n.terminalSignedOutAction),
          ),
        ],
      ),
    );
  }
}

/// UI §2.5: never interactive (clicks reach the terminal), never resizes
/// the terminal. Announced once when it appears.
class DriverPill extends StatelessWidget {
  const DriverPill({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        child: Container(
          key: const Key('pane.driverPill'),
          height: ShellxSizes.driverPill,
          // With the 16 px side insets of its Positioned: min(560, pane − 32).
          constraints: const BoxConstraints(maxWidth: ShellxSizes.pillMaxWidth),
          padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s12),
          decoration: BoxDecoration(
            color: ShellxDesktopColors.warnBg,
            borderRadius: BorderRadius.circular(ShellxRadius.pill),
            border: Border.all(color: ShellxDesktopColors.warnBorder),
            boxShadow: ShellxShadows.e1,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ExcludeSemantics(
                child: Icon(
                  Icons.smartphone,
                  size: ShellxSizes.mark,
                  color: ShellxDesktopColors.warn,
                ),
              ),
              const SizedBox(width: ShellxSpace.s6),
              Flexible(
                child: Text(
                  l10n.terminalDriverPhone,
                  style: ShellxText.body.copyWith(
                    color: ShellxDesktopColors.warn,
                  ),
                  maxLines: 1,
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
  });
  final TabNotice notice;
  final VoidCallback onDismiss;

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

  bool get _paused => _hovered || _closeFocus.hasFocus;

  /// A fresh 6 s, unless the pointer or the keyboard is on the toast.
  void _start() {
    _timer?.cancel();
    _timer = _paused
        ? null
        : Timer(ShellxMotion.toastVisibleError, widget.onDismiss);
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
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
            color: ShellxDesktopColors.noticeBg,
            borderRadius: BorderRadius.circular(ShellxRadius.r8),
            border: Border.all(color: ShellxDesktopColors.noticeBorder),
            boxShadow: ShellxShadows.e1,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ExcludeSemantics(
                child: Icon(
                  Icons.error_outline,
                  size: ShellxSizes.icon,
                  color: ShellxDesktopColors.noticeText,
                ),
              ),
              const SizedBox(width: ShellxSpace.s8),
              Flexible(
                child: Text(
                  _text(l10n),
                  style: ShellxText.body.copyWith(
                    color: ShellxDesktopColors.noticeText,
                  ),
                ),
              ),
              const SizedBox(width: ShellxSpace.s8),
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
                color: ShellxDesktopColors.noticeText,
                hoverColor: ShellxDesktopColors.noticeText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// UI §2.7: shown in the pane when there is no tab.
class EmptyTerminalState extends StatelessWidget {
  const EmptyTerminalState({super.key, required this.onOpen, this.buttonFocus});
  final VoidCallback onOpen;

  /// "Open new tab" gets the keyboard when the last tab closes.
  final FocusNode? buttonFocus;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                l10n.terminalEmptyBody,
                textAlign: TextAlign.center,
                style: ShellxText.body.copyWith(
                  color: ShellxDesktopColors.textSecondary,
                ),
              ),
              const SizedBox(height: ShellxSpace.s16),
              ShellxPrimaryButton(
                key: const Key('pane.empty.open'),
                label: l10n.terminalEmptyAction,
                onPressed: onOpen,
                focusNode: buttonFocus,
              ),
              const SizedBox(height: ShellxSpace.s8),
              ExcludeSemantics(
                child: Text(
                  newTabShortcutLabel(),
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
