import 'package:injectable/injectable.dart';

/// What the user typed in the text field of an AI session and has not sent (V2-2 §5.2), kept for a page
/// that is left and opened again: a notification, a call or a tap in the wrong place must not cost a
/// sentence. In memory only, never written anywhere and never logged. It lives as long as the app process
/// does: nothing clears it on sign-out, and a session that closes for good (`gone`, `desktop_closed`)
/// drops its own draft (see `AiSessionController`). What it holds is bounded by [capacity] and [maxChars].
///
/// The key is the caller's: the controller uses the session on its machine, since two computers both
/// have an `e.-1`.
@lazySingleton
class AiDrafts {
  /// How many drafts are kept; the one written longest ago goes first.
  static const int capacity = 20;

  /// The longest draft kept. A phone may send 32 KB; a megabyte pasted into the field is no draft, and
  /// keeping it would keep that much memory for as long as the app runs.
  static const int maxChars = 64 * 1024;

  /// In the order of writing (a map literal keeps the order of insertion): the first is the oldest.
  final _drafts = <String, String>{};

  /// The draft of [key], empty when there is none.
  String of(String key) => _drafts[key] ?? '';

  /// [text] is now what the field of [key] holds. Nothing (or only spaces: a message just sent) removes
  /// the draft; a text beyond [maxChars] is not kept.
  void keep(String key, String text) {
    _drafts.remove(key);
    if (text.trim().isEmpty || text.length > maxChars) return;
    _drafts[key] = text;
    while (_drafts.length > capacity) {
      _drafts.remove(_drafts.keys.first);
    }
  }
}
