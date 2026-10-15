part of 'messages.dart';

/// V2-2 D3, V2-2b B1: the `ai.*` protocol of the process that holds the
/// relay, reported in `session.list.result` (`ai`). 1: V2-2a. 2: V2-2b, whose
/// background service forwards `ai.*` verbatim (B2), so that whatever the
/// window offers in its listing (`f`) reaches it. A phone shows AI sessions
/// from 1 on, and uses a V2-2b feature only from 2 on, when the listing names
/// it.
const int kAiProtocol = 2;

/// V2-2 D4: the largest `body` of an `ai.*` message. One sealed batch
/// ([kMaxSealedBatchBytes], 65 493 bytes) holds it with the envelope and
/// room to spare, so an AI message never makes `SecureChannel.seal` throw
/// (which would drop the whole channel, terminals included).
const int kAiMaxBodyBytes = 48 * 1024;

/// V2-2 D4: the largest prompt a phone sends, in UTF-8 bytes.
const int kAiMaxPromptBytes = 32 * 1024;

/// V2-2b B12: the most image bytes one `ai.blob` carries.
const int kAiMaxBlobPartBytes = kAiMaxBodyBytes;

/// V2-2b B13: the most files one prompt mentions.
const int kAiMaxPromptFiles = 20;

/// V2-2b B13, B19: the longest path a phone names, in UTF-8 bytes.
const int kAiMaxPathBytes = 1024;

/// V2-2b B2: the map each `ai.*` message read from the wire came as (string
/// keys only), for [AiMessage.wire].
final _aiWireMaps = Expando<Map<String, Object?>>('ai wire map');

Map<String, Object?> _stringKeyed(Map<Object?, Object?> map) => {
  for (final MapEntry(:key, :value) in map.entries)
    if (key is String) key: value,
};

/// V2-2: messages between a phone and the AI sessions of a desktop (spec
/// V2-2 §4, V2-2b §4). Their content travels as `body` bytes (UTF-8 JSON,
/// read by `package:shellx_ai/remote.dart`), so the transport sees a flat map
/// of depth 3 whatever the content is, and never a float.
///
/// An `ai.*` message this version cannot read is skipped ([AppMessage.
/// fromMap] returns null), never fatal: only the AI view resynchronises,
/// the channel and its terminals stay. A kind this version does not know is
/// read as an [AiRaw] (B2). [toString] never shows a prompt, a folder or a
/// body (V2-1 D20).
sealed class AiMessage extends AppMessage {
  const AiMessage();

  /// The AI session the message is about; null for `ai.list`,
  /// `ai.list.result`, `ai.open`, `ai.blob` and `ai.result` without a
  /// session.
  String? get sid;

  /// V2-2b B2: what goes on the wire for this message — the map it was read
  /// from when it came from the wire (keys this version does not know
  /// included), else [toMap]. A process that forwards what it reads (the
  /// background service) so passes on what a newer peer said: a later
  /// addition needs only the window.
  Map<String, Object?> get wire => _aiWireMaps[this] ?? toMap();

  @override
  String toString() => '$runtimeType(…)';

  /// Every `ai.*` message read from the wire, with the map it came as
  /// ([wire]); null when a kind this version reads is malformed.
  static AiMessage? _fromMap(String t, _Fields f) {
    try {
      final message = _decode(t, f);
      _aiWireMaps[message] = _stringKeyed(f._map);
      return message;
    } on FormatException {
      return null; // Skipped, never fatal (see [AiMessage]).
    }
  }

  static AiMessage _decode(String t, _Fields f) => switch (t) {
    // Not the constant: each one read carries the map it came as.
    'ai.list' => AiList(),
    'ai.list.result' => AiListResult(
      available: f.boolean('available'),
      body: f.bytes('body'),
    ),
    'ai.attach' => AiAttach(
      sid: f.string('sid'),
      body: f.optionalBytes('body'),
    ),
    'ai.detach' => AiDetach(sid: f.string('sid')),
    'ai.ack' => AiAck(sid: f.string('sid'), seq: f.integer('seq')),
    'ai.earlier' => AiEarlier(
      sid: f.string('sid'),
      before: f.integer('before'),
    ),
    'ai.snapshot' => AiSnapshot(
      sid: f.string('sid'),
      seq: f.integer('seq'),
      body: f.bytes('body'),
    ),
    'ai.update' => AiUpdate(
      sid: f.string('sid'),
      seq: f.integer('seq'),
      body: f.bytes('body'),
    ),
    'ai.closed' => AiClosed(sid: f.string('sid'), reason: f.string('reason')),
    'ai.prompt' => AiPrompt(
      sid: f.string('sid'),
      rid: f.integer('rid'),
      text: f.string('text'),
      blobs: f.optionalIntegers('blobs') ?? const [],
      files: f.optionalStrings('files') ?? const [],
    ),
    'ai.answer' => AiAnswer(
      sid: f.string('sid'),
      rid: f.integer('rid'),
      permission: f.optionalInteger('permission'),
      option: f.optionalString('option'),
      ask: f.optionalInteger('ask'),
      action: f.optionalString('action'),
      body: f.optionalBytes('body'),
    ),
    'ai.cancel' => AiCancel(sid: f.string('sid'), rid: f.integer('rid')),
    'ai.stop' => AiForceStop(sid: f.string('sid'), rid: f.integer('rid')),
    'ai.unqueue' => AiUnqueue(
      sid: f.string('sid'),
      rid: f.integer('rid'),
      queued: f.integer('queued'),
    ),
    'ai.open' => AiOpen(
      rid: f.integer('rid'),
      agent: f.string('agent'),
      folder: f.string('folder'),
      resume: f.optionalString('resume'),
    ),
    'ai.result' => AiResult(
      rid: f.integer('rid'),
      ok: f.boolean('ok'),
      code: f.optionalString('code'),
      sid: f.optionalString('sid'),
      body: f.optionalBytes('body'),
    ),
    'ai.config.get' => AiConfigGet(sid: f.string('sid'), rid: f.integer('rid')),
    'ai.config' => AiConfigSet(
      sid: f.string('sid'),
      rid: f.integer('rid'),
      body: f.bytes('body'),
    ),
    'ai.blob' => AiBlob(
      rid: f.integer('rid'),
      blob: f.integer('blob'),
      part: f.integer('part'),
      parts: f.integer('parts'),
      mime: f.optionalString('mime'),
      data: f.bytes('data'),
    ),
    'ai.files' => AiFiles(
      sid: f.string('sid'),
      rid: f.integer('rid'),
      query: f.string('q'),
    ),
    'ai.item' => AiItemPart(
      sid: f.string('sid'),
      rid: f.integer('rid'),
      index: f.integer('i'),
      part: f.integer('part'),
    ),
    'ai.history' => AiHistory(
      sid: f.string('sid'),
      rid: f.integer('rid'),
      cursor: f.optionalString('cursor'),
    ),
    'ai.folder' => AiFolder(
      sid: f.string('sid'),
      rid: f.integer('rid'),
      folder: f.string('folder'),
    ),
    'ai.changes' => AiChanges(
      sid: f.string('sid'),
      rid: f.integer('rid'),
      turn: f.optionalInteger('turn'),
    ),
    'ai.diff' => AiDiff(
      sid: f.string('sid'),
      rid: f.integer('rid'),
      turn: f.optionalInteger('turn'),
      path: f.string('path'),
    ),
    'ai.revert' => AiRevert(
      sid: f.string('sid'),
      rid: f.integer('rid'),
      turn: f.optionalInteger('turn'),
      keep: f.optionalString('keep'),
    ),
    _ => AiRaw._(t, sid: f.loose<String>('sid'), rid: f.loose<int>('rid')),
  };
}

/// Phone → desktop: list the AI sessions and keep the list current (the
/// desktop sends `ai.list.result` again whenever it changes, until the
/// channel ends).
final class AiList extends AiMessage {
  const AiList();
  @override
  String? get sid => null;
  @override
  String get type => 'ai.list';
  @override
  Map<String, Object?> toMap() => {'t': type};
}

/// Desktop → phone: the AI sessions, agents and folders ([body], an
/// `AiListing`); [available] is false while no window serves AI (the
/// desktop app is closed and only the background service runs).
final class AiListResult extends AiMessage {
  const AiListResult({required this.available, required this.body});
  final bool available;
  final Uint8List body;
  @override
  String? get sid => null;
  @override
  String get type => 'ai.list.result';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'available': available,
    'body': body,
  };
}

/// Phone → desktop: mirror session [sid]. [body] (an `AiHave`) says what
/// the phone already holds, so a re-attach only brings what changed.
final class AiAttach extends AiMessage {
  const AiAttach({required this.sid, this.body});
  @override
  final String sid;
  final Uint8List? body;
  @override
  String get type => 'ai.attach';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'sid': sid,
    if (body != null) 'body': body,
  };
}

/// Phone → desktop: stop mirroring [sid].
final class AiDetach extends AiMessage {
  const AiDetach({required this.sid});
  @override
  final String sid;
  @override
  String get type => 'ai.detach';
  @override
  Map<String, Object?> toMap() => {'t': type, 'sid': sid};
}

/// Phone → desktop: every mirror message of [sid] up to [seq] arrived
/// (cumulative); it opens the desktop's send window.
final class AiAck extends AiMessage {
  const AiAck({required this.sid, required this.seq});
  @override
  final String sid;
  final int seq;
  @override
  String get type => 'ai.ack';
  @override
  Map<String, Object?> toMap() => {'t': type, 'sid': sid, 'seq': seq};
}

/// Phone → desktop: the items of [sid] before index [before] ("load
/// earlier"); answered with an `ai.update` page.
final class AiEarlier extends AiMessage {
  const AiEarlier({required this.sid, required this.before});
  @override
  final String sid;
  final int before;
  @override
  String get type => 'ai.earlier';
  @override
  Map<String, Object?> toMap() => {'t': type, 'sid': sid, 'before': before};
}

/// Desktop → phone: the first mirror message after an attach.
final class AiSnapshot extends AiMessage {
  const AiSnapshot({required this.sid, required this.seq, required this.body});
  @override
  final String sid;
  final int seq;
  final Uint8List body;
  @override
  String get type => 'ai.snapshot';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'sid': sid,
    'seq': seq,
    'body': body,
  };
}

/// Desktop → phone: what changed, a continuation, or an earlier page.
final class AiUpdate extends AiMessage {
  const AiUpdate({required this.sid, required this.seq, required this.body});
  @override
  final String sid;
  final int seq;
  final Uint8List body;
  @override
  String get type => 'ai.update';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'sid': sid,
    'seq': seq,
    'body': body,
  };
}

/// Desktop → phone: [sid] is no longer mirrored. [reason]: `gone` (the tab
/// closed), `desktop_closed` (the window quit), `unavailable` (no window
/// serves AI); a newer desktop may send other words.
final class AiClosed extends AiMessage {
  const AiClosed({required this.sid, required this.reason});
  @override
  final String sid;
  final String reason;
  @override
  String get type => 'ai.closed';
  @override
  Map<String, Object?> toMap() => {'t': type, 'sid': sid, 'reason': reason};
}

/// Phone → desktop: send [text] to [sid] (queued while a turn runs), with
/// the images it uploaded ([blobs], V2-2b B12) and the files it mentions
/// ([files], B13). An older desktop reads only [text]: a phone sends the two
/// lists only to a window whose listing offers them (B1).
final class AiPrompt extends AiMessage {
  const AiPrompt({
    required this.sid,
    required this.rid,
    required this.text,
    this.blobs = const [],
    this.files = const [],
  });
  @override
  final String sid;
  final int rid;
  final String text;

  /// Image numbers of this phone's `ai.blob` uploads.
  final List<int> blobs;

  /// Paths relative to the session folder, as `ai.files` offered them.
  final List<String> files;
  @override
  String get type => 'ai.prompt';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'sid': sid,
    'rid': rid,
    'text': text,
    if (blobs.isNotEmpty) 'blobs': blobs,
    if (files.isNotEmpty) 'files': files,
  };
}

/// Phone → desktop: the user's answer. Either [permission] with the
/// [option] picked, or [ask] with [action] (`accept`, `decline`,
/// `cancel`) and, for `accept`, the form values as [body] (JSON).
final class AiAnswer extends AiMessage {
  const AiAnswer({
    required this.sid,
    required this.rid,
    this.permission,
    this.option,
    this.ask,
    this.action,
    this.body,
  });
  @override
  final String sid;
  final int rid;
  final int? permission;
  final String? option;
  final int? ask;
  final String? action;
  final Uint8List? body;
  @override
  String get type => 'ai.answer';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'sid': sid,
    'rid': rid,
    if (permission != null) 'permission': permission,
    if (option != null) 'option': option,
    if (ask != null) 'ask': ask,
    if (action != null) 'action': action,
    if (body != null) 'body': body,
  };
}

/// Phone → desktop: stop the turn of [sid] (the desktop's Esc).
final class AiCancel extends AiMessage {
  const AiCancel({required this.sid, required this.rid});
  @override
  final String sid;
  final int rid;
  @override
  String get type => 'ai.cancel';
  @override
  Map<String, Object?> toMap() => {'t': type, 'sid': sid, 'rid': rid};
}

/// Phone → desktop: "Dừng hẳn" (only once the desktop offers it).
final class AiForceStop extends AiMessage {
  const AiForceStop({required this.sid, required this.rid});
  @override
  final String sid;
  final int rid;
  @override
  String get type => 'ai.stop';
  @override
  Map<String, Object?> toMap() => {'t': type, 'sid': sid, 'rid': rid};
}

/// Phone → desktop: drop queued prompt [queued] of [sid].
final class AiUnqueue extends AiMessage {
  const AiUnqueue({required this.sid, required this.rid, required this.queued});
  @override
  final String sid;
  final int rid;
  final int queued;
  @override
  String get type => 'ai.unqueue';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'sid': sid,
    'rid': rid,
    'queued': queued,
  };
}

/// Phone → desktop: a new AI session with [agent] in [folder] (a key from
/// the listing, never a path the phone made up). With [resume] (V2-2b B17)
/// it reopens that earlier session of the agent instead (an id `ai.history`
/// gave); an older desktop ignores it, so a phone sends it only to a window
/// that offers history.
final class AiOpen extends AiMessage {
  const AiOpen({
    required this.rid,
    required this.agent,
    required this.folder,
    this.resume,
  });
  final int rid;
  final String agent;
  final String folder;
  final String? resume;
  @override
  String? get sid => null;
  @override
  String get type => 'ai.open';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'rid': rid,
    'agent': agent,
    'folder': folder,
    'resume': ?resume,
  };
}

/// Desktop → phone: how request [rid] ended. [code] when not [ok]:
/// `stale`, `refused`, `queue_full`, `too_large`, `busy`, `not_found`,
/// `unavailable`, `on_computer`, and since V2-2b `no_images`, `confirm`,
/// `busy_turn`, `not_ready`, `undo_off`, `too_big` (a newer desktop may send
/// other words). [sid]: the new session of an `ai.open`. [body] (V2-2b B4):
/// what a V2-2b request asked for, as JSON; an older phone ignores it.
final class AiResult extends AiMessage {
  const AiResult({
    required this.rid,
    required this.ok,
    this.code,
    this.sid,
    this.body,
  });
  final int rid;
  final bool ok;
  final String? code;
  @override
  final String? sid;
  final Uint8List? body;
  @override
  String get type => 'ai.result';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'rid': rid,
    'ok': ok,
    if (code != null) 'code': code,
    if (sid != null) 'sid': sid,
    if (body != null) 'body': body,
  };
}

/// Phone → desktop (V2-2b B11): the mode, model and thinking choices of
/// [sid] a phone may make (`ai.result` [AiResult.body]: an `AiConfigView`).
final class AiConfigGet extends AiMessage {
  const AiConfigGet({required this.sid, required this.rid});
  @override
  final String sid;
  final int rid;
  @override
  String get type => 'ai.config.get';
  @override
  Map<String, Object?> toMap() => {'t': type, 'sid': sid, 'rid': rid};
}

/// Phone → desktop (V2-2b B11): one choice for [sid]; [body] is JSON
/// `{"id", "value"}` (a config option) or `{"mode"}` (an agent with only
/// modes). The desktop checks it against the choices it offers now.
final class AiConfigSet extends AiMessage {
  const AiConfigSet({required this.sid, required this.rid, required this.body});
  @override
  final String sid;
  final int rid;
  final Uint8List body;
  @override
  String get type => 'ai.config';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'sid': sid,
    'rid': rid,
    'body': body,
  };
}

/// Phone → desktop (V2-2b B12): part [part] of [parts] of image [blob] (a
/// number this phone chose), at most [kAiMaxBlobPartBytes] of [data]; [mime]
/// on part 0. Each part gets its own `ai.result`.
final class AiBlob extends AiMessage {
  const AiBlob({
    required this.rid,
    required this.blob,
    required this.part,
    required this.parts,
    required this.data,
    this.mime,
  });
  final int rid;
  final int blob;
  final int part;
  final int parts;
  final String? mime;
  final Uint8List data;
  @override
  String? get sid => null;
  @override
  String get type => 'ai.blob';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'rid': rid,
    'blob': blob,
    'part': part,
    'parts': parts,
    'mime': ?mime,
    'data': data,
  };
}

/// Phone → desktop (V2-2b B13): the files of [sid]'s folder that match
/// [query], for `@` (`ai.result` body `{"files": [...]}`).
final class AiFiles extends AiMessage {
  const AiFiles({required this.sid, required this.rid, required this.query});
  @override
  final String sid;
  final int rid;
  final String query;
  @override
  String get type => 'ai.files';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'sid': sid,
    'rid': rid,
    'q': query,
  };
}

/// Phone → desktop (V2-2b B16): slice [part] of item [index] of [sid] in
/// full (`ai.result` body `{"i", "r", "part", "parts", "text"}`).
final class AiItemPart extends AiMessage {
  const AiItemPart({
    required this.sid,
    required this.rid,
    required this.index,
    required this.part,
  });
  @override
  final String sid;
  final int rid;
  final int index;
  final int part;
  @override
  String get type => 'ai.item';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'sid': sid,
    'rid': rid,
    'i': index,
    'part': part,
  };
}

/// Phone → desktop (V2-2b B17): a page of the earlier sessions of [sid]'s
/// agent in its folder, from [cursor] (`ai.result` body `{"sessions",
/// "next"?, "current"?}`).
final class AiHistory extends AiMessage {
  const AiHistory({required this.sid, required this.rid, this.cursor});
  @override
  final String sid;
  final int rid;
  final String? cursor;
  @override
  String get type => 'ai.history';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'sid': sid,
    'rid': rid,
    'cursor': ?cursor,
  };
}

/// Phone → desktop (V2-2b B18): run [sid], a tab without a folder, in
/// [folder] (a key from the listing).
final class AiFolder extends AiMessage {
  const AiFolder({required this.sid, required this.rid, required this.folder});
  @override
  final String sid;
  final int rid;
  final String folder;
  @override
  String get type => 'ai.folder';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'sid': sid,
    'rid': rid,
    'folder': folder,
  };
}

/// Phone → desktop (V2-2b B19): the files changed since [turn] began (null:
/// since the session's first turn) — `ai.result` body: an `AiChangesView`.
final class AiChanges extends AiMessage {
  const AiChanges({required this.sid, required this.rid, this.turn});
  @override
  final String sid;
  final int rid;
  final int? turn;
  @override
  String get type => 'ai.changes';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'sid': sid,
    'rid': rid,
    'turn': ?turn,
  };
}

/// Phone → desktop (V2-2b B19): the diff of [path] (one of `ai.changes`'
/// files) since [turn] began (null: since the session's first turn).
final class AiDiff extends AiMessage {
  const AiDiff({
    required this.sid,
    required this.rid,
    required this.path,
    this.turn,
  });
  @override
  final String sid;
  final int rid;
  final int? turn;
  final String path;
  @override
  String get type => 'ai.diff';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'sid': sid,
    'rid': rid,
    'turn': ?turn,
    'path': path,
  };
}

/// Phone → desktop (V2-2b B19): put the files changed since [turn] began
/// back (null: since the session's first turn). The desktop works it out
/// again now; when some files changed after the turn it answers `confirm`
/// (with them) unless [keep] says what to do: `clean` (only the others) or
/// `all`.
final class AiRevert extends AiMessage {
  const AiRevert({required this.sid, required this.rid, this.turn, this.keep});
  @override
  final String sid;
  final int rid;
  final int? turn;
  final String? keep;
  @override
  String get type => 'ai.revert';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'sid': sid,
    'rid': rid,
    'turn': ?turn,
    'keep': ?keep,
  };
}

/// V2-2b B2: an `ai.*` kind this version does not know (a newer peer's),
/// read so that the background service passes it on as it came ([wire]),
/// the way it came: from a phone to the window, from the window to a phone.
/// A window and a phone ignore it, but for a request with an integer [rid],
/// which gets its one `ai.result` (`refused` from a window, `unavailable`
/// where none serves AI).
final class AiRaw extends AiMessage {
  AiRaw._(this.type, {this.sid, this.rid});
  @override
  final String type;
  @override
  final String? sid;
  final int? rid;
  @override
  Map<String, Object?> toMap() => _aiWireMaps[this] ?? {'t': type};
}
