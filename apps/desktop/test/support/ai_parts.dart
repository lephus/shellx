import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/ai/ai_frame_notifier.dart';
import 'package:shellx_desktop/src/ai/ai_runtimes.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/ai/ai_scope.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';

import 'ai_fakes.dart';
import 'fakes.dart';

/// A runtime over [FakeAiRuntimes] for one part of the pane (made, not
/// started), with Claude as its agent.
AiRuntime partRuntime(FakeAiRuntimes fakes) =>
    fakes.make(AiRuntimeRequest(agent: kKnownAgents.first, cwd: testAiCwd));

/// Pumps [child] inside an AI pane's scope over [runtime].
Future<({ProviderContainer container, AiPaneUi ui, TestHarness harness})>
pumpAiPart(
  WidgetTester t,
  Widget child, {
  required AiRuntime runtime,
  List<Override> overrides = const [],
  Locale locale = const Locale('en'),
}) async {
  final h = TestHarness(locale: locale);
  final c = ProviderContainer(
    overrides: [
      desktopServicesProvider.overrideWithValue(h.services()),
      ...overrides,
    ],
  );
  final frames = AiFrameNotifier(runtime.state);
  final ui = AiPaneUi();
  addTearDown(() {
    frames.dispose();
    ui.dispose();
    c.dispose();
  });
  final tab = TerminalTab.ai(
    id: kSyntheticTabIdBase,
    pane: AiPaneState(
      id: -1,
      agentId: runtime.state.agentId,
      agentName: runtime.state.agentName,
      title: 'New AI session',
      cwd: runtime.state.cwd,
    ),
  );
  t.view.physicalSize = const Size(1000, 700);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: buildDesktopTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: Scaffold(
          body: AiPaneScope(
            runtime: runtime,
            frames: frames,
            tab: tab,
            pane: tab.ai!,
            ui: ui,
            child: child,
          ),
        ),
      ),
    ),
  );
  return (container: c, ui: ui, harness: h);
}
