import 'dart:async';

import 'package:shellx_ai/remote.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/ai/domain/ai_words.dart';
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_session_controller.dart';
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_dock.dart';
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_timeline.dart';
import 'package:shellx_mobile/features/app/connection_banner.dart';
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
  final _text = TextEditingController();
  final _jumpTo = ValueNotifier<int?>(null);

  @override
  void dispose() {
    _controller.dispose();
    _text.dispose();
    _jumpTo.dispose();
    super.dispose();
  }

  void _say(String? code, {bool answer = false}) {
    if (code == null || !mounted) return;
    final text = AiWords.failure(S.of(context), code, answer: answer);
    if (text != null) _controller.popupHandler.showError(title: text);
  }

  Future<void> _send() async {
    final text = _text.text;
    final code = await _controller.send(text);
    if (!mounted) return;
    // The text stays when the message did not go (or may not have): the user decides what to do.
    if (code == null) {
      if (_text.text == text) _text.clear();
    } else {
      _say(code);
    }
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
    return _Header(
      title: (head?.title?.isNotEmpty ?? false) ? head!.title! : s.aiUntitled,
      subtitle: head == null ? widget.machineName : _subtitle(s, head),
      state: head == null ? null : AiWords.headState(head),
      onBack: () => context.router.maybePop(),
    );
  }

  String _subtitle(S s, MirrorHead head) {
    final state = AiWords.state(s, AiWords.headState(head));
    final turn = head.turn;
    final parts = [
      head.agentName,
      turn == null ? state : '$state · ${AiWords.clock(_controller.now.value.difference(turn.startedAt))}',
      ?AiWords.mode(s, head),
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
    return Column(
      children: [
        if (machine is MachineFailed)
          _Strip(key: const Key('ai.offline'), text: AiWords.machineFailure(s, machine.failure), tone: NoticeTone.warn)
        else if (link == AiLinkState.attaching && holds)
          _Strip(text: s.aiReconnecting),
        // A page that cannot show the session because the machine is gone says so with the machine's
        // words, not as a session closed on the computer.
        if (link == AiLinkState.closed && !(closed && unreachable))
          _Strip(key: const Key('ai.closed'), text: AiWords.closed(s, _controller.closedReason)),
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
    return Column(
      children: [
        if (unavailable != null) _Strip(key: const Key('ai.unavailable'), text: AiWords.state(s, unavailable)),
        Expanded(
          child: AiTimeline(
            mirror: mirror,
            version: version,
            agentName: head?.agentName ?? '',
            onLoadEarlier: link == AiLinkState.live ? _controller.loadEarlier : null,
            jumpTo: _jumpTo,
            clock: _controller.now,
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
          key: ValueKey(ask.id),
          ask: ask,
          agentName: head.agentName,
          busy: busy,
          onAnswer: (r) async => _say(await _controller.answerAsk(ask.id, r), answer: true),
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
          enabled: live && head.canSend,
          running: head.running,
          stopping: _controller.stopping.value || (head.turn?.stopping ?? false),
          canForceStop: head.turn?.canForceStop ?? false,
          sending: _controller.sending.value,
          onSend: _send,
          onStop: () async => _say(await _controller.stop()),
          onForceStop: () async => _say(await _controller.forceStop()),
        ),
      ],
    );
  }

  /// The question the computer waits for, as the form to answer it: its card when the phone holds it,
  /// else one without a form, which is answered on the computer (it can still be declined).
  MirrorAsk? _waitingAsk(MirrorHead head, AiMirror mirror) {
    final ref = head.ask;
    if (ref == null) return null;
    final card = ref.item == null ? null : mirror.at(ref.item!);
    if (card is MirrorAsk) return card.open ? card : null;
    return MirrorAsk(ref.item ?? -1, 0, 0, id: ref.id, status: 'open');
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.subtitle, required this.state, required this.onBack});

  final String title;
  final String subtitle;
  final AiRemoteState? state;
  final VoidCallback onBack;

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
                Row(
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
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({super.key, required this.text, this.tone = NoticeTone.info});

  final String text;
  final NoticeTone tone;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
    child: NoticeBanner(text: text, tone: tone),
  );
}
