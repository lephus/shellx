import 'package:flutter/services.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/ai/domain/ai_words.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// V2-1 D10 on a phone (V2-2 §5.3): the waiting permission with one big
/// button per option, in the agent's order. Every answer is one explicit
/// tap; nothing is ever picked for the user, and the buttons wait while
/// the answer travels. A permission that came without options (the computer
/// leaves them out when its header would not fit a message) is answered on
/// the computer, and says so instead of showing an empty row.
class AiPermissionPanel extends StatelessWidget {
  const AiPermissionPanel({
    super.key,
    required this.permission,
    required this.agentName,
    required this.busy,
    required this.onAnswer,
    this.onDetails,
  });

  final MirrorPermission permission;
  final String agentName;

  /// The answer is on its way: buttons disabled.
  final bool busy;
  final ValueChanged<PermissionOption> onAnswer;

  /// Shows the tool card (the diff) in the conversation.
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = context.colors;
    final onComputer = AiWords.permissionOnComputer(s, permission);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: const Key('ai.permission'),
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: colors.warnSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.warn.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.aiPermTitle(agentName), style: context.typo.paragraph13.bold.copyWith(color: colors.warn)),
            4.sizedHeight,
            Text(
              permission.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: context.typo.subHeader15.bold.copyWith(color: colors.primaryText),
            ),
            if (permission.more > 0) ...[
              2.sizedHeight,
              Text(s.aiPermMore(permission.more), style: context.typo.metadata12.copyWith(color: colors.secondaryText)),
            ],
            10.sizedHeight,
            if (onComputer != null) ...[
              // The computer left the options out (its header would not fit): only it can answer.
              Text(onComputer, style: context.typo.paragraph.copyWith(color: colors.primaryText)),
              8.sizedHeight,
            ] else
              for (final o in permission.options) ...[
                _OptionButton(option: o, busy: busy, onTap: () => onAnswer(o)),
                8.sizedHeight,
              ],
            if (onDetails != null)
              TextButton(
                key: const Key('ai.permission.details'),
                onPressed: onDetails,
                child: Text(s.aiPermDetails),
              ),
          ],
        ),
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({required this.option, required this.busy, required this.onTap});

  final PermissionOption option;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = context.colors;
    final allow = option.kind == PermissionKind.allowOnce;
    final reject = option.kind.isReject;
    final always = option.kind == PermissionKind.allowAlways || option.kind == PermissionKind.rejectAlways;
    final label = AiWords.option(s, option);
    return Semantics(
      button: true,
      label: always ? '$label, ${option.name}' : label,
      child: Opacity(
        opacity: busy ? 0.45 : 1,
        child: Material(
          color: allow ? colors.primaryFill : colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: allow ? BorderSide.none : BorderSide(color: reject ? colors.error : colors.divider),
          ),
          child: InkWell(
            key: Key('ai.option.${option.optionId}'),
            borderRadius: BorderRadius.circular(14),
            onTap: busy
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    onTap();
                  },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ExcludeSemantics(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: context.typo.subHeader15.bold.copyWith(
                          color: allow ? colors.onPrimary : (reject ? colors.error : colors.primaryText),
                        ),
                      ),
                    ),
                    if (always && option.name.isNotEmpty)
                      ExcludeSemantics(
                        child: Text(
                          option.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.typo.metadata12.copyWith(color: colors.secondaryText),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// V2-1 D22 on a phone: the waiting question's form. "Gửi câu trả lời"
/// works only when the form accepts the values (the desktop checks again).
/// A URL question, or a form too big for the phone, is answered on the
/// computer; it can still be declined here.
class AiAskPanel extends StatefulWidget {
  const AiAskPanel({
    super.key,
    required this.ask,
    required this.agentName,
    required this.busy,
    required this.onAnswer,
  });

  final MirrorAsk ask;
  final String agentName;
  final bool busy;
  final ValueChanged<ElicitationResponse> onAnswer;

  @override
  State<AiAskPanel> createState() => _AiAskPanelState();
}

class _AiAskPanelState extends State<AiAskPanel> {
  final _values = <String, Object>{};

  @override
  void initState() {
    super.initState();
    final form = widget.ask.request;
    if (form is ElicitationForm) {
      for (final f in form.fields) {
        final d = switch (f) {
          ElicitTextField(:final defaultValue) => defaultValue,
          ElicitNumberField(:final defaultValue) => defaultValue,
          ElicitBoolField(:final defaultValue) => defaultValue,
          ElicitChoiceField(:final defaultValue) => defaultValue,
          ElicitMultiChoiceField(:final defaultValue) => defaultValue,
          ElicitUnsupportedField() => null,
        };
        if (d != null) _values[f.key] = d;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = context.colors;
    final request = widget.ask.request;
    final form = request is ElicitationForm && request.supported ? request : null;
    final ok = form != null && form.accepts(_values);
    return Container(
      key: const Key('ai.ask'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(14),
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
      decoration: BoxDecoration(
        color: colors.warnSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.warn.withValues(alpha: 0.5)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.aiAskTitle(widget.agentName), style: context.typo.paragraph13.bold.copyWith(color: colors.warn)),
            4.sizedHeight,
            Text(request?.message ?? '', style: context.typo.subHeader15.copyWith(color: colors.primaryText)),
            8.sizedHeight,
            if (form == null)
              Text(
                request is ElicitationForm ? s.aiAskUnsupported : s.aiAskOnComputer,
                style: context.typo.paragraph13.copyWith(color: colors.secondaryText),
              )
            else
              for (final f in form.fields) _field(context, f),
            10.sizedHeight,
            if (form != null)
              AppButton(
                key: const Key('ai.ask.submit'),
                title: s.aiAskSubmit,
                height: 48,
                state: widget.busy || !ok ? ButtonState.disable : ButtonState.available,
                onTap: () => widget.onAnswer(ElicitAccept(Map.of(_values))),
              ),
            TextButton(
              key: const Key('ai.ask.decline'),
              onPressed: widget.busy ? null : () => widget.onAnswer(const ElicitDecline()),
              child: Text(s.aiAskDecline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(BuildContext context, ElicitField f) {
    final colors = context.colors;
    final label = f.title ?? f.key;
    void set(Object? v) => setState(() => v == null ? _values.remove(f.key) : _values[f.key] = v);
    final title = Text(label, style: context.typo.paragraph13.bold.copyWith(color: colors.primaryText));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: switch (f) {
        ElicitBoolField() => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: title,
          value: _values[f.key] == true,
          onChanged: (v) => set(v),
        ),
        ElicitChoiceField(:final options) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            RadioGroup<String>(
              groupValue: _values[f.key] as String?,
              onChanged: set,
              child: Column(
                children: [
                  for (final o in options)
                    RadioListTile<String>(contentPadding: EdgeInsets.zero, value: o.value, title: Text(o.title)),
                ],
              ),
            ),
          ],
        ),
        ElicitMultiChoiceField(:final options) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            for (final o in options)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: ((_values[f.key] as List?) ?? const []).contains(o.value),
                title: Text(o.title),
                onChanged: (on) {
                  final now = [...((_values[f.key] as List?)?.cast<String>() ?? const <String>[])];
                  if (on == true) {
                    now.add(o.value);
                  } else {
                    now.remove(o.value);
                  }
                  set(now.isEmpty ? null : now);
                },
              ),
          ],
        ),
        ElicitNumberField(:final integer) => TextFormField(
          initialValue: _values[f.key]?.toString(),
          decoration: InputDecoration(labelText: label, helperText: f.description),
          keyboardType: TextInputType.numberWithOptions(decimal: !integer, signed: true),
          onChanged: (t) => set(integer ? int.tryParse(t) : num.tryParse(t)),
        ),
        ElicitTextField() => TextFormField(
          initialValue: _values[f.key] as String?,
          decoration: InputDecoration(labelText: label, helperText: f.description),
          onChanged: (t) => set(t.isEmpty ? null : t),
        ),
        ElicitUnsupportedField() => const SizedBox.shrink(),
      },
    );
  }
}

/// The prompts waiting for the turn to end, each with "Bỏ khỏi hàng đợi".
class AiQueueRow extends StatelessWidget {
  const AiQueueRow({super.key, required this.queue, required this.onRemove});

  final List<MirrorQueued> queue;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final q in queue)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.divider),
              ),
              child: Row(
                children: [
                  Text(s.aiQueued, style: context.typo.metadata11.bold.copyWith(color: colors.secondaryText)),
                  8.sizedWidth,
                  Expanded(
                    child: Text(q.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.typo.paragraph13),
                  ),
                  IconButton(
                    key: Key('ai.unqueue.${q.id}'),
                    tooltip: s.aiRemoveQueued,
                    icon: Icon(Icons.close, size: 18, color: colors.secondaryText),
                    onPressed: () => onRemove(q.id),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The text field and its buttons (V2-1 D16 on a phone): Send, or Queue
/// while a turn runs; Stop while a turn runs and the field is empty; Force
/// stop once the computer offers it. The draft stays when sending fails.
class AiComposer extends StatefulWidget {
  const AiComposer({
    super.key,
    required this.controller,
    required this.agentName,
    required this.enabled,
    required this.running,
    required this.stopping,
    required this.canForceStop,
    required this.sending,
    required this.onSend,
    required this.onStop,
    required this.onForceStop,
  });

  final TextEditingController controller;
  final String agentName;
  final bool enabled;
  final bool running;
  final bool stopping;
  final bool canForceStop;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onForceStop;

  @override
  State<AiComposer> createState() => _AiComposerState();
}

class _AiComposerState extends State<AiComposer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = context.colors;
    final hasText = widget.controller.text.trim().isNotEmpty;
    final showStop = widget.running && !hasText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              key: const Key('ai.composer'),
              controller: widget.controller,
              enabled: widget.enabled,
              minLines: 1,
              maxLines: 6,
              textInputAction: TextInputAction.newline,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: s.aiComposerHint(widget.agentName),
                filled: true,
                fillColor: colors.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: colors.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: colors.divider),
                ),
              ),
            ),
          ),
          4.sizedWidth,
          if (widget.canForceStop)
            IconButton(
              key: const Key('ai.forceStop'),
              tooltip: s.aiForceStop,
              icon: Icon(Icons.dangerous_outlined, color: colors.error),
              onPressed: widget.onForceStop,
            ),
          if (showStop)
            IconButton.filledTonal(
              key: const Key('ai.stop'),
              tooltip: widget.stopping ? s.aiStopping : s.aiStop,
              icon: widget.stopping
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.stop_rounded),
              onPressed: widget.stopping ? null : widget.onStop,
            )
          else
            IconButton.filled(
              key: const Key('ai.send'),
              tooltip: widget.running ? s.aiQueue : s.aiSend,
              icon: widget.sending
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(widget.running ? Icons.playlist_add : Icons.arrow_upward),
              onPressed: widget.enabled && hasText && !widget.sending ? widget.onSend : null,
            ),
        ],
      ),
    );
  }
}

/// The agent's plan in one line ("Kế hoạch · 2/5"), opened by a tap.
class AiPlanStrip extends StatefulWidget {
  const AiPlanStrip({super.key, required this.plan});

  final List<PlanEntry> plan;

  @override
  State<AiPlanStrip> createState() => _AiPlanStripState();
}

class _AiPlanStripState extends State<AiPlanStrip> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final done = widget.plan.where((e) => e.status == PlanStatus.completed).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const Key('ai.plan'),
            onTap: () => setState(() => _open = !_open),
            child: Row(
              children: [
                Icon(Icons.checklist, size: 16, color: colors.secondaryText),
                6.sizedWidth,
                Text(
                  S.of(context).aiPlan(done, widget.plan.length),
                  style: context.typo.paragraph13.copyWith(color: colors.secondaryText),
                ),
                const Spacer(),
                Icon(_open ? Icons.expand_more : Icons.expand_less, size: 18, color: colors.secondaryText),
              ],
            ),
          ),
          if (_open)
            for (final e in widget.plan)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      switch (e.status) {
                        PlanStatus.completed => Icons.check_box,
                        PlanStatus.inProgress => Icons.indeterminate_check_box_outlined,
                        PlanStatus.pending => Icons.check_box_outline_blank,
                      },
                      size: 16,
                      color: colors.secondaryText,
                    ),
                    6.sizedWidth,
                    Expanded(child: Text(e.content, style: context.typo.paragraph13)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
