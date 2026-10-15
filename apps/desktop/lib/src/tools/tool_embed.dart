import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/config_controller.dart';
import '../config/shellx_config.dart';

/// V2-3 D7, D20: whether tools show inside ShellX on [platform]. `auto` is
/// macOS only until the §11.2 check passes on a real Windows machine (then
/// this one line changes, with its test).
bool toolsEmbedded(ToolEmbed mode, TargetPlatform platform) => switch (mode) {
  ToolEmbed.on => true,
  ToolEmbed.off => false,
  ToolEmbed.auto => platform == TargetPlatform.macOS,
};

/// The platform tools run on; tests make it Windows.
final toolPlatformProvider = Provider<TargetPlatform>(
  (ref) => defaultTargetPlatform,
);

/// D20: false → every way to open a tool opens the system browser.
final toolsEmbeddedProvider = Provider<bool>(
  (ref) => toolsEmbedded(
    ref.watch(shellxConfigProvider.select((s) => s.config.toolEmbed)),
    ref.watch(toolPlatformProvider),
  ),
);
