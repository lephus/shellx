import 'package:shellx_mobile/core/core.dart';

class PasswordTextField extends StatefulWidget {
  final String label;
  final String? hintText;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final void Function(String)? onChanged;
  final void Function(String)? onFieldSubmitted;

  const PasswordTextField({
    super.key,
    this.label = 'Password',
    this.hintText,
    this.controller,
    this.validator,
    this.textInputAction,
    this.onChanged,
    this.onFieldSubmitted,
  });

  @override
  State<PasswordTextField> createState() => _PasswordTextFieldState();
}

class _PasswordTextFieldState extends State<PasswordTextField> {
  bool _obscureText = true;
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

  void _toggleVisibility() {
    setState(() {
      _obscureText = !_obscureText;
    });
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
          obscureText: _obscureText,
          textInputAction: widget.textInputAction,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onFieldSubmitted,
          autovalidateMode: _hasInteracted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
          style: context.typo.subHeader,
          decoration: InputDecoration(
            hintText: widget.hintText ?? 'Enter your password',
            hintStyle: context.typo.subHeader.copyWith(
              color: context.colors.secondaryText.withValues(alpha: 0.5),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureText ? Icons.visibility_off : Icons.visibility,
                color: context.colors.secondaryText,
              ),
              onPressed: _toggleVisibility,
            ),
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
            errorStyle: context.typo.metadata12.copyWith(
              color: context.colors.error,
            ),
          ),
        ),
      ],
    );
  }
}
