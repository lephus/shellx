import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// The horizontally scrolling extra keys row right above the keyboard (spec §9.3), styled like
/// the system keyboard (`--kb-*`). Ctrl/Alt: outline = once, filled with a dot = locked.
class ExtraKeysBar extends StatelessWidget {
  const ExtraKeysBar({super.key, required this.controller, required this.onKey, required this.onPaste});

  static const double height = 50;

  final ExtraKeysController controller;

  /// Every key except Ctrl, Alt and Paste.
  final ValueChanged<ExtraKey> onKey;
  final VoidCallback onPaste;

  void _press(ExtraKey key) {
    switch (key) {
      case ExtraKey.ctrl:
      case ExtraKey.alt:
        controller.tapModifier(key);
      case ExtraKey.paste:
        onPaste();
      default:
        onKey(key);
    }
  }

  /// A screen reader label for the glyph-only key caps (`↑ ↓ ← → | ~ / -`);
  /// null for keys whose visible text is already a word (Esc, Tab, Ctrl, Alt,
  /// Home, End, PgUp, PgDn) or already localised (Dán/Paste).
  static String? _semanticsLabel(BuildContext context, ExtraKey key) {
    final s = S.of(context);
    return switch (key) {
      ExtraKey.up => s.keyArrowUp,
      ExtraKey.down => s.keyArrowDown,
      ExtraKey.left => s.keyArrowLeft,
      ExtraKey.right => s.keyArrowRight,
      ExtraKey.pipe => s.keyPipe,
      ExtraKey.tilde => s.keyTilde,
      ExtraKey.slash => s.keySlash,
      ExtraKey.minus => s.keyMinus,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: context.colors.keyboardBackground,
        border: const Border(top: BorderSide(color: Color(0x14000000))),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        children: [
          for (final key in ExtraKey.values)
            Watch(
              key: ValueKey('extra-key-${key.name}'),
              (context) => _KeyCap(
                label: extraKeyLabel(key) ?? S.of(context).keyPaste,
                semanticsLabel: _semanticsLabel(context, key),
                isPaste: key == ExtraKey.paste,
                latch: switch (key) {
                  ExtraKey.ctrl => controller.ctrl.value,
                  ExtraKey.alt => controller.alt.value,
                  _ => null,
                },
                onTap: () => _press(key),
              ),
            ),
        ],
      ),
    );
  }
}

class _KeyCap extends StatelessWidget {
  const _KeyCap({
    required this.label,
    required this.semanticsLabel,
    required this.isPaste,
    required this.latch,
    required this.onTap,
  });

  final String label;

  /// Screen-reader label for a glyph-only cap (see [ExtraKeysBar._semanticsLabel]); null keeps
  /// the default (the visible [label] itself is read).
  final String? semanticsLabel;
  final bool isPaste;
  final ModifierLatch? latch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final once = latch == ModifierLatch.oneShot;
    final locked = latch == ModifierLatch.locked;
    final foreground = locked ? colors.onPrimary : (once ? colors.primary : colors.keyboardInk);
    final textStyle = isPaste
        ? context.typo.paragraph.bold.copyWith(color: foreground)
        : TextStyle(
            fontFamily: FontFamily.jetBrainsMono,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: foreground,
          );
    Widget text = Text(label, style: textStyle);
    if (semanticsLabel != null) {
      text = Semantics(
        label: semanticsLabel,
        child: ExcludeSemantics(child: text),
      );
    }
    // The whole bar height (50 pt) is the touch target; the cap itself is 38 pt tall.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
        child: Container(
          key: once ? const ValueKey('latch-one-shot') : null,
          constraints: const BoxConstraints(minWidth: 46),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: locked ? colors.primary : colors.keyboardKey,
            borderRadius: BorderRadius.circular(9),
            border: once ? Border.all(color: colors.primary, width: 2.5) : null,
            // Design: the one-shot outline replaces the base drop shadow entirely (`.k.mod.once`
            // sets its own box-shadow); the plain and locked caps keep the base `.k` shadow.
            boxShadow: once ? null : const [BoxShadow(color: Color(0x47000000), offset: Offset(0, 1))],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              text,
              if (locked)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    key: const ValueKey('latch-locked'),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: foreground, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
