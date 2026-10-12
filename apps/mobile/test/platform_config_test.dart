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

    test('the camera and Face ID prompts are localized in Vietnamese and English, and bundled', () {
      for (final language in ['vi', 'en']) {
        final strings = readFile('ios/Runner/$language.lproj/InfoPlist.strings');
        expect(strings, contains('"NSCameraUsageDescription" = "'), reason: language);
        expect(strings, contains('"NSFaceIDUsageDescription" = "'), reason: language);
      }
      expect(readFile('ios/Runner/vi.lproj/InfoPlist.strings'), contains('ShellX dùng camera'));
      final project = readFile('ios/Runner.xcodeproj/project.pbxproj');
      expect(project, contains('path = vi.lproj/InfoPlist.strings;'));
      expect(project, contains('path = en.lproj/InfoPlist.strings;'));
      expect(project, contains('/* InfoPlist.strings in Resources */,'));
      expect(RegExp(r'knownRegions = \([^)]*\bvi,').hasMatch(project), isTrue);
    });

    test('push notifications: entitlements (aps-environment), capabilities and background mode', () {
      final entitlements = readFile('ios/Runner/Runner.entitlements');
      expect(entitlements, contains('<key>aps-environment</key>\n\t<string>development</string>'));
      final project = readFile('ios/Runner.xcodeproj/project.pbxproj');
      // The Runner target's configurations (the only ones that set entitlements), by name. Since
      // 1732434 Debug signs with RunnerDebug.entitlements (no push, so a free Apple ID can run it);
      // Profile and Release keep Runner.entitlements with aps-environment.
      final signing = <String, String>{
        for (final block in RegExp(r'isa = XCBuildConfiguration;(.*?)name = (\w+);', dotAll: true).allMatches(project))
          if (RegExp(r'CODE_SIGN_ENTITLEMENTS = ([^;]+);').firstMatch(block.group(1)!) case final entitlements?)
            block.group(2)!: entitlements.group(1)!,
      };
      expect(signing, {
        'Profile': 'Runner/Runner.entitlements',
        'Debug': 'Runner/RunnerDebug.entitlements',
        'Release': 'Runner/Runner.entitlements',
      });
      expect(readFile('ios/Runner/RunnerDebug.entitlements'), isNot(contains('aps-environment')));
      expect(project, contains('path = Runner.entitlements;'));
      expect(project, contains('com.apple.Push = {\n\t\t\t\t\t\t\t\tenabled = 1;'));
      expect(project, contains('com.apple.BackgroundModes = {\n\t\t\t\t\t\t\t\tenabled = 1;'));
      expect(
        readFile('ios/Runner/Info.plist'),
        contains('<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>remote-notification</string>'),
      );
    });

    test('Firebase: GoogleService-Info.plist of project shellxpro for com.shellx.prod, bundled', () {
      final plist = readFile('ios/Runner/GoogleService-Info.plist');
      expect(plist, contains('<string>shellxpro</string>'));
      expect(plist, contains('<string>com.shellx.prod</string>'));
      expect(
        readFile('ios/Runner.xcodeproj/project.pbxproj'),
        contains('/* GoogleService-Info.plist in Resources */,'),
      );
    });

    test('microphone and speech recognition prompts: Info.plist and both languages', () {
      final plist = readFile('ios/Runner/Info.plist');
      expect(plist, contains('<key>NSMicrophoneUsageDescription</key>'));
      expect(plist, contains('<key>NSSpeechRecognitionUsageDescription</key>'));
      for (final language in ['vi', 'en']) {
        final strings = readFile('ios/Runner/$language.lproj/InfoPlist.strings');
        expect(strings, contains('"NSMicrophoneUsageDescription" = "'), reason: language);
        expect(strings, contains('"NSSpeechRecognitionUsageDescription" = "'), reason: language);
      }
      expect(readFile('ios/Runner/vi.lproj/InfoPlist.strings'), contains('ShellX dùng micro'));
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

    test('backup and device transfer exclude everything (defence in depth)', () {
      final manifest = readFile('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
      expect(manifest, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
      final rules = readFile('android/app/src/main/res/xml/data_extraction_rules.xml');
      expect(rules, contains('<cloud-backup>'));
      expect(rules, contains('<device-transfer>'));
      expect(rules, isNot(contains('<include')));
      for (final domain in ['root', 'file', 'database', 'sharedpref', 'external']) {
        expect('<exclude domain="$domain" path="." />'.allMatches(rules), hasLength(2), reason: domain);
        expect(
          readFile('android/app/src/main/res/xml/backup_rules.xml'),
          contains('<exclude domain="$domain" path="." />'),
        );
      }
    });

    test('push notifications: permission, default channel, icon and colour', () {
      final manifest = readFile('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
      expect(manifest, contains('com.google.firebase.messaging.default_notification_channel_id'));
      expect(manifest, contains('android:value="@string/notification_channel_id"'));
      expect(manifest, contains('android:resource="@drawable/ic_notification"'));
      expect(manifest, contains('android:resource="@color/notification_color"'));
      expect(readFile('android/app/src/main/res/values/strings.xml'), contains('>shellx_notifications<'));
      expect(readFile('android/app/src/main/res/values-vi/strings.xml'), contains('Thông báo từ máy tính'));
      for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        expect(File('android/app/src/main/res/drawable-$density/ic_notification.png').existsSync(), isTrue);
      }
      final activity = readFile('android/app/src/main/kotlin/com/shellx/prod/MainActivity.kt');
      expect(activity, contains('createNotificationChannel(channel)'));
      expect(activity, contains('R.string.notification_channel_id'));
    });

    test('Firebase: google-services.json of project shellxpro for com.shellx.prod, plugin applied', () {
      final json = readFile('android/app/google-services.json');
      expect(json, contains('"project_id": "shellxpro"'));
      expect(json, contains('"package_name": "com.shellx.prod"'));
      expect(readFile('android/app/build.gradle.kts'), contains('id("com.google.gms.google-services")'));
      expect(readFile('android/settings.gradle.kts'), contains('id("com.google.gms.google-services") version'));
    });

    test('MainActivity (package com.shellx.prod) is a FlutterFragmentActivity with AppCompat themes', () {
      final activity = readFile('android/app/src/main/kotlin/com/shellx/prod/MainActivity.kt');
      expect(activity, contains('package com.shellx.prod\n'));
      expect(activity, contains('class MainActivity : FlutterFragmentActivity() {'));
      expect(Directory('android/app/src/main/kotlin/com/example').existsSync(), isFalse);
      expect(Directory('android/app/src/main/kotlin/pro').existsSync(), isFalse);
      expect(readFile('android/app/src/main/res/values/styles.xml'), contains('Theme.AppCompat'));
      expect(readFile('android/app/src/main/res/values-night/styles.xml'), contains('Theme.AppCompat'));
    });

    test('voice input: RECORD_AUDIO and the speech recognition service query', () {
      final manifest = readFile('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('android.permission.RECORD_AUDIO'));
      expect(manifest, contains('<action android:name="android.speech.RecognitionService"/>'));
    });
  });

  test('Firebase options name project shellxpro for both platforms (flutterfire configure)', () {
    final options = readFile('lib/firebase_options.dart');
    expect("projectId: 'shellxpro'".allMatches(options), hasLength(2));
    expect(options, contains("iosBundleId: 'com.shellx.prod'"));
    expect(readFile('firebase.json'), contains('"projectId":"shellxpro"'));
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

  test('the runtime packages the app works around are pinned exactly (pubspec.lock is not committed)', () {
    final pubspec = readFile('pubspec.yaml');
    expect(pubspec, contains('\n  xterm:\n    path: ../../third_party/xterm\n'));
    expect(pubspec, contains('\n  signals_flutter: 6.3.1\n'));
  });

  test('JetBrains Mono and both OFL licenses are bundled', () {
    for (final style in ['Regular', 'Bold', 'Italic', 'BoldItalic']) {
      expect(File('assets/fonts/JetBrainsMono-$style.ttf').lengthSync(), greaterThan(100000));
    }
    expect(readFile('assets/licenses/JetBrainsMono-OFL.txt'), contains('SIL OPEN FONT LICENSE'));
    expect(readFile('assets/licenses/Raleway-OFL.txt'), contains('SIL Open Font License'));
  });
}
