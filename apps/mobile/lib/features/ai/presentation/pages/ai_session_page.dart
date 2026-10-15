import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/ai/domain/ai_attachments.dart';
import 'package:shellx_mobile/features/ai/domain/ai_image_source.dart';
import 'package:shellx_mobile/features/ai/domain/ai_words.dart';
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_dictation.dart';
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_session_controller.dart';
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_attach_sheet.dart';
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_chooser.dart';
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_config_sheet.dart';
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_dock.dart';
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_folder_chooser.dart';
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_history_sheet.dart';
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_items.dart';
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_timeline.dart';
import 'package:shellx_mobile/features/app/connection_banner.dart';
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';
import 'package:shellx_mobile/features/voice/presentation/controllers/voice_composer_controller.dart'
    show VoiceIssue, VoicePhase;
import 'package:shellx_mobile/shared/shared.dart';

/// V2-2 §5.2: one AI session of a computer — the conversation, then the
/// dock: plan, the waiting permission or question, the queue and the text
/// field. Mirrors the session while open.
///
/// The page is made of four parts that each watch what they show (the header and its clock, the strips,
/// the conversation, the dock), so a second of the clock does not rebuild the conversation and a
/// message on its way does not rebuild the header.
@RoutePage()
class AiSessionPage extends StatefulWidget {
  const AiSessionPage({super.key, required this.agentId, required this.machineName, required this.sid});

  final String agentId;
  final String machineName;
  final String sid;

  @override
  State<AiSessionPage> createState() => _AiSessionPageState();
}

class _AiSessionPageState extends State<AiSessionPage> {
  late final AiSessionController _controller = getIt<AiSessionController>(param1: widget.agentId, param2: widget.sid);

  /// The text field starts from the draft this session was left with, and keeps the draft as it changes
  /// (in memory only): a page left by mistake and opened again does not cost a sentence.
  late final _text = TextEditingController(text: _controller.draft);
  final _jumpTo = ValueNotifier<int?>(null);
  late final AppLifecycleListener _lifecycle;
  String _kept = '';

  /// V2-2b B12: the images of the next message. In memory only, like the draft's text, and not kept when the page
  /// is left.
  final List<AiPickedImage> _images = [];

  /// V2-2b B13: the files picked from the `@` suggestions; those still mentioned in the text go with the message.
  final Set<String> _mentions = {};

  /// The computer's files for the `@` being typed; asked [_suggestPause] after the last keystroke.
  List<String> _suggestions = const [];
  Timer? _suggestTimer;
  var _suggestAsks = 0;
  static const Duration _suggestPause = Duration(milliseconds: 150);

  /// What the composer says of the last images (a type or size the computer does not take, an upload that did not
  /// go, a picker that did not open); null: nothing.
  String? _note;

  /// V2-2b B14: speaking into the field. Made at the first tap of the mic (a page that never hears needs no
  /// recognizer), it lives as long as the page.
  AiDictation? _dictation;

  /// Stops the dictation once the session is not live (a lost channel, a session closed).
  late final void Function() _stopWhenNotLive;

  /// V2-2b B16: the whole form of a question too big for the mirror is on its way.
  var _loadingForm = false;

  @override
  void initState() {
    super.initState();
    _kept = _text.text;
    _text.addListener(_keepDraft);
    _text.addListener(_lookForMention);
    // The clock of the turn runs only while the app is on screen: `inactive` (the notification shade, a
    // dialog of the system) still shows it, `hidden` and `paused` do not.
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _controller.setForeground(state == AppLifecycleState.resumed || state == AppLifecycleState.inactive);
        // B14: the mic hears only while the app is in front (a call, the shade, the background stop it).
        if (state != AppLifecycleState.resumed) _dictation?.stop();
      },
    );
    _stopWhenNotLive = effect(() {
      _controller.version.value;
      if (_controller.linkState != AiLinkState.live) untracked(() => _dictation?.stop());
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _stopWhenNotLive();
    _dictation?.dispose();
    _suggestTimer?.cancel();
    _text.removeListener(_lookForMention);
    _text.removeListener(_keepDraft);
    _controller.dispose();
    _text.dispose();
    _jumpTo.dispose();
    super.dispose();
  }

  void _keepDraft() {
    final text = _text.text;
    if (text == _kept) return; // a move of the cursor is no change of the text
    _kept = text;
    _controller.keepDraft(text);
  }

  /// V2-2b B22: "Mở danh sách phiên" — the computer's AI sessions, the one picked in this page's place.
  Future<void> _openList() async {
    final listing = _controller.listing;
    final ai = _controller.ai;
    if (listing == null || ai == null) return;
    await openAiChooser(
      context,
      agentId: widget.agentId,
      machineName: widget.machineName,
      ai: ai,
      listing: listing,
      replace: true,
    );
  }

  void _say(String? code, {bool answer = false}) {
    if (code == null || !mounted) return;
    final text = AiWords.failure(S.of(context), code, answer: answer, agent: _controller.head?.agentName);
    if (text != null) _controller.popupHandler.showError(title: text);
  }

  Future<void> _send() async {
    // B14: a message that goes takes the mic's words with it; what it would hear next is for a new one.
    _dictation?.stop();
    final text = _text.text;
    final images = List.of(_images);
    // B13: the files still mentioned in the text go with it; a mention deleted from the text does not.
    final files = _controller.can(AiFeature.files) ? AiMentions.stillMentioned(text, _mentions) : const <String>[];
    // F39: the note was about the last pick or the last Send; this Send says its own, below, and only for its own
    // images. A note kept would still say "Retry" after the images of this Send got through and the message
    // failed (it may have landed, D13, or can never go).
    if (_note != null) setState(() => _note = null);
    // While it is on its way the message is no draft: a page opened again before the answer comes back
    // must not start with it (and send it twice). A message that did not go is put back below.
    _controller.keepDraft('');
    final code = await _controller.send(text, images: images, files: files);
    if (!mounted) {
      // The page was left while the message was on its way. Gone, it is nobody's draft; refused, it is the
      // user's again, unless a page opened since has a draft of its own.
      if (code != null && _controller.draft.isEmpty) _controller.keepDraft(text);
      return;
    }
    // The text and the images stay when the message did not go (or may not have): the user decides what to do.
    if (code == null) {
      if (_text.text == text) _text.clear();
      setState(() {
        _images.removeWhere(images.contains);
        _mentions.clear();
        _note = null;
      });
    } else {
      _controller.keepDraft(_text.text);
      if (code == AiWords.imageFailed) {
        setState(() => _note = S.of(context).aiImageFailed);
      } else {
        _say(code);
      }
    }
  }

  /// The bytes of the images already in the next message.
  int get _imageBytes => _images.fold(0, (n, image) => n + image.bytes.length);

  /// V2-2b B12: photos from the library or the camera join the next message — five at most and 20 MB in all (F34),
  /// of a type and a size the computer takes, and without their metadata (F38): [aiTakePicked] cleans them. A photo
  /// that is not says why, in the composer.
  Future<void> _attach() async {
    final s = S.of(context);
    final room = kAiImagesMax - _images.length;
    if (room <= 0) return;
    final origin = await showAiAttachSheet(context);
    if (origin == null || !mounted) return;
    final List<Uint8List> picked;
    try {
      final source = getIt<AiImageSource>();
      picked = switch (origin) {
        AiImageOrigin.library => await source.pickPhotos(limit: room),
        AiImageOrigin.camera => [?await source.takePhoto()],
      };
    } catch (error) {
      if (kDebugMode) debugPrint('AI image pick error: ${error.runtimeType}');
      if (mounted) setState(() => _note = s.aiPickFailed);
      return;
    }
    if (!mounted || picked.isEmpty) return;
    final taken = aiTakePicked(
      picked,
      room: kAiImagesMax - _images.length,
      bytesLeft: kAiMessageImageBytes - _imageBytes,
    );
    setState(() {
      _images.addAll(taken.images);
      _note = switch (taken.problem) {
        AiImageProblem.type => s.aiImageType,
        AiImageProblem.size => s.aiImageTooBig,
        AiImageProblem.total => s.aiImagesTooMuch,
        null => null,
      };
    });
  }

  void _removeImage(AiPickedImage image) => setState(() {
    _images.remove(image);
    _note = null;
  });

  /// V2-2b B13: an `@query` at the cursor asks the computer for its files after a pause; anything else clears them.
  void _lookForMention() {
    _suggestTimer?.cancel();
    final token = AiMentions.tokenAt(_text.value);
    if (token == null || !_controller.can(AiFeature.files)) {
      _suggestAsks++; // an answer still on its way is for a token that is gone
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      return;
    }
    _suggestTimer = Timer(_suggestPause, () async {
      final ask = ++_suggestAsks;
      final paths = await _controller.files(token.query);
      // Only for the token still at the cursor.
      if (!mounted || ask != _suggestAsks || AiMentions.tokenAt(_text.value)?.query != token.query) return;
      setState(() => _suggestions = paths.take(AiMentions.maxSuggestions).toList());
    });
  }

  /// V2-2b B14: the mic. Its first tap makes the dictation; "gửi" sends when the session can take the message and
  /// there is one (text or images).
  Future<void> _mic() async {
    final language = Localizations.localeOf(context).languageCode;
    final dictation = _dictation ??= getIt<AiDictation>()
      ..attach(
        text: _text,
        canSend: () => _controller.canSend && (_text.text.trim().isNotEmpty || _images.isNotEmpty),
        onSend: () => unawaited(_send()),
      );
    setState(() {}); // the mic follows the dictation's phase from now on
    await dictation.toggle(language);
  }

  /// A suggestion picked: `@path ` in place of the token, remembered for the message.
  void _pickSuggestion(String path) {
    final token = AiMentions.tokenAt(_text.value);
    if (token == null) return;
    _mentions.add(path);
    _text.value = AiMentions.insert(_text.value, token, path);
    setState(() => _suggestions = const []);
  }

  /// V2-2b B17: "Lịch sử phiên" — an earlier session picked there opens on the computer in a new AI tab (not shown
  /// there), and here in place of this page.
  Future<void> _openHistory() async {
    final acp = await showAiHistorySheet(context, _controller);
    if (acp == null || !mounted) return;
    final opened = await _controller.resume(acp);
    if (!mounted) return;
    final sid = opened.sid;
    if (sid == null) {
      _say(opened.code);
      return;
    }
    // Keyed by its session, as the list of sessions does (`openAiChooser`): a page that takes the place of another
    // session's page is a new page — the router would otherwise keep the old one's state, and so its session.
    final route = AiSessionRoute(
      key: ValueKey('ai:${widget.agentId}/$sid'),
      agentId: widget.agentId,
      machineName: widget.machineName,
      sid: sid,
    );
    unawaited(context.router.replace(route));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => Column(
            children: [
              Watch(_header),
              if (_controller.backend case final backend?)
                ConnectionBanner(
                  backend: backend,
                  onReconnectReplaced: () => unawaited(getIt<SessionHolder>().reconnectReplaced()),
                ),
              Watch(_strips),
              Expanded(child: Watch(_conversation)),
              Watch((context) => _dock(context, box.maxHeight)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    _controller.version.value;
    _controller.now.value; // the clock: "Đang chạy · 0:12"
    final s = S.of(context);
    final head = _controller.head;
    final closed = _controller.linkState == AiLinkState.closed;
    return _Header(
      title: (head?.title?.isNotEmpty ?? false) ? head!.title! : s.aiUntitled,
      subtitle: head == null ? widget.machineName : _subtitle(s, head),
      // A closed session runs nothing: no state colour either.
      state: head == null || closed ? null : AiWords.headState(head),
      onBack: () => context.router.maybePop(),
      // V2-2b B11: "Chế độ và model", while the session is live and the computer offers it.
      onSubtitle: head != null && _controller.linkState == AiLinkState.live && _controller.can(AiFeature.config)
          ? _openConfig
          : null,
      // V2-2b B17, B20: the "⋯" menu, each entry only while the computer offers it (Task 25 adds B20's).
      menu: [
        if (!closed && head != null && head.history && _controller.can(AiFeature.history))
          (key: const Key('ai.menu.history'), label: s.aiHistory, onTap: () => unawaited(_openHistory())),
      ],
    );
  }

  /// V2-2b B11.
  void _openConfig() => unawaited(showAiConfigSheet(context, controller: _controller));

  String _subtitle(S s, MirrorHead head) {
    // A closed session is not "running", whatever it was doing when it closed: it says "closed" (the strip
    // below says why), and has no clock, mode or context to show.
    if (_controller.linkState == AiLinkState.closed) return [head.agentName, s.aiStateClosed].join(' · ');
    final state = AiWords.state(s, AiWords.headState(head));
    final turn = head.turn;
    // The clock counts only on a live link: after a loss nothing is known of the turn, and a clock that
    // went on would show a time nobody measured. The state stays; the strip says it is reconnecting.
    final counting = turn != null && _controller.linkState == AiLinkState.live;
    final parts = [
      head.agentName,
      counting ? '$state · ${AiWords.clock(_controller.now.value.difference(turn.startedAt))}' : state,
      ?AiWords.mode(s, head),
      ?head.modelName,
      if (head.usage case final u? when u.size > 0) s.aiContext(u.percent),
    ];
    return parts.join(' · ');
  }

  /// What is wrong between the phone and the session, in one place each: the computer cannot be
  /// reached (the machine says it; the link stays `attaching` meanwhile), the page is reconnecting
  /// over what it holds, or the session is closed.
  Widget _strips(BuildContext context) {
    _controller.version.value;
    final s = S.of(context);
    final machine = _controller.machineState.value;
    final closed = _controller.closed.value;
    final link = _controller.linkState;
    final mirror = _controller.mirror;
    final holds = _controller.head != null || (mirror != null && mirror.end > mirror.from);
    final unreachable = machine is MachineFailed;
    final reason = _controller.closedReason;
    // B22: a session closed on the computer may be there again under another name; the computer's AI
    // sessions are one tap away when the page holds their list.
    final openList = (reason == 'gone' || reason == 'desktop_closed') && _controller.listing != null;
    return Column(
      children: [
        if (machine is MachineFailed)
          _Strip(key: const Key('ai.offline'), text: AiWords.machineFailure(s, machine.failure), tone: NoticeTone.warn)
        else if (link == AiLinkState.attaching && holds)
          _Strip(text: s.aiReconnecting),
        // A page that cannot show the session because the machine is gone says so with the machine's
        // words, not as a session closed on the computer.
        if (link == AiLinkState.closed && !(closed && unreachable))
          _Strip(
            key: const Key('ai.closed'),
            text: AiWords.closed(s, reason),
            action: openList
                ? TextButton(key: const Key('ai.openList'), onPressed: _openList, child: Text(s.aiOpenList))
                : null,
          ),
        if (_controller.reattached.value && link != AiLinkState.closed)
          _Strip(key: const Key('ai.reattached'), text: s.aiReattached),
      ],
    );
  }

  Widget _conversation(BuildContext context) {
    final version = _controller.version.value;
    final machine = _controller.machineState.value;
    final s = S.of(context);
    final colors = context.colors;
    final link = _controller.linkState;
    final mirror = _controller.mirror;
    final head = _controller.head;
    if (mirror == null) return const SizedBox.shrink();
    final empty = mirror.end <= mirror.from;
    if (head == null && empty) {
      // Nothing came yet. A spinner only while something is on its way: when the machine cannot be
      // reached, or the session is closed, the strips say it.
      return link == AiLinkState.attaching && machine is! MachineFailed
          ? const Center(child: CircularProgressIndicator())
          : const SizedBox.shrink();
    }
    final unavailable = head?.unavailable;
    if (unavailable != null && empty) {
      // V2-2b B18: a tab without a folder takes one of the computer's from here, when the computer can.
      final folders = _controller.folders;
      if (unavailable == AiRemoteState.noFolder &&
          link == AiLinkState.live &&
          folders.isNotEmpty &&
          _controller.can(AiFeature.folder)) {
        return AiFolderChooser(
          key: const Key('ai.folders'),
          folders: folders,
          onUse: (folder) async => _say(await _controller.chooseFolder(folder)),
        );
      }
      // D14: set up on the computer; nothing to send from here.
      return Center(
        key: const Key('ai.unavailable'),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            AiWords.state(s, unavailable),
            textAlign: TextAlign.center,
            style: context.typo.paragraph.copyWith(color: colors.secondaryText),
          ),
        ),
      );
    }
    if (head != null && head.phase == 'starting' && empty) {
      // A restored session replays its history on the computer while its agent starts, and the phone gets
      // the header only until the agent is ready (then a snapshot, V2-2 D15): not an empty conversation.
      // The text field works meanwhile; what is sent queues.
      return Center(
        key: const Key('ai.starting'),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            AiWords.state(s, AiRemoteState.starting),
            textAlign: TextAlign.center,
            style: context.typo.paragraph.copyWith(color: colors.secondaryText),
          ),
        ),
      );
    }
    return Column(
      children: [
        if (unavailable != null) _Strip(key: const Key('ai.unavailable'), text: AiWords.state(s, unavailable)),
        Expanded(
          // V2-2b B16: "Xem đủ" on what the phone shows cut, when the computer offers it.
          child: AiItemActions(
            onViewAll: _controller.can(AiFeature.item) ? _viewAll : null,
            child: AiTimeline(
              mirror: mirror,
              version: version,
              agentName: head?.agentName ?? '',
              onLoadEarlier: link == AiLinkState.live ? _controller.loadEarlier : null,
              jumpTo: _jumpTo,
              clock: _controller.now,
            ),
          ),
        ),
      ],
    );
  }

  Widget _dock(BuildContext context, double available) {
    _controller.version.value;
    final head = _controller.head;
    final mirror = _controller.mirror;
    final link = _controller.linkState;
    if (head == null || mirror == null || link == AiLinkState.closed || head.unavailable != null) {
      return const SizedBox.shrink();
    }
    final live = link == AiLinkState.live;
    final answering = _controller.answering.value;
    final busy = !live || answering != null;
    final permission = head.permission;
    final ask = _waitingAsk(head, mirror);
    final panels = [
      if (head.plan.isNotEmpty) AiPlanStrip(key: const ValueKey('plan'), plan: head.plan),
      if (permission != null)
        AiPermissionPanel(
          key: const ValueKey('permission'),
          permission: permission,
          agentName: head.agentName,
          busy: busy,
          onAnswer: (o) async => _say(await _controller.answerPermission(permission, o), answer: true),
          // The card is shown only if the phone holds it.
          onDetails: permission.item == null || mirror.at(permission.item!) == null
              ? null
              : () {
                  _jumpTo.value = null; // so that asking for the same card again asks again
                  _jumpTo.value = permission.item;
                },
        )
      else if (ask != null)
        AiAskPanel(
          // A form loaded in full is another panel: its fields start from their own defaults.
          key: ValueKey((ask.id, ask.request != null)),
          ask: ask,
          agentName: head.agentName,
          busy: busy,
          onAnswer: (r) async => _say(await _controller.answerAsk(ask.id, r), answer: true),
          // V2-2b B16: a question too big for the mirror is loaded in full, then answered here.
          onLoadForm: ask.request == null && head.ask?.item != null && !_loadingForm && _controller.can(AiFeature.item)
              ? () => unawaited(_loadForm(ask.id, head.ask!.item!))
              : null,
        ),
      if (head.queue.isNotEmpty)
        AiQueueRow(
          key: const ValueKey('queue'),
          queue: head.queue,
          onRemove: (id) async => _say(await _controller.unqueue(id)),
        ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // On a small screen with the keyboard open the panels may need more than the room there is:
        // they scroll, within half of it, and the text field stays where it is.
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: available * 0.5),
          child: SingleChildScrollView(child: Column(children: panels)),
        ),
        AiComposer(
          key: const ValueKey('ai.composer.bar'),
          controller: _text,
          agentName: head.agentName,
          canSend: live && head.canSend,
          running: head.running,
          stopping: _controller.stopping.value || (head.turn?.stopping ?? false),
          canForceStop: head.turn?.canForceStop ?? false,
          sending: _controller.sending.value,
          onSend: _send,
          onStop: () async => _say(await _controller.stop()),
          onForceStop: () async => _say(await _controller.forceStop()),
          // V2-2b B12, B13: only towards a computer that takes them.
          images: _images,
          onAttach: _controller.can(AiFeature.blob) ? _attach : null,
          onRemoveImage: _removeImage,
          upload: _controller.upload.value,
          suggestions: _suggestions,
          onSuggestion: _pickSuggestion,
          note: _note ?? _voiceIssue(S.of(context), _dictation),
          listening: _dictation?.phase.value == VoicePhase.listening,
          onMic: _mic,
        ),
      ],
    );
  }

  /// What the composer says of a voice problem, in the terminal's words; null: none.
  static String? _voiceIssue(S s, AiDictation? dictation) => switch (dictation?.issue.value) {
    null => null,
    VoiceIssue.noPermission => s.voiceNoPermission,
    VoiceIssue.unsupported => s.voiceUnsupported,
    VoiceIssue.localeUnavailable =>
      dictation!.locale.value == VoiceLocale.vi ? s.voiceLocaleUnavailableVi : s.voiceLocaleUnavailableEn,
    VoiceIssue.network => s.voiceNetwork,
    VoiceIssue.failed => s.voiceFailed,
  };

  /// The question the computer waits for, as the form to answer it: its card when the phone holds it,
  /// else one without a form, which is answered on the computer (it can still be declined). A form too big
  /// for the mirror that was loaded in full (V2-2b B16) is the form.
  MirrorAsk? _waitingAsk(MirrorHead head, AiMirror mirror) {
    final ref = head.ask;
    if (ref == null) return null;
    final card = ref.item == null ? null : mirror.at(ref.item!);
    final MirrorAsk ask;
    if (card is MirrorAsk) {
      if (!card.open) return null;
      ask = card;
    } else {
      ask = MirrorAsk(ref.item ?? -1, 0, 0, id: ref.id, status: 'open');
    }
    final form = ask.request == null ? _controller.formOf(ask.id) : null;
    return form == null ? ask : MirrorAsk(ask.index, ask.rev, ask.turn, id: ask.id, status: ask.status, request: form);
  }

  /// V2-2b B16: item [index] in full, on its own page.
  void _viewAll(int index) {
    final title = _itemTitle(S.of(context), _controller.mirror?.at(index), _controller.head?.agentName ?? '');
    unawaited(context.router.push(AiItemRoute(title: title, load: (onPart) => _controller.loadFull(index, onPart))));
  }

  static String _itemTitle(S s, MirrorItem? item, String agent) => switch (item) {
    MirrorTool() => AiWords.toolTitle(s, item),
    MirrorAsk() => s.aiAskTitle(agent),
    MirrorText(kind: MirrorTextKind.thought) => s.aiThought,
    MirrorText(kind: MirrorTextKind.agent) => agent,
    _ => s.aiViewAll,
  };

  /// V2-2b B16: the whole form of question [ask] (card [index]).
  Future<void> _loadForm(int ask, int index) async {
    setState(() => _loadingForm = true);
    final code = await _controller.loadForm(ask, index);
    if (!mounted) return;
    setState(() => _loadingForm = false);
    _say(code == AiWords.outcomeUnknown ? 'offline' : code);
  }
}

/// V2-2b: one entry of the header's "⋯" menu (B17 "Lịch sử phiên", B20 "Thay đổi").
typedef AiHeaderAction = ({Key key, String label, VoidCallback onTap});

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.state,
    required this.onBack,
    this.onSubtitle,
    this.menu = const [],
  });

  final String title;
  final String subtitle;
  final AiRemoteState? state;
  final VoidCallback onBack;

  /// V2-2b B11: the subtitle opens "Chế độ và model"; null: it is plain text.
  final VoidCallback? onSubtitle;

  /// V2-2b B17, B20: the "⋯" menu; none when empty.
  final List<AiHeaderAction> menu;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dot = switch (state) {
      AiRemoteState.needsInput => colors.warn,
      AiRemoteState.running || AiRemoteState.starting => colors.link,
      AiRemoteState.failed => colors.error,
      _ => colors.secondaryText,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 6),
      child: Row(
        children: [
          IconButton(
            key: const Key('ai.back'),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: Icon(Icons.arrow_back_ios_new, color: colors.primary),
            onPressed: onBack,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  key: const Key('ai.title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typo.subHeader.bold.copyWith(color: colors.primaryText),
                ),
                2.sizedHeight,
                _subtitleRow(context, dot),
              ],
            ),
          ),
          if (menu.isNotEmpty)
            PopupMenuButton<int>(
              key: const Key('ai.menu'),
              icon: Icon(Icons.more_horiz, color: colors.primary),
              onSelected: (i) => menu[i].onTap(),
              itemBuilder: (context) => [
                for (final (i, action) in menu.indexed)
                  PopupMenuItem<int>(key: action.key, value: i, child: Text(action.label)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _subtitleRow(BuildContext context, Color dot) {
    final colors = context.colors;
    final row = Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        6.sizedWidth,
        Expanded(
          child: Text(
            subtitle,
            key: const Key('ai.status'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.typo.paragraph13.copyWith(
              color: state == AiRemoteState.needsInput ? colors.warn : colors.secondaryText,
            ),
          ),
        ),
        if (onSubtitle != null) Icon(Icons.expand_more, size: 16, color: colors.secondaryText),
      ],
    );
    final tap = onSubtitle;
    if (tap == null) return row;
    // At least 44 points under the finger: the whole line is the button.
    return InkWell(
      key: const Key('ai.status.tap'),
      onTap: tap,
      child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 44), child: row),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({super.key, required this.text, this.tone = NoticeTone.info, this.action});

  final String text;
  final NoticeTone tone;

  /// A button at the strip's end (V2-2b B22 "Mở danh sách phiên").
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
    child: NoticeBanner(text: text, tone: tone, action: action),
  );
}
