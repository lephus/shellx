import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/config/font_probe.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/terminal_style.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/device_pixel_lines.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';
import 'package:shellx_desktop/src/ui/theme/terminal_colors.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';
import 'package:xterm/xterm.dart';

import '../config/font_probe_test.dart' show FakeProbe;
import '../support/config_harness.dart';
import '../support/fake_local_sessions.dart';
import '../support/fakes.dart';
import '../support/memory_config_fs.dart';

late ProviderContainer container;
late FakeLocalSessions local;

Future<void> pump(
  WidgetTester tester,
  MemoryConfigFs fs, {
  String? config,
  FontProbe? probe,
  int sessions = 1,
}) async {
  if (config != null) fs.write(testConfigPaths().shellx, config);
  final h = TestHarness(settings: {'onboarding_done': true});
  local = FakeLocalSessions();
  for (var id = 1; id <= sessions; id++) {
    local.add(local.summary(id, origin: SessionOrigin.desktop, title: 'zsh'));
  }
  container = ProviderContainer(
    overrides: [
      desktopServicesProvider.overrideWithValue(h.services()),
      localSessionsProvider.overrideWithValue(local),
      fontProbeProvider.overrideWithValue(probe ?? FakeProbe(const {})),
      ...configOverrides(fs),
    ],
  );
  await h.seedSignedIn();
  await container
      .read(agentControllerProvider.notifier)
      .bootstrap(watchForWake: false);
  await loadConfig(container);
  container.read(windowRouterProvider.notifier).showTerminal();
  tester.view.physicalSize = const Size(1100, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDesktopTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(body: TerminalWorkspacePage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  container.dispose();
}

Future<void> reload(WidgetTester tester, MemoryConfigFs fs, String text) async {
  fs.write(testConfigPaths().shellx, text);
  await loadConfig(container);
  await tester.pumpAndSettle();
}

TerminalView view(WidgetTester tester) =>
    tester.widget<TerminalView>(find.byType(TerminalView));

Color area(WidgetTester tester) => tester
    .widgetList<ColoredBox>(find.byKey(const ValueKey('terminal.area')))
    .single
    .color;

/// Every colour xterm draws with (TerminalTheme has no ==).
List<Color> themeColors(TerminalTheme t) => [
  t.cursor,
  t.selection,
  t.foreground,
  t.background,
  t.black,
  t.red,
  t.green,
  t.yellow,
  t.blue,
  t.magenta,
  t.cyan,
  t.white,
  t.brightBlack,
  t.brightRed,
  t.brightGreen,
  t.brightYellow,
  t.brightBlue,
  t.brightMagenta,
  t.brightCyan,
  t.brightWhite,
  t.searchHitBackground,
  t.searchHitBackgroundCurrent,
  t.searchHitForeground,
];

void main() {
  testWidgets('no file looks like A1 (criterion 1)', (tester) async {
    await pump(tester, MemoryConfigFs());
    final v = view(tester);
    expect(v.textStyle.fontFamily, kTerminalFontFamily);
    expect(
      v.textStyle.fontFamilyFallback,
      const TerminalStyle().fontFamilyFallback,
    );
    expect(v.textStyle.fontSize, 13);
    expect(v.textStyle.height, 1.2);
    expect(themeColors(v.theme), themeColors(TerminalColors.theme));
    expect(v.cursorType, TerminalCursorType.block);
    expect(v.padding, ShellxSizes.terminalPadding);
    expect(area(tester), TerminalColors.theme.background);
    await finish(tester);
  });

  testWidgets('font, size, colours, cursor, padding from the file (criterion '
      '2), live', (tester) async {
    final fs = MemoryConfigFs();
    await pump(
      tester,
      fs,
      config:
          'font-family = Menlo\nfont-family = Symbols\nfont-size = 16\n'
          'background = #fdf6e3\nforeground = #002b36\ncursor-style = bar\n'
          'window-padding-x = 4\n',
    );
    var v = view(tester);
    expect(v.textStyle.fontFamily, 'Menlo');
    expect(v.textStyle.fontFamilyFallback, [
      'Symbols',
      kTerminalFontFamily,
      ...const TerminalStyle().fontFamilyFallback,
    ]);
    expect(v.textStyle.fontSize, 16);
    expect(v.theme.background, const Color(0xFFFDF6E3));
    expect(v.theme.foreground, const Color(0xFF002B36));
    expect(v.cursorType, TerminalCursorType.verticalBar);
    expect(v.padding, const EdgeInsets.fromLTRB(4, 6, 4, 6));
    // The terminal area behind the pane follows the theme (D15).
    expect(area(tester), const Color(0xFFFDF6E3));
    // Live: a reload changes the view without reopening the tab.
    final terminal = v.terminal;
    await reload(tester, fs, 'cursor-style = underline\n');
    v = view(tester);
    expect(identical(v.terminal, terminal), isTrue);
    expect(v.cursorType, TerminalCursorType.underline);
    expect(v.textStyle.fontFamily, kTerminalFontFamily);
    expect(v.textStyle.fontSize, 13);
    expect(v.padding, ShellxSizes.terminalPadding);
    expect(themeColors(v.theme), themeColors(TerminalColors.theme));
    expect(area(tester), TerminalColors.theme.background);
    await finish(tester);
  });

  testWidgets('padding and font size re-measure the grid; only the visible '
      "tab's session is resized (D18, A3 D13)", (tester) async {
    final fs = MemoryConfigFs();
    await pump(tester, fs, sessions: 2);
    final tabs = container.read(terminalTabsProvider);
    final visible = tabs.selectedId!;
    final hidden = tabs.tabs.map((t) => t.id).firstWhere((id) => id != visible);
    final before = view(tester).terminal.viewWidth;
    local.views[visible]!.resizes.clear();
    local.views[hidden]!.resizes.clear();
    await reload(tester, fs, 'window-padding-x = 40\n');
    final selected = container.read(terminalTabsProvider).selected!;
    final narrower = selected.panes[visible]!.terminal.viewWidth;
    expect(narrower, lessThan(before));
    expect(local.views[visible]!.resizes.last.$1, narrower);
    expect(local.views[hidden]!.resizes, isEmpty);
    await reload(tester, fs, 'window-padding-x = 40\nfont-size = 20\n');
    expect(
      container
          .read(terminalTabsProvider)
          .selected!
          .panes[visible]!
          .terminal
          .viewWidth,
      lessThan(narrower),
    );
    expect(local.views[hidden]!.resizes, isEmpty);
    await finish(tester);
  });

  testWidgets('split panes follow the theme; the focus outline stays readable '
      'on a light background (D15, A3 D16)', (tester) async {
    final fs = MemoryConfigFs();
    await pump(tester, fs);
    await container.read(terminalTabsProvider.notifier).split(SplitAxis.row);
    await tester.pumpAndSettle();
    DevicePixelOutline outline() => tester.widget<DevicePixelOutline>(
      find.byKey(const Key('pane.focusOutline')),
    );
    expect(outline().color, ShellxDesktopColors.accent);
    await reload(
      tester,
      fs,
      'background = #fdf6e3\ncursor-style = underline\n',
    );
    final views = tester.widgetList<TerminalView>(find.byType(TerminalView));
    expect(views, hasLength(2));
    for (final v in views) {
      expect(v.theme.background, const Color(0xFFFDF6E3));
      expect(v.cursorType, TerminalCursorType.underline);
    }
    expect(outline().color, ShellxDesktopColors.bgTerminal);
    expect(area(tester), const Color(0xFFFDF6E3));
    await finish(tester);
  });

  testWidgets('a missing font is reported after the load, once (D11)', (
    tester,
  ) async {
    final probe = FakeProbe({'Nope': (found: false, monospace: true)});
    final fs = MemoryConfigFs();
    await pump(tester, fs, config: 'font-family = Nope\n', probe: probe);
    var problems = container.read(shellxConfigProvider).problems;
    expect(problems.map((p) => (p.code.name, p.value)), [
      ('fontNotFound', 'Nope'),
    ]);
    expect(probe.probed, ['Nope']);
    // Frames and rebuilds do not probe again.
    await tester.pump(const Duration(seconds: 1));
    expect(probe.probed, ['Nope']);
    // A new load probes again; the fixed file drops the warning.
    await reload(tester, fs, 'font-family = Menlo\n');
    expect(probe.probed, ['Nope', 'Menlo']);
    problems = container.read(shellxConfigProvider).problems;
    expect(problems, isEmpty);
    await finish(tester);
  });
}
