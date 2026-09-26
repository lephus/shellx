/// Build-time configuration.
///
/// Point the app at a local relay with
/// `flutter run --dart-define=SHELLX_RELAY=http://127.0.0.1:8787`.
abstract final class AppConfig {
  static final Uri relayBaseUri = Uri.parse(
    const String.fromEnvironment('SHELLX_RELAY', defaultValue: 'https://relay.shellx.pro'),
  );

  /// Landing page with the App Store / Google Play links (spec §11).
  static final Uri downloadPage = Uri.parse('https://shellx.pro/');

  /// "Mở App Store": the listing URL is only known after the first App Store submission, so the
  /// release build passes `--dart-define=SHELLX_APP_STORE_URL=https://apps.apple.com/app/id…`;
  /// until then the landing page (which links both stores) opens.
  static final Uri appStorePage = Uri.parse(
    const String.fromEnvironment('SHELLX_APP_STORE_URL', defaultValue: 'https://shellx.pro/'),
  );

  /// "Mở Google Play": the listing of `com.shellx.prod`.
  static final Uri playStorePage = Uri.parse('https://play.google.com/store/apps/details?id=com.shellx.prod');

  /// Linked from the registration form (spec §3.1, §11).
  static final Uri termsPage = Uri.parse('https://shellx.pro/terms');
  static final Uri privacyPage = Uri.parse('https://shellx.pro/privacy');
}

/// `https://relay.shellx.pro` → `wss://relay.shellx.pro/v1/ws` (spec §6.1).
/// A plain `http` base (local `wrangler dev`) maps to `ws`.
Uri relayWebSocketUri(Uri base) => base.replace(scheme: base.scheme == 'http' ? 'ws' : 'wss', path: '/v1/ws');
