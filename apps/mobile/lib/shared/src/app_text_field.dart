import 'package:shellx_mobile/core/core.dart';

/// ShellX design `.field`: bold label, 52 pt input with radius 13; [errorText] (e.g. an answer
/// from the relay) and [helperText] sit right under the field.
class AppTextField extends StatefulWidget {
  final String label;
  final String? hintText;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool enabled;
  final int? maxLines;
  final TextInputAction? textInputAction;
  final void Function(String)? onChanged;
  final void Function(String)? onFieldSubmitted;
  final String? errorText;
  final String? helperText;
  final Iterable<String>? autofillHints;

  const AppTextField({
    super.key,
    required this.label,
    this.hintText,
    this.controller,
    this.validator,
    this.keyboardType,
    this.prefixIcon,
    this.suffixIcon,
    this.enabled = true,
    this.maxLines = 1,
    this.textInputAction,
    this.onChanged,
    this.onFieldSubmitted,
    this.errorText,
    this.helperText,
    this.autofillHints,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late final FocusNode _focusNode;
  bool _hasInteracted = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    // When user unfocuses field, enable validation on change
    if (!_focusNode.hasFocus && !_hasInteracted) {
      setState(() {
        _hasInteracted = true;
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.label,
          style: context.typo.paragraph13.bold.copyWith(color: context.colors.secondaryText),
        ),
        const SizedBox(height: 7),
        TextFormField(
          controller: widget.controller,
          focusNode: _focusNode,
          validator: (value) {
            final error = widget.validator?.call(value);
            // If there's an error and we haven't enabled on-change validation yet, do so
            if (error != null && !_hasInteracted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _hasInteracted = true;
                  });
                }
              });
            }
            return error;
          },
          keyboardType: widget.keyboardType,
          enabled: widget.enabled,
          maxLines: widget.maxLines,
          textInputAction: widget.textInputAction,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onFieldSubmitted,
          autofillHints: widget.autofillHints,
          autovalidateMode: _hasInteracted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
          style: context.typo.subHeader,
          decoration: appInputDecoration(
            context,
            hintText: widget.hintText,
            prefixIcon: widget.prefixIcon,
            suffixIcon: widget.suffixIcon,
            errorText: widget.errorText,
            helperText: widget.helperText,
          ),
        ),
      ],
    );
  }
}

/// The input box of the ShellX design, shared by [AppTextField] and `PasswordTextField`.
InputDecoration appInputDecoration(
  BuildContext context, {
  String? hintText,
  Widget? prefixIcon,
  Widget? suffixIcon,
  String? errorText,
  String? helperText,
}) {
  final colors = context.colors;
  OutlineInputBorder outline(Color color, double width) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(13),
    borderSide: BorderSide(color: color, width: width),
  );
  return InputDecoration(
    hintText: hintText,
    hintStyle: context.typo.subHeader.copyWith(color: colors.disable),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    errorText: errorText,
    helperText: helperText,
    helperMaxLines: 3,
    errorMaxLines: 3,
    helperStyle: context.typo.paragraph13.copyWith(color: colors.secondaryText),
    filled: true,
    fillColor: colors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    border: outline(colors.border, 1.5),
    enabledBorder: outline(colors.border, 1.5),
    focusedBorder: outline(colors.primary, 2),
    errorBorder: outline(colors.error, 1.5),
    focusedErrorBorder: outline(colors.error, 2),
    disabledBorder: outline(colors.border.withValues(alpha: 0.5), 1.5),
    errorStyle: context.typo.paragraph13.bold.copyWith(color: colors.error),
  );
}
