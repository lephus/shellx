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

  const AppButton({
    super.key,
    this.height = 48,
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
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: state.isAvailable ? onTap : null,
        borderRadius: BorderRadius.circular(50),
        child: Ink(
          height: height,
          width: width,
          padding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: state.isDisable == false ? border : null,
            color: state.isAvailable
                ? backgroundColor ?? context.colors.primary
                : context.colors.disable.withAlpha((0.8 * 255).toInt()),
            borderRadius: BorderRadius.circular(50),
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
                    Text(
                      title,
                      style: context.typo.subHeader.bold
                          .copyWith(
                            color: state.isDisable ? context.colors.white : (textColor ?? context.colors.black),
                          )
                          .merge(textStyle),
                    ),
                    ?suffix,
                  ],
                ),
              ),
              if (state.isLoading)
                SizedBox.square(
                  dimension: height / 2,
                  child: const CircularProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
