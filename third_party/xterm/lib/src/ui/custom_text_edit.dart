import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomTextEdit extends StatefulWidget {
  CustomTextEdit({
    super.key,
    required this.child,
    required this.onInsert,
    required this.onDelete,
    required this.onComposing,
    required this.onAction,
    required this.onKeyEvent,
    required this.focusNode,
    this.autofocus = false,
    this.readOnly = false,
    // this.initEditingState = TextEditingValue.empty,
    this.inputType = TextInputType.text,
    this.inputAction = TextInputAction.newline,
    this.keyboardAppearance = Brightness.light,
    this.deleteDetection = false,
  });

  final Widget child;

  final void Function(String) onInsert;

  final void Function() onDelete;

  final void Function(String?) onComposing;

  final void Function(TextInputAction) onAction;

  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;

  final FocusNode focusNode;

  final bool autofocus;

  final bool readOnly;

  final TextInputType inputType;

  final TextInputAction inputAction;

  final Brightness keyboardAppearance;

  final bool deleteDetection;

  @override
  CustomTextEditState createState() => CustomTextEditState();
}

class CustomTextEditState extends State<CustomTextEdit> with TextInputClient {
  TextInputConnection? _connection;

  @override
  void initState() {
    widget.focusNode.addListener(_onFocusChange);
    super.initState();
  }

  @override
  void didUpdateWidget(CustomTextEdit oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.focusNode != oldWidget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
    }

    if (!_shouldCreateInputConnection) {
      _closeInputConnectionIfNeeded();
    } else {
      if (oldWidget.readOnly && widget.focusNode.hasFocus) {
        _openInputConnection();
      }
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    _closeInputConnectionIfNeeded();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKeyEvent,
      child: widget.child,
    );
  }

  bool get hasInputConnection => _connection != null && _connection!.attached;

  void requestKeyboard() {
    if (widget.focusNode.hasFocus) {
      _openInputConnection();
    } else {
      widget.focusNode.requestFocus();
    }
  }

  void closeKeyboard() {
    if (hasInputConnection) {
      _connection?.close();
    }
    _word = ''; // ShellX: a new connection starts with an empty document.
  }

  void setEditingState(TextEditingValue value) {
    _currentEditingState = value;
    _connection?.setEditingState(value);
  }

  void setEditableRect(Rect rect, Rect caretRect) {
    if (!hasInputConnection) {
      return;
    }

    _connection?.setEditableSizeAndTransform(
      rect.size,
      Matrix4.translationValues(0, 0, 0),
    );

    _connection?.setCaretRect(caretRect);
  }

  void _onFocusChange() {
    _openOrCloseInputConnectionIfNeeded();
  }

  KeyEventResult _onKeyEvent(FocusNode focusNode, KeyEvent event) {
    if (_currentEditingState.composing.isCollapsed) {
      final result = widget.onKeyEvent(focusNode, event);
      // ShellX: a key the terminal handled (Backspace, Enter, arrows, Ctrl
      // and Cmd chords) never reaches the input method, so the word it can
      // see must follow: Backspace takes the last character off, anything
      // else ends the word.
      if (_keepsWord &&
          _word.isNotEmpty &&
          result == KeyEventResult.handled &&
          event is! KeyUpEvent) {
        _setWord(
          event.logicalKey == LogicalKeyboardKey.backspace
              ? _dropLast(_word)
              : '',
        );
      }
      return result;
    }

    return KeyEventResult.skipRemainingHandlers;
  }

  void _openOrCloseInputConnectionIfNeeded() {
    if (widget.focusNode.hasFocus && widget.focusNode.consumeKeyboardToken()) {
      _openInputConnection();
    } else if (!widget.focusNode.hasFocus) {
      _closeInputConnectionIfNeeded();
    }
  }

  bool get _shouldCreateInputConnection => kIsWeb || !widget.readOnly;

  void _openInputConnection() {
    if (!_shouldCreateInputConnection) {
      return;
    }

    if (hasInputConnection) {
      _connection!.show();
    } else {
      final config = TextInputConfiguration(
        inputType: widget.inputType,
        inputAction: widget.inputAction,
        keyboardAppearance: widget.keyboardAppearance,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
      );

      _connection = TextInput.attach(this, config);
      _word = '';

      _connection!.show();

      // setEditableRect(Rect.zero, Rect.zero);

      _connection!.setEditingState(_initEditingState);
    }
  }

  void _closeInputConnectionIfNeeded() {
    if (_connection != null && _connection!.attached) {
      _connection!.close();
      _connection = null;
    }
    _word = ''; // ShellX: a new connection starts with an empty document.
  }

  TextEditingValue get _initEditingState => widget.deleteDetection
      ? const TextEditingValue(
          text: '  ',
          selection: TextSelection.collapsed(offset: 2),
        )
      : const TextEditingValue(
          text: '',
          selection: TextSelection.collapsed(offset: 0),
        );

  late var _currentEditingState = _initEditingState.copyWith();

  @override
  TextEditingValue? get currentTextEditingValue {
    return _currentEditingState;
  }

  @override
  AutofillScope? get currentAutofillScope {
    return null;
  }

  // ShellX: the word being typed, kept in the platform's document.
  //
  // Upstream resets the document to empty after every character. macOS
  // input methods that edit typed text in place instead of composing it
  // (Vietnamese Telex and VNI: "chao" then "f" asks to replace "chao" with
  // "chào") then find nothing to edit and type the raw key. On macOS the
  // document keeps the trailing word (letters, marks, digits; at most
  // [_maxWord] characters); an edit of it reaches the terminal as
  // Backspaces plus the new tail, as a Vietnamese input method types into
  // Terminal.app.
  String _word = '';

  static const int _maxWord = 32;

  static final RegExp _wordTail = RegExp(
    r'[\p{L}\p{M}\p{N}]+$',
    unicode: true,
  );

  bool get _keepsWord =>
      defaultTargetPlatform == TargetPlatform.macOS && !widget.deleteDetection;

  static String _dropLast(String s) {
    if (s.isEmpty) return s;
    final runes = s.runes.toList()..removeLast();
    return String.fromCharCodes(runes);
  }

  static String _tailWord(String text) {
    final match = _wordTail.firstMatch(text)?.group(0);
    if (match == null) return '';
    final runes = match.runes.toList();
    return runes.length <= _maxWord
        ? match
        : String.fromCharCodes(runes.sublist(runes.length - _maxWord));
  }

  void _setWord(String word) {
    _word = word;
    final value = TextEditingValue(
      text: word,
      selection: TextSelection.collapsed(offset: word.length),
    );
    _currentEditingState = value;
    _connection?.setEditingState(value);
  }

  /// The platform's document changed from [_word] to the current text, with
  /// nothing composing: one Backspace per character of [_word] after the
  /// common prefix, then the text that replaces them.
  void _commitWordEdit() {
    final text = _currentEditingState.text;
    final base = _word;
    var prefix = 0;
    final shorter = text.length < base.length ? text.length : base.length;
    while (prefix < shorter &&
        text.codeUnitAt(prefix) == base.codeUnitAt(prefix)) {
      prefix++;
    }
    // Never split a surrogate pair.
    if (prefix > 0 &&
        prefix < base.length &&
        (base.codeUnitAt(prefix) & 0xFC00) == 0xDC00) {
      prefix--;
    }
    final deleted = base.substring(prefix).runes.length;
    for (var i = 0; i < deleted; i++) {
      widget.onDelete();
    }
    final inserted = text.substring(prefix);
    if (inserted.isNotEmpty) widget.onInsert(inserted);

    final word = _tailWord(text);
    if (word != text ||
        _currentEditingState.selection !=
            TextSelection.collapsed(offset: text.length)) {
      _setWord(word);
    } else {
      _word = word;
    }
  }

  @override
  void updateEditingValue(TextEditingValue value) {
    _currentEditingState = value;

    // Get input after composing is done
    if (!_currentEditingState.composing.isCollapsed) {
      final text = _currentEditingState.text;
      final composingText = _currentEditingState.composing.textInside(text);
      widget.onComposing(composingText);
      return;
    }

    widget.onComposing(null);

    // ShellX: see [_word].
    if (_keepsWord) {
      _commitWordEdit();
      return;
    }

    if (_currentEditingState.text.length < _initEditingState.text.length) {
      widget.onDelete();
    } else {
      final textDelta = _currentEditingState.text.substring(
        _initEditingState.text.length,
      );

      widget.onInsert(textDelta);
    }

    // Reset editing state if composing is done
    if (_currentEditingState.composing.isCollapsed &&
        _currentEditingState.text != _initEditingState.text) {
      _connection!.setEditingState(_initEditingState);
    }
  }

  @override
  void performAction(TextInputAction action) {
    // print('performAction $action');
    widget.onAction(action);
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {
    // print('updateFloatingCursor $point');
  }

  @override
  void showAutocorrectionPromptRect(int start, int end) {
    // print('showAutocorrectionPromptRect');
  }

  @override
  void connectionClosed() {
    // print('connectionClosed');
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {
    // print('performPrivateCommand $action');
  }

  @override
  void insertTextPlaceholder(Size size) {
    // print('insertTextPlaceholder');
  }

  @override
  void removeTextPlaceholder() {
    // print('removeTextPlaceholder');
  }

  @override
  void showToolbar() {
    // print('showToolbar');
  }
}
