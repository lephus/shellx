import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/src/fonts.gen.dart';
import 'package:shellx_mobile/shared/src/l10n.dart';

/// The "›_" tile of the ShellX design (`.logo`).
class ShellxLogo extends StatelessWidget {
  const ShellxLogo({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: S.of(context).appTitle,
      image: true,
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: context.colors.primary, borderRadius: BorderRadius.circular(size * 0.28)),
          child: Text(
            '›_',
            style: TextStyle(
              fontFamily: FontFamily.jetBrainsMono,
              fontWeight: FontWeight.w700,
              fontSize: size * 0.375,
              letterSpacing: -1,
              color: context.colors.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
