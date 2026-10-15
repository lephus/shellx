// Frozen copy of lib/src/protocol/ai_messages.dart at d8ad686 (see
// messages_v2.dart). Never edit.
// ignore_for_file: type=lint
part of 'messages_v2.dart';

/// V2-2 D3: the `ai.*` protocol a desktop reports in `session.list.result`
/// (`ai`). A phone shows AI sessions only when it is at least 1.
const int kAiProtocol = 1;

/// V2-2 D4: the largest `body` of an `ai.*` message. One sealed batch
/// ([kMaxSealedBatchBytes], 65 493 bytes) holds it with the envelope and
/// room to spare, so an AI message never makes `SecureChannel.seal` throw
/// (which would drop the whole channel, terminals included).
const int kAiMaxBodyBytes = 48 * 1024;

/// V2-2 D4: the largest prompt a phone sends, in UTF-8 bytes.
const int kAiMaxPromptBytes = 32 * 1024;

/// V2-2: messages between a phone and the AI sessions of a desktop (spec
/// V2-2 §4). Their content travels as [body] bytes (UTF-8 JSON, read by
/// `package:shellx_ai/remote.dart`), so the transport sees a flat map of
/// depth 3 whatever the content is, and never a float.
///
/// An `ai.*` message this version cannot read is skipped ([AppMessage.
/// fromMap] returns null), never fatal: only the AI view resynchronises,
/// the channel and its terminals stay. [toString] never shows a prompt, a
/// folder or a body (V2-1 D20).
sealed class AiMessage extends AppMessage {
  const AiMessage();

  /// The AI session the message is about; null for `ai.list`,
  /// `ai.list.result`, `ai.open` and `ai.result` without a session.
  String? get sid;

  @override
  String toString() => '$runtimeType(…)';

  /// The `ai.*` types this version reads; anything else under `ai.` is a
  /// newer peer's and is skipped.
  static AiMessage? _fromMap(String t, _Fields f) {
    try {
      return switch (t) {
        'ai.list' => const AiList(),
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
        'ai.closed' => AiClosed(
          sid: f.string('sid'),
          reason: f.string('reason'),
        ),
        'ai.prompt' => AiPrompt(
          sid: f.string('sid'),
          rid: f.integer('rid'),
          text: f.string('text'),
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
        ),
        'ai.result' => AiResult(
          rid: f.integer('rid'),
          ok: f.boolean('ok'),
          code: f.optionalString('code'),
          sid: f.optionalString('sid'),
        ),
        _ => null,
      };
    } on FormatException {
      return null; // Skipped, never fatal (see [AiMessage]).
    }
  }
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

/// Phone → desktop: send [text] to [sid] (queued while a turn runs).
final class AiPrompt extends AiMessage {
  const AiPrompt({required this.sid, required this.rid, required this.text});
  @override
  final String sid;
  final int rid;
  final String text;
  @override
  String get type => 'ai.prompt';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'sid': sid,
    'rid': rid,
    'text': text,
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
/// the listing, never a path the phone made up).
final class AiOpen extends AiMessage {
  const AiOpen({required this.rid, required this.agent, required this.folder});
  final int rid;
  final String agent;
  final String folder;
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
  };
}

/// Desktop → phone: how request [rid] ended. [code] when not [ok]:
/// `stale`, `refused`, `queue_full`, `too_large`, `busy`, `not_found`,
/// `unavailable` (a newer desktop may send other words). [sid]: the new
/// session of an `ai.open`.
final class AiResult extends AiMessage {
  const AiResult({required this.rid, required this.ok, this.code, this.sid});
  final int rid;
  final bool ok;
  final String? code;
  @override
  final String? sid;
  @override
  String get type => 'ai.result';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'rid': rid,
    'ok': ok,
    if (code != null) 'code': code,
    if (sid != null) 'sid': sid,
  };
}
