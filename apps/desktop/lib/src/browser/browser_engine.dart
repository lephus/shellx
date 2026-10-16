/// A6 §3.2, taken for V2-3 tools (D6, D16): what a page needs from
/// WKWebView (macOS) or WebView2 (Windows). No bridge, no script, no
/// screenshot: ShellX never runs code in a tool's page. One engine per
/// platform, and a fake for tests.
library;

import 'package:flutter/widgets.dart' show Widget;

/// D13 (A6 D14): why a load failed; it picks the panel's words.
enum BrowserLoadErrorKind {
  refused,
  unreachable,
  dns,
  timeout,
  certificate,

  /// macOS App Transport Security refused plain http (D19).
  ats,
  crashed,

  /// No engine (Windows without the WebView2 Runtime, §8).
  unavailable,
  other,
}

sealed class BrowserEngineEvent {
  const BrowserEngineEvent();
}

final class UrlChanged extends BrowserEngineEvent {
  const UrlChanged(this.url);
  final Uri url;

  @override
  String toString() => 'UrlChanged(…)';
}

final class TitleChanged extends BrowserEngineEvent {
  const TitleChanged(this.title);
  final String title;

  @override
  String toString() => 'TitleChanged(…)';
}

final class LoadStarted extends BrowserEngineEvent {
  const LoadStarted();
}

/// 0–100; engines without progress (WebView2) never send it.
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

  @override
  String toString() => 'LoadFailed(${kind.name})';
}

final class HistoryChanged extends BrowserEngineEvent {
  const HistoryChanged({required this.canGoBack, required this.canGoForward});
  final bool canGoBack;
  final bool canGoForward;
}

/// D9: a navigation the page may not make (a `file:`, `javascript:` or
/// `data:` page, an unknown scheme). Refused without a word.
final class NavigationBlocked extends BrowserEngineEvent {
  const NavigationBlocked();
}

/// D9: the page asked for [url] outside itself — a new window
/// (`target=_blank`, `window.open`) or a `mailto:`/`tel:` link. The engine
/// already kept it out of the page; the tool page opens it outside.
final class OpenOutside extends BrowserEngineEvent {
  const OpenOutside(this.url, {required this.newWindow});
  final Uri url;
  final bool newWindow;

  @override
  String toString() => 'OpenOutside(…)';
}

/// D9: a download was stopped; [url] is what it would have fetched, when
/// the engine says.
final class DownloadBlocked extends BrowserEngineEvent {
  const DownloadBlocked({this.url});
  final Uri? url;

  @override
  String toString() => 'DownloadBlocked(…)';
}

/// D10: a ShellX chord (config spelling, `chordConfigText`) pressed while
/// the page had the keyboard; the page never saw it.
final class ShortcutForwarded extends BrowserEngineEvent {
  const ShortcutForwarded(this.chord);
  final String chord;
}

/// D10: a mouse press inside the page (macOS reports it natively).
final class ContentClicked extends BrowserEngineEvent {
  const ContentClicked();
}

/// What a navigation may do (D9, decided by `toolNavigation`).
enum NavigationVerdict { allow, outside, block }

/// D9: [url] (null: not a URL) in the top frame ([mainFrame]) or a frame of
/// the page, or as a new window ([newWindow]).
typedef NavigationPolicy =
    NavigationVerdict Function(
      Uri? url, {
      required bool mainFrame,
      required bool newWindow,
    });

enum BrowserJsDialogKind { alert, confirm, prompt }

/// D9: an `alert`, `confirm` or `prompt` of the page. Its text is the
/// page's: shown, never logged.
final class BrowserJsDialog {
  const BrowserJsDialog({
    required this.kind,
    required this.message,
    this.defaultText,
  });
  final BrowserJsDialogKind kind;
  final String message;
  final String? defaultText;

  @override
  String toString() => 'BrowserJsDialog(${kind.name})';
}

/// D9: shows the dialog; answers null (alert), a bool (confirm) or a
/// String? (prompt; null = cancelled).
typedef BrowserDialogPresenter =
    Future<Object?> Function(BrowserJsDialog dialog);

abstract interface class BrowserEngine {
  Stream<BrowserEngineEvent> get events;

  /// D7: a native window over Flutter's (WebView2 through
  /// `webview_win_floating`): nothing Flutter draws can cover it, so it is
  /// hidden ([setVisible]) while an overlay is open. False on macOS, where
  /// the page is a platform view inside Flutter's tree.
  bool get coversFlutter;

  Future<void> load(Uri url);
  Future<void> goBack();
  Future<void> goForward();
  Future<void> reload();
  Future<void> stop();

  /// D10: the chords (config spelling) to hand back to Flutter while the
  /// page has the keyboard. Windows has no forwarding (D7): a no-op.
  Future<void> setForwardedChords(List<String> chords);

  /// D10: give the keyboard to the page.
  Future<void> focusContent();

  /// D10: give the keyboard back to Flutter.
  Future<void> releaseFocus();

  /// D7: show or hide the page (engines that [coversFlutter] only).
  Future<void> setVisible(bool visible);

  Widget buildView();

  Future<void> dispose();
}

/// D8, D22: the one data store every tool shares; "Clear tool data…".
abstract interface class BrowserDataStore {
  Future<void> clearAll();
}
