import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/agent/update_check.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_menu.dart';
import 'package:tray_manager/tray_manager.dart';

import '../support/fakes.dart';

final vi = lookupAppLocalizations(const Locale('vi'));

AgentViewState _signedIn({
  RelayConnectionState relay = RelayConnectionState.connected,
  int channels = 0,
  bool remoteAccess = true,
  List<SessionSummary> sessions = const [],
  List<TrustedDevice> trusted = const [],
  UpdateNotice? update,
}) => AgentViewState(
  phase: AuthPhase.signedIn,
  email: 'user@email.com',
  relay: relay,
  activeChannels: channels,
  remoteAccess: remoteAccess,
  sessions: sessions,
  trusted: trusted,
  update: update,
);

List<String?> _labels(Menu menu) => [
  for (final item in menu.items!) item.type == 'separator' ? '---' : item.label,
];

void main() {
  test('signed-in menu is exactly spec §8.3, in order', () {
    final state = _signedIn(
      sessions: [
        SessionSummary(
          id: 7,
          index: 1,
          shell: 'zsh',
          createdAt: DateTime(2026),
          attachedMobileId: 'm1',
        ),
      ],
      trusted: [phone('m1', 'iPhone của Phú')],
    );
    final menu = buildTrayMenu(state, vi, TrayMenuIds());
    expect(_labels(menu), [
      '● Đã kết nối — user@email.com',
      '---',
      'Cho phép truy cập từ xa',
      'Phiên đang hoạt động (1)',
      'Ghép nối điện thoại…',
      'Thiết bị đã ghép',
      '---',
      'Giữ máy không ngủ',
      'Khởi động cùng hệ thống',
      'Đổi mật khẩu…',
      'Đăng xuất',
      'Thoát',
    ]);
    expect(menu.getMenuItem(TrayKeys.status)!.disabled, isTrue);
    expect(menu.getMenuItem(TrayKeys.remoteAccess)!.checked, isTrue);
    expect(menu.getMenuItem(TrayKeys.keepAwake)!.type, 'checkbox');

    final session = menu.getMenuItem(TrayKeys.session(7))!;
    expect(session.label, 'zsh 1 — iPhone của Phú');
    expect(session.submenu!.items!.single.key, TrayKeys.closeSession(7));
    expect(session.submenu!.items!.single.label, 'Đóng');
    expect(menu.getMenuItem(TrayKeys.closeAll)!.label, 'Đóng tất cả');

    final device = menu.getMenuItem(TrayKeys.device('m1'))!;
    expect(device.submenu!.items!.single.key, TrayKeys.revoke('m1'));
    expect(device.submenu!.items!.single.label, 'Thu hồi');
  });

  test('empty lists: sessions disabled, devices show a placeholder', () {
    final menu = buildTrayMenu(_signedIn(), vi, TrayMenuIds());
    expect(menu.getMenuItem(TrayKeys.sessions)!.disabled, isTrue);
    expect(menu.getMenuItem(TrayKeys.noDevices)!.disabled, isTrue);
  });

  test('status line follows the relay and the remote-access switch', () {
    String status(AgentViewState s) => buildTrayMenu(
      s,
      vi,
      TrayMenuIds(),
    ).getMenuItem(TrayKeys.status)!.label!;
    expect(
      status(_signedIn(relay: RelayConnectionState.disconnected)),
      '○ Mất kết nối — đang thử lại…',
    );
    expect(
      status(_signedIn(relay: RelayConnectionState.replaced)),
      '○ Một bản ShellX khác đã kết nối thay máy này',
    );
    expect(
      status(
        _signedIn(remoteAccess: false, relay: RelayConnectionState.stopped),
      ),
      '○ Đã tắt truy cập từ xa',
    );
    final off = buildTrayMenu(
      _signedIn(remoteAccess: false, relay: RelayConnectionState.stopped),
      vi,
      TrayMenuIds(),
    );
    expect(off.getMenuItem(TrayKeys.pair)!.disabled, isTrue);
  });

  test('update available adds a download item under the status line', () {
    final menu = buildTrayMenu(
      _signedIn(
        update: UpdateNotice(
          version: '1.1.0',
          url: Uri.parse('https://download.shellx.pro/x.dmg'),
          required: false,
        ),
      ),
      vi,
      TrayMenuIds(),
    );
    expect(menu.items![1].key, TrayKeys.downloadUpdate);
    expect(menu.items![1].label, 'Tải ShellX 1.1.0…');
  });

  test('signed-out menu offers sign in and quit only', () {
    final menu = buildTrayMenu(
      const AgentViewState(phase: AuthPhase.signedOut),
      vi,
      TrayMenuIds(),
    );
    expect(_labels(menu), ['○ Chưa đăng nhập', '---', 'Đăng nhập…', 'Thoát']);
  });

  test('menu item ids are stable across rebuilds', () {
    final ids = TrayMenuIds();
    final first = buildTrayMenu(_signedIn(), vi, ids);
    final second = buildTrayMenu(
      _signedIn(relay: RelayConnectionState.disconnected),
      vi,
      ids,
    );
    expect(
      second.getMenuItem(TrayKeys.quit)!.id,
      first.getMenuItem(TrayKeys.quit)!.id,
    );
    expect(
      second.getMenuItem(TrayKeys.pair)!.id,
      first.getMenuItem(TrayKeys.pair)!.id,
    );
  });

  test(
    'icon: grey unless connected, highlighted while a phone is connected',
    () {
      expect(
        trayIconFor(const AgentViewState(phase: AuthPhase.signedOut)),
        TrayIconState.offline,
      );
      expect(
        trayIconFor(_signedIn(relay: RelayConnectionState.disconnected)),
        TrayIconState.offline,
      );
      expect(
        trayIconFor(_signedIn(remoteAccess: false)),
        TrayIconState.offline,
      );
      expect(trayIconFor(_signedIn()), TrayIconState.normal);
      expect(trayIconFor(_signedIn(channels: 1)), TrayIconState.active);
      expect(
        trayIconAsset(TrayIconState.active, windows: true),
        'assets/tray/tray_active.ico',
      );
      expect(
        trayIconAsset(TrayIconState.offline, windows: false),
        'assets/tray/tray_offline.png',
      );
    },
  );

  test('menu keys map back to actions', () {
    expect(
      trayActionForKey(TrayKeys.closeSession(12)),
      isA<CloseSession>().having((a) => a.id, 'id', 12),
    );
    expect(
      trayActionForKey(TrayKeys.revoke('m-1')),
      isA<RevokeDevice>().having((a) => a.mobileId, 'mobileId', 'm-1'),
    );
    expect(trayActionForKey(TrayKeys.remoteAccess), isA<ToggleRemoteAccess>());
    expect(trayActionForKey(TrayKeys.quit), isA<Quit>());
    expect(trayActionForKey(TrayKeys.status), isNull);
    expect(trayActionForKey('session_close:abc'), isNull);
    expect(trayActionForKey(null), isNull);
  });

  group('reconnect (binding ruling, replaces the 4001 dead end)', () {
    test('replaced relay: a Reconnect item appears with the status line', () {
      final menu = buildTrayMenu(
        _signedIn(relay: RelayConnectionState.replaced),
        vi,
        TrayMenuIds(),
      );
      expect(menu.items![1].key, TrayKeys.reconnect);
      expect(menu.items![1].label, 'Kết nối lại');
    });

    test('no Reconnect item unless the relay was replaced', () {
      for (final relay in [
        RelayConnectionState.connected,
        RelayConnectionState.connecting,
        RelayConnectionState.disconnected,
        RelayConnectionState.stopped,
      ]) {
        final menu = buildTrayMenu(_signedIn(relay: relay), vi, TrayMenuIds());
        expect(menu.getMenuItem(TrayKeys.reconnect), isNull);
      }
    });

    test('the key maps to the Reconnect action', () {
      expect(trayActionForKey(TrayKeys.reconnect), isA<Reconnect>());
    });
  });
}
