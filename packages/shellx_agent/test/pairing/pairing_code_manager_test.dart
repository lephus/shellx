import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  late DateTime now;
  late PairingCodeManager manager;

  setUp(() {
    now = DateTime.utc(2026, 9, 25, 12);
    manager = PairingCodeManager(now: () => now, random: Random(1));
  });

  test('no code is active initially', () {
    expect(manager.activeSecret, isNull);
  });

  test('create returns a 32-byte secret valid for 5 minutes', () {
    final offer = manager.create();
    expect(offer.secret, hasLength(32));
    expect(offer.expiresAt, now.add(const Duration(minutes: 5)));
    expect(manager.activeSecret, offer.secret);

    now = now.add(const Duration(minutes: 4, seconds: 59));
    expect(manager.activeSecret, offer.secret);
    now = now.add(const Duration(seconds: 1));
    expect(manager.activeSecret, isNull);
  });

  test('a new code replaces the previous one', () {
    final first = manager.create();
    final second = manager.create();
    expect(second.secret, isNot(first.secret));
    expect(manager.activeSecret, second.secret);
  });

  test('invalidate removes the code', () {
    manager.create();
    manager.invalidate();
    expect(manager.activeSecret, isNull);
  });

  test('the default random source is secure and codes differ', () {
    final real = PairingCodeManager();
    expect(real.create().secret, isNot(real.create().secret));
  });

  test(
    'returned secrets are copied; mutations do not corrupt the live code',
    () {
      final offer = manager.create();
      final originalSecretBytes = Uint8List.fromList(offer.secret);

      // Mutate the returned secret.
      offer.secret[0] = 255;
      offer.secret[1] = 254;

      // The active secret should still have the original bytes.
      final active = manager.activeSecret!;
      expect(active, originalSecretBytes);
      expect(active[0], isNot(255));
      expect(active[1], isNot(254));

      // Mutate the active secret returned.
      active[2] = 200;

      // The next call to activeSecret should return a fresh copy.
      final nextActive = manager.activeSecret!;
      expect(nextActive[2], isNot(200));
      expect(nextActive, originalSecretBytes);
    },
  );
}
