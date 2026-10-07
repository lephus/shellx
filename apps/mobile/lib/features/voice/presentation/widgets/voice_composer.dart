import 'package:flutter/semantics.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';
import 'package:shellx_mobile/features/voice/presentation/controllers/voice_composer_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Why the active tab cannot take a line now; the composer says it under the field.
enum VoiceSendBlock {
  /// The session exited or is gone (or there is no tab): only a new session can take the line.
  ended,

  /// Another device took the session, or the computer disconnected this phone: "Gắn lại" first.
  detached,

  /// Still connecting or reconnecting: the line can go once it is back.
  disconnected,
}

/// The panel above the extra keys while voice input is open (voice spec §3.1): where the line
/// goes, the language, the editable text, Send and ✕, the issue line (§5) and why Send is off.
/// Starting to listen shows "Đang nghe…" in the field and is announced to the screen reader.
class VoiceComposer extends StatefulWidget {
  const VoiceComposer({
    super.key,
    required this.controller,
    required this.target,
    required this.blocked,
    required this.onOpenSettings,
  });

  final VoiceComposerController controller;

  /// "zsh · MacBook"; null without a tab.
  final String? target;

  /// Null while the active tab is live (Send works).
  final VoiceSendBlock? blocked;
  final VoidCallback onOpenSettings;

  @override
  State<VoiceComposer> createState() => _VoiceComposerState();
}

class _VoiceComposerState extends State<VoiceComposer> {
  late void Function() _stopPhase;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(VoiceComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _stopPhase();
      _subscribe();
    }
  }

  @override
  void dispose() {
    _stopPhase();
    super.dispose();
  }

  /// Announces each start of a listen (the first value included: the composer opens listening).
  void _subscribe() {
    var wasListening = false;
    _stopPhase = widget.controller.phase.subscribe((phase) {
      final listening = phase == VoicePhase.listening;
      if (listening && !wasListening) WidgetsBinding.instance.addPostFrameCallback((_) => _announceListening());
      wasListening = listening;
    });
  }

  void _announceListening() {
    if (!mounted) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      S.of(context).voiceListeningAnnounce,
      Directionality.of(context),
    );
  }

  String? _issueText(S strings, VoiceIssue? issue, VoiceLocale locale) => switch (issue) {
    null => null,
    VoiceIssue.noPermission => strings.voiceNoPermission,
    VoiceIssue.unsupported => strings.voiceUnsupported,
    VoiceIssue.localeUnavailable =>
      locale == VoiceLocale.vi ? strings.voiceLocaleUnavailableVi : strings.voiceLocaleUnavailableEn,
    VoiceIssue.network => strings.voiceNetwork,
    VoiceIssue.failed => strings.voiceFailed,
  };

  String _blockedText(S strings, VoiceSendBlock blocked) => switch (blocked) {
    VoiceSendBlock.ended => strings.voiceEnded,
    VoiceSendBlock.detached => strings.voiceDetached,
    VoiceSendBlock.disconnected => strings.voiceNotLive,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = S.of(context);
    final controller = widget.controller;
    final blocked = widget.blocked;
    final canSend = blocked == null;
    final note = context.typo.paragraph13.copyWith(color: colors.secondaryText);
    return Watch((context) {
      final listening = controller.phase.value == VoicePhase.listening;
      final locale = controller.locale.value;
      final unavailable = controller.unavailable.value;
      final issue = controller.issue.value;
      final issueText = _issueText(strings, issue, locale);
      final hint = switch ((listening, locale)) {
        (true, VoiceLocale.vi) => strings.voiceListeningVi,
        (true, VoiceLocale.en) => strings.voiceListeningEn,
        (false, VoiceLocale.vi) => strings.voiceHintVi,
        (false, VoiceLocale.en) => strings.voiceHintEn,
      };
      return Container(
        color: colors.keyboardBackground,
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.target == null ? '' : strings.voiceTarget(widget.target!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.typo.paragraph.copyWith(color: colors.keyboardInk),
                  ),
                ),
                4.sizedWidth,
                _LocaleSwitch(
                  locale: locale,
                  unavailable: unavailable,
                  onChanged: controller.setLocale,
                ),
                IconButton(
                  key: const ValueKey('voice-close'),
                  tooltip: strings.voiceClose,
                  icon: Icon(Icons.close, color: colors.keyboardInk),
                  onPressed: controller.close,
                ),
              ],
            ),
            4.sizedHeight,
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('voice-text'),
                    controller: controller.text,
                    readOnly: listening,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    keyboardType: TextInputType.multiline,
                    // A command, not prose (A10 D30): no autocorrect, suggestions, learning, capital
                    // after a full stop, and iOS Smart Punctuation (`--` → `—`, `'` → `’`) off.
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    smartDashesType: SmartDashesType.disabled,
                    smartQuotesType: SmartQuotesType.disabled,
                    textCapitalization: TextCapitalization.none,
                    // A command: `--` vs `—`, `'` vs `’` and `l` vs `1` must read as in the terminal.
                    style: TextStyle(fontFamily: FontFamily.jetBrainsMono, fontSize: 15, color: colors.keyboardInk),
                    decoration: InputDecoration(
                      hintText: hint,
                      // keyboardInk at 70 %: ≥ 5.4:1 on the key colour in both themes (secondaryText is 4.4 in dark).
                      hintStyle: context.typo.subHeader15.copyWith(
                        fontFamily: FontFamily.raleway,
                        color: colors.keyboardInk.withValues(alpha: 0.7),
                      ),
                      hintMaxLines: 2,
                      isDense: true,
                      filled: true,
                      fillColor: colors.keyboardKey,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                ListenableBuilder(
                  listenable: controller.text,
                  builder: (context, _) => IconButton(
                    key: const ValueKey('voice-send'),
                    // An empty line still sends Enter: say so.
                    tooltip: controller.text.text.trim().isEmpty ? strings.voiceSendEnter : strings.voiceSend,
                    icon: Icon(
                      Icons.send,
                      color: canSend ? colors.keyboardLink : colors.keyboardInk.withValues(alpha: 0.4),
                    ),
                    onPressed: canSend ? controller.sendNow : null,
                  ),
                ),
              ],
            ),
            if (issueText != null)
              Padding(
                key: const ValueKey('voice-issue'),
                padding: const EdgeInsets.only(top: 6, right: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(issueText, style: context.typo.paragraph13.bold.copyWith(color: colors.keyboardError)),
                    if (issue == VoiceIssue.noPermission)
                      TextButton(
                        onPressed: widget.onOpenSettings,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          alignment: AlignmentDirectional.centerStart,
                        ),
                        child: Text(
                          strings.openSettings,
                          style: context.typo.subHeader15.bold.copyWith(color: colors.keyboardLink),
                        ),
                      ),
                  ],
                ),
              ),
            if (blocked != null)
              Padding(
                key: const ValueKey('voice-blocked'),
                padding: const EdgeInsets.only(top: 6, right: 4),
                child: Text(_blockedText(strings, blocked), style: note),
              ),
          ],
        ),
      );
    });
  }
}

/// VI | EN: a two-segment control, each segment at least 44 × 44 pt, no checkmark (the fill
/// shows the choice), so nothing moves when it changes. A language the phone cannot recognise is
/// disabled.
class _LocaleSwitch extends StatelessWidget {
  const _LocaleSwitch({required this.locale, required this.unavailable, required this.onChanged});

  final VoiceLocale locale;
  final Set<VoiceLocale> unavailable;
  final ValueChanged<VoiceLocale> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = S.of(context);
    return SegmentedButton<VoiceLocale>(
      showSelectedIcon: false,
      segments: [
        for (final option in VoiceLocale.values)
          ButtonSegment(
            value: option,
            enabled: !unavailable.contains(option),
            label: Text(
              option.languageCode.toUpperCase(),
              key: ValueKey('voice-locale-${option.languageCode}'),
              semanticsLabel: option == VoiceLocale.vi ? strings.voiceLanguageVi : strings.voiceLanguageEn,
            ),
          ),
      ],
      selected: {locale},
      onSelectionChanged: (selection) => onChanged(selection.single),
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 44)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
        tapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
        textStyle: WidgetStatePropertyAll(context.typo.paragraph.bold),
        side: WidgetStatePropertyAll(BorderSide(color: colors.keyboardInk.withValues(alpha: 0.15))),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colors.primaryFill : colors.keyboardKey,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? colors.keyboardInk.withValues(alpha: 0.4)
              : states.contains(WidgetState.selected)
              ? colors.onPrimary
              : colors.keyboardInk,
        ),
      ),
    );
  }
}
