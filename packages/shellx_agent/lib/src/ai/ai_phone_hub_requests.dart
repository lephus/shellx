part of 'ai_phone_hub.dart';

/// What a V2-2b request answers (B4): nothing but `ok`, a [body] (JSON), a
/// refusal [code] — or a refusal with a body (`confirm`).
final class _Reply {
  const _Reply.ok([this.body]) : code = null;
  const _Reply.refuse(this.code, [this.body]);

  final String? code;
  final Uint8List? body;
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
}
