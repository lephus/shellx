import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
import 'package:shellx_desktop/src/terminal/clipboard_media.dart';
import 'package:shellx_desktop/src/terminal_sharing/config_file_editor.dart';
import 'package:shellx_desktop/src/terminal_sharing/powershell.dart';
import 'package:shellx_desktop/src/terminal_sharing/sharing_paths.dart';
import 'package:shellx_desktop/src/terminal_sharing/terminal_sharing_setup.dart';

import 'fake_pty.dart';

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

  /// `'POST /v1/auth/logout'` → a future the answer waits for (a slow relay).
  final Map<String, Future<void>> holds = {};
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
    final route = '${request.method} ${request.url.path}';
    final hold = holds[route];
    if (hold != null) await hold;
    if (offline) throw http.ClientException('offline');
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
  bool started = false;
  bool stopped = false;
  int pairingStarts = 0;
  int pairingCancels = 0;
  int reconnects = 0;
  final List<String> revoked = [];
  bool phonesDisconnected = false;

  void emitRelay(RelayConnectionState state) {
    currentRelay = state;
    relayController.add(state);
  }

  @override
  Future<void> start() async => started = true;

  /// While set and not completed, [stop] marks the runtime stopped at once
  /// but its future completes only with this (a relay stop that waits for an
  /// upgrade still in flight).
  Completer<void>? stopGate;

  @override
  Future<void> stop() async {
    stopped = true;
    phonesDisconnected = true;
    await stopGate?.future;
  }

  @override
  RelayConnectionState get relayState => currentRelay;
  @override
  Stream<RelayConnectionState> get relayStates => relayController.stream;
  @override
  Stream<AgentEvent> get events => eventController.stream;
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
  void reconnectNow() => reconnects++;

  final StreamController<DesktopPhoneAttached> attachedController =
      StreamController<DesktopPhoneAttached>.broadcast(sync: true);
  List<DesktopSessionSummary> currentDesktopSessions = [];
  bool sharing = false;

  /// Calls of [setTerminalSharing], in order.
  final List<bool> sharingCalls = [];

  /// Makes `setTerminalSharing(true)` throw (the port cannot be opened).
  bool failSharingStart = false;
  final List<int> disconnectedPhones = [];

  @override
  List<DesktopSessionSummary> get desktopSessions => currentDesktopSessions;
  @override
  Stream<DesktopPhoneAttached> get desktopPhoneAttached =>
      attachedController.stream;
  @override
  bool get terminalSharing => sharing;
  @override
  Future<void> setTerminalSharing(bool enabled) async {
    sharingCalls.add(enabled);
    if (enabled && failSharingStart) {
      throw const SocketException('bind failed');
    }
    sharing = enabled;
  }

  @override
  void disconnectDesktopPhone(int id) => disconnectedPhones.add(id);
}

/// Records what the controller asks of the installer; touches no file.
final class FakeSharingSetup extends TerminalSharingSetup {
  FakeSharingSetup({bool windows = false})
    : super(
        paths: SharingPaths(
          windows: windows,
          home: '/Users/phu',
          binDir: '/Users/phu/Library/Application Support/ShellX/bin',
          binary:
              '/Users/phu/Library/Application Support/ShellX/bin/shellx-term',
          termDir: '/Users/phu/Library/Application Support/ShellX/term',
          bundledBinary:
              '/Applications/ShellX.app/Contents/Helpers/shellx-term',
        ),
      );

  final List<String> calls = [];
  bool failEnable = false;
  bool needsSetupResult = false;
  List<String> failedFiles = [];
  SharingPlan plan = const SharingPlan(
    files: [
      PlannedFile(
        ConfigTarget(
          path: '/Users/phu/.zshrc',
          block: 'block',
          create: true,
          newFileEol: '\n',
        ),
        exists: true,
      ),
    ],
    bashSkipped: true,
    powerShells: [],
  );

  @override
  Future<SharingPlan> prepare() async {
    calls.add('prepare');
    return plan;
  }

  @override
  Future<SharingInstall> enable(SharingPlan plan) async {
    calls.add('enable');
    await enableGate?.future;
    if (failEnable) {
      throw const SharingSetupException(
        '/Users/phu/.zshrc',
        FileSystemException('denied'),
      );
    }
    return SharingInstall(
      () async => calls.add('undo'),
      editedFiles: [for (final f in plan.files) f.path],
    );
  }

  /// The knownFiles of the last disable.
  List<String> disableKnownFiles = [];

  @override
  Future<DisableResult> disable({
    Future<void> Function()? stopServer,
    List<String> knownFiles = const [],
  }) async {
    calls.add('disable');
    disableKnownFiles = knownFiles;
    await stopServer?.call();
    calls.add('disabled');
    return DisableResult(failedFiles: failedFiles, binRemoved: true);
  }

  @override
  Future<bool> needsSetup() async {
    calls.add('needsSetup');
    return needsSetupResult;
  }

  /// While set and not completed, [enable] waits for it.
  Completer<void>? enableGate;

  /// While set and not completed, [maintain] waits for it.
  Completer<void>? maintainGate;

  @override
  Future<void> maintain({required bool enabled}) async {
    calls.add('maintain:$enabled');
    await maintainGate?.future;
    calls.add('maintained');
  }

  final List<PowerShellInstall> allowedScripts = [];

  bool allowScriptsResult = true;

  @override
  Future<bool> allowLocalScripts(PowerShellInstall install) async {
    allowedScripts.add(install);
    return allowScriptsResult;
  }
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

/// The in-memory secure store, able to fail like a keychain that refuses
/// access.
final class FlakyKeyValueStore implements KeyValueStore {
  final InMemoryKeyValueStore _values = InMemoryKeyValueStore();

  /// Keys whose reads throw.
  final Set<String> failingReads = {};

  /// Keys whose writes throw.
  final Set<String> failingWrites = {};

  /// Keys whose deletes throw.
  final Set<String> failingDeletes = {};

  /// Key → a future its reads wait for (a keychain prompt still open).
  final Map<String, Future<void>> readHolds = {};

  @override
  Future<String?> read(String key) async {
    final hold = readHolds[key];
    if (hold != null) await hold;
    if (failingReads.contains(key)) {
      throw Exception('keychain refused $key: SECRET-DETAIL');
    }
    return _values.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (failingWrites.contains(key)) {
      throw Exception('keychain refused writing $key: SECRET-DETAIL');
    }
    await _values.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    if (failingDeletes.contains(key)) {
      throw Exception('keychain refused deleting $key: SECRET-DETAIL');
    }
    await _values.delete(key);
  }
}

final class ShownNotification {
  const ShownNotification(this.title, this.body, this.onClick, {this.id});
  final String title;
  final String? body;
  final void Function()? onClick;
  final String? id;
}

final class RecordingNotifier implements SystemNotifier {
  final List<ShownNotification> shown = [];
  final List<String> closed = [];

  /// Throws instead of showing (notifications denied by the OS).
  bool fail = false;

  @override
  Future<void> show({
    required String title,
    String? body,
    String? id,
    void Function()? onClick,
  }) async {
    if (fail) throw Exception('notifications denied');
    shown.add(ShownNotification(title, body, onClick, id: id));
  }

  @override
  Future<void> close(String id) async => closed.add(id);
}

final class RecordingUrlOpener implements UrlOpener {
  final List<Uri> opened = [];

  /// Throws instead of opening (e.g. `open` could not be started).
  bool fail = false;

  @override
  Future<void> open(Uri uri) async {
    if (fail) throw const ProcessException('/usr/bin/open', [], 'failed');
    opened.add(uri);
  }

  final List<int> ports = [];

  @override
  Future<void> openLocalPort(int port) async {
    if (fail) throw const ProcessException('/usr/bin/open', [], 'failed');
    ports.add(port);
  }

  /// A10: links clicked in the terminal.
  final List<Uri> webLinks = [];

  @override
  Future<void> openWebLink(Uri uri) async {
    if (fail) throw const ProcessException('/usr/bin/open', [], 'failed');
    webLinks.add(uri);
  }

  /// A10: paths shown in Finder / Explorer (path, isDirectory).
  final List<(String, bool)> revealed = [];

  @override
  Future<void> reveal(String path, {required bool isDirectory}) async {
    if (fail) throw const ProcessException('/usr/bin/open', [], 'failed');
    revealed.add((path, isDirectory));
  }
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
    this.sharingSetup,
  }) : settings = InMemorySettingsStore({
         // A11 D24: the first-run tour is its own tests' business.
         SettingKeys.tourDone: true,
         ...?settings,
       }),
       l10n = lookupAppLocalizations(locale);

  final FlakyKeyValueStore secureStore = FlakyKeyValueStore();
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

  /// Null: the terminal-sharing switch is not offered.
  final FakeSharingSetup? sharingSetup;

  /// New runtimes fail to open the terminal-sharing port.
  bool sharingStartFails = false;

  /// The clock DesktopServices.now reads.
  DateTime now = DateTime(2026, 10, 5, 12);
  int quits = 0;
  int imageDeletes = 0;
  final List<String> shutdownOrder = [];
  Future<void> Function() remoteShutdown = () async {};

  /// Calls of DesktopServices.awaitPtyKills.
  int ptyKillWaits = 0;

  /// What DesktopServices.awaitPtyKills waits for (swap it any time; the
  /// default settles at once).
  Future<void> Function() ptyKills = () async {};

  /// Short, so a test of the timeout does not wait the real 3 s.
  static const Duration ptyKillTimeout = Duration(milliseconds: 100);

  FakeAgentRuntime get runtime => runtimes.last;

  /// The process's one SessionManager (A1 D7), over fake PTYs.
  final FakePtyFactory ptys = FakePtyFactory();
  late final SessionManager sessions = SessionManager(
    ptyFactory: ptys,
    shellResolver: const FixedShellResolver(),
    homeDirectory: '/Users/phu',
    baseEnvironment: const {'HOME': '/Users/phu'},
  );

  late final ShellxApi api = ShellxApi(
    baseUri: Uri.parse('https://relay.test'),
    httpClient: relay.client,
  );

  /// Every ShellxApi made through DesktopServices.createApi.
  final List<ShellxApi> createdApis = [];

  /// The process's one TrustedStore (owned by [services]); tests seed and
  /// inspect trust through it.
  TrustedStore get trusted => services().trusted;

  /// One [DesktopServices] per harness, like one per process in the app.
  DesktopServices services() => _services;

  late final DesktopServices _services = DesktopServices(
    secureStore: secureStore,
    settings: settings,
    api: api,
    createApi: () {
      final created = ShellxApi(
        baseUri: Uri.parse('https://relay.test'),
        httpClient: relay.client,
      );
      createdApis.add(created);
      return created;
    },
    runtimeFactory: (params) {
      final runtime = FakeAgentRuntime(params)
        ..failSharingStart = sharingStartFails;
      runtimes.add(runtime);
      return runtime;
    },
    sessions: sessions,
    keepAwake: keepAwake,
    launchAtLogin: launchAtLogin,
    notifier: notifier,
    urlOpener: urlOpener,
    l10n: l10n,
    appVersion: appVersion,
    platform: platform,
    deviceName: 'Phus-MacBook-Pro',
    quitApp: () async {
      shutdownOrder.add('quit');
      quits++;
    },
    deletePastedImages: () async {
      imageDeletes++;
    },
    stopRemoteRetries: () => shutdownOrder.add('retries'),
    shutdownRemote: () async {
      shutdownOrder.add('remote');
      await remoteShutdown();
    },
    shutdownTimeout: const Duration(milliseconds: 200),
    awaitPtyKills: () {
      ptyKillWaits++;
      return ptyKills();
    },
    ptyKillTimeout: ptyKillTimeout,
    terminalSharing: sharingSetup,
    now: () => now,
  );

  /// Stores credentials as a previous successful login would have.
  Future<void> seedSignedIn({String email = 'phu@example.com'}) async {
    await secureStore.write('auth_token', relay.token);
    await secureStore.write('device_id', relay.deviceId);
    await secureStore.write('user_id', relay.userId);
    await secureStore.write('email', email);
  }
}

/// A10 D15: a clipboard with nothing but text (the default in tests: the
/// real one talks to a native plugin).
final class EmptyClipboardMedia implements ClipboardMedia {
  const EmptyClipboardMedia();

  @override
  Future<List<String>> files() async => const [];

  @override
  Future<Uint8List?> image() async => null;
}
