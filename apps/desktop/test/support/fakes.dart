import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_runtime.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/platform/keep_awake.dart';
import 'package:shellx_desktop/src/platform/launch_at_login.dart';
import 'package:shellx_desktop/src/platform/notifier.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/platform/url_opener.dart';

/// In-process stand-in for the relay REST API (spec §10.2 wire format).
final class FakeRelayApi {
  final List<http.Request> requests = [];
  String userId = '11111111-1111-4111-8111-111111111111';
  String deviceId = '22222222-2222-4222-8222-222222222222';
  String token = 'token-1';
  bool offline = false;

  /// Called with every request as it arrives (before [offline] or
  /// [failures] apply), so a test can check what else happened first.
  void Function(http.Request request)? onRequest;

  /// `'POST /v1/auth/login'` → (status, error code) to fail that route with.
  final Map<String, (int, String)> failures = {};
  Map<String, Object?> version = {
    'min_agent': '1.0.0',
    'min_mobile': '1.0.0',
    'latest_agent': {
      'version': '1.0.0',
      'mac_url': 'https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg',
      'win_url':
          'https://download.shellx.pro/desktop/1.0.0/ShellX-Setup-1.0.0.exe',
    },
  };

  late final MockClient client = MockClient((request) async {
    requests.add(request);
    onRequest?.call(request);
    if (offline) throw http.ClientException('offline');
    final route = '${request.method} ${request.url.path}';
    final failure = failures[route];
    if (failure != null) {
      return http.Response(
        jsonEncode({
          'error': {'code': failure.$2, 'message': failure.$2},
        }),
        failure.$1,
        headers: {'content-type': 'application/json'},
      );
    }
    if (route == 'POST /v1/auth/login' || route == 'POST /v1/auth/register') {
      return http.Response(
        jsonEncode({'user_id': userId, 'device_id': deviceId, 'token': token}),
        route.endsWith('register') ? 201 : 200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (route == 'GET /v1/version') {
      return http.Response(
        jsonEncode(version),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('', 204);
  });

  List<String> get routes => [
    for (final r in requests) '${r.method} ${r.url.path}',
  ];

  http.Request last(String route) =>
      requests.lastWhere((r) => '${r.method} ${r.url.path}' == route);

  String? bearerOf(http.Request request) => request.headers.entries
      .firstWhere(
        (e) => e.key.toLowerCase() == 'authorization',
        orElse: () => const MapEntry('', ''),
      )
      .value;
}

final class FakeAgentRuntime implements AgentRuntime {
  FakeAgentRuntime(this.params);

  final RuntimeParams params;
  final StreamController<RelayConnectionState> relayController =
      StreamController<RelayConnectionState>.broadcast(sync: true);
  final StreamController<AgentEvent> eventController =
      StreamController<AgentEvent>.broadcast(sync: true);
  final StreamController<void> sessionController =
      StreamController<void>.broadcast(sync: true);

  RelayConnectionState currentRelay = RelayConnectionState.connecting;
  List<SessionSummary> currentSessions = [];
  bool started = false;
  bool stopped = false;
  int pairingStarts = 0;
  int pairingCancels = 0;
  int reconnects = 0;
  final List<String> revoked = [];
  final List<int> closedSessions = [];
  bool closedAll = false;

  void emitRelay(RelayConnectionState state) {
    currentRelay = state;
    relayController.add(state);
  }

  @override
  Future<void> start() async => started = true;

  @override
  Future<void> stop() async {
    stopped = true;
    closedAll = true;
  }

  @override
  RelayConnectionState get relayState => currentRelay;
  @override
  Stream<RelayConnectionState> get relayStates => relayController.stream;
  @override
  Stream<AgentEvent> get events => eventController.stream;
  @override
  List<SessionSummary> get sessions => currentSessions;
  @override
  Stream<void> get sessionChanges => sessionController.stream;

  /// Codes from this fake expire at 12:05 plus one minute per extra start.
  @override
  PairingView startPairing() {
    pairingStarts++;
    return PairingView(
      uri: PairingUri(
        agentDeviceId: params.credentials.deviceId,
        agentPublicKey: params.identity.publicKey,
        secret: Uint8List(32),
      ),
      expiresAt: DateTime(2026, 9, 25, 12, 4 + pairingStarts),
    );
  }

  @override
  void cancelPairing() => pairingCancels++;
  @override
  Future<void> revoke(String mobileId) async {
    revoked.add(mobileId);
    await params.trusted.remove(mobileId);
  }

  @override
  void closeSession(int id) => closedSessions.add(id);
  @override
  void closeAllSessions() => closedAll = true;
  @override
  void reconnectNow() => reconnects++;
}

final class RecordingKeepAwake implements KeepAwake {
  final List<bool> calls = [];
  bool? get last => calls.isEmpty ? null : calls.last;

  /// Records the call, then fails the way WindowsKeepAwake does.
  bool fail = false;

  @override
  Future<void> setEnabled(bool enabled) async {
    calls.add(enabled);
    if (fail) throw StateError('SetThreadExecutionState failed');
  }
}

final class FakeLaunchAtLogin implements LaunchAtLogin {
  bool enabled = false;
  bool fail = false;
  @override
  Future<bool> isEnabled() async => enabled;
  @override
  Future<void> setEnabled(bool value) async {
    if (fail) throw Exception('denied');
    enabled = value;
  }
}

final class ShownNotification {
  const ShownNotification(this.title, this.body, this.onClick);
  final String title;
  final String? body;
  final void Function()? onClick;
}

final class RecordingNotifier implements SystemNotifier {
  final List<ShownNotification> shown = [];

  /// Throws instead of showing (notifications denied by the OS).
  bool fail = false;

  @override
  Future<void> show({
    required String title,
    String? body,
    void Function()? onClick,
  }) async {
    if (fail) throw Exception('notifications denied');
    shown.add(ShownNotification(title, body, onClick));
  }
}

final class RecordingUrlOpener implements UrlOpener {
  final List<Uri> opened = [];
  @override
  Future<void> open(Uri uri) async => opened.add(uri);
}

final PairingIdGenerator _pairingIds = PairingIdGenerator();

/// A trusted phone for tests (a fresh pairing id unless [pairingId] is set).
TrustedDevice phone(String id, String name, {String? pairingId}) =>
    TrustedDevice(
      mobileId: id,
      publicKey: Uint8List(32),
      name: name,
      pairedAt: DateTime(2026, 9, 1),
      pairingId: pairingId ?? _pairingIds.next(),
    );

/// Bundles every fake so tests can inspect them.
final class TestHarness {
  TestHarness({
    Map<String, bool>? settings,
    Locale locale = const Locale('en'),
    this.appVersion = '1.0.0',
    this.platform = DevicePlatform.macos,
  }) : settings = InMemorySettingsStore(settings),
       l10n = lookupAppLocalizations(locale);

  final InMemoryKeyValueStore secureStore = InMemoryKeyValueStore();
  final InMemorySettingsStore settings;
  final FakeRelayApi relay = FakeRelayApi();
  final RecordingKeepAwake keepAwake = RecordingKeepAwake();
  final FakeLaunchAtLogin launchAtLogin = FakeLaunchAtLogin();
  final RecordingNotifier notifier = RecordingNotifier();
  final RecordingUrlOpener urlOpener = RecordingUrlOpener();
  final AppLocalizations l10n;
  final String appVersion;
  final DevicePlatform platform;
  final List<FakeAgentRuntime> runtimes = [];
  int quits = 0;

  /// Calls of DesktopServices.awaitPtyKills.
  int ptyKillWaits = 0;

  /// What DesktopServices.awaitPtyKills waits for (swap it any time; the
  /// default settles at once).
  Future<void> Function() ptyKills = () async {};

  /// Short, so a test of the timeout does not wait the real 3 s.
  static const Duration ptyKillTimeout = Duration(milliseconds: 100);

  FakeAgentRuntime get runtime => runtimes.last;

  late final ShellxApi api = ShellxApi(
    baseUri: Uri.parse('https://relay.test'),
    httpClient: relay.client,
  );

  /// The process's one TrustedStore (owned by [services]); tests seed and
  /// inspect trust through it.
  TrustedStore get trusted => services().trusted;

  /// One [DesktopServices] per harness, like one per process in the app.
  DesktopServices services() => _services;

  late final DesktopServices _services = DesktopServices(
    secureStore: secureStore,
    settings: settings,
    api: api,
    runtimeFactory: (params) {
      final runtime = FakeAgentRuntime(params);
      runtimes.add(runtime);
      return runtime;
    },
    keepAwake: keepAwake,
    launchAtLogin: launchAtLogin,
    notifier: notifier,
    urlOpener: urlOpener,
    l10n: l10n,
    appVersion: appVersion,
    platform: platform,
    deviceName: 'Phus-MacBook-Pro',
    quitApp: () async => quits++,
    awaitPtyKills: () {
      ptyKillWaits++;
      return ptyKills();
    },
    ptyKillTimeout: ptyKillTimeout,
  );

  /// Stores credentials as a previous successful login would have.
  Future<void> seedSignedIn({String email = 'phu@example.com'}) async {
    await secureStore.write('auth_token', relay.token);
    await secureStore.write('device_id', relay.deviceId);
    await secureStore.write('user_id', relay.userId);
    await secureStore.write('email', email);
  }
}
