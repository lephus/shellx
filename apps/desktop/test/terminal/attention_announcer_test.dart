import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/terminal/attention_announcer.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';

void main() {
  test('focused window, other tab: announced at most once per 3 s per tab '
      '(D24)', () {
    final said = <String>[];
    var now = DateTime(2026, 10, 7, 9);
    final a = AttentionAnnouncer(
      announce: said.add,
      l10n: lookupAppLocalizations(const Locale('en')),
      now: () => now,
    );
    AttentionArrival arrival(String text) => AttentionArrival(
      tabId: 2,
      kind: AttentionKind.message,
      text: text,
      at: now,
    );
    a.arrived(
      arrival('one'),
      tab: 'api',
      windowFocused: true,
      tabSelected: false,
    );
    a.arrived(
      arrival('two'),
      tab: 'api',
      windowFocused: true,
      tabSelected: false,
    );
    a.arrived(
      arrival('x'),
      tab: 'api',
      windowFocused: false,
      tabSelected: false,
    );
    now = now.add(const Duration(seconds: 3));
    a.arrived(
      arrival('three'),
      tab: 'api',
      windowFocused: true,
      tabSelected: false,
    );
    expect(said, [
      'New notification from api: one',
      'New notification from api: three',
    ]);
  });
}
