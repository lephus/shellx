import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/desktop_services.dart';
import '../text_editing_shortcuts.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_scope.dart';
import 'ai_theme.dart';

/// D22: the agent's question in the conversation (it counts as "needs
/// input", D13).
/// - A form: text, number, yes/no, one choice and several choices; Send
///   answers `accept` with the values once every required field is valid,
///   Decline answers `decline`, Cancel `cancel`.
/// - A URL: the whole URL first, "Open in browser" (http/https only, on a
///   click) answers `accept`; `elicitation/complete` marks it done.
/// - A type ShellX cannot show was declined already: the card says so.
/// Once answered it folds to one line.
class AiAskCard extends ConsumerStatefulWidget {
  const AiAskCard({super.key, required this.item});
  final AskItem item;

  @override
  ConsumerState<AiAskCard> createState() => _AiAskCardState();
}

class _AiAskCardState extends ConsumerState<AiAskCard> {
  final _text = <String, TextEditingController>{};
  final _values = <String, Object>{};
  var _invalid = false;

  @override
  void initState() {
    super.initState();
    final request = widget.item.request;
    if (request is! ElicitationForm) return;
    for (final f in request.fields) {
      switch (f) {
        case ElicitTextField(:final defaultValue):
          _text[f.key] = TextEditingController(text: defaultValue ?? '');
        case ElicitNumberField(:final defaultValue):
          _text[f.key] = TextEditingController(
            text: defaultValue == null ? '' : '$defaultValue',
          );
        case ElicitBoolField(:final defaultValue?):
          _values[f.key] = defaultValue;
        case ElicitChoiceField(:final defaultValue?):
          _values[f.key] = defaultValue;
        case ElicitMultiChoiceField(:final defaultValue?):
          _values[f.key] = [...defaultValue];
        case ElicitBoolField() ||
            ElicitChoiceField() ||
            ElicitMultiChoiceField() ||
            ElicitUnsupportedField():
          break;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _answer(ElicitationResponse response) =>
      AiPaneScope.of(context).runtime.answerAsk(widget.item.id, response);

  /// The form's answer: only fields the user gave (an empty text is none).
  Map<String, Object> _content(ElicitationForm form) {
    final out = <String, Object>{};
    for (final f in form.fields) {
      final text = _text[f.key]?.text.trim();
      final Object? value = switch (f) {
        ElicitTextField() => text == null || text.isEmpty ? null : text,
        ElicitNumberField(:final integer) =>
          text == null || text.isEmpty
              ? null
              : (integer
                        ? int.tryParse(text)
                        : num.tryParse(text.replaceAll(',', '.'))) ??
                    text,
        _ => _values[f.key],
      };
      if (value != null) out[f.key] = value;
    }
    return out;
  }

  void _send(ElicitationForm form) {
    final content = _content(form);
    if (!form.accepts(content)) {
      setState(() => _invalid = true);
      return;
    }
    _answer(ElicitAccept(content));
  }

  Future<void> _open(ElicitationUrl request) async {
    try {
      await ref
          .read(desktopServicesProvider)
          .urlOpener
          .openWebLink(Uri.parse(request.url));
    } on Object catch (error) {
      debugPrint('ShellX: page not opened: ${error.runtimeType}');
      return;
    }
    if (mounted) _answer(const ElicitAccept());
  }

  Widget _field(AppLocalizations l10n, ElicitField f) {
    final label = Row(
      children: [
        Flexible(
          child: Text(
            f.title ?? f.key,
            style: ShellxText.bodyStrong.copyWith(
              color: ShellxDesktopColors.textPrimary,
            ),
          ),
        ),
        if (f.required) ...[
          const SizedBox(width: ShellxSpace.s6),
          Text(
            l10n.aiAskRequired,
            style: ShellxText.caption.copyWith(color: ShellxDesktopColors.warn),
          ),
        ],
      ],
    );
    final Widget input = switch (f) {
      ElicitTextField() || ElicitNumberField() => Shortcuts(
        shortcuts: textEditingShortcuts(),
        child: TextField(
          key: Key('ai.ask.${f.key}'),
          controller: _text[f.key],
          keyboardType: switch (f) {
            ElicitNumberField() => const TextInputType.numberWithOptions(
              decimal: true,
            ),
            ElicitTextField(format: 'email') => TextInputType.emailAddress,
            ElicitTextField(format: 'uri') => TextInputType.url,
            _ => TextInputType.text,
          },
          inputFormatters: [
            if (f case ElicitTextField(:final maxLength?))
              LengthLimitingTextInputFormatter(maxLength),
          ],
          decoration: const InputDecoration(isDense: true),
        ),
      ),
      ElicitBoolField() => Switch(
        key: Key('ai.ask.${f.key}'),
        value: _values[f.key] == true,
        onChanged: (on) => setState(() => _values[f.key] = on),
      ),
      ElicitChoiceField(:final options) => Wrap(
        spacing: ShellxSpace.s6,
        children: [
          for (final o in options)
            ChoiceChip(
              key: Key('ai.ask.${f.key}.${o.value}'),
              label: Text(o.title),
              selected: _values[f.key] == o.value,
              onSelected: (_) => setState(() => _values[f.key] = o.value),
            ),
        ],
      ),
      ElicitMultiChoiceField(:final options) => Wrap(
        spacing: ShellxSpace.s6,
        children: [
          for (final o in options)
            FilterChip(
              key: Key('ai.ask.${f.key}.${o.value}'),
              label: Text(o.title),
              selected:
                  (_values[f.key] as List<String>?)?.contains(o.value) ?? false,
              onSelected: (on) => setState(() {
                final list = [...?(_values[f.key] as List<String>?)];
                on ? list.add(o.value) : list.remove(o.value);
                _values[f.key] = list;
              }),
            ),
        ],
      ),
      ElicitUnsupportedField() => const SizedBox.shrink(),
    };
    return Padding(
      padding: const EdgeInsets.only(top: ShellxSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label,
          if (f.description case final d?)
            Text(
              d,
              style: ShellxText.small.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
          const SizedBox(height: ShellxSpace.s4),
          input,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final item = widget.item;
    final request = item.request;
    final agent = AiPaneScope.of(context).state.agentName;
    final dim = ShellxText.small.copyWith(
      color: ShellxDesktopColors.textSecondary,
    );
    if (item.autoDeclined) {
      return Text(
        '${request.message} — ${l10n.aiAskUnsupported}',
        key: const Key('ai.ask.unsupported'),
        style: dim,
      );
    }
    final response = item.response;
    if (response != null) {
      final word = switch (response) {
        ElicitAccept() when item.completed => l10n.aiAskCompleted,
        ElicitAccept() => l10n.aiAskAnswered,
        ElicitDecline() => l10n.aiAskDeclined,
        ElicitCancel() => l10n.aiAskCancelled,
      };
      return Text(
        '${request.message} — $word',
        key: const Key('ai.ask.done'),
        style: dim,
      );
    }
    final children = <Widget>[
      Text(
        request.message,
        style: ShellxText.body.copyWith(color: ShellxDesktopColors.textPrimary),
      ),
    ];
    final actions = <Widget>[];
    switch (request) {
      case ElicitationForm(:final title, :final description, :final fields):
        if (title != null) {
          children.add(Text(title, style: ShellxText.bodyStrong));
        }
        if (description != null) children.add(Text(description, style: dim));
        children.addAll([for (final f in fields) _field(l10n, f)]);
        if (_invalid) {
          children.add(
            Padding(
              padding: const EdgeInsets.only(top: ShellxSpace.s8),
              child: Text(
                l10n.aiAskInvalid,
                key: const Key('ai.ask.invalid'),
                style: ShellxText.small.copyWith(
                  color: ShellxDesktopColors.err,
                ),
              ),
            ),
          );
        }
        actions.addAll([
          FilledButton(
            key: const Key('ai.ask.send'),
            onPressed: () => _send(request),
            child: Text(l10n.aiAskSend),
          ),
          OutlinedButton(
            key: const Key('ai.ask.decline'),
            onPressed: () => _answer(const ElicitDecline()),
            child: Text(l10n.aiAskDecline),
          ),
        ]);
      case ElicitationUrl(:final url, :final isWebUrl):
        children.addAll([
          Text(l10n.aiAskUrlNote(agent), style: dim),
          SelectableText(url, key: const Key('ai.ask.url'), style: kAiMono),
        ]);
        actions.add(
          FilledButton(
            key: const Key('ai.ask.open'),
            onPressed: isWebUrl ? () => unawaited(_open(request)) : null,
            child: Text(l10n.aiAskOpen),
          ),
        );
      case ElicitationOther():
        break;
    }
    actions.add(
      TextButton(
        key: const Key('ai.ask.cancel'),
        onPressed: () => _answer(const ElicitCancel()),
        child: Text(l10n.aiAskCancel),
      ),
    );
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        key: const Key('ai.ask'),
        padding: const EdgeInsets.all(ShellxSpace.s12),
        decoration: BoxDecoration(
          color: ShellxDesktopColors.warnBg,
          borderRadius: BorderRadius.circular(ShellxRadius.r8),
          border: Border.all(color: ShellxDesktopColors.warnBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...children,
            const SizedBox(height: ShellxSpace.s12),
            Wrap(spacing: ShellxSpace.s8, children: actions),
          ],
        ),
      ),
    );
  }
}
