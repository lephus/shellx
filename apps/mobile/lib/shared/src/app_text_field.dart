import 'package:shellx_mobile/core/core.dart';

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
          style: context.typo.paragraph.semiBold,
        ),
        const SizedBox(height: 8),
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
          autovalidateMode: _hasInteracted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
          style: context.typo.subHeader,
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: context.typo.subHeader.copyWith(
              color: context.colors.secondaryText.withValues(alpha: 0.5),
            ),
            prefixIcon: widget.prefixIcon,
            suffixIcon: widget.suffixIcon,
            filled: true,
            fillColor: context.colors.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: context.colors.border,
                width: 1,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: context.colors.border,
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: context.colors.primary,
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: context.colors.error,
                width: 1,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: context.colors.error,
                width: 2,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: context.colors.border.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            errorStyle: context.typo.metadata12.copyWith(
              color: context.colors.error,
            ),
          ),
        ),
      ],
    );
  }
}
