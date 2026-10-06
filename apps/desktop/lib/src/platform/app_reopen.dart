import 'package:flutter/services.dart';

/// `pro.shellx.desktop/app` (AppDelegate.swift). Native → Dart: `reopen`
/// (Finder, Spotlight, Launchpad or the Dock open the running app again;
/// macOS sends a reopen event instead of starting a second process, so the
/// single-instance signal never fires) and `quitRequested` (⌘Q or the app
/// menu's Quit, A1 D10). Dart → native: `setDockVisible`.
const MethodChannel appChannel = MethodChannel('pro.shellx.desktop/app');

void listenForAppChannel({
  required void Function() onReopen,
  required void Function() onQuitRequested,
  MethodChannel channel = appChannel,
}) {
  channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'reopen':
        onReopen();
      case 'quitRequested':
        onQuitRequested();
    }
  });
}

/// macOS: `.regular` activation policy while the window is visible (Dock
/// icon, ⌘Tab, menu bar with ⌘Q), `.accessory` while hidden (A1 D10).
Future<void> setDockVisible(
  bool visible, {
  MethodChannel channel = appChannel,
}) => channel.invokeMethod<void>('setDockVisible', visible);
