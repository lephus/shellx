import 'dart:typed_data';

import '../util/bytes.dart';
import '../util/cbor_values.dart';
import 'channel_id.dart';

const int kRelayProtocolVersion = 1;
const int kMaxFrameBytes = 64 * 1024;

/// Number of header bytes in front of a DATA frame payload.
const int kDataFrameHeaderBytes = 26;

const int _typeData = 0x01;
const int _typePresence = 0x02;
const int _typeError = 0x03;
const int _typeEvent = 0x04;

abstract final class RelayCloseCode {
  static const int replaced = 4001;
  static const int revoked = 4002;
  static const int rateLimited = 4003;
}

enum RelayErrorCode {
  peerOffline(1),
  frameTooLarge(2),
  rateLimited(3),
  badFrame(4);

  const RelayErrorCode(this.wire);
  final int wire;

  /// Throws [FrameFormatException] for an unknown code.
  static RelayErrorCode fromWire(int wire) {
    for (final code in values) {
      if (code.wire == wire) {
        return code;
      }
    }
    throw FrameFormatException('Unknown relay error code $wire');
  }
}

final class FrameFormatException implements Exception {
  const FrameFormatException(this.message);
  final String message;

  @override
  String toString() => 'FrameFormatException: $message';
}

/// A binary WebSocket frame exchanged with the relay hub (spec section 6.2).
sealed class RelayFrame {
  const RelayFrame();

  Uint8List encode();

  /// Parses one binary frame. Throws [FrameFormatException] if the frame is
  /// truncated, has the wrong version, has an unknown type or bad fields.
  static RelayFrame decode(Uint8List bytes) {
    if (bytes.length < 2) {
      throw const FrameFormatException('Frame shorter than 2 bytes');
    }
    if (bytes[0] != kRelayProtocolVersion) {
      throw FrameFormatException('Unsupported frame version ${bytes[0]}');
    }
    switch (bytes[1]) {
      case _typeData:
        if (bytes.length < kDataFrameHeaderBytes) {
          throw const FrameFormatException('DATA frame too short');
        }
        return DataFrame(
          peer: uuidFromBytes(Uint8List.sublistView(bytes, 2, 18)),
          channel: ChannelId(Uint8List.sublistView(bytes, 18, 26)),
          payload: Uint8List.fromList(Uint8List.sublistView(bytes, 26)),
        );
      case _typePresence:
        if (bytes.length != 19) {
          throw const FrameFormatException('PRESENCE frame must be 19 bytes');
        }
        final flag = bytes[18];
        if (flag > 1) {
          throw FrameFormatException('Bad PRESENCE flag $flag');
        }
        return PresenceFrame(
          deviceId: uuidFromBytes(Uint8List.sublistView(bytes, 2, 18)),
          online: flag == 1,
        );
      case _typeError:
        if (bytes.length != 28) {
          throw const FrameFormatException('ERROR frame must be 28 bytes');
        }
        return ErrorFrame(
          code: RelayErrorCode.fromWire((bytes[2] << 8) | bytes[3]),
          deviceId: uuidFromBytes(Uint8List.sublistView(bytes, 4, 20)),
          channel: ChannelId(Uint8List.sublistView(bytes, 20, 28)),
        );
      case _typeEvent:
        return EventFrame(_decodeEvent(Uint8List.sublistView(bytes, 2)));
      default:
        throw FrameFormatException('Unknown frame type ${bytes[1]}');
    }
  }

  static Map<String, String> _decodeEvent(Uint8List body) {
    final Object? decoded;
    try {
      decoded = decodeCbor(body);
    } on FormatException catch (error) {
      throw FrameFormatException('Bad EVENT CBOR: ${error.message}');
    }
    if (decoded is! Map) {
      throw const FrameFormatException('EVENT body must be a CBOR map');
    }
    final event = <String, String>{};
    for (final entry in decoded.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || value is! String) {
        throw const FrameFormatException('EVENT keys and values must be text');
      }
      event[key] = value;
    }
    return event;
  }
}

final class DataFrame extends RelayFrame {
  DataFrame({required this.peer, required this.channel, required this.payload});

  /// Upstream: destination device. Downstream: source device.
  final String peer;
  final ChannelId channel;
  final Uint8List payload;

  @override
  Uint8List encode() => concatBytes([
    [kRelayProtocolVersion, _typeData],
    uuidToBytes(peer),
    channel.bytes,
    payload,
  ]);

  @override
  bool operator ==(Object other) =>
      other is DataFrame &&
      other.peer == peer &&
      other.channel == channel &&
      constantTimeEquals(other.payload, payload);

  @override
  int get hashCode => Object.hash(peer, channel, Object.hashAll(payload));

  @override
  String toString() =>
      'DataFrame(peer: $peer, channel: $channel, ${payload.length} bytes)';
}

final class PresenceFrame extends RelayFrame {
  const PresenceFrame({required this.deviceId, required this.online});

  final String deviceId;
  final bool online;

  @override
  Uint8List encode() => concatBytes([
    [kRelayProtocolVersion, _typePresence],
    uuidToBytes(deviceId),
    [if (online) 1 else 0],
  ]);

  @override
  bool operator ==(Object other) =>
      other is PresenceFrame &&
      other.deviceId == deviceId &&
      other.online == online;

  @override
  int get hashCode => Object.hash(deviceId, online);

  @override
  String toString() => 'PresenceFrame(deviceId: $deviceId, online: $online)';
}

final class ErrorFrame extends RelayFrame {
  ErrorFrame({required this.code, this.deviceId = nilUuid, ChannelId? channel})
    : channel = channel ?? ChannelId.zero;

  final RelayErrorCode code;
  final String deviceId;
  final ChannelId channel;

  @override
  Uint8List encode() => concatBytes([
    [kRelayProtocolVersion, _typeError, code.wire >> 8, code.wire & 0xff],
    uuidToBytes(deviceId),
    channel.bytes,
  ]);

  @override
  bool operator ==(Object other) =>
      other is ErrorFrame &&
      other.code == code &&
      other.deviceId == deviceId &&
      other.channel == channel;

  @override
  int get hashCode => Object.hash(code, deviceId, channel);

  @override
  String toString() =>
      'ErrorFrame(code: ${code.name}, deviceId: $deviceId, channel: $channel)';
}

final class EventFrame extends RelayFrame {
  const EventFrame(this.event);

  /// For example `{"event": "pairing_removed", "agent_id": ...,
  /// "mobile_id": ..., "pairing_id": ...}`.
  final Map<String, String> event;

  @override
  Uint8List encode() => concatBytes([
    [kRelayProtocolVersion, _typeEvent],
    encodeCbor(event),
  ]);

  @override
  bool operator ==(Object other) {
    if (other is! EventFrame || other.event.length != event.length) {
      return false;
    }
    for (final entry in event.entries) {
      if (other.event[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
    event.entries.map((entry) => Object.hash(entry.key, entry.value)),
  );

  @override
  String toString() => 'EventFrame($event)';
}
