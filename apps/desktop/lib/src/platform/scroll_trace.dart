import 'dart:io';

// ignore: implementation_imports
import 'package:xterm/src/ui/render.dart' show RenderTerminal;

/// Diagnostics for "the terminal will not scroll", on only when the app is
/// started with `SHELLX_SCROLL_TRACE=<file>`.
///
/// Appends one line per terminal layout with the live scroll state (offset,
/// max extent, viewport height, buffer line count, alt-buffer, stick). No
/// terminal text is written, so the file can be shared. Consecutive
/// identical states are collapsed so an idle terminal does not flood it.
final class ScrollTrace {
  ScrollTrace._(this._sink);

  final IOSink _sink;
  final Stopwatch _clock = Stopwatch()..start();
  String _last = '';
  int _repeat = 0;

  static ScrollTrace? _instance;

  static void installFrom(Map<String, String> env) {
    final path = env['SHELLX_SCROLL_TRACE'];
    if (path == null || path.isEmpty || _instance != null) return;
    final t = ScrollTrace._(File(path).openWrite(mode: FileMode.append));
    _instance = t;
    t._line('start');
    RenderTerminal.debugScrollHook = ({
      required int terminalId,
      required double offset,
      required double maxExtent,
      required double viewport,
      required int bufferLines,
      required bool altBuffer,
      required bool stickToBottom,
    }) {
      final line =
          't=$terminalId '
          'offset=${offset.toStringAsFixed(1)} '
          'max=${maxExtent.toStringAsFixed(1)} '
          'viewport=${viewport.toStringAsFixed(1)} '
          'lines=$bufferLines alt=$altBuffer stick=$stickToBottom';
      t._collapsed(line);
    };
  }

  void _collapsed(String line) {
    if (line == _last) {
      _repeat++;
      return;
    }
    if (_repeat > 0) {
      _line('  (x$_repeat)');
      _repeat = 0;
    }
    _last = line;
    _line(line);
  }

  void _line(String s) {
    _sink.writeln('${_clock.elapsedMilliseconds.toString().padLeft(8)} $s');
  }
}
