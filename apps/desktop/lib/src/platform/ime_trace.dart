import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Diagnostics for input-method problems, on only when the app is started
/// with `SHELLX_IME_TRACE=<file>`.
///
/// Appends one line per text-input event to the file: the platform channel's
/// method names both ways, key downs and focus/lifecycle changes. Never the
/// text: lengths, ranges and key kinds only ("letter", "space", ...), so the
/// file can be shared to debug a Telex word that does not combine.
final class ImeTrace {
  ImeTrace._(this._sink);

  final IOSink _sink;
  final Stopwatch _clock = Stopwatch()..start();

  static ImeTrace? _instance;

  /// Starts tracing when [env] names a file; otherwise does nothing.
  static void installFrom(Map<String, String> env) {
    final path = env['SHELLX_IME_TRACE'];
    if (path == null || path.isEmpty || _instance != null) return;
    final t = ImeTrace._(File(path).openWrite(mode: FileMode.append));
    _instance = t;
    t._line('start');
    // ignore: invalid_use_of_visible_for_testing_member
    TextInput.setChannel(
      MethodChannel(
        'flutter/textinput',
        const JSONMethodCodec(),
        _TracingMessenger(ServicesBinding.instance.defaultBinaryMessenger, t),
      ),
    );
    HardwareKeyboard.instance.addHandler(t._onKey);
    FocusManager.instance.addListener(t._onFocus);
    WidgetsBinding.instance.addObserver(_Lifecycle(t));
  }

  /// A line from elsewhere (terminal output sizes), when tracing is on.
  static void note(String s) => _instance?._line(s);

  void _line(String s) {
    _sink.writeln('${_clock.elapsedMilliseconds.toString().padLeft(8)} $s');
  }

  bool _onKey(KeyEvent e) {
    if (e is KeyDownEvent || e is KeyRepeatEvent) {
      _line(
        'key ${e is KeyRepeatEvent ? 'repeat' : 'down'} '
        '${_kind(e)}${HardwareKeyboard.instance.isMetaPressed ? ' +cmd' : ''}'
        '${HardwareKeyboard.instance.isControlPressed ? ' +ctrl' : ''}'
        '${HardwareKeyboard.instance.isAltPressed ? ' +alt' : ''}',
      );
    }
    return false;
  }

  static String _kind(KeyEvent e) {
    final c = e.character;
    if (c != null && c.length == 1) {
      final u = c.codeUnitAt(0);
      if (u == 0x20) return 'space';
      if ((u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A)) {
        return 'letter';
      }
      if (u >= 0x30 && u <= 0x39) return 'digit';
      if (u >= 0x20 && u < 0x7F) return 'punct';
    }
    return 'other:${e.logicalKey.debugName ?? e.logicalKey.keyId}';
  }

  String? _lastFocus;
  void _onFocus() {
    final f = FocusManager.instance.primaryFocus;
    final d = f == null ? 'none' : '${f.runtimeType}#${identityHashCode(f)}';
    if (d == _lastFocus) return;
    _lastFocus = d;
    _line('focus $d');
  }

  /// Method name plus the shape of an editing state, never its text.
  static String describe(MethodCall call) {
    final args = call.arguments;
    final out = StringBuffer(call.method);
    Map<Object?, Object?>? state;
    if (args is Map) state = args;
    if (args is List && args.length >= 2 && args[1] is Map) {
      state = args[1] as Map;
    }
    if (args is List && args.isNotEmpty && args.first is int) {
      out.write(' client=${args.first}');
    }
    if (state != null && state.containsKey('text')) {
      final text = state['text'];
      out.write(
        ' len=${text is String ? text.length : '?'}'
        ' sel=${state['selectionBase']}..${state['selectionExtent']}'
        ' comp=${state['composingBase']}..${state['composingExtent']}',
      );
    } else if (call.method == 'TextInput.setCaretRect' && args is Map) {
      out.write(' x=${args['x']} y=${args['y']}');
    } else if (args is List && args.length >= 2 && args[1] is String) {
      out.write(' ${args[1]}'); // performAction: an action name
    }
    return out.toString();
  }
}

final class _Lifecycle with WidgetsBindingObserver {
  _Lifecycle(this._t);
  final ImeTrace _t;

  @override
  void didChangeAppLifecycleState(ui.AppLifecycleState state) =>
      _t._line('lifecycle ${state.name}');
}

final class _TracingMessenger implements BinaryMessenger {
  _TracingMessenger(this._inner, this._t);

  final BinaryMessenger _inner;
  final ImeTrace _t;
  static const _codec = JSONMethodCodec();

  void _log(String dir, ByteData? data) {
    if (data == null) return;
    try {
      _t._line('$dir ${ImeTrace.describe(_codec.decodeMethodCall(data))}');
    } on Object {
      _t._line('$dir ?');
    }
  }

  @override
  // ignore: deprecated_member_use
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    ui.PlatformMessageResponseCallback? callback,
    // ignore: deprecated_member_use
  ) => _inner.handlePlatformMessage(channel, data, callback);

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    _log('->', message);
    return _inner.send(channel, message);
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {
    _inner.setMessageHandler(
      channel,
      handler == null
          ? null
          : (data) {
              _log('<-', data);
              return handler(data);
            },
    );
  }
}
