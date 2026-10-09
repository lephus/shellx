/// A6 D26: the browser panes' private profile — never the user's system
/// browser profile, cleared every run unless "Giữ dữ liệu" is on.
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/settings_store.dart';
import '../terminal/sidebar_workspaces.dart' show settingsStoreProvider;

/// macOS side of D26 (Task 7 implements it over the BrowserNative channel).
abstract interface class WebsiteDataClearer {
  Future<void> clearWebsiteData();
}

final class BrowserProfile {
  BrowserProfile({
    required this.isWindows,
    required bool Function() keepData,
    String? localAppData,
    WebsiteDataClearer? clearer,
    Random? random,
  }) : _keepData = keepData,
       _localAppData = localAppData,
       _clearer = clearer,
       _random = random ?? Random.secure();

  final bool isWindows;
  final bool Function() _keepData;
  final String? _localAppData;
  final WebsiteDataClearer? _clearer;
  final Random _random;

  String? _userDataPath;

  /// Windows: the WebView2 user data folder chosen by [prepare].
  String? get userDataPath => _userDataPath;

  /// Whether the macOS clearer is wired (the real app must have it, or
  /// "keep data off" would clear nothing).
  bool get hasClearer => _clearer != null;

  /// Never a fallback location: without `%LOCALAPPDATA%` there is no safe
  /// place for a profile (a shared `C:\Users\Default` would be wrong).
  Directory get _root {
    final base = _localAppData;
    if (base == null || base.isEmpty) {
      throw StateError('no_local_app_data');
    }
    return Directory(
      '$base${Platform.pathSeparator}ShellX${Platform.pathSeparator}webview',
    );
  }

  /// Before the first web view of this run. Windows: removes every
  /// per-run folder of earlier runs (WebView2 locked them while running)
  /// and picks this run's folder. macOS: clears the app's website data
  /// unless kept — also covers a crash last time. Throws [StateError] on
  /// Windows without `%LOCALAPPDATA%`: no web view may start then.
  Future<void> prepare() async {
    if (!isWindows) {
      if (!_keepData()) await _clearer?.clearWebsiteData();
      return;
    }
    final root = _root;
    await root.create(recursive: true);
    await for (final entry in root.list(followLinks: false)) {
      final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (entry is Directory && name.startsWith('s-')) {
        try {
          await entry.delete(recursive: true);
        } on FileSystemException {
          // Still locked by a WebView2 process that outlived its app: next run.
        }
      }
    }
    final marker = File('${root.path}${Platform.pathSeparator}clear-profile');
    // Keeping is off now: whatever an earlier "keep" run left goes too.
    if (!_keepData() || await marker.exists()) {
      final kept = Directory('${root.path}${Platform.pathSeparator}profile');
      try {
        if (await kept.exists()) await kept.delete(recursive: true);
        if (await marker.exists()) await marker.delete();
      } on FileSystemException {
        // Still locked: try again next run.
      }
    }
    final name = _keepData() ? 'profile' : 's-${_hex(8)}';
    final dir = Directory('${root.path}${Platform.pathSeparator}$name');
    await dir.create(recursive: true);
    _userDataPath = dir.path;
  }

  /// On quit. macOS clears now; Windows cannot (folder locked) — the next
  /// [prepare] removes it.
  Future<void> onQuit() async {
    if (!isWindows && !_keepData()) await _clearer?.clearWebsiteData();
  }

  /// Tray "Xóa dữ liệu trình duyệt". macOS: everything now. Windows: the
  /// kept profile folder is removed at the next start (it is in use now);
  /// returns false when the change waits for a restart.
  Future<bool> clearNow() async {
    if (!isWindows) {
      await _clearer?.clearWebsiteData();
      return true;
    }
    if (_localAppData == null || _localAppData.isEmpty) return true;
    final kept = Directory('${_root.path}${Platform.pathSeparator}profile');
    if (_userDataPath == kept.path) {
      await File(
        '${_root.path}${Platform.pathSeparator}clear-profile',
      ).create(recursive: true);
      return false;
    }
    if (await kept.exists()) await kept.delete(recursive: true);
    return true;
  }

  String _hex(int bytes) => List.generate(
    bytes,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// The profile of this run. The window's startup (Task 9) calls [prepare]
/// before the first web view and passes the macOS clearer; until then
/// [clearNow] on macOS has nothing to clear (see [BrowserProfile.hasClearer]).
final browserProfileProvider = Provider<BrowserProfile>((ref) {
  final settings = ref.watch(settingsStoreProvider);
  return BrowserProfile(
    isWindows: Platform.isWindows,
    localAppData: Platform.environment['LOCALAPPDATA'],
    keepData: () =>
        settings.getBool(SettingKeys.browserKeepData, defaultValue: false),
  );
});
