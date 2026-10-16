import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/widgets/extra_keys_bar.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Agent quick reply D2: takes the extra keys' place while the tab's coding agent waits for the user
/// (`needs_input`): `1 2 3 y n Enter Esc ↑ ↓`, each sending exactly one key, then "⌨" for the extra keys.
/// Same height and look as [ExtraKeysBar], so the terminal does not move when they swap.
class AgentReplyBar extends StatelessWidget {
  const AgentReplyBar({super.key, required this.onKey, required this.onShowExtraKeys, this.leading});

  final ValueChanged<ReplyKey> onKey;

  /// "⌨": back to the extra keys until the agent asks again.
  final VoidCallback onShowExtraKeys;

  /// Before the keys: the composer / voice button, as on [ExtraKeysBar].
  final Widget? leading;

  static String? _semanticsLabel(S s, ReplyKey key) => switch (key) {
    ReplyKey.one => s.replyKeyOption(1),
    ReplyKey.two => s.replyKeyOption(2),
    ReplyKey.three => s.replyKeyOption(3),
    ReplyKey.yes => s.replyKeyYes,
    ReplyKey.no => s.replyKeyNo,
    ReplyKey.enter => s.replyKeyEnter,
    ReplyKey.esc => s.replyKeyEscape,
    ReplyKey.up => s.keyArrowUp,
    ReplyKey.down => s.keyArrowDown,
  };

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final colors = context.colors;
    return Semantics(
      container: true,
      label: strings.replyBarLabel,
      child: Container(
        height: ExtraKeysBar.height,
        decoration: BoxDecoration(
          color: colors.keyboardBackground,
          border: const Border(top: BorderSide(color: Color(0x14000000))),
        ),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 3),
          children: [
            ?leading,
            for (final key in ReplyKey.values)
              KeyCap(
                key: ValueKey('reply-key-${key.name}'),
                label: replyKeyLabel(key),
                semanticsLabel: _semanticsLabel(strings, key),
                onTap: () => onKey(key),
              ),
            Tooltip(
              message: strings.replyShowExtraKeys,
              child: Semantics(
                button: true,
                label: strings.replyShowExtraKeys,
                onTap: onShowExtraKeys,
                child: ExcludeSemantics(
                  child: GestureDetector(
                    key: const ValueKey('reply-keyboard'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onShowExtraKeys,
                    child: SizedBox(
                      width: 48,
                      height: ExtraKeysBar.height,
                      child: Icon(Icons.keyboard_outlined, size: 22, color: colors.keyboardInk),
                    ),
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
