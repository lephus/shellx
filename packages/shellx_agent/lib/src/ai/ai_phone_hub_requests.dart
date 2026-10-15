part of 'ai_phone_hub.dart';

/// What a V2-2b request answers (B4): nothing but `ok`, a [body] (JSON), a
/// refusal [code] — or a refusal with a body (`confirm`).
final class _Reply {
  const _Reply.ok([this.body]) : code = null;
  const _Reply.refuse(String this.code, [this.body]);

  final String? code;
  final Uint8List? body;
}

/// How long a phone's full item is kept for its next slices, and how many a
/// phone has at most (V2-2b B16): at most 4 × 2 MiB of text per phone.
const _fullItemKeep = Duration(seconds: 60);
const _fullItemsPerPhone = 4;

/// One item made in full for one phone (V2-2b B16): the item it was made of,
/// at [rev] (F21: a runtime that replaced the session's has other items under
/// the same session id and index, whatever their rev), its JSON text and where
/// its slices end.
final class _FullItem {
  _FullItem(this.item, this.rev, this.text, this.ends, this.at);

  final TimelineItem item;
  final int rev;
  final String text;
  final List<int> ends;

  /// When a slice of it was last asked for.
  DateTime at;
}

/// The V2-2b requests (B4, B11, …): each answers with one `ai.result`, a
/// body maybe, checked against the window as it is when it runs.
extension _AiPhoneRequests on AiPhoneHub {
  /// One V2-2b request about [sid]: [run] works it out on the session's
  /// control as the window has it now, and one `ai.result` goes back to
  /// [phone] only (a request belongs to the channel that made it). A session
  /// that is not there is `not_found`; the window's own refusal
  /// ([AiRefused]) its code and body; anything else the window's code throws
  /// `refused` (nothing escapes into its zone). A body over
  /// [kAiMaxBodyBytes] is never sent — it would drop the phone's whole
  /// channel, terminals included —: `too_big` instead.
  Future<void> _ask(
    String mobileId,
    _Phone phone,
    String sid,
    int rid,
    Future<_Reply> Function(AiControl control) run,
  ) async {
    _Reply reply;
    try {
      final control = _controlOf(sid);
      reply = control == null
          ? const _Reply.refuse('not_found')
          : await run(control);
    } on AiRefused catch (refusal) {
      reply = _Reply.refuse(refusal.code, refusal.body);
    } on Object {
      reply = const _Reply.refuse('refused');
    }
    final body = reply.body;
    if (body != null && body.length > kAiMaxBodyBytes) {
      reply = const _Reply.refuse('too_big');
    }
    _send(
      mobileId,
      AiResult(
        rid: rid,
        ok: reply.code == null,
        code: reply.code,
        body: reply.body,
      ),
      phone,
    );
  }

  /// V2-2b B11: the choices of [sid] a phone may make ([aiConfigViewOf]).
  void _configGet(String mobileId, _Phone phone, String sid, int rid) =>
      unawaited(
        _ask(
          mobileId,
          phone,
          sid,
          rid,
          (c) async => _Reply.ok(encodeConfigView(aiConfigViewOf(c.state))),
        ),
      );

  /// V2-2b B11, R16: one choice, checked against what the session offers now
  /// — a choice acting without asking is the computer's (`on_computer`) —,
  /// then set as the computer's chip sets it (the window checks it once
  /// more). The agent saying no is `refused`.
  void _configSet(String mobileId, _Phone phone, AiConfigSet m) => unawaited(
    _ask(mobileId, phone, m.sid, m.rid, (c) async {
      final j = decodeBody(m.body);
      if (j == null) return const _Reply.refuse('refused');
      final mode = j['mode'];
      if (mode is String) {
        final no = aiModeRefusal(c.state, mode);
        if (no != null) return _Reply.refuse(no);
        await c.setMode(mode);
        return const _Reply.ok();
      }
      final id = j['id'];
      final value = j['value'];
      if (id is! String) return const _Reply.refuse('refused');
      final no = aiConfigRefusal(c.state, id, value);
      if (no != null) return _Reply.refuse(no);
      await c.setConfig(id, value!);
      return const _Reply.ok();
    }),
  );

  /// V2-2b B12: one part of an image a phone uploads for its next prompt;
  /// every part gets its own `ai.result`. Not about a session: the image is
  /// the phone's until a prompt takes it.
  void _blob(String mobileId, AiBlob part) {
    String? code;
    try {
      code = _blobs.put(mobileId, part);
    } on Object {
      code = 'refused';
    }
    _send(mobileId, AiResult(rid: part.rid, ok: code == null, code: code));
  }

  /// V2-2b B13: the files of [f]'s session folder matching its query, for
  /// the phone's `@` — at most eight, best first, as the composer offers
  /// them. A path the phone could not send back (R18, or over
  /// [kAiMaxPathBytes] once in JSON: eight always fit one body) is left out.
  void _files(String mobileId, _Phone phone, AiFiles f) => unawaited(
    _ask(mobileId, phone, f.sid, f.rid, (c) async {
      if (utf8Length(f.query) > _maxFileQueryBytes) {
        return const _Reply.refuse('too_large');
      }
      final files = await c.files(f.query);
      return _Reply.ok(
        encodeBody({
          'files': files
              .where(
                (path) =>
                    _isRelativePath(path) &&
                    utf8Length(jsonEncode(path)) <= kAiMaxPathBytes,
              )
              .take(_maxFilesShown)
              .toList(),
        }),
      );
    }),
  );

  /// V2-2b B16, R14: slice [AiItemPart.part] of item [AiItemPart.index] in
  /// full. The item is made once per rev and kept for the phone's next
  /// slices ([_fullItemKeep], [_fullItemsPerPhone]) — for that very item
  /// only (F21) —; its body says the rev (`r`), so a phone that sees it
  /// change (a command still running) starts again. An item over
  /// [kAiFullItemBytes] is read on the computer (`too_big`); one with nothing
  /// more to show, an index or a part that is not there, `refused`.
  void _fullItem(String mobileId, _Phone phone, AiItemPart m) => unawaited(
    _ask(mobileId, phone, m.sid, m.rid, (c) async {
      final items = c.state.timeline.items;
      if (m.index < 0 || m.index >= items.length) {
        return const _Reply.refuse('refused');
      }
      final item = items[m.index];
      final now = _now();
      phone.items.removeWhere((_, f) {
        final idle = now.difference(f.at);
        return idle > _fullItemKeep || idle.isNegative;
      });
      final key = '${m.sid}/${m.index}';
      var full = phone.items[key];
      // Kept for the very item, at its rev: a session id outlives its runtime
      // (a folder changed, an agent switched), and the new runtime's item at
      // the same index can have the same rev with other content.
      if (full == null || !identical(full.item, item) || full.rev != item.rev) {
        final text = aiFullItemJson(item);
        if (text == null) return const _Reply.refuse('refused');
        if (utf8Length(text) > kAiFullItemBytes) {
          return const _Reply.refuse('too_big');
        }
        full = _FullItem(item, item.rev, text, aiSliceEnds(text), now);
      }
      // The one asked for last is the one kept longest.
      phone.items
        ..remove(key)
        ..[key] = full;
      while (phone.items.length > _fullItemsPerPhone) {
        phone.items.remove(phone.items.keys.first);
      }
      full.at = now;
      final parts = full.ends.length;
      if (m.part < 0 || m.part >= parts) return const _Reply.refuse('refused');
      final start = m.part == 0 ? 0 : full.ends[m.part - 1];
      return _Reply.ok(
        encodeBody({
          'i': m.index,
          'r': full.rev,
          'part': m.part,
          'parts': parts,
          'text': full.text.substring(start, full.ends[m.part]),
        }),
      );
    }),
  );

  /// V2-2b B17: a page of the agent's earlier sessions in the session's
  /// folder. Only while the agent runs (`not_ready` before it does: the phone
  /// asks again once it runs); an agent without `session/list` is
  /// `refused`. An agent page longer than [kAiHistoryPage] is served from
  /// here in pages of that many, under the hub's own cursor, so that the
  /// phone skips none; the agent's next cursor comes after the last of them.
  void _history(String mobileId, _Phone phone, AiHistory h) {
    unawaited(
      _ask(mobileId, phone, h.sid, h.rid, (c) async {
        final s = c.state;
        if (s.phase != AgentPhase.ready && s.phase != AgentPhase.running) {
          return const _Reply.refuse('not_ready');
        }
        if (!s.capabilities.listSessions) {
          return const _Reply.refuse('refused');
        }
        final cursor = h.cursor;
        final held = phone.historyRest;
        final List<SessionSummary> sessions;
        final String? after;
        if (held != null && held.sid == h.sid && held.cursor == cursor) {
          sessions = held.rest;
          after = held.next;
        } else {
          if (cursor != null &&
              (cursor.isEmpty || utf8Length(cursor) > kAiHistoryCursorBytes)) {
            return const _Reply.refuse('refused');
          }
          final page = await c.listSessions(cursor: cursor);
          if (page == null) return const _Reply.refuse('refused');
          sessions = page.sessions;
          after = page.nextCursor;
        }
        phone.historyRest = null;
        var next = after;
        if (sessions.length > kAiHistoryPage) {
          final mine = 'shellx-rest-${_nextHistoryRest++}';
          phone.historyRest = (
            sid: h.sid,
            cursor: mine,
            rest: sessions.sublist(kAiHistoryPage),
            next: after,
          );
          next = mine;
        }
        return _Reply.ok(
          encodeHistoryPage(
            ListSessionsResult(
              sessions: sessions.take(kAiHistoryPage).toList(),
              nextCursor: next,
            ),
            current: s.sessionId,
          ),
        );
      }),
    );
  }

  /// V2-2b B18: the folder of a tab that has none (V2-2 D14 `no_folder`): a
  /// key the window offers now (D9, R18), never a path. The window then does
  /// what the tab's own "Use this folder" does, and the hub looks at its tabs
  /// at once: a phone parked on the session attaches again and its agent
  /// starts (V2-2 §13 D15). One answer, to [phone] only.
  Future<void> _folder(String mobileId, _Phone phone, AiFolder f) async {
    String? code;
    try {
      final paneId = _paneOf(f.sid);
      final entry = paneId == null
          ? null
          : _source.sessions.where((e) => e.paneId == paneId).firstOrNull;
      if (paneId == null || entry == null) {
        code = 'not_found';
      } else if (entry.unavailable != AiRemoteState.noFolder ||
          !_source.folders.any((x) => x.key == f.folder)) {
        code = 'refused';
      } else if (!await _source.chooseFolder(paneId, f.folder)) {
        code = 'refused';
      } else {
        _rescan();
      }
    } on Object {
      code = 'refused'; // the window's code failed: still one answer
    }
    _send(mobileId, AiResult(rid: f.rid, ok: code == null, code: code), phone);
  }
}

/// V2-2b B13: the longest `@` query a phone may ask (a token, not a text).
const int _maxFileQueryBytes = 200;

/// V2-2b B13: the most files one `ai.files` answers.
const int _maxFilesShown = 8;

final _drive = RegExp('^[A-Za-z]:');

/// V2-2b R18: whether [path] names a file inside a session's folder as `@`
/// offers it — relative, `/` between its parts and none of them empty, `.`
/// or `..`, at most [kAiMaxPathBytes]. The window checks it again (offered,
/// inside the folder, there).
bool _isRelativePath(String path) {
  if (path.isEmpty ||
      utf8Length(path) > kAiMaxPathBytes ||
      path.startsWith('/') ||
      path.contains(r'\') ||
      path.contains('\u0000') ||
      _drive.hasMatch(path)) {
    return false;
  }
  return path
      .split('/')
      .every((part) => part.isNotEmpty && part != '.' && part != '..');
}
