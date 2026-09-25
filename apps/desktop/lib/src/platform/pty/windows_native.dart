import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' show GetShortPathName;

import 'process_table.dart';

/// 8.3 short form of [path] (pure ASCII when short names are enabled on the
/// volume), or [path] unchanged when the conversion fails. Windows only.
String windowsShortPath(String path) {
  final longPath = path.toNativeUtf16();
  try {
    final needed = GetShortPathName(longPath, nullptr, 0);
    if (needed == 0) return path;
    final buffer = calloc<Uint16>(needed).cast<Utf16>();
    try {
      final written = GetShortPathName(longPath, buffer, needed);
      if (written == 0 || written >= needed) return path;
      return buffer.toDartString();
    } finally {
      calloc.free(buffer);
    }
  } finally {
    calloc.free(longPath);
  }
}

const int _th32csSnapProcess = 0x00000002;
const int _maxPath = 260;

// PROCESSENTRY32W from tlhelp32.h. win32 5.15.0 does not bind Toolhelp32.
final class _ProcessEntry32W extends Struct {
  @Uint32()
  external int dwSize;
  @Uint32()
  external int cntUsage;
  @Uint32()
  external int th32ProcessID;
  @UintPtr()
  external int th32DefaultHeapID;
  @Uint32()
  external int th32ModuleID;
  @Uint32()
  external int cntThreads;
  @Uint32()
  external int th32ParentProcessID;
  @Int32()
  external int pcPriClassBase;
  @Uint32()
  external int dwFlags;
  @Array(_maxPath)
  external Array<Uint16> szExeFile;
}

typedef _SnapshotNative = IntPtr Function(Uint32 flags, Uint32 processId);
typedef _SnapshotDart = int Function(int flags, int processId);
typedef _WalkNative =
    Int32 Function(IntPtr snapshot, Pointer<_ProcessEntry32W> entry);
typedef _WalkDart = int Function(int snapshot, Pointer<_ProcessEntry32W> entry);
typedef _CloseNative = Int32 Function(IntPtr handle);
typedef _CloseDart = int Function(int handle);

/// Windows process table via CreateToolhelp32Snapshot (synchronous, ~1 ms).
final class WindowsProcessTable implements ProcessTable {
  WindowsProcessTable() : _kernel32 = DynamicLibrary.open('kernel32.dll');

  final DynamicLibrary _kernel32;
  late final _SnapshotDart _createSnapshot = _kernel32
      .lookupFunction<_SnapshotNative, _SnapshotDart>(
        'CreateToolhelp32Snapshot',
      );
  late final _WalkDart _first = _kernel32
      .lookupFunction<_WalkNative, _WalkDart>('Process32FirstW');
  late final _WalkDart _next = _kernel32.lookupFunction<_WalkNative, _WalkDart>(
    'Process32NextW',
  );
  late final _CloseDart _closeHandle = _kernel32
      .lookupFunction<_CloseNative, _CloseDart>('CloseHandle');

  List<ProcessEntry> snapshotSync() {
    final snapshot = _createSnapshot(_th32csSnapProcess, 0);
    if (snapshot == -1 || snapshot == 0) return const <ProcessEntry>[];
    final entry = calloc<_ProcessEntry32W>();
    try {
      entry.ref.dwSize = sizeOf<_ProcessEntry32W>();
      final result = <ProcessEntry>[];
      var ok = _first(snapshot, entry);
      while (ok != 0) {
        result.add(
          ProcessEntry(
            pid: entry.ref.th32ProcessID,
            parentPid: entry.ref.th32ParentProcessID,
            name: _exeName(entry.ref.szExeFile),
          ),
        );
        ok = _next(snapshot, entry);
      }
      return result;
    } finally {
      calloc.free(entry);
      _closeHandle(snapshot);
    }
  }

  @override
  Future<List<ProcessEntry>> snapshot() async => snapshotSync();
}

String _exeName(Array<Uint16> chars) {
  final units = <int>[];
  for (var i = 0; i < _maxPath; i++) {
    final unit = chars[i];
    if (unit == 0) break;
    units.add(unit);
  }
  return String.fromCharCodes(units);
}
