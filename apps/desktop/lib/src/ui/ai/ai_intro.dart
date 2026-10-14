import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/agent_controller.dart';
import '../../config/config_controller.dart' show shellxConfigProvider;
import '../../config/shellx_config.dart' show NewTabKind;
import '../../platform/settings_store.dart';
import '../../terminal/sidebar_workspaces.dart' show settingsStoreProvider;
import '../settings/pages/page_parts.dart' show settingById;
import '../settings/settings_writer.dart';
import '../theme/shellx_desktop_theme.dart';

/// D4: how new tabs open, written to the configuration file as
/// `new-tab-kind` (as Settings › General writes it). Never throws.
Future<void> chooseNewTabKind(WidgetRef ref, NewTabKind kind) async {
  final result = await ref
      .read(settingsWriterProvider)
      .set(settingById('new-tab-kind'), kind.name);
  if (result is! Saved) {
    debugPrint('ShellX: new-tab-kind not saved: ${result.runtimeType}');
  }
}

/// D4: the one-time "New: an AI interface" card is due — for someone who
/// finished onboarding before V2 and has not answered it (`ai_intro_shown`).
/// Onboarding itself asks the question, so it marks the card done.
final aiIntroDueProvider = NotifierProvider<AiIntroDue, bool>(AiIntroDue.new);

class AiIntroDue extends Notifier<bool> {
  @override
  bool build() {
    // Onboarding is the agent's to know (a daemon key): its state, not the
    // store.
    final onboarded = ref.watch(
      agentControllerProvider.select((s) => s.onboardingDone),
    );
    return onboarded &&
        !ref
            .read(settingsStoreProvider)
            .getBool(SettingKeys.aiIntroShown, defaultValue: false);
  }

  /// Answered or closed: never again. Never throws.
  Future<void> done() async {
    state = false;
    try {
      await ref
          .read(settingsStoreProvider)
          .setBool(SettingKeys.aiIntroShown, true);
    } on Object catch (error) {
      debugPrint('ShellX: intro not saved: ${error.runtimeType}');
    }
  }
}

/// D4: onboarding's "How do you want to work?" — AI interface or Terminal,
/// written at once; "You can change this any time in Settings › General."
class AiOnboardingChoice extends ConsumerWidget {
  const AiOnboardingChoice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final kind = ref.watch(
      shellxConfigProvider.select((s) => s.config.newTabKind),
    );
    Widget option(NewTabKind value, String title, String body, Key key) {
      final on = kind == value;
      return Semantics(
        selected: on,
        button: true,
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(ShellxRadius.r6),
          onTap: () => unawaited(chooseNewTabKind(ref, value)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: ShellxSpace.s6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  on
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: on
                      ? ShellxDesktopColors.accent
                      : ShellxDesktopColors.textSecondary,
                ),
                const SizedBox(width: ShellxSpace.s8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.bodyLarge),
                      Text(body, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.aiOnboardingTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: ShellxSpace.s4),
        option(
          NewTabKind.ai,
          l10n.aiNewTabKindAi,
          l10n.aiOnboardingAiBody,
          const Key('onboarding.ai'),
        ),
        option(
          NewTabKind.terminal,
          l10n.aiNewTabKindTerminal,
          l10n.aiOnboardingTerminalBody,
          const Key('onboarding.terminal'),
        ),
        Text(l10n.aiOnboardingNote, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// D4: the one-time card for people who knew ShellX before V2, at the foot
/// of the sidebar: "New: an AI interface. How should new tabs open?" — AI
/// interface / Terminal / ×. Nothing when it is not due.
class AiIntroCard extends ConsumerWidget {
  const AiIntroCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(aiIntroDueProvider)) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final intro = ref.read(aiIntroDueProvider.notifier);
    Future<void> pick(NewTabKind kind) async {
      await chooseNewTabKind(ref, kind);
      await intro.done();
    }

    return Container(
      key: const Key('ai.intro'),
      margin: const EdgeInsets.fromLTRB(
        ShellxSpace.s8,
        ShellxSpace.s4,
        ShellxSpace.s8,
        0,
      ),
      padding: const EdgeInsets.fromLTRB(
        ShellxSpace.s8,
        ShellxSpace.s4,
        0,
        ShellxSpace.s8,
      ),
      decoration: BoxDecoration(
        color: ShellxDesktopColors.surface,
        borderRadius: BorderRadius.circular(ShellxRadius.r8),
        border: Border.all(color: ShellxDesktopColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                size: 14,
                color: ShellxDesktopColors.accent,
              ),
              const SizedBox(width: ShellxSpace.s6),
              Expanded(
                child: Text(
                  l10n.aiIntroText,
                  style: ShellxText.small.copyWith(
                    color: ShellxDesktopColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                key: const Key('ai.intro.close'),
                tooltip: l10n.actionClose,
                iconSize: 14,
                visualDensity: VisualDensity.compact,
                onPressed: () => unawaited(intro.done()),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Wrap(
            spacing: ShellxSpace.s6,
            children: [
              OutlinedButton(
                key: const Key('ai.intro.ai'),
                onPressed: () => unawaited(pick(NewTabKind.ai)),
                child: Text(l10n.aiNewTabKindAi),
              ),
              TextButton(
                key: const Key('ai.intro.terminal'),
                onPressed: () => unawaited(pick(NewTabKind.terminal)),
                child: Text(l10n.aiNewTabKindTerminal),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
