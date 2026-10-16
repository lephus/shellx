import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shellx_core/shellx_core.dart';

/// What this phone reports as `device.name` / `device.platform` (spec §5.2:
/// the mobile device name is the phone model).
final class DeviceDescription {
  const DeviceDescription({required this.name, required this.platform});

  final String name;
  final DevicePlatform platform;
}

/// "samsung" + "SM-S911B" → "Samsung SM-S911B"; "Xiaomi" + "Xiaomi 13" → "Xiaomi 13".
String formatAndroidModelName(String manufacturer, String model) {
  final maker = manufacturer.trim();
  final name = model.trim();
  if (maker.isEmpty || name.toLowerCase().startsWith(maker.toLowerCase())) return name;
  return '${maker[0].toUpperCase()}${maker.substring(1)} $name';
}

/// Runs before the first frame (a pre-resolved dependency): a platform error or an empty model
/// falls back to a generic name ("iPhone", "Android") instead of blocking the launch.
Future<DeviceDescription> describeThisDevice([DeviceInfoPlugin? plugin]) async {
  final ios = Platform.isIOS;
  final platform = ios ? DevicePlatform.ios : DevicePlatform.android;
  final fallback = ios ? 'iPhone' : 'Android';
  String name;
  try {
    final info = plugin ?? DeviceInfoPlugin();
    if (ios) {
      name = (await info.iosInfo).modelName;
    } else {
      final android = await info.androidInfo;
      name = formatAndroidModelName(android.manufacturer, android.model);
    }
  } catch (error) {
    if (kDebugMode) debugPrint('describeThisDevice error: ${error.runtimeType}');
    name = '';
  }
  return DeviceDescription(name: name.trim().isEmpty ? fallback : name.trim(), platform: platform);
}
