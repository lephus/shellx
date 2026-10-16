import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/secure_key_value_store.dart';

/// V2-5a Task 2: the Keychain service comes from the running bundle id, so
/// an isolated test build never touches the released app's items.
void main() {
  Map<String, String> macOptions(String bundleId) =>
      SecureKeyValueStore.storageFor(bundleId).mOptions.toMap();

  test('the released app keeps pro.shellx.desktop (its users\' items)', () {
    expect(kProductionBundleId, 'pro.shellx.desktop');
    expect(keychainServiceFor('pro.shellx.desktop'), 'pro.shellx.desktop');
    final options = macOptions('pro.shellx.desktop');
    expect(options['accountName'], 'pro.shellx.desktop');
    expect(options['usesDataProtectionKeychain'], 'false');
  });

  test('any other bundle id gets its own service, equal to the id', () {
    for (final id in [
      'pro.shellx.desktop.itest',
      'pro.shellx.desktop.smoketest',
      'pro.shellx.desktop2',
      'com.example.other',
    ]) {
      expect(keychainServiceFor(id), id);
      expect(macOptions(id)['accountName'], id);
      expect(macOptions(id)['usesDataProtectionKeychain'], 'false');
    }
    expect(keychainServiceFor(''), 'pro.shellx.desktop.unknown');
    expect(macOptions('')['accountName'], isNot('pro.shellx.desktop'));
  });

  test('both processes pass the running bundle id, nothing else', () {
    final main = File('lib/main.dart').readAsStringSync();
    final daemon = File('lib/daemon_main.dart').readAsStringSync();
    final passed = RegExp(r'bundleId: ([\w.]+),');
    expect(passed.allMatches(main).map((m) => m[1]), [
      'info.packageName',
      'info.packageName',
    ]);
    expect(passed.allMatches(daemon).map((m) => m[1]), [
      'info.packageName',
      'bundleId',
    ]);
    // The store is the only place that names Keychain options.
    final lib = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('MacOsOptions('))
        .map((f) => f.path.replaceAll(r'\', '/'));
    expect(lib, ['lib/src/platform/secure_key_value_store.dart']);
  });
}
