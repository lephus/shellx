import 'package:shellx_core/shellx_core.dart';

import '../../l10n/app_localizations.dart';

final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// Client-side pre-check only; the relay does the real validation (spec §5.2).
bool looksLikeEmail(String value) => _email.hasMatch(value.trim());

/// 8-128 characters, counted the way the relay does: Unicode **code points**
/// after NFC (`relay/src/auth/password-policy.ts`), not UTF-16 code units.
/// An emoji is one code point but two UTF-16 code units (a surrogate pair),
/// so `String.length` would disagree with the relay at the boundary (an
/// 8-emoji password is valid; a 4-emoji one is not). `.runes.length` counts
/// code points; NFC normalisation is not attempted here without a new
/// dependency — the relay stays authoritative and its error is shown when it
/// disagrees.
bool validPasswordLength(String value) =>
    value.runes.length >= 8 && value.runes.length <= 128;

/// Human text for a relay error (spec §10.2 codes, §12 messages). Any code
/// this switch does not know (for example `payload_too_large`, or another
/// code introduced later) falls through to the generic
/// [AppLocalizations.errorUnexpected] text — never a raw code on its own.
String apiErrorText(ApiException error, AppLocalizations l10n) {
  if (error.status == 429) return l10n.errorRateLimited;
  if (error.status == 0 || error.code == 'network') return l10n.errorNetwork;
  return switch (error.code) {
    'invalid_email' => l10n.errorEmailInvalid,
    'disposable_email' => l10n.errorDisposableEmail,
    'weak_password' => l10n.errorPasswordLength,
    'email_taken' => l10n.errorEmailTaken,
    'invalid_credentials' => l10n.errorInvalidCredentials,
    'agent_only' => l10n.errorAgentOnly,
    _ => l10n.errorUnexpected(error.code),
  };
}

/// `m:ss`, never negative.
String formatCountdown(Duration remaining) {
  final clamped = remaining.isNegative ? Duration.zero : remaining;
  final seconds = (clamped.inSeconds % 60).toString().padLeft(2, '0');
  return '${clamped.inMinutes}:$seconds';
}
