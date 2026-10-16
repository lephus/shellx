import '../../l10n/app_localizations.dart';
import 'tab_attention.dart';

/// A4 D24: a screen reader hears a new notice for another tab while the
/// window is in use — at most once per [gap] per tab. The text goes only
/// to [announce], never to a log (N9).
final class AttentionAnnouncer {
  AttentionAnnouncer({
    required void Function(String text) announce,
    required AppLocalizations l10n,
    DateTime Function()? now,
    this.gap = const Duration(seconds: 3),
  }) : _announce = announce,
       _l10n = l10n,
       _now = now ?? DateTime.now;

  final void Function(String text) _announce;
  final AppLocalizations _l10n;
  final DateTime Function() _now;
  final Duration gap;
  final _last = <int, DateTime>{};

  void arrived(
    AttentionArrival a, {
    required String tab,
    required bool windowFocused,
    required bool tabSelected,
  }) {
    if (!windowFocused || tabSelected) return;
    final now = _now();
    final last = _last[a.tabId];
    if (last != null && now.difference(last) < gap) return;
    _last[a.tabId] = now;
    _announce(_l10n.attentionAnnounce(tab, a.text));
  }
}
