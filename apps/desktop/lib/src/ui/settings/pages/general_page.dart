import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../agent/desktop_services.dart';
import '../../../agent/update_check.dart';
import '../../config/config_ui_request.dart';
import '../../theme/shellx_desktop_theme.dart';
import '../update_check_ui.dart';
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
        settingWidget(settingById('app-language')),
        settingWidget(settingById('launch-at-startup')),
        settingWidget(settingById('keep-awake')),
        settingWidget(settingById('background-service')),
        // A11 D9 -> D24: the tour again. The window swaps Settings for it.
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: TextButton(
              key: const Key('settings.tour'),
              onPressed: () => ref
                  .read(configUiRequestProvider.notifier)
                  .request(ConfigUiRequest.tour),
              child: Text(l10n.settingsOpenTour),
            ),
          ),
        ),
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
        const _UpdateRow(),
      ],
    );
  }
}

/// A12 D20: the button, and what it found right under it (a live region:
/// the answer is spoken). It never installs anything: "Download" opens the
/// page the relay named, if the app trusts it.
class _UpdateRow extends ConsumerWidget {
  const _UpdateRow();

  Future<void> _download(WidgetRef ref, Uri url) async {
    try {
      await ref.read(desktopServicesProvider).urlOpener.open(url);
    } on Object catch (e) {
      debugPrint('ShellX: update page not opened: ${e.runtimeType}');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ui = ref.watch(updateCheckUiProvider);
    final result = ui.result;
    final style = ShellxText.small.copyWith(
      color: ShellxDesktopColors.textSecondary,
    );
    final lines = <Widget>[];
    if (ui.checking) {
      lines.add(Text(l10n.updateChecking, style: style));
    } else {
      switch (result) {
        case UpToDate(:final version):
          lines.add(Text(l10n.updateUpToDate(version), style: style));
        case Available(:final notice):
          lines.add(Text(l10n.updateAvailable(notice.version), style: style));
          if (notice.required) {
            lines.add(Text(l10n.updateRequired, style: style));
          }
        case Failed():
          lines.add(Text(l10n.updateFailed, style: style));
        case null:
          break;
      }
    }
    final available = !ui.checking && result is Available ? result : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                key: const Key('settings.update.check'),
                onPressed: ui.checking
                    ? null
                    : () => unawaited(
                        ref.read(updateCheckUiProvider.notifier).check(),
                      ),
                child: Text(l10n.updateCheck),
              ),
              if (available != null)
                TextButton(
                  key: const Key('settings.update.download'),
                  onPressed: () =>
                      unawaited(_download(ref, available.notice.url)),
                  child: Text(l10n.updateDownload),
                ),
            ],
          ),
          if (lines.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Semantics(
                liveRegion: true,
                container: true,
                child: Column(
                  key: const Key('settings.update.result'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: lines,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
