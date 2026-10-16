import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/agent/tour_state.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';

void main() {
  test('a fresh install shows the tour, not "what is new"', () {
    expect(
      decideFirstRun(
        tourDone: false,
        lastSeen: null,
        current: '1.2.0',
        hasNotesFor: true,
      ),
      FirstRunStep.tour,
    );
  });

  test('an upgrade with notes shows "what is new" once; without notes '
      'nothing', () {
    expect(
      decideFirstRun(
        tourDone: true,
        lastSeen: '1.1.0',
        current: '1.2.0',
        hasNotesFor: true,
      ),
      FirstRunStep.whatsNew,
    );
    expect(
      decideFirstRun(
        tourDone: true,
        lastSeen: '1.1.0',
        current: '1.2.0',
        hasNotesFor: false,
      ),
      FirstRunStep.none,
    );
    expect(
      decideFirstRun(
        tourDone: true,
        lastSeen: '1.2.0',
        current: '1.2.0',
        hasNotesFor: true,
      ),
      FirstRunStep.none,
    );
  });

  test('the build number after + does not make an upgrade', () {
    expect(
      decideFirstRun(
        tourDone: true,
        lastSeen: '1.2.0+3',
        current: '1.2.0+4',
        hasNotesFor: true,
      ),
      FirstRunStep.none,
    );
  });

  test('an existing user from before A11 is treated as an upgrade, not a '
      'first run', () {
    expect(
      decideFirstRun(
        tourDone: false,
        lastSeen: null,
        current: '1.2.0',
        hasNotesFor: true,
        existingUser: true,
      ),
      FirstRunStep.whatsNew,
    );
    expect(
      decideFirstRun(
        tourDone: false,
        lastSeen: null,
        current: '1.2.0',
        hasNotesFor: false,
        existingUser: true,
      ),
      FirstRunStep.none,
    );
  });

  test('a user who finished the tour in this release sees nothing', () {
    expect(
      decideFirstRun(
        tourDone: true,
        lastSeen: null,
        current: '1.2.0',
        hasNotesFor: true,
      ),
      FirstRunStep.none,
    );
  });

  test('TourState stores the two UI-owned keys', () async {
    final store = InMemorySettingsStore();
    final s = TourState(store);
    expect(s.tourDone, isFalse);
    expect(s.lastSeenVersion, isNull);
    await s.markTourDone();
    await s.setLastSeenVersion('1.2.0+5');
    expect(TourState(store).tourDone, isTrue);
    expect(TourState(store).lastSeenVersion, '1.2.0');
    expect(store.values[SettingKeys.tourDone], isTrue);
    expect(UiSettingKeys.all, contains(SettingKeys.tourDone));
    expect(UiSettingKeys.all, contains(SettingKeys.lastSeenVersion));
  });

  test('existing user: any UI-owned trace of a previous run', () {
    expect(hasUsedAppBefore(InMemorySettingsStore()), isFalse);
    final s = InMemorySettingsStore()..ints[SettingKeys.windowWidth] = 900;
    expect(hasUsedAppBefore(s), isTrue);
    final w = InMemorySettingsStore()
      ..strings[SettingKeys.terminalWorkspaces] = ['{}'];
    expect(hasUsedAppBefore(w), isTrue);
  });

  test('a store failure never throws out of the helpers', () async {
    final store = InMemorySettingsStore()..fail = true;
    final logged = <String>[];
    final old = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logged.add(m ?? '');
    try {
      await TourState(store).markTourDone();
      await TourState(store).setLastSeenVersion('1.0.0');
    } finally {
      debugPrint = old;
    }
    expect(logged, isNotEmpty);
    expect(logged.join(), isNot(contains('1.0.0')));
  });
}
