import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/ui/app.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fakes.dart';

/// UI-A5 §7.1, §7.3, §7.4 as dialogs over the window (the ConfirmRequest
/// the background-service flows build).
void main() {
  late TestHarness h;
  late ProviderContainer container;
  final en = lookupAppLocalizations(const Locale('en'));

  Future<void> pump(WidgetTester tester) async {
    h = TestHarness(settings: {'onboarding_done': true});
    container = ProviderContainer(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
    await container
        .read(agentControllerProvider.notifier)
        .bootstrap(watchForWake: false);
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ShellxDesktopApp(locale: Locale('en')),
      ),
    );
    await tester.pump();
  }

  void testApp(String d, Future<void> Function(WidgetTester) body) =>
      testWidgets(d, (tester) async {
        try {
          await body(tester);
        } finally {
          await tester.pumpWidget(const SizedBox());
          container.dispose();
        }
      });

  ConfirmRequest oldService({required Future<bool> Function()? onConfirm}) =>
      ConfirmRequest(
        title: en.daemonOldTitle,
        body: en.daemonOldBody('1.6.0', '1.5.2', 4),
        confirmLabel: en.daemonOldRestart,
        cancelLabel: en.daemonOldLater,
        onConfirm: onConfirm,
      );

  testApp('7.3: destructive restart, focus starts on "Later", Esc = Later', (
    tester,
  ) async {
    await pump(tester);
    final answer = container
        .read(windowRouterProvider.notifier)
        .confirm(oldService(onConfirm: null));
    await tester.pumpAndSettle();
    expect(find.text('The background service is out of date'), findsOneWidget);
    expect(find.textContaining('holds 4 sessions'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Restart Service'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    final later = tester.widget<OutlinedButton>(
      find.byKey(const Key('confirm.cancel')),
    );
    expect(later.autofocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await answer, isFalse);
  });

  testApp('7.3: while restarting the primary loads and both buttons lock', (
    tester,
  ) async {
    await pump(tester);
    final gate = Completer<bool>();
    final answer = container
        .read(windowRouterProvider.notifier)
        .confirm(oldService(onConfirm: () => gate.future));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm.ok')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('confirm.cancel')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('confirm.ok')))
          .onPressed,
      isNull,
    );
    gate.complete(true);
    expect(await answer, isTrue);
  });

  ConfirmRequest startFailed(Future<bool> Function() retry) => ConfirmRequest(
    title: en.daemonStartFailedTitle,
    body: en.daemonStartFailedBody,
    confirmLabel: en.daemonRetry,
    cancelLabel: en.quitUiAction,
    destructive: false,
    escapeCloses: false,
    onConfirm: retry,
  );

  testApp('7.4: Try Again retries and stays while it fails; Esc does nothing; '
      'Quit answers no', (tester) async {
    await pump(tester);
    var tries = 0;
    final answer = container
        .read(windowRouterProvider.notifier)
        .confirm(startFailed(() async => ++tries > 1));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't start the background service"), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(container.read(windowRouterProvider).confirm, isNotNull);
    await tester.tap(find.byKey(const Key('confirm.ok')));
    await tester.pumpAndSettle();
    expect(tries, 1);
    expect(container.read(windowRouterProvider).confirm, isNotNull);
    await tester.tap(find.byKey(const Key('confirm.ok')));
    await tester.pumpAndSettle();
    expect(await answer, isTrue);
  });

  testApp('7.4: "Quit" is the secondary button', (tester) async {
    await pump(tester);
    final answer = container
        .read(windowRouterProvider.notifier)
        .confirm(startFailed(() async => false));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm.cancel')));
    await tester.pumpAndSettle();
    expect(await answer, isFalse);
  });

  testApp('7.1: two buttons, Quit is the default, Quit Completely is the '
      'other, Esc stays', (tester) async {
    await pump(tester);
    final request = ConfirmRequest(
      title: en.quitUiExplainedTitle,
      body: en.quitUiExplainedBody(3),
      confirmLabel: en.quitUiAction,
      secondaryLabel: en.quitAllAction,
      destructive: false,
    );
    final answer = container
        .read(windowRouterProvider.notifier)
        .confirm(request);
    await tester.pumpAndSettle();
    expect(find.text('Your shells keep running'), findsOneWidget);
    expect(find.textContaining('3 tabs keep running'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('confirm.ok')))
          .autofocus,
      isTrue,
    );
    await tester.tap(find.byKey(const Key('confirm.cancel')));
    await tester.pumpAndSettle();
    expect(await answer, isFalse);
    expect(request.secondaryChosen, isTrue);
  });

  testApp('7.1: Esc closes it without choosing either', (tester) async {
    await pump(tester);
    final request = ConfirmRequest(
      title: en.quitUiExplainedTitle,
      body: en.quitUiExplainedBody(1),
      confirmLabel: en.quitUiAction,
      secondaryLabel: en.quitAllAction,
      destructive: false,
    );
    final answer = container
        .read(windowRouterProvider.notifier)
        .confirm(request);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await answer, isFalse);
    expect(request.secondaryChosen, isFalse);
  });
}
