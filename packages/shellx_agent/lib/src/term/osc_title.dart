import 'dart:convert';
import 'dart:typed_data';

enum _State {
  ground,
  escape,
  param,
  payload,
  payloadEscape,
  ignore,
  ignoreEscape,
}

/// Finds window titles (OSC 0 and OSC 2, ended by BEL or ST) in terminal
/// output, across chunk boundaries (spec §7.4). Longer than 4 KiB is not a
/// title anyone wants to see: such a sequence is skipped.
final class OscTitleParser {
  static const int maxTitleLength = 200;
  static const int _maxPayload = 4096;

  _State _state = _State.ground;
  final _param = StringBuffer();
  final _payload = BytesBuilder(copy: false);

  void reset() {
    _state = _State.ground;
    _param.clear();
    _payload.clear();
  }

  String? feed(Uint8List data) {
    String? title;
    for (final byte in data) {
      title = _step(byte) ?? title;
    }
    return title;
  }

  String? _step(int byte) {
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
          final p = _param.toString();
          _payload.clear();
          _state = p == '0' || p == '2' ? _State.payload : _State.ignore;
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
        } else if (_payload.length >= _maxPayload) {
          _payload.clear();
          _state = _State.ignore;
        } else {
          _payload.addByte(byte);
        }
      case _State.payloadEscape:
        if (byte == 0x5c) return _finish();
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

  String _finish() {
    _state = _State.ground;
    final text = utf8.decode(_payload.takeBytes(), allowMalformed: true);
    return String.fromCharCodes(text.runes.take(maxTitleLength));
  }
}
