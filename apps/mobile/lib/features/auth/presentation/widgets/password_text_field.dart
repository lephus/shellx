import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Password field with the eye button (the ShellX design has no "repeat password" field).
class PasswordTextField extends StatefulWidget {
  final String label;
  final String? hintText;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final void Function(String)? onChanged;
  final void Function(String)? onFieldSubmitted;
  final String? errorText;
  final String? helperText;
  final Iterable<String>? autofillHints;

  const PasswordTextField({
    super.key,
    required this.label,
    this.hintText,
    this.controller,
    this.validator,
    this.textInputAction,
    this.onChanged,
    this.onFieldSubmitted,
    this.errorText,
    this.helperText,
    this.autofillHints,
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
          obscureText: _obscureText,
          textInputAction: widget.textInputAction,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onFieldSubmitted,
          autofillHints: widget.autofillHints,
          autovalidateMode: _hasInteracted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
          style: context.typo.subHeader,
          decoration: appInputDecoration(
            context,
            hintText: widget.hintText,
            errorText: widget.errorText,
            helperText: widget.helperText,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: context.colors.disable,
              ),
              tooltip: _obscureText ? S.of(context).passwordShow : S.of(context).passwordHide,
              onPressed: _toggleVisibility,
            ),
          ),
        ),
      ],
    );
  }
}
