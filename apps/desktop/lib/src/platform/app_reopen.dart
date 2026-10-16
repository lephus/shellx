import 'package:flutter/services.dart';

/// `pro.shellx.desktop/app` (AppDelegate.swift; Windows
/// flutter_window.cpp sends only the three A5a calls). Native → Dart:
/// `reopen` (Finder, Spotlight, Launchpad or the Dock open the running app
/// again; macOS sends a reopen event instead of starting a second process,
/// so the single-instance signal never fires), `quitRequested` (⌘Q or the
/// app menu's Quit, A1 D10), `saveBeforeExit` (A5a D18: log out, restart
/// or shut down; answered once the save is done) and `exitCancelled` (that
/// exit did not happen after all) and `quitAfterSave` (Windows Restart
/// Manager: the save is done, now quit) and `quitAllRequested` (A5b: the
/// app menu's ⌥⌘Q). Dart → native: `setDockVisible`, `activate`,
/// `setQuitAllTitle`.
const MethodChannel appChannel = MethodChannel('pro.shellx.desktop/app');

void listenForAppChannel({
  required void Function() onReopen,
  required void Function() onQuitRequested,
  Future<void> Function()? onSaveBeforeExit,
  void Function()? onExitCancelled,
  void Function()? onQuitAfterSave,
  void Function()? onQuitAllRequested,
  MethodChannel channel = appChannel,
}) {
  channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'reopen':
        onReopen();
      case 'quitRequested':
        onQuitRequested();
      case 'saveBeforeExit':
        // A5a D18: the OS is shutting down or logging out; the native side
        // waits (at most 3 s) for this call to return.
        await onSaveBeforeExit?.call();
      case 'exitCancelled':
        onExitCancelled?.call();
      case 'quitAfterSave':
        onQuitAfterSave?.call();
      case 'quitAllRequested':
        // A5b D14: ⌥⌘Q in the app menu ("Thoát hoàn toàn").
        onQuitAllRequested?.call();
    }
  });
}

/// macOS: `.regular` activation policy while the window is visible (Dock
/// icon, ⌘Tab, menu bar with ⌘Q), `.accessory` while hidden (A1 D10).
Future<void> setDockVisible(
  bool visible, {
  MethodChannel channel = appChannel,
}) => channel.invokeMethod<void>('setDockVisible', visible);

/// macOS (A5b UI-A5 §6.1): adds "Thoát hoàn toàn ⌥⌘Q" after Quit in the
/// app menu, titled [title]; called once at startup, only by a window that
/// attaches to the background service.
Future<void> setQuitAllTitle(
  String title, {
  MethodChannel channel = appChannel,
}) => channel.invokeMethod<void>('setQuitAllTitle', title);

/// macOS: `NSApp.activate(ignoringOtherApps: true)`, so the window comes in
/// front of the app the user was in (a tray click, the Dock, a second
/// launch).
Future<void> activateMacApp({MethodChannel channel = appChannel}) =>
    channel.invokeMethod<void>('activate');
