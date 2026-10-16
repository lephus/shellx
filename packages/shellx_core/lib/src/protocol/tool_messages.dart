part of 'messages.dart';

/// V2-4 E6: the `tool.*` protocol a desktop reports in `session.list.result`
/// (`tools`). A phone shows the Tool group only when it is at least 1.
const int kToolProtocol = 1;

/// V2-4 E7: the largest `data` of a `tool.data` or a `tool.ws.msg`, and the
/// largest `body` of a `tool.list.result` or a `tool.opened`. One sealed
/// batch ([kMaxSealedBatchBytes], 65 493 bytes) holds it with its envelope,
/// so a tool message never makes `SecureChannel.seal` throw (which would
/// drop the whole channel, terminals and AI included).
const int kToolMaxChunkBytes = 48 * 1024;

/// V2-4 E7, E9: the largest `head` of a `tool.req` or a `tool.res`: the
/// UTF-8 bytes of every name and value ([toolHeadBytes]).
const int kToolMaxHeadBytes = 32 * 1024;

/// V2-4 E9: at most this many headers (name/value pairs) in a `head`.
const int kToolMaxHeaders = 100;

/// V2-4 E9: the longest request target, in UTF-8 bytes.
const int kToolMaxTargetBytes = 8 * 1024;

/// V2-4 E9: the longest method.
const int kToolMaxMethodLength = 16;

/// V2-4 §4.1: how a stream ended (`tool.end`'s `code`). A newer peer may send
/// another word: [toolEndCode] reads it as [aborted].
abstract final class ToolCode {
  static const refused = 'refused';
  static const disabled = 'disabled';
  static const gone = 'gone';
  static const busy = 'busy';
  static const tooLarge = 'too_large';
  static const timeout = 'timeout';
  static const desktopClosed = 'desktop_closed';
  static const unavailable = 'unavailable';
  static const aborted = 'aborted';
  static const badRequest = 'bad_request';

  static const all = {
    refused,
    disabled,
    gone,
    busy,
    tooLarge,
    timeout,
    desktopClosed,
    unavailable,
    aborted,
    badRequest,
  };
}

/// [code] as this version reads it: null stays null (a WebSocket that
/// closed normally), a word it does not know is [ToolCode.aborted].
String? toolEndCode(String? code) =>
    code == null || ToolCode.all.contains(code) ? code : ToolCode.aborted;

/// The UTF-8 bytes of every name and value of [head] (what the transport
/// carries; a Latin-1 value byte above 0x7F takes two).
int toolHeadBytes(List<String> head) {
  var total = 0;
  for (final s in head) {
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c < 0x80) {
        total += 1;
      } else if (c < 0x800) {
        total += 2;
      } else if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
        total += 4; // a surrogate pair
        i++;
      } else {
        total += 3;
      }
    }
  }
  return total;
}

/// V2-4: messages between a phone and the personal web tools a desktop lets
/// it open (spec V2-4 §4). Headers travel as a flat `head` list `[name,
/// value, …]`, bodies and WebSocket payloads as byte strings, so the
/// transport sees depth 3 and never a float.
///
/// A `tool.*` message this version cannot read is skipped ([AppMessage.
/// fromMap] returns null), never fatal: only that stream ends, the channel
/// and its terminals stay. [toString] never shows a URL, a header or a body
/// (V2-4 E18).
sealed class ToolMessage extends AppMessage {
  const ToolMessage();

  @override
  String toString() => '$runtimeType(…)';

  /// The `tool.*` types this version reads; anything else under `tool.` is
  /// a newer peer's and is skipped.
  static ToolMessage? _fromMap(String t, _Fields f) {
    try {
      return switch (t) {
        'tool.list' => const ToolList(),
        'tool.list.result' => ToolListResult(
          available: f.boolean('available'),
          body: f.bytes('body'),
        ),
        'tool.open' => ToolOpen(rid: f.integer('rid'), tool: f.string('tool')),
        'tool.opened' => ToolOpened(
          rid: f.integer('rid'),
          ok: f.boolean('ok'),
          code: f.optionalString('code'),
          body: f.optionalBytes('body'),
        ),
        'tool.close' => ToolClose(tool: f.string('tool')),
        'tool.req' => ToolRequest(
          id: f.integer('id'),
          tool: f.string('tool'),
          method: f.string('m'),
          target: f.string('target'),
          head: f._strings('head'),
          alias: f.optionalInteger('alias'),
          ws: f.optionalBoolean('ws') ?? false,
          end: f.boolean('end'),
        ),
        'tool.res' => ToolResponse(
          id: f.integer('id'),
          status: f.integer('status'),
          head: f._strings('head'),
          end: f.boolean('end'),
        ),
        'tool.data' => ToolData(
          id: f.integer('id'),
          data: f.bytes('data'),
          end: f.boolean('end'),
        ),
        'tool.ack' => ToolAck(f._integers('acks')),
        'tool.ws.msg' => ToolWsMessage(
          id: f.integer('id'),
          data: f.bytes('data'),
          text: f.boolean('text'),
          fin: f.boolean('fin'),
        ),
        'tool.end' => ToolEnd(
          id: f.integer('id'),
          code: f.optionalString('code'),
          wsCode: f.optionalInteger('ws_code'),
          wsReason: f.optionalString('ws_reason'),
        ),
        _ => null,
      };
    } on FormatException {
      return null; // Skipped, never fatal (see [ToolMessage]).
    }
  }
}

extension on _Fields {
  /// A flat list of strings with an even length (`[name, value, …]`).
  List<String> _strings(String key) {
    final list = this.list(key);
    if (list.length.isOdd) throw FormatException('"$key" has an odd length');
    return [
      for (final item in list)
        item is String ? item : throw FormatException('"$key" not strings'),
    ];
  }

  /// A flat list of integers with an even length (`[id, n, …]`).
  List<int> _integers(String key) {
    final list = this.list(key);
    if (list.length.isOdd) throw FormatException('"$key" has an odd length');
    return [
      for (final item in list)
        item is int ? item : throw FormatException('"$key" not integers'),
    ];
  }
}

/// Phone → desktop: list the tools this phone may open and keep the list
/// current (the desktop sends `tool.list.result` again whenever it changes,
/// until the channel ends).
final class ToolList extends ToolMessage {
  const ToolList();
  @override
  String get type => 'tool.list';
  @override
  Map<String, Object?> toMap() => {'t': type};
}

/// Desktop → phone: the tools ([body], UTF-8 JSON, V2-4 §4.2). [available]
/// is false while the process that holds the relay has no list yet (a
/// background service that restarted before the window pushed one).
final class ToolListResult extends ToolMessage {
  const ToolListResult({required this.available, required this.body});
  final bool available;
  final Uint8List body;
  @override
  String get type => 'tool.list.result';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'available': available,
    'body': body,
  };
}

/// Phone → desktop: about to open [tool] (an id from the list, never a
/// URL): the desktop checks its flag and tries its port.
final class ToolOpen extends ToolMessage {
  const ToolOpen({required this.rid, required this.tool});
  final int rid;
  final String tool;
  @override
  String get type => 'tool.open';
  @override
  Map<String, Object?> toMap() => {'t': type, 'rid': rid, 'tool': tool};
}

/// Desktop → phone: how `tool.open` [rid] went. [code] when not [ok]
/// (`refused`, `disabled`, `gone`, `busy`, `unavailable`); [body] when [ok]:
/// UTF-8 JSON `{"v": 1, "tools": [{"id", "port", "path"}]}`, the tools of
/// the same workspace to serve on their ports (V2-4 E4), this one first.
final class ToolOpened extends ToolMessage {
  const ToolOpened({required this.rid, required this.ok, this.code, this.body});
  final int rid;
  final bool ok;
  final String? code;
  final Uint8List? body;
  @override
  String get type => 'tool.opened';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'rid': rid,
    'ok': ok,
    if (code != null) 'code': code,
    if (body != null) 'body': body,
  };
}

/// Phone → desktop: the page of [tool] was left; every stream of it from
/// this phone ends.
final class ToolClose extends ToolMessage {
  const ToolClose({required this.tool});
  final String tool;
  @override
  String get type => 'tool.close';
  @override
  Map<String, Object?> toMap() => {'t': type, 'tool': tool};
}

/// Phone → desktop: open stream [id] (a number the phone picks, unique on
/// its channel) to [tool]: [method] (`m` on the wire) on [target] (origin
/// form, `/path?query`) with [head]. [alias]: the port the phone serves the
/// tool on when it is not the tool's own (V2-4 E3). [ws]: a WebSocket
/// upgrade. [end]: there is no body (else `tool.data` follows).
final class ToolRequest extends ToolMessage {
  const ToolRequest({
    required this.id,
    required this.tool,
    required this.method,
    required this.target,
    required this.head,
    this.alias,
    this.ws = false,
    required this.end,
  });
  final int id;
  final String tool;
  final String method;
  final String target;
  final List<String> head;
  final int? alias;
  final bool ws;
  final bool end;
  @override
  String get type => 'tool.req';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'id': id,
    'tool': tool,
    'm': method,
    'target': target,
    'head': head,
    if (alias != null) 'alias': alias,
    if (ws) 'ws': true,
    'end': end,
  };
}

/// Desktop → phone: the response head of stream [id]; 101 when its
/// WebSocket is open. [end]: no body follows.
final class ToolResponse extends ToolMessage {
  const ToolResponse({
    required this.id,
    required this.status,
    required this.head,
    required this.end,
  });
  final int id;
  final int status;
  final List<String> head;
  final bool end;
  @override
  String get type => 'tool.res';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'id': id,
    'status': status,
    'head': head,
    'end': end,
  };
}

/// Both ways: a piece of the body of stream [id] (≤ [kToolMaxChunkBytes]);
/// [end]: the last one (it may be empty).
final class ToolData extends ToolMessage {
  const ToolData({required this.id, required this.data, required this.end});
  final int id;
  final Uint8List data;
  final bool end;
  @override
  String get type => 'tool.data';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'id': id,
    'data': data,
    'end': end,
  };
}

/// Both ways: `[id₁, n₁, id₂, n₂, …]`: every byte of stream idₖ up to nₖ
/// (cumulative) was taken; it opens the sender's window again.
final class ToolAck extends ToolMessage {
  const ToolAck(this.acks);
  final List<int> acks;
  @override
  String get type => 'tool.ack';
  @override
  Map<String, Object?> toMap() => {'t': type, 'acks': acks};
}

/// Both ways: a piece of a WebSocket message of stream [id] (UTF-8 for
/// [text]); a long message comes in several, the last with [fin].
final class ToolWsMessage extends ToolMessage {
  const ToolWsMessage({
    required this.id,
    required this.data,
    required this.text,
    required this.fin,
  });
  final int id;
  final Uint8List data;
  final bool text;
  final bool fin;
  @override
  String get type => 'tool.ws.msg';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'id': id,
    'data': data,
    'text': text,
    'fin': fin,
  };
}

/// Both ways: stream [id] is over. [code] ([ToolCode]) when it failed or was
/// cut; none when a WebSocket closed with [wsCode] and [wsReason].
final class ToolEnd extends ToolMessage {
  const ToolEnd({required this.id, this.code, this.wsCode, this.wsReason});
  final int id;
  final String? code;
  final int? wsCode;
  final String? wsReason;
  @override
  String get type => 'tool.end';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'id': id,
    if (code != null) 'code': code,
    if (wsCode != null) 'ws_code': wsCode,
    if (wsReason != null) 'ws_reason': wsReason,
  };
}
