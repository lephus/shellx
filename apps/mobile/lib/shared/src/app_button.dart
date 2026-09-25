import 'package:shellx_mobile/core/core.dart';

enum ButtonState {
  available,
  disable,
  loading
  ;

  bool get isAvailable => this == available;
  bool get isDisable => this == disable;
  bool get isLoading => this == loading;
}

/// ShellX design `.btn`: 54 pt tall, radius 15, bold label on [AppColors.primary]; a disabled
/// button keeps its colours at 45 % opacity ("nút mờ tới khi hợp lệ").
class AppButton extends StatelessWidget {
  final double height;
  final double? width;
  final ButtonState state;
  final Function()? onTap;
  final String title;
  final Widget? suffix;
  final Widget? prefix;
  final EdgeInsets? padding;
  final Color? backgroundColor;
  final Color? textColor;
  final Border? border;
  final TextStyle? textStyle;
  final MainAxisSize? mainAxisSize;
  final double radius;

  const AppButton({
    super.key,
    this.height = 54,
    this.width,
    this.state = ButtonState.available,
    this.onTap,
    required this.title,
    this.suffix,
    this.prefix,
    this.padding,
    this.backgroundColor,
    this.border,
    this.textColor,
    this.textStyle,
    this.mainAxisSize,
    this.radius = 15,
  });

  @override
  Widget build(BuildContext context) {
    final background = backgroundColor ?? context.colors.primary;
    final foreground = textColor ?? context.colors.onPrimary;
    final shape = BorderRadius.circular(radius);
    return Opacity(
      opacity: state.isDisable ? 0.45 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: state.isAvailable ? onTap : null,
          borderRadius: shape,
          child: Ink(
            height: height,
            width: width,
            padding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: border,
              color: background,
              borderRadius: shape,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: state.isLoading ? 0 : 1,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: mainAxisSize ?? MainAxisSize.min,
                    children: [
                      ?prefix,
                      Flexible(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: context.typo.subHeader.bold.copyWith(color: foreground).merge(textStyle),
                        ),
                      ),
                      ?suffix,
                    ],
                  ),
                ),
                if (state.isLoading)
                  SizedBox.square(
                    dimension: height / 2.4,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: foreground),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
