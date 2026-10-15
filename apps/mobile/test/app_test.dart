import 'dart:async';

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/core/router/auth_guard.dart';
import 'package:shellx_mobile/core/router/update_guard.dart';
import 'package:shellx_mobile/features/ai/domain/ai_drafts.dart';
import 'package:shellx_mobile/features/ai/domain/ai_words.dart';
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_session_controller.dart';
import 'package:shellx_mobile/features/app/app.dart';
import 'package:shellx_mobile/features/app/font_licenses.dart';
import 'package:shellx_mobile/features/app/launch.dart';
import 'package:shellx_mobile/features/app/splash_page.dart';
import 'package:shellx_mobile/features/auth/presentation/controllers/login_controller.dart';
import 'package:shellx_mobile/features/auth/presentation/controllers/register_controller.dart';
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';
import 'package:shellx_mobile/features/machines/presentation/controllers/machine_list_controller.dart';
import 'package:shellx_mobile/features/notifications/domain/push_messaging.dart';
import 'package:shellx_mobile/features/notifications/presentation/notification_opener.dart';
import 'package:shellx_mobile/features/notifications/presentation/push_controller.dart';
import 'package:shellx_mobile/features/pairing/presentation/controllers/qr_scanner_controller.dart';
import 'package:shellx_mobile/features/settings/presentation/controllers/delete_account_controller.dart';
import 'package:shellx_mobile/features/settings/presentation/controllers/settings_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_page_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';
import 'package:shellx_mobile/features/voice/presentation/controllers/voice_composer_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

import 'support/fake_biometrics.dart';
import 'support/fake_links.dart';
import 'support/fake_popup_handler.dart';
import 'support/fake_push.dart';
import 'support/fake_relay_http.dart';
import 'support/fake_speech.dart';
import 'support/fakes.dart';

/// The secure store of the phone: in memory, and every read fails while [readError] is set (a
/// locked or broken Keychain/Keystore).
class _Keychain implements KeyValueStore {
  final InMemoryKeyValueStore _values = InMemoryKeyValueStore();
  Object? readError;

  @override
  Future<String?> read(String key) {
    final error = readError;
    return error != null ? Future.error(error) : _values.read(key);
  }

  @override
  Future<void> write(String key, String value) => _values.write(key, value);

  @override
  Future<void> delete(String key) => _values.delete(key);
}

/// The whole app with the real router, guards, SessionHolder and SessionEnforcer; only the relay
/// HTTP API, the backend (shellx_client), biometrics and toasts are fakes.
void main() {
  late FakeRelayHttp relay;
  late _Keychain store;
  late FakeBackendFactory backends;
  late FakeBiometricAuthenticator biometrics;
  late FakePopupHandler popups;
  late FakeExternalLinks links;
  late AppSettings settings;
  late SessionHolderImpl session;
  late WorkspaceRegistry registry;
  late AppLockController lock;
  late AppRouter router;
  late FakePushMessaging messaging;
  late PushController push;
  late DateTime clock;

  /// Runs on every backend the factory makes: what a test needs the computer to hold already.
  void Function(FakeBackend backend)? onNewBackend;

  setUp(() async {
    onNewBackend = null;
    SharedPreferences.setMockInitialValues({});
    // AdaptiveTheme (the base's theme switcher) reads its mode through SharedPreferencesAsync.
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    relay = FakeRelayHttp();
    store = _Keychain();
    backends = FakeBackendFactory(() {
      final backend = FakeBackend(devices: [agentDevice(agentA, 'MacBook-Pro')], pinnedList: [pinned(agentA)])
        ..onlineIds.add(agentA)
        ..addMachine(agentA);
      onNewBackend?.call(backend);
      return backend;
    });
    biometrics = FakeBiometricAuthenticator();
    popups = FakePopupHandler();
    links = FakeExternalLinks();
    final api = ShellxApi(baseUri: Uri.parse('http://127.0.0.1:8787'), httpClient: relay.client);
    final packageInfo = PackageInfo(
      appName: 'ShellX',
      packageName: 'com.shellx.prod',
      version: '1.0.0',
      buildNumber: '1',
    );
    final events = AuthEventNotifier();
    final pendingUnpairs = PendingUnpairs(store);
    session = SessionHolderImpl(
      api: api,
      storage: AuthStorageImpl(store),
      store: store,
      device: const DeviceDescription(name: 'Pixel 8', platform: DevicePlatform.android),
      packageInfo: packageInfo,
      backends: backends,
      events: events,
      pendingUnpairs: pendingUnpairs,
    );
    final versionGate = VersionGate(api, packageInfo);
    // Loaded at launch, as dependency injection does before the first frame.
    settings = AppSettings(store);
    clock = DateTime(2026, 9, 26, 9);
    lock = AppLockController(
      authenticator: biometrics,
      isEnabled: () => settings.biometricLock.peek(),
      now: () => clock,
    );
    registry = WorkspaceRegistry(session.backend);
    router = AppRouter(authGuard: AuthGuard(session), updateGuard: UpdateGuard(versionGate));
    messaging = FakePushMessaging()..answer = PushPermission.denied;
    push = PushController(
      messaging: messaging,
      session: session,
      prefs: await SharedPreferences.getInstance(),
      opener: NotificationOpener(session, registry, RouterMachineNavigator(router)),
      device: const DeviceDescription(name: 'Pixel 8', platform: DevicePlatform.android),
      lock: lock,
      popup: () => popups,
    );
    getIt
      ..registerSingleton<PopupHandler>(popups)
      ..registerSingleton<ExternalLinks>(links)
      ..registerSingleton<VersionGate>(versionGate)
      ..registerSingleton<SessionHolder>(session)
      ..registerSingleton<AppLockController>(lock)
      ..registerSingleton<AppRouter>(router)
      ..registerSingleton<PushController>(push)
      ..registerFactory<LoginController>(() => LoginController(session))
      ..registerFactory<RegisterController>(() => RegisterController(session))
      ..registerFactory<MachineListController>(() => MachineListController.create(session, registry, push, settings))
      ..registerFactoryParam<TerminalPageController, String, void>(
        (agentId, _) => TerminalPageController(agentId, registry, session, settings),
      )
      ..registerFactoryParam<AiSessionController, String, String>(
        (agentId, sid) => AiSessionController(agentId, sid, session, AiDrafts(), registry),
      )
      ..registerFactory<VoiceComposerController>(() => VoiceComposerController(FakeSpeechInput(), settings))
      ..registerFactory<QrScannerController>(() => QrScannerController(session))
      ..registerFactory<SettingsController>(
        () => SettingsController(
          session,
          settings,
          lock,
          biometrics,
          registry,
          packageInfo,
          pendingUnpairs,
          push,
          links,
        ),
      )
      ..registerFactory<DeleteAccountController>(() => DeleteAccountController(session));
    getIt.registerSingleton<SessionEnforcer>(SessionEnforcerImpl(events, router)..initialize());
  });

  tearDown(() async {
    push.dispose();
    registry.dispose();
    await getIt.reset();
  });

  /// What `SplashPage` does: the part of `configureDependencies()` that reads storage (the
  /// settings), [prepareLaunch], then the app itself in the splash's place. [prepare] replaces
  /// those steps.
  Future<void> launch(WidgetTester tester, {Future<void> Function()? prepare}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Future<void> start() async {
      await settings.load();
      await prepareLaunch();
    }

    await tester.pumpWidget(
      AdaptiveTheme(
        light: ThemeDataFactory.create(Brightness.light),
        dark: ThemeDataFactory.create(Brightness.dark),
        initial: AdaptiveThemeMode.light,
        builder: (light, dark) => AppLaunch(prepare: prepare ?? start),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RootApp), findsOneWidget);
  }

  Future<void> signIn(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).at(0), 'me@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'correct horse');
    await tester.tap(find.widgetWithText(AppButton, 'Sign in'));
    await tester.pumpAndSettle();
  }

  Future<void> openTerminal(WidgetTester tester) async {
    await tester.tap(find.text('MacBook-Pro'));
    await tester.pumpAndSettle();
    expect(find.text('zsh 1'), findsOneWidget);
  }

  List<String> stack() => [for (final page in router.stack) page.routeData.name];

  testWidgets('an outdated app is blocked with the store link', (tester) async {
    relay.minMobile = '2.0.0';
    await launch(tester);
    expect(find.text('App update required'), findsOneWidget);
    expect(backends.backends, isEmpty); // the relay is never started
    await tester.tap(find.text('Open Google Play'));
    expect(links.opened, [Uri.parse('https://play.google.com/store/apps/details?id=com.shellx.prod')]);
  });

  testWidgets('a saved session opens the machine list directly', (tester) async {
    await AuthStorageImpl(store).save(
      const AccountSession(userId: testUserId, deviceId: testDeviceId, token: 'saved', email: 'me@example.com'),
    );
    await launch(tester);
    expect(find.text('Your computers'), findsOneWidget);
    expect(find.text('MacBook-Pro'), findsOneWidget);
  });

  testWidgets('push: the permission is asked once a paired machine is listed (spec §6)', (tester) async {
    await launch(tester);
    await signIn(tester);
    expect(find.text('Your computers'), findsOneWidget);
    expect(messaging.requests, 1);
  });

  testWidgets('push: tapping a notification opens that machine\'s terminal (spec §6)', (tester) async {
    await launch(tester);
    await signIn(tester);
    messaging.opened.add(
      const PushMessage(title: 'MacBook-Pro · Phiên 1', body: 'Build xong', data: {'agent_id': agentA}),
    );
    await tester.pumpAndSettle();
    expect(stack(), [MachineListRoute.name, TerminalRoute.name]);
    expect(find.text('zsh 1'), findsOneWidget);

    // Already on that machine: nothing more is pushed.
    messaging.opened.add(const PushMessage(data: {'agent_id': agentA}));
    await tester.pumpAndSettle();
    expect(stack(), [MachineListRoute.name, TerminalRoute.name]);
  });

  testWidgets('push: the notification that launched the app opens its machine (spec §6)', (tester) async {
    await AuthStorageImpl(store).save(
      const AccountSession(userId: testUserId, deviceId: testDeviceId, token: 'saved', email: 'me@example.com'),
    );
    messaging.initial = const PushMessage(data: {'agent_id': agentA, 'session_id': '5'});
    await launch(tester);
    expect(stack(), [MachineListRoute.name, TerminalRoute.name]);
  });

  group('push: an AI session (V2-2 D11)', () {
    PushMessage aiPush(String sid, {String agentId = agentA}) => PushMessage(
      title: 'MacBook-Pro · Claude',
      body: 'Cần bạn trả lời: Sửa src/main.ts',
      data: {'agent_id': agentId, 'kind': 'ai', 'ai_session': sid},
    );

    PermissionRequest permission() => PermissionRequest.fromJson({
      'sessionId': 's',
      'toolCall': {'toolCallId': 'c1', 'title': 'Edit src/main.ts', 'kind': 'edit'},
      'options': [
        {'optionId': 'allow', 'name': 'Yes', 'kind': 'allow_once'},
        {'optionId': 'reject', 'name': 'No', 'kind': 'reject_once'},
      ],
    });

    /// The computer holds [sid] (idle, so the page has nothing that ticks or spins) before the phone asks.
    void computerHolds(String sid, {bool waiting = false, String agentId = agentA}) {
      final previous = onNewBackend;
      onNewBackend = (backend) {
        previous?.call(backend);
        final ai = backend.machines[agentId]!.ai.session(sid);
        if (waiting) {
          ai.desktop
            ..beginTurn(const [TextBlock('Sửa')], DateTime.now())
            ..addPermission(permission(), DateTime.now());
        }
        ai.sync();
      };
    }

    String? topSid() => (router.topRoute.args as AiSessionRouteArgs?)?.sid;

    /// Frames for [time], 100 ms apart (what `pumpAndSettle` does until there is nothing left to draw).
    Future<void> pumpFor(WidgetTester tester, Duration time) async {
      for (var passed = Duration.zero; passed < time; passed += const Duration(milliseconds: 100)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    FakeAiMachine ai() => backends.backends.single.machines[agentA]!.ai;

    testWidgets('opens that session over the machine list; the same push again opens no second page', (tester) async {
      computerHolds('e.-1');
      computerHolds('e.-2');
      await launch(tester);
      await signIn(tester);
      messaging.opened.add(aiPush('e.-1'));
      await tester.pumpAndSettle();
      expect(stack(), [MachineListRoute.name, AiSessionRoute.name]);
      expect(topSid(), 'e.-1');
      expect((router.topRoute.args as AiSessionRouteArgs).machineName, 'MacBook-Pro');
      expect(find.byKey(const Key('ai.composer.bar')), findsOneWidget);

      messaging.opened.add(aiPush('e.-1'));
      await tester.pumpAndSettle();
      expect(stack(), [MachineListRoute.name, AiSessionRoute.name]);

      // Another session of the same machine takes the place of the first: still one page.
      messaging.opened.add(aiPush('e.-2'));
      await tester.pumpAndSettle();
      expect(stack(), [MachineListRoute.name, AiSessionRoute.name]);
      expect(topSid(), 'e.-2');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a session that no longer exists shows as closed on the computer; back is the machine list', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester);
      messaging.opened.add(aiPush('e.-9'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(stack(), [MachineListRoute.name, AiSessionRoute.name]);

      ai().session('e.-9').close('gone'); // what the computer answers an attach to a session it does not hold
      await tester.pumpAndSettle();
      final strip = find.byKey(const Key('ai.closed'));
      expect(strip, findsOneWidget);
      expect(
        find.descendant(of: strip, matching: find.text(AiWords.closed(S.of(tester.element(strip)), 'gone'))),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ai.composer.bar')), findsNothing, reason: 'nothing to write to');
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('ai.back')));
      await tester.pumpAndSettle();
      expect(stack(), [MachineListRoute.name]);
    });

    for (final reason in ['desktop_closed', 'unavailable']) {
      testWidgets('the computer closed the session ($reason) or cannot serve it now: the strip says so', (
        tester,
      ) async {
        computerHolds('e.-1');
        await launch(tester);
        await signIn(tester);
        messaging.opened.add(aiPush('e.-1'));
        await tester.pumpAndSettle();
        ai().session('e.-1').close(reason);
        await tester.pumpAndSettle();
        final strip = find.byKey(const Key('ai.closed'));
        expect(strip, findsOneWidget);
        expect(
          find.descendant(of: strip, matching: find.text(AiWords.closed(S.of(tester.element(strip)), reason))),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the notification that launched the app opens its session', (tester) async {
      await AuthStorageImpl(store).save(
        const AccountSession(userId: testUserId, deviceId: testDeviceId, token: 'saved', email: 'me@example.com'),
      );
      computerHolds('e.-1');
      messaging.initial = aiPush('e.-1');
      await launch(tester);
      expect(stack(), [MachineListRoute.name, AiSessionRoute.name]);
      expect(topSid(), 'e.-1');
    });

    testWidgets('opening it answers nothing: the request waits for a tap, however long it takes', (tester) async {
      computerHolds('e.-1', waiting: true);
      await launch(tester);
      await signIn(tester);
      messaging.opened.add(aiPush('e.-1'));
      await pumpFor(tester, const Duration(seconds: 1)); // a running turn ticks: nothing settles
      expect(find.byKey(const Key('ai.permission')), findsOneWidget);

      await pumpFor(tester, const Duration(seconds: 10));
      await tester.pump(const Duration(minutes: 5));
      expect(find.byKey(const Key('ai.permission')), findsOneWidget);
      final machineAi = ai();
      expect(machineAi.permissionAnswers, isEmpty);
      expect(machineAi.askAnswers, isEmpty);
      expect(machineAi.prompts, isEmpty);
      expect(machineAi.cancels, isEmpty);
      expect(machineAi.forceStops, isEmpty);
      expect(machineAi.opened, isEmpty);
    });

    testWidgets('a push of a terminal session while an AI session is open goes to that machine\'s terminal', (
      tester,
    ) async {
      computerHolds('e.-1');
      await launch(tester);
      await signIn(tester);
      messaging.opened.add(aiPush('e.-1'));
      await tester.pumpAndSettle();
      expect(stack(), [MachineListRoute.name, AiSessionRoute.name]);

      messaging.opened.add(const PushMessage(title: 'MacBook-Pro · Phiên 1', data: {'agent_id': agentA}));
      await tester.pumpAndSettle();
      expect(stack(), [MachineListRoute.name, TerminalRoute.name]);
    });

    testWidgets('the same session id on another machine is another session: it opens, in the place of the first', (
      tester,
    ) async {
      onNewBackend = (backend) {
        backend.pinnedList.add(pinned(agentB));
        backend.deviceList.add(agentDevice(agentB, 'Mac-mini'));
        backend.addMachine(agentB);
      };
      computerHolds('e.-1');
      computerHolds('e.-1', agentId: agentB);
      await launch(tester);
      await signIn(tester);
      messaging.opened.add(aiPush('e.-1'));
      await tester.pumpAndSettle();
      expect((router.topRoute.args as AiSessionRouteArgs).agentId, agentA);

      messaging.opened.add(aiPush('e.-1', agentId: agentB));
      await tester.pumpAndSettle();
      expect(stack(), [MachineListRoute.name, AiSessionRoute.name]);
      final top = router.topRoute.args as AiSessionRouteArgs;
      expect((top.agentId, top.sid, top.machineName), (agentB, 'e.-1', 'Mac-mini'));
    });

    testWidgets('an AI push of a machine that is not paired on this phone opens nothing', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester);
      messaging.opened.add(
        PushMessage(data: {'agent_id': agentB, 'kind': 'ai', 'ai_session': 'e.-1'}),
      );
      await tester.pumpAndSettle();
      expect(stack(), [MachineListRoute.name]);
    });
  });

  testWidgets('push: a message in the foreground shows the in-app banner (spec §6)', (tester) async {
    await launch(tester);
    await signIn(tester);
    messaging.foreground.add(const PushMessage(title: 'MacBook-Pro · Phiên 1', body: '✓ make · 45 giây'));
    expect(popups.infos, ['MacBook-Pro · Phiên 1']);
  });

  testWidgets('sign in → machine list → settings → sign out returns to login', (tester) async {
    await launch(tester);
    expect(find.widgetWithText(AppButton, 'Sign in'), findsOneWidget);
    await signIn(tester);
    expect(find.text('Your computers'), findsOneWidget);
    expect(find.text('MacBook-Pro'), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Sign out'), 200);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppButton, 'Sign in'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    expect(backends.backends.single.disposed, isTrue);
    expect(find.text('me@example.com'), findsOneWidget); // prefilled for the next sign-in
  });

  testWidgets('a revoked token while a terminal is open goes back to login (spec §12)', (tester) async {
    await launch(tester);
    await signIn(tester);
    await openTerminal(tester);

    backends.backends.single.emitRelay(RelayConnectionState.revoked);
    await tester.pumpAndSettle();
    expect(find.text('Your sign-in has expired. Please sign in again.'), findsOneWidget);
    expect(find.text('me@example.com'), findsOneWidget);
    expect(find.text('zsh 1'), findsNothing);
    // R1: the terminal page leaves with the rest of the stack; it pops nothing itself.
    expect(stack(), [LoginRoute.name]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R1: a machine that stops trusting the phone as the token is revoked: only the login page', (
    tester,
  ) async {
    await launch(tester);
    await signIn(tester);
    await openTerminal(tester);
    final backend = backends.backends.single;
    final machine = backend.machines[agentA]!;

    // The page's own exit (untrusted → pop after this frame) and the enforcer's replaceAll land
    // in the same frame.
    machine.emitState(const MachineFailed(MachineConnectionFailure.untrusted));
    backend.emitRelay(RelayConnectionState.revoked);
    await tester.pumpAndSettle();

    expect(stack(), [LoginRoute.name]);
    expect(find.text('Your sign-in has expired. Please sign in again.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R1: a revocation after the terminal closed as untrusted also clears the re-pair dialog', (
    tester,
  ) async {
    await launch(tester);
    await signIn(tester);
    await openTerminal(tester);
    final backend = backends.backends.single;

    backend.machines[agentA]!.emitState(const MachineFailed(MachineConnectionFailure.untrusted));
    await tester.pumpAndSettle();
    expect(find.text('Pair again'), findsOneWidget);

    backend.emitRelay(RelayConnectionState.revoked);
    await tester.pumpAndSettle();
    expect(stack(), [LoginRoute.name]);
    expect(find.text('Pair again'), findsNothing);
    expect(find.text('Your sign-in has expired. Please sign in again.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete account from settings ends on the login screen', (tester) async {
    await launch(tester);
    await signIn(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Delete account'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'correct horse');
    await tester.pump();
    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();

    expect(find.text('Your account has been deleted.'), findsOneWidget);
    expect(await store.read(AuthStorage.tokenKey), isNull);
    expect(await store.read(DeviceIdentity.storageKey), isNull);
    expect(stack(), [LoginRoute.name]);
  });

  testWidgets('R3: the login form appears only once the sign-out has finished', (tester) async {
    await launch(tester);
    await signIn(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    relay.logoutGate = Completer<void>();
    await tester.scrollUntilVisible(find.text('Sign out'), 200);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pumpAndSettle();

    // Still signing out (POST /v1/auth/logout pending): no form to submit yet.
    expect(find.widgetWithText(AppButton, 'Sign in'), findsNothing);
    expect(stack(), isNot(contains(LoginRoute.name)));

    relay.logoutGate!.complete();
    await tester.pumpAndSettle();
    expect(stack(), [LoginRoute.name]);
    await signIn(tester);
    expect(find.text('Your computers'), findsOneWidget);
    expect(backends.backends, hasLength(2));
  });

  testWidgets('R2: dialogs open on the router\'s navigator, under the lock', (tester) async {
    await launch(tester);
    await signIn(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Sign out'), 200);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final dialog = tester.element(find.byType(AlertDialog));
    expect(Navigator.of(dialog), same(router.navigatorKey.currentState));
    expect(Navigator.of(dialog, rootNavigator: true), same(router.navigatorKey.currentState));

    // Back after more than 5 minutes: the lock covers the dialog too.
    biometrics.result = false;
    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    clock = clock.add(const Duration(minutes: 6));
    for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(find.text('ShellX is locked'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Sign out'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(session.isAuthenticated.value, isTrue);
  });

  testWidgets('the lock screen covers the app on launch when enabled', (tester) async {
    biometrics.result = false;
    await launch(tester);
    expect(find.text('ShellX is locked'), findsOneWidget);
    biometrics.result = true;
    await tester.tap(find.text('Unlock with Face ID'));
    await tester.pumpAndSettle();
    expect(find.text('ShellX is locked'), findsNothing);
  });

  testWidgets('R4: a keychain that cannot be read at launch, settings included: locked, then login', (
    tester,
  ) async {
    await AuthStorageImpl(store).save(
      const AccountSession(userId: testUserId, deviceId: testDeviceId, token: 'saved', email: 'me@example.com'),
    );
    await store.write(AppSettings.biometricLockKey, 'false');
    // Fails before the settings load, as the Keychain would under dependency injection.
    store.readError = PlatformException(code: 'keychain');
    biometrics.result = false;
    await launch(tester);
    expect(find.text('ShellX is locked'), findsOneWidget);
    expect(tester.takeException(), isNull);

    store.readError = null;
    biometrics.result = true;
    await tester.tap(find.text('Unlock with Face ID'));
    await tester.pumpAndSettle();
    expect(stack(), [LoginRoute.name]);
    expect(backends.backends, isEmpty);
    await signIn(tester);
    expect(find.text('Your computers'), findsOneWidget);
  });

  testWidgets('a launch step that fails outright still opens the app locked, then on the login page', (
    tester,
  ) async {
    biometrics.result = false;
    await launch(tester, prepare: () async => throw PlatformException(code: 'keychain'));
    expect(find.text('ShellX is locked'), findsOneWidget);
    expect(tester.takeException(), isNull);

    biometrics.result = true;
    // The biometric kind was never detected: the button names the conservative default.
    await tester.tap(find.textContaining('Unlock with'));
    await tester.pumpAndSettle();
    expect(stack(), [LoginRoute.name]);
    await signIn(tester);
    expect(find.text('Your computers'), findsOneWidget);
  });

  testWidgets('R4: an unreachable relay at launch does not block the app', (tester) async {
    relay.versionOffline = true;
    await launch(tester);
    expect(stack(), [LoginRoute.name]);
    await signIn(tester);
    expect(find.text('Your computers'), findsOneWidget);
  });

  testWidgets('R5: the relay is suspended in the background and resumed on return', (tester) async {
    await launch(tester);
    await signIn(tester);
    final backend = backends.backends.single;

    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    expect(backend.suspendCalls, 1);
    for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(backend.resumeCalls, 1);
    expect(find.text('Your computers'), findsOneWidget);
  });

  test('both font licences are registered for the licences page', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerFontLicenses();
    final packages = [await for (final entry in LicenseRegistry.licenses) ...entry.packages];
    expect(packages, containsAll(['JetBrains Mono', 'Raleway']));
  });
}
