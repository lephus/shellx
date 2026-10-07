import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../terminal/find_session.dart';
import '../text_editing_shortcuts.dart';
import '../theme/shellx_desktop_theme.dart';

/// A10 D3: the find bar of one pane, over the top-right corner of its
/// terminal. It overlays: the terminal's grid never changes. Enter / ↓ the
/// next match, Shift+Enter / ↑ the previous, Esc closes ([onClose] gives
/// the keyboard back to the terminal).
class FindBar extends StatefulWidget {
  const FindBar({
    super.key,
    required this.session,
    required this.focusNode,
    required this.onClose,
    this.seed,
  });

  final FindSession session;

  /// The input's node: focused when the bar opens or ⌘F is pressed again.
  final FocusNode focusNode;
  final VoidCallback onClose;

  /// Text to start from (one selected line, A10 D3).
  final String? seed;

  static const double width = 360;
  static const double height = 36;

  @override
  State<FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<FindBar> {
  late final TextEditingController _text = TextEditingController(
    text: widget.session.query.isEmpty
        ? widget.seed ?? ''
        : widget.session.query,
  );

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_changed);
    if (_text.text != widget.session.query) {
      widget.session.setQuery(_text.text);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.focusNode.requestFocus();
      _text.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _text.text.length,
      );
    });
  }

  @override
  void dispose() {
    widget.session.removeListener(_changed);
    _text.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      HardwareKeyboard.instance.isShiftPressed
          ? widget.session.previous()
          : widget.session.next();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      widget.session.next();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      widget.session.previous();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String _count(AppLocalizations l10n) {
    final s = widget.session;
    if (!s.hasQuery) return '';
    if (s.matches.isEmpty) return l10n.findNoMatches;
    return s.capped
        ? l10n.findCountCapped(s.current + 1, s.matches.length)
        : l10n.findCount(s.current + 1, s.matches.length);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = widget.session;
    final none = s.hasQuery && s.matches.isEmpty;
    final count = _count(l10n);
    return Semantics(
      container: true,
      label: l10n.findLabel,
      child: Container(
        key: const Key('find.bar'),
        width: FindBar.width,
        height: FindBar.height,
        padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s8),
        decoration: BoxDecoration(
          color: ShellxDesktopColors.surface,
          borderRadius: BorderRadius.circular(ShellxRadius.r8),
          border: Border.all(color: ShellxDesktopColors.border),
          boxShadow: ShellxShadows.e1,
        ),
        child: Row(
          children: [
            Expanded(
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: _onKey,
                child: Shortcuts(
                  // The window's paste and copy must not take these keys.
                  shortcuts: textEditingShortcuts(),
                  child: TextField(
                    key: const Key('find.field'),
                    controller: _text,
                    focusNode: widget.focusNode,
                    style: ShellxText.body.copyWith(
                      color: ShellxDesktopColors.textTitle,
                    ),
                    cursorColor: ShellxDesktopColors.accent,
                    maxLines: 1,
                    maxLength: kMaxFindQuery,
                    onChanged: s.setQuery,
                    decoration: InputDecoration(
                      isDense: true,
                      counterText: '',
                      border: InputBorder.none,
                      hintText: l10n.findPlaceholder,
                      hintStyle: ShellxText.body.copyWith(
                        color: ShellxDesktopColors.textPlaceholder,
                      ),
                      semanticCounterText: '',
                    ),
                  ),
                ),
              ),
            ),
            // Read aloud when it changes ("3 of 17").
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s4),
                child: Text(
                  count,
                  key: const Key('find.count'),
                  style: ShellxText.caption.copyWith(
                    color: none
                        ? ShellxDesktopColors.err
                        : ShellxDesktopColors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            _Toggle(
              key: const Key('find.matchCase'),
              label: 'Aa',
              tooltip: l10n.findMatchCase,
              on: s.matchCase,
              onPressed: s.toggleMatchCase,
            ),
            _IconButton(
              key: const Key('find.previous'),
              icon: Icons.keyboard_arrow_up,
              tooltip: l10n.findPrevious,
              onPressed: s.matches.isEmpty ? null : s.previous,
            ),
            _IconButton(
              key: const Key('find.next'),
              icon: Icons.keyboard_arrow_down,
              tooltip: l10n.findNext,
              onPressed: s.matches.isEmpty ? null : s.next,
            ),
            _IconButton(
              key: const Key('find.close'),
              icon: Icons.close,
              tooltip: l10n.findClose,
              onPressed: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 24,
    height: 24,
    child: IconButton(
      padding: EdgeInsets.zero,
      iconSize: 16,
      tooltip: tooltip,
      onPressed: onPressed,
      color: ShellxDesktopColors.textSecondary,
      disabledColor: ShellxDesktopColors.textSecondary.withValues(
        alpha: ShellxDesktopColors.disabledOpacity,
      ),
      icon: Icon(icon),
    ),
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    super.key,
    required this.label,
    required this.tooltip,
    required this.on,
    required this.onPressed,
  });
  final String label;
  final String tooltip;
  final bool on;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      toggled: on,
      label: tooltip,
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(ShellxRadius.r4),
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? ShellxDesktopColors.primarySoft : null,
            borderRadius: BorderRadius.circular(ShellxRadius.r4),
          ),
          child: Text(
            label,
            style: ShellxText.caption.copyWith(
              color: on
                  ? ShellxDesktopColors.accent
                  : ShellxDesktopColors.textSecondary,
            ),
          ),
        ),
      ),
    ),
  );
}
