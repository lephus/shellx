import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_presenter.dart';
import 'package:tray_manager/tray_manager.dart';

final class _FakeTrayHost implements TrayHost {
  final List<(String, bool)> icons = [];
  final List<Menu> menus = [];
  @override
  Future<void> setIcon(String asset, {required bool isTemplate}) async =>
      icons.add((asset, isTemplate));
  @override
  Future<void> setToolTip(String text) async {}
  @override
  Future<void> setMenu(Menu menu) async => menus.add(menu);
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
      expect(host.menus, hasLength(3));
    },
  );

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
}
