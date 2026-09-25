import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
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

Future<DeviceDescription> describeThisDevice([DeviceInfoPlugin? plugin]) async {
  final info = plugin ?? DeviceInfoPlugin();
  if (Platform.isIOS) {
    final ios = await info.iosInfo;
    return DeviceDescription(name: ios.modelName, platform: DevicePlatform.ios);
  }
  final android = await info.androidInfo;
  return DeviceDescription(
    name: formatAndroidModelName(android.manufacturer, android.model),
    platform: DevicePlatform.android,
  );
}
