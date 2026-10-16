import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/settings_schema.dart';

/// The page Settings opens on next (V2-1 D7: the AI pane's "Settings ›
/// Agents"); null: the usual first page. The overlay clears it.
final settingsStartPageProvider =
    NotifierProvider<SettingsStartPage, SettingPage?>(SettingsStartPage.new);

class SettingsStartPage extends Notifier<SettingPage?> {
  @override
  SettingPage? build() => null;

  void set(SettingPage? page) => state = page;
}
