import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_core/shellx_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/agent_controller.dart';
import '../../agent/desktop_services.dart';
import '../../platform/url_opener.dart';
import '../window_router.dart';

/// First-run onboarding (spec §8.2 step 2).
class OnboardingPage extends ConsumerWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final services = ref.watch(desktopServicesProvider);
    final isMac = services.platform == DevicePlatform.macos;
    final launch = ref.watch(
      agentControllerProvider.select((s) => s.launchAtStartup),
    );
    final agent = ref.read(agentControllerProvider.notifier);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.onboardingTitle, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),
          SwitchListTile(
            key: const Key('onboarding.launch'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.onboardingLaunchAtStartup),
            value: launch,
            // Never throws (reverts or notifies on failure).
            onChanged: (value) => unawaited(agent.setLaunchAtStartup(value)),
          ),
          if (isMac) ...[
            const SizedBox(height: 16),
            Text(
              l10n.onboardingFullDiskTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(l10n.onboardingFullDiskBody),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('onboarding.fda'),
                onPressed: () => unawaited(_openPrivacySettings(services)),
                child: Text(l10n.onboardingOpenSettings),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(l10n.onboardingSleepTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(l10n.onboardingSleepBody),
          const Spacer(),
          Text(
            l10n.onboardingTrayHint(isMac ? 'macos' : 'windows'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('onboarding.finish'),
            // completeOnboarding never throws.
            onPressed: () async {
              await agent.completeOnboarding();
              ref.read(windowRouterProvider.notifier).close();
            },
            child: Text(l10n.onboardingFinish),
          ),
        ],
      ),
    );
  }

  /// Opening System Settings may fail (e.g. `open` cannot be started):
  /// never an unhandled error, a notification instead.
  static Future<void> _openPrivacySettings(DesktopServices services) async {
    try {
      await services.urlOpener.open(SystemUrlOpener.fullDiskAccessPane);
    } catch (error) {
      debugPrint(
        'ShellX: opening System Settings failed: ${error.runtimeType}',
      );
      try {
        await services.notifier.show(
          title: services.l10n.errorUnexpected('internal'),
        );
      } catch (_) {
        // Nothing else to do here.
      }
    }
  }
}
