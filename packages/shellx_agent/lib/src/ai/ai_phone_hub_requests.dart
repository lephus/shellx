part of 'ai_phone_hub.dart';

/// What a V2-2b request answers (B4): nothing but `ok`, a [body] (JSON), a
/// refusal [code] — or a refusal with a body (`confirm`).
final class _Reply {
  const _Reply.ok([this.body]) : code = null;
  const _Reply.refuse(this.code, [this.body]);

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
}
