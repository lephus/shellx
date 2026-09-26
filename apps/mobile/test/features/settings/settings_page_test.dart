import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';
import 'package:shellx_mobile/features/settings/presentation/controllers/delete_account_controller.dart';
import 'package:shellx_mobile/features/settings/presentation/controllers/settings_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';
import 'package:shellx_mobile/shared/shared.dart';

import '../../support/app_harness.dart';
import '../../support/fake_biometrics.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fakes.dart';

void main() {
  late AppSettings settings;
  late FakeBiometricAuthenticator biometrics;
  late AppLockController lock;
  late FakeBackend backend;
  late FakeSessionHolder session;
  late WorkspaceRegistry registry;
  late FakePopupHandler popups;
  late InMemoryKeyValueStore store;
  late PendingUnpairs pendingUnpairs;

  setUp(() async {
    store = InMemoryKeyValueStore();
    pendingUnpairs = PendingUnpairs(store);
    settings = AppSettings(store);
    await settings.load();
    biometrics = FakeBiometricAuthenticator();
    lock = AppLockController(authenticator: biometrics, isEnabled: () => settings.biometricLock.peek());
    await lock.detectKind();
    backend = FakeBackend(
      devices: [agentDevice(agentA, 'MacBook-Pro'), agentDevice(agentB, 'DESKTOP-42')],
      pinnedList: [pinned(agentA)],
    )..addMachine(agentA);
    session = FakeSessionHolder(backend);
    registry = WorkspaceRegistry(session.backend);
    popups = FakePopupHandler();
    getIt
      ..registerSingleton<PopupHandler>(popups)
      ..registerFactory<SettingsController>(
        () => SettingsController(
          session,
          settings,
          lock,
          biometrics,
          registry,
          PackageInfo(appName: 'ShellX', packageName: 'com.shellx.prod', version: '1.0.0', buildNumber: '1'),
          pendingUnpairs,
        ),
      )
      ..registerFactory<DeleteAccountController>(() => DeleteAccountController(session));
  });

  tearDown(() async {
    registry.dispose();
    await getIt.reset();
  });

  Future<void> openSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      routedApp(
        open: () => const SettingsRoute(),
        routes: [
          AutoRoute(page: SettingsRoute.page),
          AutoRoute(page: DeleteAccountRoute.page),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await openPushed(tester);
  }

  testWidgets('design: grouped cards, account email, version footer, paired machines by name', (tester) async {
    await openSettings(tester);
    for (final header in ['TERMINAL', 'BẢO MẬT', 'MÁY ĐÃ GHÉP NỐI', 'TÀI KHOẢN']) {
      expect(find.text(header), findsOneWidget, reason: header);
    }
    expect(find.text('me@example.com'), findsOneWidget);
    expect(find.text('ShellX 1.0.0 (1)'), findsOneWidget);
    expect(find.text('MacBook-Pro'), findsOneWidget);
    expect(find.text('DESKTOP-42'), findsNothing); // not paired
    expect(find.text('user@macbook'), findsNothing); // the preview is one rich text
    expect(find.textContaining('user@macbook', findRichText: true), findsOneWidget);
  });

  testWidgets('font size slider previews while it moves and stores the size on release', (tester) async {
    await openSettings(tester);
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(19);
    slider.onChanged!(20);
    await tester.pump();
    expect(settings.fontSize.value, 20);
    expect(find.text('20'), findsWidgets);
    expect(await store.read(AppSettings.fontSizeKey), isNull); // not on every step

    slider.onChangeEnd!(20);
    await tester.pumpAndSettle();
    expect(await store.read(AppSettings.fontSizeKey), '20.0');
  });

  testWidgets('a font size that cannot be stored shows the toast', (tester) async {
    settings = AppSettings(_UnwritableStore());
    await openSettings(tester);
    tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(20);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(popups.errors, isNotEmpty);
  });

  testWidgets('a biometric setting that cannot be stored shows the toast and changes nothing', (tester) async {
    settings = AppSettings(_UnwritableStore());
    lock.lockOnLaunch();
    await openSettings(tester);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(popups.errors, isNotEmpty);
    expect(settings.biometricLock.value, isTrue);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
    expect(lock.isLocked.value, isTrue); // settingChanged() only runs after a stored change
  });

  testWidgets('biometric switch is on by default and can be turned off', (tester) async {
    lock.lockOnLaunch();
    await openSettings(tester);
    expect(find.text('Khóa bằng Face ID'), findsOneWidget);
    expect(find.text('Hỏi khi mở app và khi quay lại sau hơn 5 phút.'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(settings.biometricLock.value, isFalse);
    // AppLockController.settingChanged() ran after the setting changed: turning the lock off must
    // not leave the user stuck behind it.
    expect(lock.isLocked.value, isFalse);
  });

  testWidgets('biometric switch is disabled without passcode or biometrics', (tester) async {
    biometrics.available = false;
    await openSettings(tester);
    expect(find.text('Thiết bị chưa đặt mã khóa hoặc sinh trắc học'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNull);
  });

  testWidgets('unpair asks, unpairs, drops the tabs and refreshes the list (spec §5.5)', (tester) async {
    registry.forMachine(agentA);
    await openSettings(tester);
    await tester.tap(find.text('Bỏ ghép nối'));
    await tester.pumpAndSettle();
    expect(find.text('Bỏ ghép nối MacBook-Pro? Bạn sẽ phải quét lại mã QR để dùng máy này.'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Bỏ ghép nối').last);
    await tester.pumpAndSettle();
    expect(backend.unpaired, [agentA]);
    expect(() => registry.forMachine(agentA), throwsStateError); // the old workspace is gone
    expect(find.text('Chưa ghép nối máy nào.'), findsOneWidget);
  });

  testWidgets('a failed unpair keeps the row with a retry, and still drops the workspace', (tester) async {
    registry.forMachine(agentA);
    backend.unpairError = const ApiException(status: 0, code: 'network', message: 'offline');
    await openSettings(tester);
    await tester.tap(find.text('Bỏ ghép nối'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Bỏ ghép nối').last);
    await tester.pumpAndSettle();

    expect(backend.unpaired, [agentA]);
    expect(() => registry.forMachine(agentA), throwsStateError); // dropped even though unpair threw
    expect(find.text('MacBook-Pro'), findsOneWidget); // still listed, not silently gone
    expect(find.text('Chưa bỏ ghép nối được.'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
    expect(popups.errors, isNotEmpty); // the guard's error toast still shows

    backend.unpairError = null;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa bỏ ghép nối được.'), findsNothing);
    expect(find.text('Chưa ghép nối máy nào.'), findsOneWidget);
  });

  testWidgets('two machines failing to unpair both keep their row; retrying one leaves the other', (tester) async {
    registry.forMachine(agentA);
    backend.pinnedList = [...backend.pinnedList, pinned(agentB)];
    backend.addMachine(agentB);
    registry.forMachine(agentB);
    backend.unpairError = const ApiException(status: 0, code: 'network', message: 'offline');
    await openSettings(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Bỏ ghép nối').at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Bỏ ghép nối').last);
    await tester.pumpAndSettle();
    // Only one "Bỏ ghép nối" button remains: the other row already turned into a retry.
    await tester.tap(find.widgetWithText(TextButton, 'Bỏ ghép nối'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Bỏ ghép nối').last);
    await tester.pumpAndSettle();

    expect(find.text('MacBook-Pro'), findsOneWidget);
    expect(find.text('DESKTOP-42'), findsOneWidget);
    expect(find.text('Chưa bỏ ghép nối được.'), findsNWidgets(2));
    expect(find.text('Thử lại'), findsNWidgets(2));

    backend.unpairError = null;
    await tester.tap(find.text('Thử lại').first);
    await tester.pumpAndSettle();

    expect(find.text('Chưa bỏ ghép nối được.'), findsOneWidget);
    expect(find.text('MacBook-Pro'), findsNothing); // retried and gone
    expect(find.text('DESKTOP-42'), findsOneWidget); // the other one is left alone
  });

  group('a failed unpair survives leaving Settings', () {
    Future<void> leaveAndReopen(WidgetTester tester) async {
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
      await openPushed(tester);
    }

    testWidgets('the row and its retry come back on the next visit', (tester) async {
      registry.forMachine(agentA);
      backend.unpairError = const ApiException(status: 0, code: 'network', message: 'offline');
      await openSettings(tester);
      await tester.tap(find.text('Bỏ ghép nối'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Bỏ ghép nối').last);
      await tester.pumpAndSettle();
      expect(await pendingUnpairs.load('user-1'), [(agentId: agentA, name: 'MacBook-Pro')]);

      await leaveAndReopen(tester);
      expect(find.text('MacBook-Pro'), findsOneWidget);
      expect(find.text('Chưa bỏ ghép nối được.'), findsOneWidget);

      backend.unpairError = null;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(find.text('Chưa ghép nối máy nào.'), findsOneWidget);
      expect(await pendingUnpairs.load('user-1'), isEmpty);

      await leaveAndReopen(tester);
      expect(find.text('Chưa bỏ ghép nối được.'), findsNothing);
    });

    testWidgets('leaving while the DELETE is still retrying records its failure all the same', (tester) async {
      registry.forMachine(agentA);
      final gate = backend.unpairGate = Completer<void>();
      backend.unpairError = const ApiException(status: 0, code: 'network', message: 'offline');
      await openSettings(tester);
      await tester.tap(find.text('Bỏ ghép nối'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Bỏ ghép nối').last);
      await tester.pump();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(await pendingUnpairs.load('user-1'), [(agentId: agentA, name: 'MacBook-Pro')]);

      backend.unpairGate = null;
      await openPushed(tester);
      expect(find.text('MacBook-Pro'), findsOneWidget);
      expect(find.text('Chưa bỏ ghép nối được.'), findsOneWidget);
    });

    testWidgets('a machine paired again is listed as paired, and its old record is dropped', (tester) async {
      await pendingUnpairs.add('user-1', agentA, 'MacBook-Pro');
      await openSettings(tester);
      expect(find.text('MacBook-Pro'), findsOneWidget);
      expect(find.text('Chưa bỏ ghép nối được.'), findsNothing);
      expect(find.text('Bỏ ghép nối'), findsOneWidget);
      expect(await pendingUnpairs.load('user-1'), isEmpty);
    });
  });

  testWidgets('a failed unpair whose name was never known shows the fallback, not blank', (tester) async {
    registry.forMachine(agentA);
    backend.devicesError = const ApiException(status: 0, code: 'network', message: 'offline');
    backend.unpairError = const ApiException(status: 0, code: 'network', message: 'offline');
    await openSettings(tester);
    // devices() failed on the very first load, so the pinned machine has no known name yet.
    expect(find.text('Máy không xác định'), findsOneWidget);

    await tester.tap(find.text('Bỏ ghép nối'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Bỏ ghép nối').last);
    await tester.pumpAndSettle();

    expect(find.text('Máy không xác định'), findsOneWidget); // still the fallback, not blank
    expect(find.text('Chưa bỏ ghép nối được.'), findsOneWidget);
  });

  testWidgets('pinnedMachines() failing shows the toast, not an endless spinner', (tester) async {
    backend.pinnedError = const ApiException(status: 0, code: 'network', message: 'offline');
    await openSettings(tester);
    expect(find.byType(AppCircularProgress), findsNothing);
    expect(find.text('Chưa ghép nối máy nào.'), findsOneWidget);
    expect(popups.errors, isNotEmpty);
  });

  testWidgets('sign out asks for confirmation', (tester) async {
    await openSettings(tester);
    await tester.tap(find.text('Đăng xuất'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(session.logoutCalls, 0);
    await tester.tap(find.text('Đăng xuất'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Đăng xuất'));
    await tester.pumpAndSettle();
    expect(session.logoutCalls, 1);
  });

  group('delete account', () {
    Future<void> openDeletePage(WidgetTester tester) async {
      await openSettings(tester);
      await tester.tap(find.text('Xóa tài khoản'));
      await tester.pumpAndSettle();
    }

    AppButton deleteButton(WidgetTester tester) =>
        tester.widget<AppButton>(find.widgetWithText(AppButton, 'Xóa vĩnh viễn'));

    testWidgets('warns what is lost and requires the password', (tester) async {
      await openDeletePage(tester);
      expect(find.text('Không hoàn tác được'), findsOneWidget);
      expect(find.text('Xóa tài khoản me@example.com, mọi máy và mọi ghép nối.'), findsOneWidget);
      expect(find.text('Mọi máy tính đang đăng nhập sẽ bị đăng xuất.'), findsOneWidget);
      expect(deleteButton(tester).state, ButtonState.disable);

      await tester.enterText(find.byType(TextField), 'correct horse');
      await tester.pump();
      expect(deleteButton(tester).state, ButtonState.available);
      await tester.tap(find.text('Xóa vĩnh viễn'));
      await tester.pumpAndSettle();
      expect(session.deletePasswords, ['correct horse']);
    });

    testWidgets('a wrong password shows "Mật khẩu không đúng." under the field', (tester) async {
      session.deleteError = const ApiException(status: 401, code: 'invalid_credentials', message: 'no');
      await openDeletePage(tester);
      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.pump();
      await tester.tap(find.text('Xóa vĩnh viễn'));
      await tester.pumpAndSettle();
      expect(find.text('Mật khẩu không đúng.'), findsOneWidget);
      expect(popups.errors, isEmpty);

      await tester.enterText(find.byType(TextField), 'wrong again');
      await tester.pump();
      expect(find.text('Mật khẩu không đúng.'), findsNothing);
    });

    testWidgets('"Hủy" goes back to Settings', (tester) async {
      await openDeletePage(tester);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(find.text('ShellX 1.0.0 (1)'), findsOneWidget);
    });

    testWidgets('rate limiting shows the spec message', (tester) async {
      session.deleteError = const ApiException(status: 429, code: 'rate_limited', message: 'slow');
      await openDeletePage(tester);
      await tester.enterText(find.byType(TextField), 'pw');
      await tester.pump();
      await tester.tap(find.text('Xóa vĩnh viễn'));
      await tester.pumpAndSettle();
      expect(find.text('Thử lại sau ít phút.'), findsOneWidget);
    });

    testWidgets('while a deletion is pending, back navigation and "Hủy" do nothing', (tester) async {
      final gate = Completer<void>();
      session.deleteGate = gate;
      await openDeletePage(tester);
      await tester.enterText(find.byType(TextField), 'correct horse');
      await tester.pump();
      await tester.tap(find.text('Xóa vĩnh viễn'));
      await tester.pump();

      // Still on the delete page: the back button and "Hủy" cannot pop it while busy. A loading
      // spinner is on screen (the delete button), so `pump()` instead of `pumpAndSettle()` — its
      // indeterminate animation never settles.
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      expect(find.text('Xóa tài khoản'), findsWidgets);
      await tester.tap(find.text('Hủy'));
      await tester.pump();
      expect(find.text('Xóa tài khoản'), findsWidgets);
      expect(session.deletePasswords, ['correct horse']); // exactly the one call, not retried

      gate.complete();
      await tester.pumpAndSettle();
      expect(session.deletePasswords, ['correct horse']);
    });
  });
}

/// A Keychain/Keystore that reads fine but cannot be written.
class _UnwritableStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) => Future.error(StateError('keychain'));

  @override
  Future<void> delete(String key) async {}
}
