/// A6 §3.2: what a browser pane needs from WKWebView / WebView2. One
/// implementation per platform (Tasks 7, 8) and a fake for tests.
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart' show Widget;

import 'browser_bridge.dart';

/// D14: why a load failed (drives the error page copy).
enum BrowserLoadErrorKind {
  refused,
  unreachable,
  dns,
  timeout,
  certificate,
  crashed,
  unavailable,
  other,
}

sealed class BrowserEngineEvent {
  const BrowserEngineEvent();
}

final class UrlChanged extends BrowserEngineEvent {
  const UrlChanged(this.url);
  final Uri url;
}

final class TitleChanged extends BrowserEngineEvent {
  const TitleChanged(this.title);
  final String title;
}

final class LoadStarted extends BrowserEngineEvent {
  const LoadStarted();
}

/// 0–100; engines without progress (WebView2) never send it (D13).
final class LoadProgress extends BrowserEngineEvent {
  const LoadProgress(this.percent);
  final int percent;
}

final class LoadFinished extends BrowserEngineEvent {
  const LoadFinished();
}

final class LoadFailed extends BrowserEngineEvent {
  const LoadFailed(this.kind);
  final BrowserLoadErrorKind kind;
}

final class HistoryChanged extends BrowserEngineEvent {
  const HistoryChanged({required this.canGoBack, required this.canGoForward});
  final bool canGoBack;
  final bool canGoForward;
}

/// One raw bridge message from the page (D21) — parsed by the controller.
final class BridgeReceived extends BrowserEngineEvent {
  const BridgeReceived(this.raw);
  final String raw;
}

/// D10: a top-level navigation to a scheme a pane may not show.
final class NavigationBlocked extends BrowserEngineEvent {
  const NavigationBlocked();
}

/// D10: a download was cancelled.
final class DownloadBlocked extends BrowserEngineEvent {
  const DownloadBlocked();
}

/// D15: a ShellX chord pressed while the web content had the keyboard.
final class ShortcutForwarded extends BrowserEngineEvent {
  const ShortcutForwarded(this.chord);
  final String chord;
}

/// D16: a mouse press inside the web content (macOS reports it natively;
/// on Windows the Flutter `Listener` around the texture sees it).
final class ContentClicked extends BrowserEngineEvent {
  const ContentClicked();
}

abstract interface class BrowserEngine {
  Stream<BrowserEngineEvent> get events;

  /// The page → ShellX channel this engine uses (D21).
  BridgeTransport get transport;

  Future<void> load(Uri url);
  Future<void> goBack();
  Future<void> goForward();
  Future<void> reload();
  Future<void> stop();

  /// Runs [script] in the top frame; the result, if any, comes back as a
  /// [BridgeReceived] (D19). Throws when the engine rejects the script.
  Future<void> runScript(String script);

  /// D24: the viewport as PNG at the screen's pixel ratio.
  Future<Uint8List> capturePng();

  /// D15: the chords to hand back to Flutter while the page has focus.
  Future<void> setForwardedChords(List<String> chords);

  /// D16: give the keyboard to the web content (first responder /
  /// WebView2 `MoveFocus`).
  Future<void> focusContent();

  /// D16: give the keyboard back to Flutter (the page must not keep the
  /// first responder once another pane or region has the focus).
  Future<void> releaseFocus();

  Widget buildView();

  Future<void> dispose();
}
