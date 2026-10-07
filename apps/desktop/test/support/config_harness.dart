import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/config/config_paths.dart';

import 'memory_config_fs.dart';

const kTestHome = '/home/me';

ConfigPaths testConfigPaths({bool windows = false}) =>
    configPathsFor(windows: windows, env: const {}, home: kTestHome);

/// A9: every test that loads a configuration reads [fs], never the
/// developer's real `~/.config/shellx/config`.
List<Override> configOverrides(
  MemoryConfigFs fs, {
  TargetPlatform platform = TargetPlatform.macOS,
}) => [
  configFsProvider.overrideWithValue(fs),
  configPathsProvider.overrideWithValue(testConfigPaths()),
  configPlatformProvider.overrideWithValue(platform),
];

Future<ConfigState> loadConfig(ProviderContainer container) =>
    container.read(shellxConfigProvider.notifier).load();
