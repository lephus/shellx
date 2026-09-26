import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/src/assets.gen.dart';
import 'package:shellx_mobile/shared/src/l10n.dart';

/// The ShellX tile artwork (`.logo`). It carries its own dark tile background,
/// so it looks the same in light and dark themes.
class ShellxLogo extends StatelessWidget {
  const ShellxLogo({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: S.of(context).appTitle,
      image: true,
      child: ExcludeSemantics(
        child: Assets.images.logo.image(width: size, height: size, filterQuality: FilterQuality.medium),
      ),
    );
  }
}
