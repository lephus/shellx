import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../mux/mux_paths.dart';
import '../mux/windows_pipe_transport.dart';
import '../platform/settings_store.dart';
import '../terminal/sidebar_workspaces.dart' show settingsStoreProvider;
import 'cli_install.dart';
import 'cli_settings.dart';
import 'ui_command_handler.dart';

/// Where the host listens (A5b `MuxPaths`); set in `main.dart`.
final cliMuxPathsProvider = Provider<MuxPaths>(
  (_) => throw UnimplementedError('cliMuxPathsProvider is set in main'),
);

/// D7, D8: the command's folder; null without `HOME` / `LOCALAPPDATA`.
final cliPathsProvider = Provider<CliPaths?>((_) => null);

/// D8: "Install the shellx command for all terminals…"; set in `main.dart`.
final cliPathInstallerProvider = Provider<PathInstaller?>((_) => null);

/// Ruling M10 (macOS): after an install, whether `/usr/local/bin` is
/// missing from the login shell's `PATH`, and what to add; set in
/// `main.dart`.
final cliLoginPathCheckProvider = Provider<Future<LoginPathHint?> Function()?>(
  (_) => null,
);

/// Ruling M6: lets Quit stop the host first, before the sessions close.
final cliHostControlProvider = Provider<CliHostControl>(
  (_) => CliHostControl(),
);

final class CliHostControl {
  /// Set by a running [CliService].
  Future<void> Function()? stop;

  /// Stops the host once; nothing when none runs.
  Future<void> stopNow() async {
    final s = stop;
    stop = null;
    await s?.call();
  }
}

/// D26 "Copy the agent skill install command".
final cliClipboardProvider = Provider<Future<void> Function(String text)>(
  (_) =>
      (text) => Clipboard.setData(ClipboardData(text: text)),
);

/// A7 D2, C1: the command-line host of the window process (before A5b's
/// daemon). Starts after the single-instance lock is held, and also holds
/// the mux directory's own lock (`mux.lock`, the one A5b's daemon takes),
/// so two hosts never serve one address.
final class CliService {
  CliService._(this._host, this._lock, this._settings, this.address);

  bool _stopped = false;

  final CliHost _host;
  final _MuxLock _lock;
  final CliSettings _settings;

  /// The socket path or pipe name (`SHELLX_SOCKET`).
  final String address;

  /// D7: refreshes `<support>/cli/shellx` (failures logged by type only),
  /// then serves the CLI API. [token] is the launch's `SHELLX_CLI_TOKEN`;
  /// clients without it get the full API only while "Allow other
  /// terminals" is ticked (amendment). Throws when the host cannot start
  /// (the app then runs without the command line).
  static Future<CliService> start(
    ProviderContainer c, {
    required String appVersion,
    required String token,
    bool installBinary = true,
  }) async {
    if (installBinary) {
      final paths = c.read(cliPathsProvider);
      if (paths != null) {
        try {
          await CliBinaryInstaller(paths).ensureCurrent();
        } on Object catch (e) {
          debugPrint('ShellX: cli binary install failed: ${e.runtimeType}');
        }
      }
    }
    final paths = c.read(cliMuxPathsProvider);
    final settings = c.read(settingsStoreProvider);
    final lock = await _MuxLock.acquire(paths);
    final CliHost host;
    try {
      host = CliHost(
        transport: paths.windows ? WindowsPipeTransport() : UnixMuxTransport(),
        address: paths.address,
        endpointFile: MuxEndpointFile(paths.endpoint),
        ui: c.read(uiCommandHandlerProvider),
        enabled: () =>
            settings.getBool(SettingKeys.cliControlEnabled, defaultValue: true),
        token: token,
        allowExternal: () =>
            settings.getBool(SettingKeys.cliAllowExternal, defaultValue: false),
        appVersion: appVersion,
        log: (m) => debugPrint('ShellX: $m'),
      );
      await host.start();
    } catch (_) {
      await lock.release();
      rethrow;
    }
    final cliSettings = c.read(cliSettingsProvider.notifier)
      ..onChanged = host.recheck;
    final service = CliService._(host, lock, cliSettings, paths.address);
    c.read(cliHostControlProvider).stop = service.stop;
    return service;
  }

  /// Closes every connection and removes the endpoint file. Once.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    if (_settings.onChanged == _host.recheck) _settings.onChanged = null;
    try {
      await _host.stop();
    } finally {
      await _lock.release();
    }
  }
}

/// `mux/mux.lock`, exclusive, for the host's lifetime. The directory is
/// made first (0700 on macOS: the socket and the endpoint live there).
final class _MuxLock {
  _MuxLock(this._handle);
  final RandomAccessFile _handle;

  static Future<_MuxLock> acquire(MuxPaths paths) async {
    await Directory(paths.muxDirectory).create(recursive: true);
    if (!paths.windows) {
      final r = await Process.run('/bin/chmod', ['700', paths.muxDirectory]);
      if (r.exitCode != 0) {
        throw FileSystemException('chmod 700 failed', paths.muxDirectory);
      }
    }
    final handle = await File(paths.lock).open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.exclusive);
    } on FileSystemException {
      await handle.close();
      throw StateError('another ShellX host holds the mux lock');
    }
    return _MuxLock(handle);
  }

  Future<void> release() async {
    try {
      await _handle.unlock();
    } finally {
      await _handle.close();
    }
  }
}
