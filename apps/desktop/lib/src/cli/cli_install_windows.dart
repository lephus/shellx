import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:win32/win32.dart';

import 'cli_install.dart';

/// A7 D8 Windows: `HKCU\Environment` through the registry API. Values are
/// read as stored (`%USERPROFILE%` stays unexpanded) and written as
/// `REG_EXPAND_SZ`. Throws [StateError] with the Win32 code on failure.
/// ⚠ MANUAL (Windows): not exercised by the macOS suite.
final class WindowsUserEnvironment implements RegistryAccess {
  static const _key = 'Environment';

  @override
  String? read(String name) => using((arena) {
    final key = _open(arena, KEY_QUERY_VALUE);
    try {
      final valueName = name.toNativeUtf16(allocator: arena);
      final size = arena<Uint32>();
      var status = RegQueryValueEx(
        key,
        valueName,
        nullptr,
        nullptr,
        nullptr,
        size,
      );
      if (status == ERROR_FILE_NOT_FOUND) return null;
      if (status != ERROR_SUCCESS) {
        throw StateError('RegQueryValueEx failed: $status');
      }
      // Room for a missing terminating NUL.
      final bytes = size.value + 2;
      final data = arena<Uint8>(bytes);
      size.value = bytes;
      status = RegQueryValueEx(key, valueName, nullptr, nullptr, data, size);
      if (status != ERROR_SUCCESS) {
        throw StateError('RegQueryValueEx failed: $status');
      }
      final units = data.cast<Uint16>().asTypedList(size.value ~/ 2);
      final end = units.indexOf(0);
      return String.fromCharCodes(end < 0 ? units : units.sublist(0, end));
    } finally {
      RegCloseKey(key);
    }
  });

  @override
  void write(String name, String value) => using((arena) {
    final key = _open(arena, KEY_SET_VALUE);
    try {
      final data = value.toNativeUtf16(allocator: arena);
      final status = RegSetValueEx(
        key,
        name.toNativeUtf16(allocator: arena),
        0,
        REG_EXPAND_SZ,
        data.cast<Uint8>(),
        (value.length + 1) * 2,
      );
      if (status != ERROR_SUCCESS) {
        throw StateError('RegSetValueEx failed: $status');
      }
    } finally {
      RegCloseKey(key);
    }
  });

  int _open(Arena arena, int access) {
    final handle = arena<IntPtr>();
    final status = RegOpenKeyEx(
      HKEY_CURRENT_USER,
      _key.toNativeUtf16(allocator: arena),
      0,
      access,
      handle,
    );
    if (status != ERROR_SUCCESS) {
      throw StateError('RegOpenKeyEx failed: $status');
    }
    return handle.value;
  }
}

/// Tells Explorer (and the terminals it starts next) that the user's
/// environment changed: `WM_SETTINGCHANGE` with "Environment". A broadcast
/// waits on every top-level window (up to 1 s each, skipping hung ones),
/// so it runs on its own isolate, never on the UI's; failures are logged
/// by type.
void broadcastEnvironmentChange() {
  unawaited(
    Isolate.run(_broadcast).catchError(
      (Object e) => debugPrint('ShellX: broadcast failed: ${e.runtimeType}'),
    ),
  );
}

void _broadcast() => using((arena) {
  SendMessageTimeout(
    HWND_BROADCAST,
    WM_SETTINGCHANGE,
    0,
    'Environment'.toNativeUtf16(allocator: arena).address,
    SMTO_ABORTIFHUNG,
    1000,
    arena<IntPtr>(),
  );
});
