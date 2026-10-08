import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_font_size.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:xterm/xterm.dart' show TerminalView;

import '../support/config_workspace.dart';
import '../support/fake_local_sessions.dart';

void main() {
  test('effective size is global plus the workspace step, clamped to 9–28', () {
    expect(effectiveFontSize(13, 0), 13);
    expect(effectiveFontSize(13, 2), 15);
    expect(effectiveFontSize(27, 5), 28);
    expect(effectiveFontSize(10, -6), 9);
  });

  test('the step survives JSON and an old workspace entry has none', () {
    const w = Workspace(id: 'a', name: 'A', fontStep: 2);
    expect(Workspace.decode(w.encode())!.fontStep, 2);
    expect(
      Workspace.decode('{"id":"a","name":"A","collapsed":false}')!.fontStep,
      0,
    );
    expect(Workspace.decode('{"id":"a","name":"A","zoom":"big"}')!.fontStep, 0);
    expect(Workspace.decode('{"id":"a","name":"A","zoom":99}')!.fontStep, 10);
    expect(Workspace.decode('{"id":"a","name":"A","zoom":-99}')!.fontStep, -6);
  });

  test('a workspace without a step writes no zoom key (older builds)', () {
    expect(
      const Workspace(id: 'a', name: 'A').encode(),
      isNot(contains('zoom')),
    );
    expect(
      const Workspace(id: 'a', name: 'A', fontStep: 1.5).encode(),
      contains('"zoom":1.5'),
    );
  });

  group('SidebarWorkspaces zoom', () {
    late FakeLocalSessions local;
    late InMemorySettingsStore settings;
    late ProviderContainer c;

    setUp(() async {
      local = FakeLocalSessions();
      settings = InMemorySettingsStore();
      c = ProviderContainer.test(
        overrides: [
          localSessionsProvider.overrideWithValue(local),
          appL10nProvider.overrideWithValue(
            lookupAppLocalizations(const Locale('en')),
          ),
          settingsStoreProvider.overrideWithValue(settings),
          terminalFontSizeProvider.overrideWith(() => _Fixed(13)),
        ],
      );
      c.read(sidebarWorkspacesProvider);
      await c.read(sidebarWorkspacesProvider.notifier).create();
    });

    SidebarWorkspaces sidebar() => c.read(sidebarWorkspacesProvider.notifier);

    test(
      'zooming one workspace leaves the other and the global size alone',
      () {
        final other = c.read(sidebarWorkspacesProvider).workspaces.last.id;
        sidebar().zoom(other, 1);
        expect(c.read(sidebarWorkspacesProvider).workspace(other)!.fontStep, 1);
        expect(
          c
              .read(sidebarWorkspacesProvider)
              .workspace(kDefaultWorkspaceId)!
              .fontStep,
          0,
        );
        expect(c.read(terminalFontSizeProvider), 13);
      },
    );

    test('the step is bounded −6…+10 and reset returns to 0', () {
      final id = c.read(sidebarWorkspacesProvider).workspaces.last.id;
      for (var i = 0; i < 30; i++) {
        sidebar().zoom(id, 1);
      }
      expect(c.read(sidebarWorkspacesProvider).workspace(id)!.fontStep, 10);
      for (var i = 0; i < 40; i++) {
        sidebar().zoom(id, -1);
      }
      expect(c.read(sidebarWorkspacesProvider).workspace(id)!.fontStep, -6);
      sidebar().resetZoom(id);
      expect(c.read(sidebarWorkspacesProvider).workspace(id)!.fontStep, 0);
    });

    test('the step is saved with the workspace list and read back', () async {
      final id = c.read(sidebarWorkspacesProvider).workspaces.last.id;
      sidebar().zoom(id, 2);
      await pumpEventQueue();
      final back = loadWorkspaces(
        settings.strings[SettingKeys.terminalWorkspaces]!,
      );
      expect(back.firstWhere((w) => w.id == id).fontStep, 2);
    });

    test('renaming or collapsing keeps the step', () {
      final id = c.read(sidebarWorkspacesProvider).workspaces.last.id;
      sidebar().zoom(id, 3);
      sidebar().rename(id, 'Backend');
      sidebar().setCollapsed(id, true);
      expect(c.read(sidebarWorkspacesProvider).workspace(id)!.fontStep, 3);
    });

    test('fontStepOf gives the step of the workspace holding a tab', () {
      final s = c.read(sidebarWorkspacesProvider);
      final id = s.workspaces.last.id;
      final tab = s.tabsOf(id).single;
      sidebar().zoom(id, 4);
      expect(c.read(sidebarWorkspacesProvider).fontStepOf(tab), 4);
      expect(c.read(sidebarWorkspacesProvider).fontStepOf(-5), 0);
    });
  });

  group('on screen', () {
    final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

    /// The font size of the view inside tab [tabId]'s pane tree (found by
    /// walking up, so an offstage tab works too).
    double sizeOf(WidgetTester t, int tabId) {
      for (final e
          in find.byType(TerminalView, skipOffstage: false).evaluate()) {
        var inside = false;
        e.visitAncestorElements((a) {
          if (a.widget.key == ValueKey('terminal.$tabId')) inside = true;
          return !inside;
        });
        if (inside) return (e.widget as TerminalView).textStyle.fontSize;
      }
      throw StateError('no terminal view in tab $tabId');
    }

    Future<void> chord(
      WidgetTester t,
      LogicalKeyboardKey key, {
      bool alt = false,
    }) async {
      await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      if (alt) await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await t.sendKeyEvent(key);
      if (alt) await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await t.pumpAndSettle();
    }

    testWidgets('Cmd+Alt+= zooms the selected tab\'s workspace only; Cmd+= '
        'moves both; Cmd+Alt+0 resets', (t) async {
      final rig = await pumpConfiguredWorkspace(t);
      final c = rig.container;
      final first = c.read(terminalTabsProvider).selected!.id;
      await c.read(sidebarWorkspacesProvider.notifier).create();
      await t.pumpAndSettle();
      final second = c.read(terminalTabsProvider).selected!.id;
      c.read(terminalTabsProvider.notifier).select(first);
      await t.pumpAndSettle();
      expect(sizeOf(t, first), 13);
      expect(sizeOf(t, second), 13);

      final firstResizes = rig.local.views[first]!.resizes.length;
      final secondResizes = rig.local.views[second]!.resizes.length;
      await chord(t, LogicalKeyboardKey.equal, alt: true);
      expect(sizeOf(t, first), 14);
      expect(sizeOf(t, second), 13);
      expect(
        rig.local.views[first]!.resizes.length,
        greaterThan(firstResizes),
        reason: 'the shell of the zoomed workspace learns its new grid',
      );
      expect(rig.local.views[second]!.resizes.length, secondResizes);

      c.read(terminalTabsProvider.notifier).select(second);
      await t.pumpAndSettle();
      expect(sizeOf(t, second), 13, reason: 'switching changes nothing');

      c.read(terminalTabsProvider.notifier).select(first);
      await t.pumpAndSettle();
      await chord(t, LogicalKeyboardKey.equal);
      expect(sizeOf(t, first), 15);
      expect(sizeOf(t, second), 14);

      await chord(t, LogicalKeyboardKey.minus, alt: true);
      expect(sizeOf(t, first), 14);
      await chord(t, LogicalKeyboardKey.equal, alt: true);
      expect(sizeOf(t, first), 15);
      await chord(t, LogicalKeyboardKey.digit0, alt: true);
      expect(sizeOf(t, first), 14, reason: 'back to the global size');
      expect(sizeOf(t, second), 14);
      await disposeWorkspace(t, c);
    }, variant: mac);
  });
}

class _Fixed extends TerminalFontSize {
  _Fixed(this.value);
  final double value;
  @override
  double build() => value;
}
