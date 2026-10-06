import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_menu.dart';
import 'package:shellx_desktop/src/tray/tray_presenter.dart';
import 'package:tray_manager/tray_manager.dart';

class _FakeTrayHost implements TrayHost {
  final List<(String, bool)> icons = [];
  final List<Menu> menus = [];

  /// setIcon calls that fail before one succeeds.
  int iconFailures = 0;

  @override
  Future<void> setIcon(String asset, {required bool isTemplate}) async {
    if (iconFailures > 0) {
      iconFailures--;
      throw StateError('tray not ready');
    }
    icons.add((asset, isTemplate));
  }

  @override
  Future<void> setToolTip(String text) async {}
  @override
  Future<void> setMenu(Menu menu) async => menus.add(menu);
}

final class _FailingMenuHost extends _FakeTrayHost {
  int menuFailures = 1;

  @override
  Future<void> setMenu(Menu menu) async {
    if (menuFailures > 0) {
      menuFailures--;
      throw StateError('tray not ready');
    }
    await super.setMenu(menu);
  }
}

void main() {
  const connected = AgentViewState(
    phase: AuthPhase.signedIn,
    email: 'a@b.co',
    relay: RelayConnectionState.connected,
  );

  test(
    'icon changes only when its state changes; macOS template except active',
    () async {
      final host = _FakeTrayHost();
      final presenter = TrayPresenter(
        host: host,
        l10n: lookupAppLocalizations(const Locale('en')),
        isWindows: false,
        onAction: (_) async {},
      );
      await presenter.render(connected);
      await presenter.render(connected.copyWith(email: 'c@d.co'));
      await presenter.render(connected.copyWith(activeChannels: 1));
      expect(host.icons, [
        ('assets/tray/tray_normal.png', true),
        ('assets/tray/tray_active.png', false),
      ]);
      // Each render shows another email in the status line.
      expect(host.menus, hasLength(3));
      await presenter.render(connected.copyWith(activeChannels: 2));
      // Only the channel count changed: the menu shows nothing of it.
      expect(host.menus, hasLength(3));
    },
  );

  test('the native menu is set only when what it shows changes (ruling I3): '
      'a tab title or a running command does not rebuild it', () async {
    final host = _FakeTrayHost();
    final presenter = TrayPresenter(
      host: host,
      l10n: lookupAppLocalizations(const Locale('en')),
      isWindows: false,
      onAction: (_) async {},
    );
    SessionSummary session({String title = '', bool running = false}) =>
        SessionSummary(
          id: 7,
          index: 1,
          shell: 'zsh',
          createdAt: DateTime(2026, 10, 6),
          attachedMobileId: null,
          title: title,
          runningCommand: running,
        );
    await presenter.render(connected.copyWith(sessions: [session()]));
    for (var i = 0; i < 20; i++) {
      await presenter.render(
        connected.copyWith(
          sessions: [session(title: 'vim $i', running: i.isEven)],
        ),
      );
    }
    expect(host.menus, hasLength(1));
    await presenter.render(
      connected.copyWith(sessions: [session(), session()]),
    );
    expect(host.menus, hasLength(2));
  });

  test('a menu that failed to set is set again on the next render', () async {
    final host = _FailingMenuHost();
    final presenter = TrayPresenter(
      host: host,
      l10n: lookupAppLocalizations(const Locale('en')),
      isWindows: false,
      onAction: (_) async {},
    );
    await expectLater(presenter.render(connected), throwsStateError);
    await presenter.render(connected);
    expect(host.menus, hasLength(1));
  });

  test('an icon that failed to set is set again on the next render', () async {
    final host = _FakeTrayHost()..iconFailures = 1;
    final presenter = TrayPresenter(
      host: host,
      l10n: lookupAppLocalizations(const Locale('en')),
      isWindows: false,
      onAction: (_) async {},
    );
    await expectLater(presenter.render(connected), throwsStateError);
    expect(host.icons, isEmpty);

    await presenter.render(connected);
    expect(host.icons, [('assets/tray/tray_normal.png', true)]);
    expect(host.menus, hasLength(1));
  });

  test('clicks are translated to actions; unknown keys are ignored', () async {
    final actions = <TrayAction>[];
    final presenter = TrayPresenter(
      host: _FakeTrayHost(),
      l10n: lookupAppLocalizations(const Locale('en')),
      isWindows: true,
      onAction: (a) async => actions.add(a),
    );
    presenter.onMenuItemClick(MenuItem(key: TrayKeys.pair));
    presenter.onMenuItemClick(MenuItem(key: TrayKeys.status));
    await Future<void>.delayed(Duration.zero);
    expect(actions.single, isA<PairPhone>());
  });

  test('a click on Reconnect is routed like any other action', () async {
    final actions = <TrayAction>[];
    final presenter = TrayPresenter(
      host: _FakeTrayHost(),
      l10n: lookupAppLocalizations(const Locale('en')),
      isWindows: false,
      onAction: (a) async => actions.add(a),
    );
    presenter.onMenuItemClick(MenuItem(key: TrayKeys.reconnect));
    await Future<void>.delayed(Duration.zero);
    expect(actions.single, isA<Reconnect>());
  });

  MenuItem clearItem(Menu menu) => menu.items!
      .firstWhere((i) => i.key == TrayKeys.terminal)
      .submenu!
      .items!
      .firstWhere((i) => i.key == TrayKeys.clearSavedScrollback);

  test(
    'a change of the local state alone rebuilds the menu (A5a D13)',
    () async {
      final host = _FakeTrayHost();
      final presenter = TrayPresenter(
        host: host,
        l10n: lookupAppLocalizations(const Locale('en')),
        isWindows: false,
        onAction: (_) async {},
      );
      await presenter.render(connected);
      expect(clearItem(host.menus.last).disabled, isTrue);
      await presenter.renderLocal(
        const TrayLocalState(hasSavedScrollback: true),
      );
      expect(host.menus, hasLength(2));
      expect(clearItem(host.menus.last).disabled, isFalse);
      // The next agent change keeps the local state.
      await presenter.render(connected.copyWith(email: 'c@d.co'));
      expect(clearItem(host.menus.last).disabled, isFalse);
    },
  );

  test(
    'a burst keeps the latest state and the latest local state together',
    () async {
      final gate = Completer<void>();
      final host = _GatedHost(gate.future);
      final presenter = TrayPresenter(
        host: host,
        l10n: lookupAppLocalizations(const Locale('en')),
        isWindows: false,
        onAction: (_) async {},
      );
      final first = presenter.render(connected);
      unawaited(presenter.render(connected.copyWith(email: 'c@d.co')));
      unawaited(
        presenter.renderLocal(const TrayLocalState(hasSavedScrollback: true)),
      );
      gate.complete();
      await first;
      expect(host.menus, hasLength(2));
      final status = host.menus.last.items!
          .firstWhere((i) => i.key == TrayKeys.status)
          .label!;
      expect(status, contains('c@d.co'));
      expect(clearItem(host.menus.last).disabled, isFalse);
    },
  );

  test('renderLocal before any agent state draws nothing', () async {
    final host = _FakeTrayHost();
    final presenter = TrayPresenter(
      host: host,
      l10n: lookupAppLocalizations(const Locale('en')),
      isWindows: false,
      onAction: (_) async {},
    );
    await presenter.renderLocal(const TrayLocalState(hasSavedScrollback: true));
    expect(host.menus, isEmpty);
  });
}

final class _GatedHost extends _FakeTrayHost {
  _GatedHost(this.gate);
  final Future<void> gate;
  bool _waited = false;

  @override
  Future<void> setMenu(Menu menu) async {
    if (!_waited) {
      _waited = true;
      await gate;
    }
    await super.setMenu(menu);
  }
}
