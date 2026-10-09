import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_menu.dart';
import 'package:tray_manager/tray_manager.dart';

final vi = lookupAppLocalizations(const Locale('vi'));

MenuItem? find(List<MenuItem> items, String key) {
  for (final i in items) {
    if (i.key == key) return i;
    final sub = i.submenu?.items;
    if (sub != null) {
      final hit = find(sub, key);
      if (hit != null) return hit;
    }
  }
  return null;
}

void main() {
  test('tray keys map to the browser actions', () {
    expect(
      trayActionForKey(TrayKeys.browserKeepData),
      isA<ToggleBrowserKeepData>(),
    );
    expect(
      trayActionForKey(TrayKeys.browserAgentAllOrigins),
      isA<RequestBrowserAgentAllOrigins>(),
    );
    expect(
      trayActionForKey(TrayKeys.browserClearData),
      isA<ClearBrowserData>(),
    );
  });

  for (final signedIn in [false, true]) {
    test('Trình duyệt submenu before Dòng lệnh (signedIn: $signedIn)', () {
      final state = signedIn
          ? const AgentViewState(phase: AuthPhase.signedIn, email: 'a@b.c')
          : const AgentViewState(phase: AuthPhase.signedOut);
      final items = buildTrayMenu(
        state,
        vi,
        TrayMenuIds(),
        local: const TrayLocalState(browserKeepData: true),
      ).items!;
      final notifications = items.indexWhere(
        (i) => i.key == TrayKeys.notifications,
      );
      final browser = items.indexWhere((i) => i.key == TrayKeys.browser);
      final commandLine = items.indexWhere(
        (i) => i.key == TrayKeys.commandLine,
      );
      // A7 D26: "Trình duyệt" goes before "Dòng lệnh".
      expect(browser, notifications + 1);
      expect(commandLine, browser + 1);
      expect(items[browser].label, 'Trình duyệt');
      final keep = find(items, TrayKeys.browserKeepData)!;
      expect(keep.label, 'Giữ dữ liệu trình duyệt (cookie, đăng nhập)');
      expect(keep.checked, isTrue);
      final all = find(items, TrayKeys.browserAgentAllOrigins)!;
      expect(all.label, 'Cho phép agent điều khiển mọi trang');
      expect(all.checked, isFalse);
      expect(
        find(items, TrayKeys.browserClearData)!.label,
        'Xóa dữ liệu trình duyệt',
      );
    });
  }
}
