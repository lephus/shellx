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
  for (final signedIn in [false, true]) {
    test('Terminal submenu right before Thông báo (signedIn: $signedIn)', () {
      final state = signedIn
          ? const AgentViewState(phase: AuthPhase.signedIn, email: 'a@b.c')
          : const AgentViewState(phase: AuthPhase.signedOut);
      final menu = buildTrayMenu(
        state,
        vi,
        TrayMenuIds(),
        local: const TrayLocalState(
          restoreScrollback: true,
          hasSavedScrollback: false,
        ),
      );
      final items = menu.items!;
      final terminal = items.indexWhere((i) => i.key == TrayKeys.terminal);
      final notifications = items.indexWhere(
        (i) => i.key == TrayKeys.notifications,
      );
      expect(terminal, greaterThanOrEqualTo(0));
      expect(notifications, terminal + 1);
      expect(items[terminal].label, 'Terminal');
      final check = find(items, TrayKeys.restoreScrollback)!;
      expect(check.label, 'Lưu nội dung terminal khi thoát');
      expect(check.checked, isTrue);
      final clear = find(items, TrayKeys.clearSavedScrollback)!;
      expect(clear.label, 'Xóa nội dung đã lưu');
      expect(clear.disabled, isTrue); // nothing saved yet
    });
  }

  test('switch off and something saved: unchecked, clear enabled', () {
    final menu = buildTrayMenu(
      const AgentViewState(phase: AuthPhase.signedOut),
      lookupAppLocalizations(const Locale('en')),
      TrayMenuIds(),
      local: const TrayLocalState(
        restoreScrollback: false,
        hasSavedScrollback: true,
      ),
    );
    final items = menu.items!;
    final check = find(items, TrayKeys.restoreScrollback)!;
    expect(check.label, 'Save terminal contents on quit');
    expect(check.checked, isFalse);
    final clear = find(items, TrayKeys.clearSavedScrollback)!;
    expect(clear.label, 'Clear saved contents');
    expect(clear.disabled, isFalse);
  });

  test('the local state defaults to on, nothing saved', () {
    const local = TrayLocalState();
    expect(local.restoreScrollback, isTrue);
    expect(local.hasSavedScrollback, isFalse);
    expect(
      const TrayLocalState(hasSavedScrollback: true),
      const TrayLocalState(hasSavedScrollback: true),
    );
  });

  test('keys map to actions', () {
    expect(
      trayActionForKey(TrayKeys.restoreScrollback),
      isA<ToggleRestoreScrollback>(),
    );
    expect(
      trayActionForKey(TrayKeys.clearSavedScrollback),
      isA<ClearSavedScrollback>(),
    );
  });

  test('strings (vi/en) match UI-A5 §9', () {
    final en = lookupAppLocalizations(const Locale('en'));
    expect(
      vi.terminalRestoredDivider('14:32'),
      '— Phiên được khôi phục · 14:32 —',
    );
    expect(en.terminalRestoredDivider('14:32'), '— Session restored · 14:32 —');
    expect(vi.restoreTimeYesterday('14:32'), 'hôm qua 14:32');
    expect(
      en.restoreAbnormalStrip(1, '14:31'),
      "ShellX didn't close normally last time. Reopened 1 tab; contents as "
      'of 14:31.',
    );
    expect(
      vi.restoreAbnormalNoText(5),
      'ShellX đã đóng bất thường lần trước. Đã mở lại 5 tab.',
    );
    expect(en.restorePanesFailed(2), "Couldn't reopen 2 panes");
    expect(en.trayTerminal, 'Terminal');
    expect(vi.restoreStripCloseLabel, 'Đóng thông báo khôi phục');
  });
}
