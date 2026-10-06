import 'dart:convert';
import 'dart:typed_data';

/// Something a shell hook or a program said through an OSC sequence
/// (push spec §4.1).
sealed class OscEvent {
  const OscEvent();
}

/// `OSC 133 ; C` (or VS Code's `633 ; C`): the command line just entered
/// starts running.
final class CommandStarted extends OscEvent {
  const CommandStarted();
  @override
  bool operator ==(Object other) => other is CommandStarted;
  @override
  int get hashCode => 133;
  @override
  String toString() => 'CommandStarted()';
}

/// `OSC 133 ; D [; <exit code>]`: the command finished (no code means 0).
final class CommandFinished extends OscEvent {
  const CommandFinished(this.exitCode);
  final int exitCode;
  @override
  bool operator ==(Object other) =>
      other is CommandFinished && other.exitCode == exitCode;
  @override
  int get hashCode => exitCode.hashCode;
  @override
  String toString() => 'CommandFinished($exitCode)';
}

/// `OSC 633 ; E ; <command line> [; <nonce>]` (VS Code's convention),
/// already unescaped.
final class CommandLineSeen extends OscEvent {
  const CommandLineSeen(this.commandLine);
  final String commandLine;
  @override
  bool operator ==(Object other) =>
      other is CommandLineSeen && other.commandLine == commandLine;
  @override
  int get hashCode => commandLine.hashCode;
  @override
  String toString() => 'CommandLineSeen($commandLine)';
}

/// A program asks for a notification: `OSC 9 ; <body>` (title null) or
/// `OSC 777 ; notify ; <title> ; <body>` (title null when empty).
final class NotifyRequested extends OscEvent {
  const NotifyRequested({required this.title, required this.body});
  final String? title;
  final String body;
  @override
  bool operator ==(Object other) =>
      other is NotifyRequested && other.title == title && other.body == body;
  @override
  int get hashCode => Object.hash(title, body);
  @override
  String toString() => 'NotifyRequested($title, $body)';
}

/// `OSC 7 ; file://<host>/<path>`: the shell's working directory, printed
/// by the ShellX hooks at every prompt (A2 C1). [url] is as sent;
/// `parseCwdUrl` decodes it.
final class CwdReported extends OscEvent {
  const CwdReported(this.url);
  final String url;
  @override
  bool operator ==(Object other) => other is CwdReported && other.url == url;
  @override
  int get hashCode => url.hashCode;
  @override
  String toString() => 'CwdReported(…)';
}

enum _State {
  ground,
  escape,
  param,
  payload,
  payloadEscape,
  ignore,
  ignoreEscape,
}

/// Finds OSC 7, 133 (C, D), 633 (E), 9 and 777 (`notify`) in terminal output,
/// ended by BEL or ST, across chunk boundaries (like `OscTitleParser`).
/// A payload over 4 KiB is skipped; titles and bodies are cut to 200
/// characters; malformed UTF-8 is replaced, never fatal. The bytes
/// themselves are untouched: the terminal output goes on as it was.
final class OscEventParser {
  static const int maxTextLength = 200;
  static const int maxPayload = 4096;
  static const _numbers = {'7', '133', '633', '9', '777'};

  _State _state = _State.ground;
  final _param = StringBuffer();
  final _payload = BytesBuilder(copy: false);
  String _number = '';

  /// Forgets a sequence cut off by a new connection.
  void reset() {
    _state = _State.ground;
    _param.clear();
    _payload.clear();
  }

  List<OscEvent> feed(Uint8List data) {
    final events = <OscEvent>[];
    for (final byte in data) {
      final event = _step(byte);
      if (event != null) events.add(event);
    }
    return events;
  }

  OscEvent? _step(int byte) {
    switch (_state) {
      case _State.ground:
        if (byte == 0x1b) _state = _State.escape;
      case _State.escape:
        if (byte == 0x5d) {
          _param.clear();
          _state = _State.param;
        } else if (byte != 0x1b) {
          _state = _State.ground;
        }
      case _State.param:
        if (byte >= 0x30 && byte <= 0x39 && _param.length < 3) {
          _param.writeCharCode(byte);
        } else if (byte == 0x3b) {
          _number = _param.toString();
          _payload.clear();
          _state = _numbers.contains(_number) ? _State.payload : _State.ignore;
        } else if (byte == 0x07) {
          _state = _State.ground;
        } else if (byte == 0x1b) {
          _state = _State.escape;
        } else {
          _state = _State.ignore;
        }
      case _State.payload:
        if (byte == 0x07) return _finish();
        if (byte == 0x1b) {
          _state = _State.payloadEscape;
        } else if (_payload.length >= maxPayload) {
          _payload.clear();
          _state = _State.ignore;
        } else {
          _payload.addByte(byte);
        }
      case _State.payloadEscape:
        if (byte == 0x5c) return _finish();
        // ESC not followed by '\': the sequence was abandoned.
        _payload.clear();
        _state = _State.escape;
        return _step(byte);
      case _State.ignore:
        if (byte == 0x07) {
          _state = _State.ground;
        } else if (byte == 0x1b) {
          _state = _State.ignoreEscape;
        }
      case _State.ignoreEscape:
        if (byte == 0x5c) {
          _state = _State.ground;
        } else {
          _state = _State.escape;
          return _step(byte);
        }
    }
    return null;
  }

  OscEvent? _finish() {
    _state = _State.ground;
    final text = utf8.decode(_payload.takeBytes(), allowMalformed: true);
    return switch (_number) {
      '7' => _osc7(text),
      '133' => _semanticPrompt(text),
      '633' => _vscode(text),
      '9' => _osc9(text),
      '777' => _osc777(text),
      _ => null,
    };
  }

  static OscEvent? _semanticPrompt(String text) {
    final parts = text.split(';');
    switch (parts.first) {
      case 'C':
        return const CommandStarted();
      case 'D':
        final code = parts.length > 1 ? parts[1].trim() : '';
        if (code.isEmpty) return const CommandFinished(0);
        final parsed = int.tryParse(code);
        return parsed == null ? null : CommandFinished(parsed);
      default:
        return null;
    }
  }

  /// VS Code's own shell integration reports start and end as `633;C` and
  /// `633;D[;<code>]` (no 133): accepted like 133, so commands in VS Code
  /// terminals notify too.
  static OscEvent? _vscode(String text) {
    final parts = text.split(';');
    switch (parts.first) {
      case 'E':
        if (parts.length < 2) return null;
        return CommandLineSeen(_clip(unescapeVsCode(parts[1])));
      case 'C' || 'D':
        return _semanticPrompt(text);
      default:
        return null;
    }
  }

  static final _progress = RegExp(r'^[0-9]+;');

  static OscEvent? _osc9(String text) {
    // OSC 9;4;… is ConEmu / Windows Terminal progress, not a notification.
    if (text.trim().isEmpty || _progress.hasMatch(text)) return null;
    return NotifyRequested(title: null, body: _clip(text));
  }

  static OscEvent? _osc7(String text) =>
      text.startsWith('file://') ? CwdReported(text) : null;

  static OscEvent? _osc777(String text) {
    final first = text.indexOf(';');
    if (first < 0 || text.substring(0, first) != 'notify') return null;
    final rest = text.substring(first + 1);
    final second = rest.indexOf(';');
    final title = second < 0 ? '' : rest.substring(0, second);
    final body = second < 0 ? rest : rest.substring(second + 1);
    if (body.trim().isEmpty) return null;
    return NotifyRequested(
      title: title.trim().isEmpty ? null : _clip(title),
      body: _clip(body),
    );
  }

  static String _clip(String text) =>
      String.fromCharCodes(text.runes.take(maxTextLength));

  /// VS Code's escaping of `OSC 633 ; E`: `\\` is a backslash and `\xHH`
  /// a character (`\x3b` for `;`, control characters); anything else stays
  /// as written.
  static String unescapeVsCode(String text) {
    if (!text.contains(r'\')) return text;
    final out = StringBuffer();
    var i = 0;
    while (i < text.length) {
      final c = text[i];
      if (c == r'\' && i + 1 < text.length) {
        final next = text[i + 1];
        if (next == r'\') {
          out.write(r'\');
          i += 2;
          continue;
        }
        if (next == 'x' && i + 3 < text.length) {
          final code = int.tryParse(text.substring(i + 2, i + 4), radix: 16);
          if (code != null) {
            out.writeCharCode(code);
            i += 4;
            continue;
          }
        }
      }
      out.write(c);
      i++;
    }
    return out.toString();
  }
}
