/// Windows named-pipe transport for the mux wire (A5b D4).
///
/// ⚠ Compiled and analyzed on macOS only; run on Windows by hand (A5b
/// Task 3 Step 5, `test/mux/windows_pipe_transport_test.dart`).
///
/// Win32 calls, and why:
/// - `OpenProcessToken` + `GetTokenInformation(TokenUser)` +
///   `ConvertSidToStringSidW`: the current user's SID, which names the pipe
///   ([pipeNameForUser]) and is the only principal in its DACL.
/// - `ConvertStringSecurityDescriptorToSecurityDescriptorW`
///   (`D:P(A;;GA;;;<SID>)`): a protected DACL with one ACE, full access for
///   that user — no one else may open or create an instance.
/// - `CreateNamedPipeW` (`PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED`, the
///   first instance also `FILE_FLAG_FIRST_PIPE_INSTANCE`; byte mode,
///   `PIPE_REJECT_REMOTE_CLIENTS`): the first instance fails when another
///   process already owns the name (a squatter, D4) → [StateError].
/// - `ConnectNamedPipe` (overlapped): waits for a client in the listener
///   isolate; `ERROR_PIPE_CONNECTED` means one arrived before the call.
/// - `WaitNamedPipeW` + `CreateFileW(..., FILE_FLAG_OVERLAPPED)`: the client
///   side; a missing or busy pipe → [SocketException].
/// - `ReadFile` / `WriteFile` (overlapped) in two isolates per connection:
///   a handle opened for synchronous I/O serializes reads and writes, so a
///   blocked read would block every write; overlapped I/O lets both run.
/// - `CreateEventW` / `WaitForMultipleObjects` / `SetEvent`: each blocking
///   wait also watches a manual-reset "stop" event the main isolate sets on
///   close (no race with an I/O not yet issued).
/// - `CancelIoEx` + `GetOverlappedResult(wait)`: cancel a pending I/O and
///   wait for it to finish before its `OVERLAPPED` is freed.
/// - `CloseHandle`: by the main isolate, after both I/O isolates exited.
///
/// Bound by hand (missing from `win32` 5.15): `WaitNamedPipeW`,
/// `WaitForMultipleObjects`, `ConvertSidToStringSidW`,
/// `ConvertStringSecurityDescriptorToSecurityDescriptorW`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:win32/win32.dart';

/// `\\.\pipe\shellx-mux-<first 16 hex of sha256(utf8(sid))>`.
String pipeNameForUser(String sid) =>
    r'\\.\pipe\shellx-mux-' +
    bytesToHex(sha256Bytes(utf8.encode(sid))).substring(0, 16);

/// The current process user's SID string (`S-1-5-21-…`). Windows only.
String currentUserSid() => using((arena) {
  final token = arena<IntPtr>();
  if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, token) == 0) {
    throw WindowsException(HRESULT_FROM_WIN32(GetLastError()));
  }
  try {
    final length = arena<Uint32>();
    GetTokenInformation(token.value, TokenUser, nullptr, 0, length);
    final info = arena<Uint8>(length.value);
    if (GetTokenInformation(
          token.value,
          TokenUser,
          info,
          length.value,
          length,
        ) ==
        0) {
      throw WindowsException(HRESULT_FROM_WIN32(GetLastError()));
    }
    // TOKEN_USER { SID_AND_ATTRIBUTES User { PSID Sid; DWORD Attributes } }
    return sidToString(info.cast<Pointer<Void>>().value);
  } finally {
    CloseHandle(token.value);
  }
});

/// `ConvertSidToStringSidW` of the SID at [sid].
String sidToString(Pointer<Void> sid) => using((arena) {
  final out = arena<Pointer<Utf16>>();
  if (_convertSidToStringSid(sid, out) == 0) {
    throw WindowsException(HRESULT_FROM_WIN32(GetLastError()));
  }
  try {
    return out.value.toDartString();
  } finally {
    LocalFree(out.value);
  }
});

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _advapi32 = DynamicLibrary.open('advapi32.dll');

final _waitNamedPipe = _kernel32
    .lookupFunction<
      Int32 Function(Pointer<Utf16>, Uint32),
      int Function(Pointer<Utf16>, int)
    >('WaitNamedPipeW');

final _waitForMultipleObjects = _kernel32
    .lookupFunction<
      Uint32 Function(Uint32, Pointer<IntPtr>, Int32, Uint32),
      int Function(int, Pointer<IntPtr>, int, int)
    >('WaitForMultipleObjects');

final _convertSidToStringSid = _advapi32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Pointer<Utf16>>),
      int Function(Pointer<Void>, Pointer<Pointer<Utf16>>)
    >('ConvertSidToStringSidW');

final _convertStringSd = _advapi32
    .lookupFunction<
      Int32 Function(Pointer<Utf16>, Uint32, Pointer<Pointer>, Pointer<Uint32>),
      int Function(Pointer<Utf16>, int, Pointer<Pointer>, Pointer<Uint32>)
    >('ConvertStringSecurityDescriptorToSecurityDescriptorW');

const _bufferSize = 65536;
const _sddlRevision1 = 1;

final class WindowsPipeTransport implements MuxTransport {
  /// [address] is a full pipe name (`\\.\pipe\…`). Throws [StateError]
  /// when the name is taken by another process (D4).
  @override
  Future<MuxListener> listen(String address) async {
    final sid = currentUserSid();
    final stop = CreateEvent(nullptr, TRUE, FALSE, nullptr);
    final events = ReceivePort();
    final isolate = await Isolate.spawn(_listenLoop, (
      address,
      sid,
      stop,
      events.sendPort,
    ));
    final listener = _PipeListener(address, stop, isolate, events);
    final first = await listener._started.future;
    if (first != null) {
      await listener.close();
      throw StateError('pipe name taken');
    }
    return listener;
  }

  @override
  Future<MuxConnection> connect(
    String address, {
    Duration timeout = const Duration(seconds: 1),
  }) async {
    final handle = await Isolate.run(
      () => _openClient(address, timeout.inMilliseconds),
    );
    if (handle == null) throw const SocketException('pipe unavailable');
    return _PipeConnection.start(handle);
  }
}

/// Blocking: waits for an instance, then opens it. Null on failure.
int? _openClient(String name, int timeoutMs) => using((arena) {
  final native = name.toNativeUtf16(allocator: arena);
  if (_waitNamedPipe(native, timeoutMs < 1 ? 1 : timeoutMs) == 0) return null;
  final handle = CreateFile(
    native,
    GENERIC_READ | GENERIC_WRITE,
    0,
    nullptr,
    OPEN_EXISTING,
    FILE_FLAG_OVERLAPPED,
    0,
  );
  return handle == INVALID_HANDLE_VALUE ? null : handle;
});

/// Waits for [handle]'s pending overlapped I/O or [stop]. True when the I/O
/// completed (bytes in [transferred]); false on stop or error (the I/O is
/// cancelled and drained first).
bool _await(
  int handle,
  Pointer<OVERLAPPED> overlapped,
  int stop,
  Pointer<Uint32> transferred,
  Arena arena,
) {
  final handles = arena<IntPtr>(2)
    ..[0] = overlapped.ref.hEvent
    ..[1] = stop;
  final which = _waitForMultipleObjects(2, handles, FALSE, INFINITE);
  if (which == WAIT_OBJECT_0) {
    return GetOverlappedResult(handle, overlapped, transferred, FALSE) != 0;
  }
  CancelIoEx(handle, overlapped);
  GetOverlappedResult(handle, overlapped, transferred, TRUE);
  return false;
}

/// Listener isolate: one pipe instance after another. Sends `null` once
/// the first instance exists (or an error code), then each connected
/// handle; ends when [stop] is set.
void _listenLoop((String, String, int, SendPort) args) {
  final (name, sid, stop, out) = args;
  using((arena) {
    final sd = arena<Pointer>();
    if (_convertStringSd(
          'D:P(A;;GA;;;$sid)'.toNativeUtf16(allocator: arena),
          _sddlRevision1,
          sd,
          nullptr,
        ) ==
        0) {
      out.send(GetLastError());
      return;
    }
    final attributes = arena<SECURITY_ATTRIBUTES>()
      ..ref.nLength = sizeOf<SECURITY_ATTRIBUTES>()
      ..ref.lpSecurityDescriptor = sd.value
      ..ref.bInheritHandle = FALSE;
    final native = name.toNativeUtf16(allocator: arena);
    final overlapped = arena<OVERLAPPED>()
      ..ref.hEvent = CreateEvent(nullptr, TRUE, FALSE, nullptr);
    final transferred = arena<Uint32>();
    var first = true;
    try {
      while (true) {
        final pipe = CreateNamedPipe(
          native,
          PIPE_ACCESS_DUPLEX |
              FILE_FLAG_OVERLAPPED |
              (first ? FILE_FLAG_FIRST_PIPE_INSTANCE : 0),
          PIPE_TYPE_BYTE |
              PIPE_READMODE_BYTE |
              PIPE_WAIT |
              PIPE_REJECT_REMOTE_CLIENTS,
          PIPE_UNLIMITED_INSTANCES,
          _bufferSize,
          _bufferSize,
          0,
          attributes,
        );
        if (pipe == INVALID_HANDLE_VALUE) {
          if (first) out.send(GetLastError());
          return;
        }
        if (first) {
          out.send(null);
          first = false;
        }
        var connected = ConnectNamedPipe(pipe, overlapped) != 0;
        if (!connected) {
          final error = GetLastError();
          if (error == ERROR_PIPE_CONNECTED) {
            connected = true;
          } else if (error == ERROR_IO_PENDING) {
            connected = _await(pipe, overlapped, stop, transferred, arena);
          }
        }
        if (!connected) {
          CloseHandle(pipe);
          if (WaitForSingleObject(stop, 0) == WAIT_OBJECT_0) return;
          continue;
        }
        out.send(pipe);
      }
    } finally {
      CloseHandle(overlapped.ref.hEvent);
      LocalFree(sd.value);
    }
  });
}

final class _PipeListener implements MuxListener {
  _PipeListener(this.address, this._stop, this._isolate, this._events) {
    _events.listen((Object? message) {
      if (!_started.isCompleted) {
        _started.complete(message as int?);
        return;
      }
      if (message is int) {
        _connections.add(_PipeConnection.start(message));
      }
    });
  }

  @override
  final String address;
  final int _stop;
  final Isolate _isolate;
  final ReceivePort _events;
  final _started = Completer<int?>();
  final _connections = StreamController<MuxConnection>.broadcast();
  bool _closed = false;

  @override
  Stream<MuxConnection> get connections => _connections.stream;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final exited = ReceivePort();
    _isolate.addOnExitListener(exited.sendPort);
    SetEvent(_stop);
    await exited.first.timeout(
      const Duration(seconds: 2),
      onTimeout: () => _isolate.kill(priority: Isolate.immediate),
    );
    exited.close();
    _events.close();
    CloseHandle(_stop);
    unawaited(_connections.close());
  }
}

/// Reader isolate: posts each chunk read, then `null` at the end.
void _readLoop((int, int, SendPort) args) {
  final (handle, stop, out) = args;
  using((arena) {
    final overlapped = arena<OVERLAPPED>()
      ..ref.hEvent = CreateEvent(nullptr, TRUE, FALSE, nullptr);
    final buffer = arena<Uint8>(_bufferSize);
    final transferred = arena<Uint32>();
    try {
      while (true) {
        if (ReadFile(handle, buffer, _bufferSize, nullptr, overlapped) == 0 &&
            GetLastError() != ERROR_IO_PENDING) {
          return; // ERROR_BROKEN_PIPE: the peer closed.
        }
        if (!_await(handle, overlapped, stop, transferred, arena)) return;
        if (transferred.value == 0) continue;
        out.send(
          TransferableTypedData.fromList([
            Uint8List.fromList(buffer.asTypedList(transferred.value)),
          ]),
        );
      }
    } finally {
      CloseHandle(overlapped.ref.hEvent);
      out.send(null);
    }
  });
}

/// Writer isolate: sends its port first; writes each chunk in order; `null`
/// ends it after the queued writes.
void _writeLoop((int, int, SendPort) args) {
  final (handle, stop, out) = args;
  final inbox = ReceivePort();
  out.send(inbox.sendPort);
  final arena = Arena();
  final overlapped = arena<OVERLAPPED>()
    ..ref.hEvent = CreateEvent(nullptr, TRUE, FALSE, nullptr);
  final transferred = arena<Uint32>();
  var finished = false;
  void finish() {
    if (finished) return;
    finished = true;
    inbox.close();
    CloseHandle(overlapped.ref.hEvent);
    arena.releaseAll();
  }

  inbox.listen((Object? message) {
    if (message is! TransferableTypedData) {
      finish();
      return;
    }
    if (finished) return;
    final bytes = message.materialize().asUint8List();
    final native = calloc<Uint8>(bytes.length);
    try {
      native.asTypedList(bytes.length).setAll(0, bytes);
      var offset = 0;
      while (offset < bytes.length) {
        final ok =
            WriteFile(
              handle,
              native + offset,
              bytes.length - offset,
              nullptr,
              overlapped,
            ) !=
            0;
        if (!ok && GetLastError() != ERROR_IO_PENDING) {
          finish();
          return;
        }
        if (!_await(handle, overlapped, stop, transferred, arena)) {
          finish();
          return;
        }
        offset += transferred.value;
      }
    } finally {
      calloc.free(native);
    }
  });
}

/// One connected pipe handle (either side), framed by [StreamMuxConnection].
final class _PipeConnection {
  _PipeConnection._(this._handle)
    : _stop = CreateEvent(nullptr, TRUE, FALSE, nullptr);

  static MuxConnection start(int handle) {
    final pipe = _PipeConnection._(handle);
    final input = StreamController<Uint8List>();
    final readPort = ReceivePort();
    readPort.listen((Object? message) {
      if (message is TransferableTypedData) {
        input.add(message.materialize().asUint8List());
      } else {
        readPort.close();
        unawaited(input.close());
      }
    });
    final writePort = ReceivePort();
    writePort.listen((Object? message) {
      if (message is SendPort) pipe._writer.complete(message);
    });
    pipe._ports.addAll([readPort, writePort]);
    pipe._reader = Isolate.spawn(_readLoop, (
      handle,
      pipe._stop,
      readPort.sendPort,
    ));
    pipe._writerIsolate = Isolate.spawn(_writeLoop, (
      handle,
      pipe._stop,
      writePort.sendPort,
    ));
    return StreamMuxConnection(input.stream, pipe._write, pipe._close);
  }

  final int _handle;
  final int _stop;
  final _writer = Completer<SendPort>();
  final _ports = <ReceivePort>[];
  late final Future<Isolate> _reader;
  late final Future<Isolate> _writerIsolate;
  Future<void> _pending = Future<void>.value();

  void _write(Uint8List bytes) {
    final chunk = TransferableTypedData.fromList([bytes]);
    _pending = _pending.then((_) async => (await _writer.future).send(chunk));
  }

  Future<void> _close() async {
    // Queued writes go out first (bounded), then both loops stop.
    final writer = await _writerIsolate;
    final writerExit = ReceivePort();
    writer.addOnExitListener(writerExit.sendPort);
    await _pending;
    (await _writer.future).send(null);
    await writerExit.first.timeout(
      const Duration(seconds: 1),
      onTimeout: () => null,
    );
    writerExit.close();
    final reader = await _reader;
    final readerExit = ReceivePort();
    reader.addOnExitListener(readerExit.sendPort);
    SetEvent(_stop);
    await readerExit.first.timeout(
      const Duration(seconds: 1),
      onTimeout: () => null,
    );
    readerExit.close();
    CloseHandle(_handle);
    CloseHandle(_stop);
    for (final port in _ports) {
      port.close();
    }
  }
}
