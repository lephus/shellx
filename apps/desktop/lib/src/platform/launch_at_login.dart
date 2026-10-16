import 'dart:io';

import 'package:launch_at_startup/launch_at_startup.dart';

abstract interface class LaunchAtLogin {
  Future<bool> isEnabled();
  Future<void> setEnabled(bool enabled);
}

/// Package launch_at_startup. Windows: HKCU\...\Run value "ShellX".
/// macOS: the `launch_at_startup` channel in MainFlutterWindow.swift
/// (SMAppService on 13+, LaunchAgent plist on 12).
final class PackageLaunchAtLogin implements LaunchAtLogin {
  PackageLaunchAtLogin() {
    final exe = Platform.resolvedExecutable;
    launchAtStartup.setup(
      appName: 'ShellX',
      appPath: Platform.isWindows ? '"$exe"' : exe,
    );
  }

  @override
  Future<bool> isEnabled() => launchAtStartup.isEnabled();

  @override
  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
  }
}
