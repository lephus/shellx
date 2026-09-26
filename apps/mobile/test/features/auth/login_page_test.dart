import 'package:flutter/services.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/auth/presentation/controllers/login_controller.dart';
import 'package:shellx_mobile/features/auth/presentation/controllers/register_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fakes.dart';

void main() {
  late FakeSessionHolder session;
  late FakePopupHandler popups;
  late FakeExternalLinks links;

  setUp(() {
    session = FakeSessionHolder();
    popups = FakePopupHandler();
    links = FakeExternalLinks();
    getIt
      ..registerSingleton<PopupHandler>(popups)
      ..registerSingleton<ExternalLinks>(links)
      ..registerFactory<LoginController>(() => LoginController(session))
      ..registerFactory<RegisterController>(() => RegisterController(session));
  });

  tearDown(getIt.reset);

  Future<void> openLogin(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      routedApp(
        open: () => const LoginRoute(),
        routes: [
          AutoRoute(page: LoginRoute.page),
          AutoRoute(page: RegisterRoute.page),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await openPushed(tester);
  }

  Future<void> fill(WidgetTester tester, String email, String password) async {
    await tester.enterText(find.byType(TextField).at(0), email);
    await tester.enterText(find.byType(TextField).at(1), password);
    await tester.pump();
  }

  Finder button(String title) => find.widgetWithText(AppButton, title);
  ButtonState stateOf(WidgetTester tester, String title) => tester.widget<AppButton>(button(title)).state;

  group('sign in', () {
    testWidgets('design: subtitle, forgot-password hint, "Tạo tài khoản"; signs in', (tester) async {
      await openLogin(tester);
      expect(find.text('Dùng cùng tài khoản với ShellX trên máy tính.'), findsOneWidget);
      expect(find.text('Quên mật khẩu? Đổi mật khẩu trong ShellX trên máy tính đang đăng nhập.'), findsOneWidget);
      expect(find.text('Chưa có tài khoản?'), findsOneWidget);
      await fill(tester, 'me@example.com', 'secret');
      await tester.tap(button('Đăng nhập'));
      await tester.pumpAndSettle();
      expect(session.authCalls, [('login', 'me@example.com', 'secret')]);
    });

    testWidgets('shows invalid_credentials and 429 with the spec texts', (tester) async {
      await openLogin(tester);
      await fill(tester, 'me@example.com', 'wrong');
      session.authError = const ApiException(status: 401, code: 'invalid_credentials', message: 'x');
      await tester.tap(button('Đăng nhập'));
      await tester.pumpAndSettle();

      session.authError = const ApiException(status: 429, code: 'rate_limited', message: 'x');
      await tester.tap(button('Đăng nhập'));
      await tester.pumpAndSettle();
      expect(popups.errors, ['Email hoặc mật khẩu không đúng.', 'Thử lại sau ít phút.']);
    });

    testWidgets('rejects an obviously invalid email without calling the relay', (tester) async {
      await openLogin(tester);
      await fill(tester, 'not-an-email', 'whatever');
      await tester.tap(button('Đăng nhập'));
      await tester.pump();
      expect(find.text('Email không hợp lệ.'), findsOneWidget);
      expect(session.authCalls, isEmpty);
    });

    testWidgets('after a 4002: the expired banner and the email prefilled', (tester) async {
      session
        ..lastEmail = 'phu@shellx.pro'
        ..signOutReasonValue = SignOutReason.revoked;
      await openLogin(tester);
      expect(find.text('Phiên đăng nhập đã hết hiệu lực. Hãy đăng nhập lại.'), findsOneWidget);
      expect(find.text('phu@shellx.pro'), findsOneWidget);
      expect(find.text('Dùng cùng tài khoản với ShellX trên máy tính.'), findsNothing);
    });

    testWidgets('after deleting the account: "Tài khoản đã được xóa."', (tester) async {
      session.signOutReasonValue = SignOutReason.accountDeleted;
      await openLogin(tester);
      expect(find.text('Tài khoản đã được xóa.'), findsOneWidget);
    });

    testWidgets('R3: while a sign-in runs, neither the button nor the keyboard sends it again', (tester) async {
      await openLogin(tester);
      session.authGate = Completer<void>();
      await fill(tester, 'me@example.com', 'secret');
      await tester.tap(button('Đăng nhập'));
      await tester.pump();
      expect(stateOf(tester, 'Đăng nhập'), ButtonState.loading);

      await tester.tap(button('Đăng nhập'), warnIfMissed: false);
      await tester.showKeyboard(find.byType(TextField).at(1));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(session.authCalls, [('login', 'me@example.com', 'secret')]);

      session.authGate!.complete();
      await tester.pumpAndSettle();
      expect(stateOf(tester, 'Đăng nhập'), ButtonState.available);
    });
  });

  group('create account', () {
    Future<void> openRegister(WidgetTester tester) async {
      await openLogin(tester);
      await tester.tap(find.text('Tạo tài khoản'));
      await tester.pumpAndSettle();
      expect(find.text('Một tài khoản cho điện thoại và mọi máy tính của bạn.'), findsOneWidget);
    }

    testWidgets('checked while typing; the button stays dimmed until valid', (tester) async {
      await openRegister(tester);
      expect(stateOf(tester, 'Tạo tài khoản'), ButtonState.disable);

      await fill(tester, 'not-an-email', 'short');
      expect(find.text('Email không hợp lệ.'), findsOneWidget);
      expect(find.text('Từ 8 đến 128 ký tự. Còn thiếu 3 ký tự.'), findsOneWidget);
      expect(stateOf(tester, 'Tạo tài khoản'), ButtonState.disable);

      await fill(tester, 'me@example.com', 'long enough');
      expect(find.text('Email không hợp lệ.'), findsNothing);
      expect(find.text('Từ 8 đến 128 ký tự.'), findsOneWidget);
      expect(stateOf(tester, 'Tạo tài khoản'), ButtonState.available);

      await tester.tap(button('Tạo tài khoản'));
      await tester.pumpAndSettle();
      expect(session.authCalls, [('register', 'me@example.com', 'long enough')]);
    });

    testWidgets('the relay\'s disposable-email answer stays under the email until it changes', (tester) async {
      await openRegister(tester);
      session.authError = const ApiException(status: 400, code: 'disposable_email', message: 'x');
      await fill(tester, 'ban@yopmail.com', 'long enough');
      await tester.tap(button('Tạo tài khoản'));
      await tester.pumpAndSettle();
      expect(find.text('Email tạm thời không dùng được. Hãy dùng email thật.'), findsOneWidget);
      expect(stateOf(tester, 'Tạo tài khoản'), ButtonState.disable);
      expect(popups.errors, isEmpty);

      await tester.enterText(find.byType(TextField).at(0), 'ban@example.com');
      await tester.pump();
      expect(find.text('Email tạm thời không dùng được. Hãy dùng email thật.'), findsNothing);
      expect(stateOf(tester, 'Tạo tài khoản'), ButtonState.available);
    });

    testWidgets('the terms line links both pages', (tester) async {
      await openRegister(tester);
      await tester.tap(find.text('Điều khoản'));
      await tester.tap(find.text('Chính sách quyền riêng tư'));
      expect(links.opened, [Uri.parse('https://shellx.pro/terms'), Uri.parse('https://shellx.pro/privacy')]);
    });

    testWidgets('a link the phone cannot open shows the error toast instead of failing silently', (tester) async {
      await openRegister(tester);
      links.error = PlatformException(code: 'ACTIVITY_NOT_FOUND');
      await tester.tap(find.text('Điều khoản'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(popups.errors, ['Đã có lỗi xảy ra (PlatformException).']);
    });

    testWidgets('too long: "Thừa N ký tự."; weak_password stays under the password', (tester) async {
      await openRegister(tester);
      await fill(tester, 'me@example.com', 'a' * 130);
      expect(find.text('Từ 8 đến 128 ký tự. Thừa 2 ký tự.'), findsOneWidget);
      expect(stateOf(tester, 'Tạo tài khoản'), ButtonState.disable);

      session.authError = const ApiException(status: 400, code: 'weak_password', message: 'x');
      await fill(tester, 'me@example.com', 'long enough');
      await tester.tap(button('Tạo tài khoản'));
      await tester.pumpAndSettle();
      expect(find.text('Mật khẩu phải có 8–128 ký tự.'), findsOneWidget);
      expect(stateOf(tester, 'Tạo tài khoản'), ButtonState.disable);
      expect(popups.errors, isEmpty);
    });

    testWidgets('the missing and extra characters are counted in code points (emoji)', (tester) async {
      await openRegister(tester);
      await fill(tester, 'me@example.com', '😀' * 5);
      expect(find.text('Từ 8 đến 128 ký tự. Còn thiếu 3 ký tự.'), findsOneWidget);
      expect(stateOf(tester, 'Tạo tài khoản'), ButtonState.disable);

      await fill(tester, 'me@example.com', '😀' * 130);
      expect(find.text('Từ 8 đến 128 ký tự. Thừa 2 ký tự.'), findsOneWidget);
      expect(stateOf(tester, 'Tạo tài khoản'), ButtonState.disable);

      await fill(tester, 'me@example.com', '😀' * 8);
      expect(find.text('Từ 8 đến 128 ký tự.'), findsOneWidget);
      expect(stateOf(tester, 'Tạo tài khoản'), ButtonState.available);
    });

    testWidgets('R3: the keyboard submits only what the button would, once', (tester) async {
      await openRegister(tester);
      await fill(tester, 'me@example.com', 'short');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(session.authCalls, isEmpty);

      session.authGate = Completer<void>();
      await fill(tester, 'me@example.com', 'long enough');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(stateOf(tester, 'Tạo tài khoản'), ButtonState.loading);

      await tester.showKeyboard(find.byType(TextField).at(1));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.tap(button('Tạo tài khoản'), warnIfMissed: false);
      await tester.pump();
      expect(session.authCalls, [('register', 'me@example.com', 'long enough')]);

      session.authGate!.complete();
      await tester.pumpAndSettle();
    });
  });
}
