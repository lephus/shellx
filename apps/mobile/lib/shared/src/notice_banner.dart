import 'package:shellx_mobile/core/core.dart';

enum NoticeTone { warn, info }

/// The rounded banner of the ShellX design (`.banner`): the lost-connection notice (warn, with a
/// spinner) and the "sign-in expired" notice on the login page (info, with a lock).
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({super.key, required this.text, this.tone = NoticeTone.warn, this.leading, this.action});

  final String text;
  final NoticeTone tone;
  final Widget? leading;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (background, foreground) = switch (tone) {
      NoticeTone.warn => (colors.warnSoft, colors.warn),
      NoticeTone.info => (colors.primarySoft, colors.primary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(13)),
      child: IconTheme(
        data: IconThemeData(color: foreground, size: 20),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Expanded(
              child: Text(text, style: context.typo.paragraph.bold.copyWith(color: foreground)),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// The small spinner of the lost-connection banner.
class NoticeSpinner extends StatelessWidget {
  const NoticeSpinner({super.key});

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 16,
    child: CircularProgressIndicator(strokeWidth: 2.5, color: IconTheme.of(context).color),
  );
}
