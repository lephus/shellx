import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/app/splash_page.dart';

void main() {
  test('prepareLaunch throwing → splash still navigates: guardLaunch swallows the error', () async {
    // Must complete instead of propagating.
    await guardLaunch(() async => throw Exception('boom'));
  });

  test('guardLaunch still runs the action through to completion when it succeeds', () async {
    var ran = false;
    await guardLaunch(() async => ran = true);
    expect(ran, isTrue);
  });
}
