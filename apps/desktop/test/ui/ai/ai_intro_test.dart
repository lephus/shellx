import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/ai/ai_intro.dart';
import 'package:shellx_desktop/src/ui/app.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../../support/ai_fakes.dart';
import '../../support/config_harness.dart';
import '../../support/config_workspace.dart';
import '../../support/fakes.dart';
import '../../support/memory_config_fs.dart';

/// V2-1 D4: how new tabs open — onboarding's question and the one-time card.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets('onboarding asks "How do you want to work?"; the answer is '
      'written to the file; Finish marks the intro card done', (t) async {
    final h = TestHarness(settings: {SettingKeys.aiIntroShown: false});
    final fs = MemoryConfigFs();
    final c = ProviderContainer(
      overrides: [
        desktopServicesProvider.overrideWithValue(h.services()),
        ...configOverrides(fs),
      ],
    );
    addTearDown(c.dispose);
    await loadConfig(c);
    t.view.physicalSize = const Size(1100, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const ShellxDesktopApp(locale: Locale('en')),
      ),
    );
    c.read(windowRouterProvider.notifier).open(const OnboardingRoute());
    await t.pumpAndSettle();
    expect(find.text('How do you want to work?'), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('onboarding.ai')));
    await t.tap(find.byKey(const Key('onboarding.ai')));
    await t.pumpAndSettle();
    expect(fs.text(testConfigPaths().shellx), contains('new-tab-kind = ai'));
    await t.tap(find.byKey(const Key('onboarding.finish')));
    await t.pumpAndSettle();
    expect(c.read(agentControllerProvider).onboardingDone, isTrue);
    expect(
      h.settings.getBool(SettingKeys.aiIntroShown, defaultValue: false),
      isTrue,
    );
  });

  testWidgets('someone from before V2 sees the card once; "AI interface" '
      'writes the file, and ⌘T opens AI sessions from then on', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final h = TestHarness(
      settings: {
        SettingKeys.onboardingDone: true,
        SettingKeys.aiIntroShown: false,
      },
    );
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      harness: h,
      extra: fakes.overrides,
    );
    expect(
      find.text('New: an AI interface. How should new tabs open?'),
      findsOneWidget,
    );
    await t.tap(find.byKey(const Key('ai.intro.ai')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.intro')), findsNothing);
    expect(w.fs.text(testConfigPaths().shellx), contains('new-tab-kind = ai'));
    expect(
      h.settings.getBool(SettingKeys.aiIntroShown, defaultValue: false),
      isTrue,
    );
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyT);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pumpAndSettle();
    expect(w.container.read(terminalTabsProvider).selected!.isAi, isTrue);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('× closes the card for good and changes nothing', (t) async {
    final h = TestHarness(
      settings: {
        SettingKeys.onboardingDone: true,
        SettingKeys.aiIntroShown: false,
      },
    );
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      harness: h,
    );
    await t.tap(find.byKey(const Key('ai.intro.close')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.intro')), findsNothing);
    expect(w.fs.files, isEmpty, reason: 'no configuration was written');
    expect(
      h.settings.getBool(SettingKeys.aiIntroShown, defaultValue: false),
      isTrue,
    );
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  test('a new install never gets the card (onboarding asks)', () {
    final h = TestHarness(settings: {SettingKeys.aiIntroShown: false});
    final c = ProviderContainer.test(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
    expect(c.read(aiIntroDueProvider), isFalse);
  });
}
