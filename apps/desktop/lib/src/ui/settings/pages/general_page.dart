import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../agent/desktop_services.dart';
import '../../theme/shellx_desktop_theme.dart';
import 'page_parts.dart';

/// General: the app switches that are not about one area (launch at login,
/// keep awake, the background service) and the version.
class GeneralPage extends ConsumerWidget {
  const GeneralPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    String? version;
    try {
      version = ref.watch(desktopServicesProvider).appVersion;
    } catch (_) {
      version = null; // No desktop services (a test): no version line.
    }
    return PageFrame(
      children: [
        settingWidget(settingById('launch-at-startup')),
        settingWidget(settingById('keep-awake')),
        settingWidget(settingById('background-service')),
        if (version != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
            child: Text(
              l10n.settingsVersion(version),
              key: const Key('settings.version'),
              style: ShellxText.small.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}
