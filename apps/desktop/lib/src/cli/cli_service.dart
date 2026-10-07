import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../mux/mux_paths.dart';
import '../mux/windows_pipe_transport.dart';
import '../platform/settings_store.dart';
import '../terminal/sidebar_workspaces.dart' show settingsStoreProvider;
import 'cli_host_control.dart';
import 'cli_install.dart';
import 'ui_command_handler.dart';

export 'cli_host_control.dart';

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

/// D26 "Copy the agent skill install command".
final cliClipboardProvider = Provider<Future<void> Function(String text)>(
  (_) =>
      (text) => Clipboard.setData(ClipboardData(text: text)),
);

/// A7 D2, C1: the command-line host of the window process (before A5b's
/// daemon). Starts after the single-instance lock is held, and also holds
/// the mux directory's own lock (`mux.lock`, the one A5b's daemon takes),
/// so two hosts never serve one address.
///
/// Final ruling M1: it listens ([listen]) before the shells' environment
/// is built, so only a running host's address and token reach them; the
/// window comes later ([attach]) — requests that arrive before wait for it.
// TODO(A5b Task 7): `cli_control_enabled` and `cli_allow_external` are
// daemon-owned (D13); this host moves to the daemon, which reads them from
// its own store. Until then this file is exempt from the ownership scan.
final class CliService {
  CliService._(
    this._host,
    this._lock,
    this._ui,
    this._settingsStore,
    this.address,
  );

  bool _stopped = false;

  final CliHost _host;
  final _MuxLock _lock;
  final _LateUi _ui;
  final SettingsStore _settingsStore;
  bool _attached = false;

  /// The socket path or pipe name (`SHELLX_SOCKET`).
  final String address;

  /// D7: refreshes [cliPaths]' `shellx` (failures logged by type only),
  /// then serves the CLI API at [paths]. [token] is the launch's
  /// `SHELLX_CLI_TOKEN`; clients without it get the full API only while
  /// "Allow other terminals" is ticked in [settings] (amendment). `ui.*`
  /// requests wait until [attach]. Throws when the host cannot start (the
  /// app then runs without the command line); nothing is left listening
  /// or locked then (final ruling M3).
  static Future<CliService> listen({
    required MuxPaths paths,
    required SettingsStore settings,
    required String appVersion,
    required String token,
    CliPaths? cliPaths,
    bool installBinary = true,
  }) async {
    if (installBinary && cliPaths != null) {
      try {
        await CliBinaryInstaller(cliPaths).ensureCurrent();
      } on Object catch (e) {
        debugPrint('ShellX: cli binary install failed: ${e.runtimeType}');
      }
    }
    final lock = await _MuxLock.acquire(paths);
    final ui = _LateUi();
    CliHost? host;
    try {
      host = CliHost(
        transport: paths.windows ? WindowsPipeTransport() : UnixMuxTransport(),
        address: paths.address,
        endpointFile: MuxEndpointFile(paths.endpoint),
        ui: ui,
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
      // M3: listening may have begun before the failure (the endpoint file).
      try {
        await host?.stop();
      } on Object catch (e) {
        debugPrint('ShellX: cli host stop failed: ${e.runtimeType}');
      }
      await lock.release();
      rethrow;
    }
    return CliService._(host, lock, ui, settings, paths.address);
  }

  /// [listen] with what [c] provides, then [attach] to it (tests).
  static Future<CliService> start(
    ProviderContainer c, {
    required String appVersion,
    required String token,
    bool installBinary = true,
  }) async {
    final service = await listen(
      paths: c.read(cliMuxPathsProvider),
      cliPaths: c.read(cliPathsProvider),
      settings: c.read(settingsStoreProvider),
      appVersion: appVersion,
      token: token,
      installBinary: installBinary,
    );
    service.attach(c);
    return service;
  }

  /// The window is up: requests reach its tabs; the tray's settings
  /// recheck open connections; Quit stops the host first (ruling M6).
  /// Once. [c]'s settings store must be the one [listen] got.
  void attach(ProviderContainer c) {
    if (_stopped || _attached) return;
    assert(identical(c.read(settingsStoreProvider), _settingsStore));
    _attached = true;
    c.read(cliHostControlProvider)
      ..stop = stop
      ..recheck = _host.recheck;
    _ui.bind(c.read(uiCommandHandlerProvider));
  }

  /// Closes every connection and removes the endpoint file. Once.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    try {
      await _host.stop();
    } finally {
      await _lock.release();
    }
  }
}

/// Final ruling M1: the window's [UiApi] once [bind] gave it; until then
/// requests and notices wait, and events start once it is there.
final class _LateUi implements UiApi {
  final _ui = Completer<UiApi>();
  UiApi? _bound;

  /// A window that never attaches (a startup that hangs) cannot hold a
  /// request open: after this the request fails as `busy`.
  static const attachWait = Duration(seconds: 15);

  Future<UiApi> _ready() => _bound != null
      ? Future.value(_bound)
      : _ui.future.timeout(
          attachWait,
          onTimeout: () =>
              throw const CliFailure('busy', 'ShellX is still starting'),
        );

  void bind(UiApi ui) {
    _bound = ui;
    _ui.complete(ui);
  }

  @override
  Future<Map<String, Object?>> handle(
    MuxMessage request, {
    Future<void>? cancelled,
    bool Function()? isGone,
  }) async =>
      (await _ready()).handle(request, cancelled: cancelled, isGone: isGone);

  @override
  Stream<Map<String, Object?>> events() =>
      _bound?.events() ??
      Stream.fromFuture(_ui.future).asyncExpand((ui) => ui.events());

  @override
  Future<void> notifyApp({String? title, required String body}) async =>
      (await _ready()).notifyApp(title: title, body: body);

  /// No window yet: no pane either.
  @override
  bool notifyPane(int pane, {String? title, required String body}) =>
      _bound?.notifyPane(pane, title: title, body: body) ?? false;
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
