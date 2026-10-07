import 'package:flutter/material.dart';

import '../../../config/settings_schema.dart';
import 'page_parts.dart';

/// Appearance: theme, font, size, weight, line height, padding, cursor and
/// colors. (Task 10 adds the live sample and the theme list.)
class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context) => PageFrame(
    children: [
      for (final def in kSettings)
        if (def.page == SettingPage.appearance) settingWidget(def),
    ],
  );
}
