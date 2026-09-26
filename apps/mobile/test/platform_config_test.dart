import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// `flutter test` runs with the package root (apps/mobile) as the working directory.
String readFile(String path) => File(path).readAsStringSync();

void main() {
  group('iOS', () {
    test('deployment target is iOS 15.0 everywhere', () {
      final project = readFile('ios/Runner.xcodeproj/project.pbxproj');
      expect(project, contains('IPHONEOS_DEPLOYMENT_TARGET = 15.0;'));
      expect(RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = (?!15\.0;)').hasMatch(project), isFalse);
      expect(readFile('ios/Podfile'), contains("platform :ios, '15.0'"));
    });

    test('bundle identifier is com.shellx.prod', () {
      final project = readFile('ios/Runner.xcodeproj/project.pbxproj');
      expect(project, contains('PRODUCT_BUNDLE_IDENTIFIER = com.shellx.prod;'));
      expect(project, contains('PRODUCT_BUNDLE_IDENTIFIER = com.shellx.prod.RunnerTests;'));
      expect(RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = (?!com\.shellx\.prod[.;])').hasMatch(project), isFalse);
      expect(project, isNot(contains('com.example')));
      expect(project, isNot(contains('pro.shellx.mobile')));
    });

    test('Info.plist declares camera, Face ID, display name and both UI languages', () {
      final plist = readFile('ios/Runner/Info.plist');
      expect(plist, contains('<key>CFBundleDisplayName</key>\n\t<string>ShellX</string>'));
      expect(plist, contains('<key>NSCameraUsageDescription</key>'));
      expect(plist, contains('<key>NSFaceIDUsageDescription</key>'));
      expect(plist, contains('<key>CFBundleLocalizations</key>'));
      expect(plist, contains('<string>vi</string>'));
    });
  });

  group('Android', () {
    test('application id and namespace com.shellx.prod, minSdk 26 (Android 8.0)', () {
      final gradle = readFile('android/app/build.gradle.kts');
      expect(gradle, contains('applicationId = "com.shellx.prod"'));
      expect(gradle, contains('namespace = "com.shellx.prod"'));
      expect(gradle, contains('minSdk = 26'));
    });

    test('manifest has the permissions and disables backup', () {
      final manifest = readFile('android/app/src/main/AndroidManifest.xml');
      for (final permission in ['INTERNET', 'CAMERA', 'USE_BIOMETRIC']) {
        expect(manifest, contains('android.permission.$permission'));
      }
      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('android:label="ShellX"'));
    });

    test('MainActivity (package com.shellx.prod) is a FlutterFragmentActivity with AppCompat themes', () {
      final activity = readFile('android/app/src/main/kotlin/com/shellx/prod/MainActivity.kt');
      expect(activity, contains('package com.shellx.prod\n'));
      expect(activity, contains('class MainActivity : FlutterFragmentActivity()'));
      expect(Directory('android/app/src/main/kotlin/com/example').existsSync(), isFalse);
      expect(Directory('android/app/src/main/kotlin/pro').existsSync(), isFalse);
      expect(readFile('android/app/src/main/res/values/styles.xml'), contains('Theme.AppCompat'));
      expect(readFile('android/app/src/main/res/values-night/styles.xml'), contains('Theme.AppCompat'));
    });
  });

  test('the base package name is gone from sources and platform files', () {
    const baseName =
        'yalla'
        'bb';
    final roots = ['lib', 'test', 'android', 'ios'].map(Directory.new);
    final offenders = [
      for (final root in roots)
        for (final file in root.listSync(recursive: true).whereType<File>())
          if (RegExp(r'\.(dart|arb|kts|kt|xml|plist|pbxproj|xcconfig|swift|gradle)$').hasMatch(file.path) &&
              file.readAsStringSync().toLowerCase().contains(baseName))
            file.path,
    ];
    expect(offenders, isEmpty);
    expect(readFile('pubspec.yaml'), contains('name: shellx_mobile'));
  });

  test('no dio / refresh-token stack and no native crypto plugin', () {
    final pubspec = readFile('pubspec.yaml');
    for (final package in ['dio', 'awesome_dio_interceptor', 'cryptography_flutter', 'flutter_riverpod']) {
      expect(pubspec, isNot(contains('$package:')), reason: package);
    }
    expect(pubspec, contains('resolution: workspace'));
  });

  test('JetBrains Mono and both OFL licenses are bundled', () {
    for (final style in ['Regular', 'Bold', 'Italic', 'BoldItalic']) {
      expect(File('assets/fonts/JetBrainsMono-$style.ttf').lengthSync(), greaterThan(100000));
    }
    expect(readFile('assets/licenses/JetBrainsMono-OFL.txt'), contains('SIL OPEN FONT LICENSE'));
    expect(readFile('assets/licenses/Raleway-OFL.txt'), contains('SIL Open Font License'));
  });
}
