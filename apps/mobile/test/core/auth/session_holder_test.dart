import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;

import '../../support/fake_relay_http.dart';
import '../../support/fakes.dart';

PackageInfo packageInfo(String version) =>
    PackageInfo(appName: 'ShellX', packageName: 'pro.shellx.mobile', version: version, buildNumber: '1');

/// Secure storage whose deletes fail, as a locked or broken Keychain/Keystore can.
class _FailingDeletes extends AuthStorageImpl {
  _FailingDeletes(super.store);

  @override
  Future<void> deleteToken() => Future.error(PlatformException(code: 'keychain'));

  @override
  Future<void> forgetAccount(String userId) => Future.error(PlatformException(code: 'keychain'));
}

void main() {
  late FakeRelayHttp relay;
  late InMemoryKeyValueStore store;
  late ShellxApi api;
  late FakeBackendFactory backends;
  late AuthEventNotifier notifier;
  late List<AuthEvent> events;

  SessionHolderImpl holder({AuthStorage? storage}) => SessionHolderImpl(
    api: api,
    storage: storage ?? AuthStorageImpl(store),
    store: store,
    device: const DeviceDescription(name: 'iPhone 15', platform: DevicePlatform.ios),
    packageInfo: packageInfo('1.0.0'),
    backends: backends,
    events: notifier,
  );

  setUp(() {
    relay = FakeRelayHttp();
    store = InMemoryKeyValueStore();
    api = ShellxApi(baseUri: Uri.parse('http://127.0.0.1:8787'), httpClient: relay.client);
    backends = FakeBackendFactory();
    notifier = AuthEventNotifier();
    events = [];
    notifier.addListener('test', events.add);
  });

  Future<void> saveSession() => AuthStorageImpl(store).save(
    const AccountSession(userId: testUserId, deviceId: testDeviceId, token: 'saved', email: 'a@b.co'),
  );

  Iterable<http.Request> logoutRequests() => relay.requests.where((r) => r.url.path == '/v1/auth/logout');

  test('restores a saved session and starts its backend, without an event', () async {
    await saveSession();
    final session = holder();
    await session.restore();
    expect(session.isAuthenticated.value, isTrue);
    expect(session.requireBackend, same(backends.backends.single));
    expect(api.token, 'saved');
    expect(backends.sessions.single.userId, testUserId);
    expect(events, isEmpty);
  });

  test('nothing saved: stays signed out and remembers no email', () async {
    final session = holder();
    await session.restore();
    expect(session.isAuthenticated.value, isFalse);
    expect(session.backend.value, isNull);
    expect(() => session.requireBackend, throwsStateError);
  });

  test('login normalises the email and sends the mobile device info', () async {
    final session = holder();
    await session.restore();
    await session.login('  Me@Example.COM ', 'correct horse');

    final body = jsonDecode(relay.lastTo('/v1/auth/login').body) as Map<String, Object?>;
    expect(body['email'], 'me@example.com');
    final device = body['device'] as Map<String, Object?>;
    expect(device['kind'], 'mobile');
    expect(device['platform'], 'ios');
    expect(device['name'], 'iPhone 15');
    final identity = await DeviceIdentity.loadOrCreate(store);
    expect(device['public_key'], base64UrlNoPad(identity.publicKey));
    expect(backends.identities.single.publicKey, identity.publicKey);

    expect(session.isAuthenticated.value, isTrue);
    expect(events.single, isA<SignedInEvent>());
    final saved = await AuthStorageImpl(store).load();
    expect(saved?.token, 'token-1');
    expect(saved?.email, 'me@example.com');
  });

  test('register uses /v1/auth/register', () async {
    final session = holder();
    await session.register('new@example.com', 'long enough');
    expect(relay.requests.map((r) => r.url.path), contains('/v1/auth/register'));
    expect(session.isAuthenticated.value, isTrue);
  });

  test('a rejected login throws ApiException and stays signed out', () async {
    relay.loginError = {'status': 401, 'code': 'invalid_credentials', 'message': 'no'};
    final session = holder();
    await expectLater(
      session.login('a@b.co', 'wrong password'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'invalid_credentials')),
    );
    expect(session.isAuthenticated.value, isFalse);
    expect(await AuthStorageImpl(store).load(), isNull);
    expect(events, isEmpty);
  });

  test('logout deletes only the token (spec §5.2)', () async {
    await saveSession();
    await store.write(DeviceIdentity.storageKey, base64UrlNoPad((await NoiseKeyPair.generate()).privateKey));
    final key = await store.read(DeviceIdentity.storageKey);
    await store.write('pinned_machines_$testUserId', '[]');
    final session = holder();
    await session.restore();

    await session.logout();

    expect(relay.lastTo('/v1/auth/logout').headers['authorization'], 'Bearer saved');
    expect(backends.backends.single.disposed, isTrue);
    expect(await store.read(AuthStorage.tokenKey), isNull);
    expect(await store.read(DeviceIdentity.storageKey), key);
    expect(await store.read('pinned_machines_$testUserId'), '[]');
    expect(await store.read(AuthStorage.userIdKey), testUserId);
    expect(api.token, isNull);
    expect(session.isAuthenticated.value, isFalse);
    expect(session.lastEmail, 'a@b.co');
    expect(session.signOutReason.value, SignOutReason.loggedOut);
    expect((events.single as SignedOutEvent).reason, SignOutReason.loggedOut);
  });

  test('logout still signs out locally when the relay is unreachable', () async {
    await saveSession();
    relay.logoutOffline = true;
    final session = holder();
    await session.restore();
    await session.logout();
    expect(session.isAuthenticated.value, isFalse);
    expect(await store.read(AuthStorage.tokenKey), isNull);
  });

  test('sign-out is fail-closed: the saved token is gone while the logout request hangs', () {
    fakeAsync((async) {
      unawaited(saveSession());
      async.flushMicrotasks();
      relay.logoutGate = Completer<void>(); // The relay never answers.
      final session = holder();
      unawaited(session.restore());
      async.flushMicrotasks();
      expect(session.isAuthenticated.value, isTrue);

      var done = false;
      unawaited(session.logout().then((_) => done = true));
      async.flushMicrotasks();

      // Killed now, the app comes back signed out.
      expect(logoutRequests(), hasLength(1));
      expect(store.values, isNot(contains(AuthStorage.tokenKey)));
      expect(backends.backends.single.disposed, isTrue);
      expect(done, isFalse);

      // The request is bounded: the sign-out ends without an answer.
      async.elapse(const Duration(seconds: 10));
      expect(done, isTrue);
      expect(session.isAuthenticated.value, isFalse);
      expect(api.token, isNull);
      expect((events.single as SignedOutEvent).reason, SignOutReason.loggedOut);
    });
  });

  test('a keychain error while deleting the token still signs out', () async {
    await saveSession();
    final session = holder(storage: _FailingDeletes(store));
    await session.restore();

    await session.logout();

    expect(backends.backends.single.disposed, isTrue);
    expect(logoutRequests(), hasLength(1));
    expect(api.token, isNull);
    expect(session.isAuthenticated.value, isFalse);
    expect((events.single as SignedOutEvent).reason, SignOutReason.loggedOut);
  });

  test('a second logout, or a 4002, during a sign-out joins it: one sign-out, one dispose', () async {
    await saveSession();
    relay.logoutGate = Completer<void>();
    final session = holder();
    await session.restore();
    final backend = backends.backends.single;

    final first = session.logout();
    await pumpEventQueue();
    final second = session.logout();
    backend.emitRelay(RelayConnectionState.revoked);
    expect(second, same(first));

    relay.logoutGate!.complete();
    await first;
    await pumpEventQueue();

    expect(backend.disposeCalls, 1);
    expect(logoutRequests(), hasLength(1));
    expect(events, hasLength(1));
    expect((events.single as SignedOutEvent).reason, SignOutReason.loggedOut);
  });

  test('logout during a 4002 sign-out joins it and sends no logout request', () async {
    await saveSession();
    final session = holder();
    await session.restore();
    final backend = backends.backends.single;

    backend.emitRelay(RelayConnectionState.revoked);
    await session.logout();
    await pumpEventQueue();

    expect(backend.disposeCalls, 1);
    expect(logoutRequests(), isEmpty);
    expect(session.signOutReason.value, SignOutReason.revoked);
    expect(events.whereType<SignedOutEvent>().map((e) => e.reason), [SignOutReason.revoked]);
  });

  test('close code 4002 (revoked) deletes the token and signs out (spec §12)', () async {
    await saveSession();
    final session = holder();
    await session.restore();

    backends.backends.single.emitRelay(RelayConnectionState.revoked);
    await pumpEventQueue();

    expect(session.isAuthenticated.value, isFalse);
    expect(session.signOutReason.value, SignOutReason.revoked);
    expect(await store.read(AuthStorage.tokenKey), isNull);
    expect(relay.requests.where((r) => r.url.path == '/v1/auth/logout'), isEmpty);
    expect((events.single as SignedOutEvent).reason, SignOutReason.revoked);
  });

  test('reconnectReplaced restarts the same backend after 4001', () async {
    await saveSession();
    final session = holder();
    await session.restore();
    final backend = backends.backends.single;
    backend.emitRelay(RelayConnectionState.replaced);

    await session.reconnectReplaced();

    expect(backends.backends, hasLength(1));
    expect(backend.suspendCalls, 1);
    expect(backend.resumeCalls, 1);
    expect(backend.relayState, RelayConnectionState.connected);
  });

  test('background suspends the relay, foreground resumes it (spec §9.4, §12)', () async {
    await saveSession();
    final session = holder();
    await session.restore();
    final backend = backends.backends.single;

    session.onBackground();
    session.onBackground();
    expect(backend.suspendCalls, 1);

    session.onForeground();
    session.onForeground();
    expect(backend.resumeCalls, 1);
    expect(backend.reconnectCalls, 0);
  });

  test('a replaced (4001) connection is never resumed automatically', () async {
    await saveSession();
    final session = holder();
    await session.restore();
    final backend = backends.backends.single;
    backend.emitRelay(RelayConnectionState.replaced);

    session.onBackground();
    session.onForeground();

    expect(backend.suspendCalls, 0);
    expect(backend.resumeCalls, 0);
    expect(backend.reconnectCalls, 0);
  });

  test('foreground without a background skips the backoff of a disconnected relay', () async {
    await saveSession();
    final session = holder();
    await session.restore();
    final backend = backends.backends.single;

    backend.relayStateValue = RelayConnectionState.disconnected;
    session.onForeground();
    backend.relayStateValue = RelayConnectionState.connected;
    session.onForeground();

    expect(backend.reconnectCalls, 1);
  });

  group('deleteAccount', () {
    test('wrong password throws invalid_credentials and keeps the session', () async {
      await saveSession();
      final session = holder();
      await session.restore();

      await expectLater(
        session.deleteAccount('nope'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'invalid_credentials')),
      );
      expect(session.isAuthenticated.value, isTrue);
      expect(backends.backends.single.disposed, isFalse);
      expect(await store.read(AuthStorage.tokenKey), 'saved');
    });

    test("success forgets token, device key and this user's pins only", () async {
      await saveSession();
      await store.write(DeviceIdentity.storageKey, 'private-key');
      await store.write('pinned_machines_$testUserId', '[]');
      await store.write('pinned_machines_other-user', '[]');
      final session = holder();
      await session.restore();

      await session.deleteAccount('correct horse');

      final request = relay.lastTo('/v1/account');
      expect(request.method, 'DELETE');
      expect(request.headers['authorization'], 'Bearer saved');
      expect(backends.backends.single.disposed, isTrue);
      for (final key in [
        AuthStorage.tokenKey,
        AuthStorage.userIdKey,
        AuthStorage.deviceIdKey,
        AuthStorage.emailKey,
        DeviceIdentity.storageKey,
        'pinned_machines_$testUserId',
      ]) {
        expect(await store.read(key), isNull, reason: key);
      }
      expect(await store.read('pinned_machines_other-user'), '[]');
      expect(api.token, isNull);
      expect(session.isAuthenticated.value, isFalse);
      expect(session.signOutReason.value, SignOutReason.accountDeleted);
      expect((events.single as SignedOutEvent).reason, SignOutReason.accountDeleted);
    });

    test('the 4002 close that accompanies the deletion is not treated as a revocation', () async {
      await saveSession();
      final session = holder();
      await session.restore();
      final backend = backends.backends.single;

      final deletion = session.deleteAccount('correct horse');
      backend.emitRelay(RelayConnectionState.revoked);
      await deletion;
      await pumpEventQueue();

      expect(session.signOutReason.value, SignOutReason.accountDeleted);
      expect(events.whereType<SignedOutEvent>().map((e) => e.reason), [SignOutReason.accountDeleted]);
    });

    test('a lost response after the relay already revoked signs out as revoked and rethrows', () async {
      await saveSession();
      final session = holder();
      await session.restore();
      final backend = backends.backends.single;
      relay.accountResponseLost = true;
      relay.onAccountDeleted = () => backend.emitRelay(RelayConnectionState.revoked);

      await expectLater(
        session.deleteAccount('correct horse'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'network')),
      );

      expect(backend.disposeCalls, 1);
      expect(await store.read(AuthStorage.tokenKey), isNull);
      expect(logoutRequests(), isEmpty);
      expect(api.token, isNull);
      expect(session.isAuthenticated.value, isFalse);
      expect(session.signOutReason.value, SignOutReason.revoked);
      expect(events.whereType<SignedOutEvent>().map((e) => e.reason), [SignOutReason.revoked]);
    });

    test('a keychain error while forgetting the account still signs out', () async {
      await saveSession();
      final session = holder(storage: _FailingDeletes(store));
      await session.restore();

      await session.deleteAccount('correct horse');

      expect(backends.backends.single.disposed, isTrue);
      expect(api.token, isNull);
      expect(session.isAuthenticated.value, isFalse);
      expect(session.lastEmail, isNull);
      expect((events.single as SignedOutEvent).reason, SignOutReason.accountDeleted);
    });
  });
}
