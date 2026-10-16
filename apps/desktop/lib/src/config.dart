/// Relay base URL: production by default, override for local development with
/// `flutter run --dart-define=SHELLX_RELAY=http://127.0.0.1:8787`.
const String kRelayBaseUrl = String.fromEnvironment(
  'SHELLX_RELAY',
  defaultValue: 'https://relay.shellx.pro',
);

/// `wss://<host>/v1/ws` for an https base, `ws://<host>/v1/ws` for http.
Uri relayWebSocketUri(Uri base) =>
    base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws', path: '/v1/ws');
