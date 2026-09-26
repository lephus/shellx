import 'package:shellx_mobile/core/core.dart';

enum StatusTone { ok, error, warn }

/// The round state icon of the ShellX design (`.state-ic`): success, error or warning.
class StatusCircle extends StatelessWidget {
  const StatusCircle({super.key, required this.icon, this.tone = StatusTone.ok});

  final IconData icon;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (background, foreground) = switch (tone) {
      StatusTone.ok => (colors.primarySoft, colors.primary),
      StatusTone.error => (colors.errorSoft, colors.error),
      StatusTone.warn => (colors.warnSoft, colors.warn),
    };
    // Decorative next to its own text in every design use; the text carries the meaning.
    return ExcludeSemantics(
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Icon(icon, size: 38, color: foreground),
      ),
    );
  }
}
