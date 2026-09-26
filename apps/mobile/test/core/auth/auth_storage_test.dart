import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;

void main() {
  const session = AccountSession(userId: 'user-1', deviceId: 'device-1', token: 'token-1', email: 'me@example.com');
  late InMemoryKeyValueStore store;
  late AuthStorage storage;

  setUp(() {
    store = InMemoryKeyValueStore();
    storage = AuthStorageImpl(store);
  });

  test('saves and loads the session under the plan keys', () async {
    expect(await storage.load(), isNull);
    await storage.save(session);
    expect(await storage.load(), session);
    expect(store.values, {
      'auth_token': 'token-1',
      'auth_user_id': 'user-1',
      'auth_device_id': 'device-1',
      'auth_email': 'me@example.com',
    });
  });

  test('deleteToken signs out but keeps ids, email, device key and pins (spec §5.2)', () async {
    await storage.save(session);
    await store.write(DeviceIdentity.storageKey, 'private-key');
    await store.write('pinned_machines_user-1', '[]');

    await storage.deleteToken();

    expect(await storage.load(), isNull);
    expect(await storage.lastEmail(), 'me@example.com');
    expect(
      store.values.keys,
      unorderedEquals(['auth_user_id', 'auth_device_id', 'auth_email', 'device_private_key', 'pinned_machines_user-1']),
    );
  });

  test("forgetAccount removes the session, the device key and only this user's pins and pending unpairs", () async {
    await storage.save(session);
    await store.write(DeviceIdentity.storageKey, 'private-key');
    await store.write('pinned_machines_user-1', '[]');
    await store.write('pinned_machines_user-2', '[]');
    await store.write('pending_unpairs_user-1', '[]');
    await store.write('pending_unpairs_user-2', '[]');

    await storage.forgetAccount('user-1');

    expect(store.values, {'pinned_machines_user-2': '[]', 'pending_unpairs_user-2': '[]'});
  });

  test('the session never prints its token', () {
    expect(session.toString(), isNot(contains('token-1')));
  });
}
