import 'dart:async';

import 'package:shellx_ai/remote.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/ai/domain/ai_words.dart';
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_session_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// V2-2b B11: "Chế độ và model" over the session page.
Future<void> showAiConfigSheet(BuildContext context, {required AiSessionController controller}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => AiConfigSheet(controller: controller),
    );

/// V2-2b B11: the session's mode, model and thinking — and the model's own switch ("Fast") — as the computer
/// offers them to a phone: never a choice acting without asking (R16). A tap is one choice, sent once; the
/// sheet closes when the computer took it, and stays, saying why, when it did not. Claude's known modes are
/// worded as in the session's status line.
class AiConfigSheet extends StatefulWidget {
  const AiConfigSheet({super.key, required this.controller});

  final AiSessionController controller;

  @override
  State<AiConfigSheet> createState() => _AiConfigSheetState();
}

class _AiConfigSheetState extends State<AiConfigSheet> {
  AiConfigView? _view;
  String? _error;

  /// The option (its id, or `mode` for the legacy modes) whose choice is on its way: nothing else is
  /// sent meanwhile.
  String? _busy;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final got = await widget.controller.loadConfig();
    if (!mounted) return;
    setState(() {
      _view = got.view;
      _error = got.code;
    });
  }

  Future<void> _set(String key, Future<String?> Function() send) async {
    if (_busy != null) return;
    setState(() => _busy = key);
    final code = await send();
    if (!mounted) return;
    setState(() => _busy = null);
    if (code == null) {
      Navigator.of(context).pop();
      return;
    }
    final s = S.of(context);
    final text = code == 'on_computer' ? s.aiConfigOnComputer : AiWords.failure(s, code);
    if (text != null) widget.controller.popupHandler.showError(title: text);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = context.colors;
    final view = _view;
    final error = _error;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.aiConfigTitle, key: const Key('ai.config.title'), style: context.typo.heading20.heavy),
            12.sizedHeight,
            if (view == null && error == null)
              const Center(
                child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
              )
            else if (view == null)
              Text(
                AiWords.failure(s, error!) ?? s.somethingWentWrong,
                key: const Key('ai.config.error'),
                style: context.typo.paragraph.copyWith(color: colors.secondaryText),
              )
            else ...[
              for (final o in view.options) ..._option(context, o),
              if (view.modes case final modes?) ..._modes(context, modes),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _option(BuildContext context, AiConfigOptionView o) {
    final s = S.of(context);
    if (o.isSwitch) {
      return [
        SwitchListTile(
          key: Key('ai.config.${o.id}'),
          contentPadding: EdgeInsets.zero,
          title: Text(o.name),
          value: o.current == true,
          onChanged: _busy != null ? null : (on) => _set(o.id, () => widget.controller.setConfig(o.id, on)),
        ),
      ];
    }
    final group = switch (o.category) {
      'mode' => s.aiConfigMode,
      'model' => s.aiConfigModel,
      'thought_level' => s.aiConfigEffort,
      _ => o.name,
    };
    return [
      _Header(group),
      _Choices(
        id: o.id,
        current: o.current is String ? o.current! as String : null,
        choices: [
          for (final c in o.choices)
            (c, o.category == 'mode' ? AiWords.modeName(s, c.value, c.name) ?? c.name : c.name),
        ],
        busy: _busy != null,
        onPick: (value) => _set(o.id, () => widget.controller.setConfig(o.id, value)),
      ),
      if (o.more) _More(s.aiConfigMore),
    ];
  }

  List<Widget> _modes(BuildContext context, AiModesView modes) {
    final s = S.of(context);
    return [
      _Header(s.aiConfigMode),
      _Choices(
        id: 'mode',
        current: modes.current,
        choices: [for (final c in modes.choices) (c, AiWords.modeName(s, c.value, c.name) ?? c.name)],
        busy: _busy != null,
        onPick: (value) => _set('mode', () => widget.controller.setMode(value)),
      ),
      if (modes.more) _More(s.aiConfigMore),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 2),
    child: Text(
      text.toUpperCase(),
      style: context.typo.paragraph13.bold.copyWith(color: context.colors.secondaryText, letterSpacing: 0.8),
    ),
  );
}

/// The choices of one option, one row each (`ai.config.<id>.<value>`), the current one selected. A row
/// that is not the current one sends it; nothing is sent while another choice is on its way.
class _Choices extends StatelessWidget {
  const _Choices({
    required this.id,
    required this.current,
    required this.choices,
    required this.busy,
    required this.onPick,
  });

  final String id;
  final String? current;
  final List<(AiConfigChoiceView, String)> choices;
  final bool busy;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => RadioGroup<String>(
    groupValue: current,
    onChanged: (value) {
      if (value == null || value == current || busy) return;
      onPick(value);
    },
    child: Column(
      children: [
        for (final (c, label) in choices)
          RadioListTile<String>(
            key: Key('ai.config.$id.${c.value}'),
            contentPadding: EdgeInsets.zero,
            enabled: !busy,
            value: c.value,
            title: Text(label),
            subtitle: c.group == null ? null : Text(c.group!),
          ),
      ],
    ),
  );
}

class _More extends StatelessWidget {
  const _More(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: context.typo.paragraph13.copyWith(color: context.colors.secondaryText)),
  );
}
