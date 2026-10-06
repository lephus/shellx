import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';
import 'package:shellx_mobile/features/voice/presentation/controllers/voice_composer_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// The panel above the extra keys while voice input is open (voice spec §3.1): where the line
/// goes, the language, the editable text, Send and ✕, and the issue line (§5).
class VoiceComposer extends StatelessWidget {
  const VoiceComposer({
    super.key,
    required this.controller,
    required this.target,
    required this.canSend,
    required this.onOpenSettings,
  });

  final VoiceComposerController controller;

  /// "zsh · MacBook"; null without a tab.
  final String? target;
  final bool canSend;
  final VoidCallback onOpenSettings;

  String? _issueText(S strings, VoiceIssue? issue, VoiceLocale locale) => switch (issue) {
    null => null,
    VoiceIssue.noPermission => strings.voiceNoPermission,
    VoiceIssue.unsupported => strings.voiceUnsupported,
    VoiceIssue.localeUnavailable =>
      locale == VoiceLocale.vi ? strings.voiceLocaleUnavailableVi : strings.voiceLocaleUnavailableEn,
    VoiceIssue.network => strings.voiceNetwork,
    VoiceIssue.failed => strings.voiceFailed,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = S.of(context);
    return Watch((context) {
      final listening = controller.phase.value == VoicePhase.listening;
      final locale = controller.locale.value;
      final unavailable = controller.unavailable.value;
      final issue = controller.issue.value;
      final issueText = _issueText(strings, issue, locale);
      return Container(
        color: context.colors.keyboardBackground,
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    target == null ? '' : strings.voiceTarget(target!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.typo.paragraph.copyWith(color: colors.keyboardInk),
                  ),
                ),
                for (final option in VoiceLocale.values)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: ChoiceChip(
                      key: ValueKey('voice-locale-${option.languageCode}'),
                      label: Text(
                        option.languageCode.toUpperCase(),
                        semanticsLabel: option == VoiceLocale.vi ? strings.voiceLanguageVi : strings.voiceLanguageEn,
                      ),
                      selected: option == locale,
                      onSelected: unavailable.contains(option) ? null : (_) => controller.setLocale(option),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                IconButton(
                  key: const ValueKey('voice-close'),
                  tooltip: strings.voiceClose,
                  icon: Icon(Icons.close, color: colors.keyboardInk),
                  onPressed: controller.close,
                ),
              ],
            ),
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
                    decoration: InputDecoration(
                      hintText: locale == VoiceLocale.vi ? strings.voiceHintVi : strings.voiceHintEn,
                      isDense: true,
                      filled: true,
                      fillColor: colors.keyboardKey,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('voice-send'),
                  tooltip: strings.voiceSend,
                  icon: Icon(Icons.send, color: canSend ? colors.primary : colors.keyboardInk.withValues(alpha: 0.4)),
                  onPressed: canSend ? controller.sendNow : null,
                ),
              ],
            ),
            if (issueText != null)
              Row(
                key: const ValueKey('voice-issue'),
                children: [
                  Expanded(
                    child: Text(issueText, style: context.typo.paragraph.copyWith(color: colors.error)),
                  ),
                  if (issue == VoiceIssue.noPermission)
                    TextButton(onPressed: onOpenSettings, child: Text(strings.openSettings)),
                ],
              ),
            if (!canSend)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(strings.voiceNotLive, style: context.typo.paragraph.copyWith(color: colors.keyboardInk)),
              ),
          ],
        ),
      );
    });
  }
}
