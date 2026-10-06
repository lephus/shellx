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

/// Client open flags: overlapped I/O, and identification-level security
/// QoS so a server that is not ours can identify the client but never
/// impersonate it.
const kPipeClientFlags =
    FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION;
const _sddlRevision1 = 1;

final class WindowsPipeTransport implements MuxTransport {
  /// [address] is a full pipe name (`\\.\pipe\…`). Throws [StateError]
  /// when the name is taken by another process (D4).
  @override
  Future<MuxListener> listen(String address) async {
    final sid = currentUserSid();
    final stop = CreateEvent(nullptr, TRUE, FALSE, nullptr);
    final events = ReceivePort();
    final ended = ReceivePort();
    final Isolate isolate;
    try {
      isolate = await Isolate.spawn(
        _listenLoop,
        (address, sid, stop, events.sendPort),
        onExit: ended.sendPort,
        onError: ended.sendPort,
      );
    } on Object {
      events.close();
      ended.close();
      CloseHandle(stop);
      rethrow;
    }
    final listener = _PipeListener(address, stop, isolate, events, ended);
    final int? first;
    try {
      first = await listener._started.future;
    } on Object {
      await listener.close();
      rethrow;
    }
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
    kPipeClientFlags,
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
  _PipeListener(
    this.address,
    this._stop,
    this._isolate,
    this._events,
    this._ended,
  ) {
    _events.listen((Object? message) {
      if (!_started.isCompleted) {
        _started.complete(message as int?);
        return;
      }
      if (message is! int) return;
      if (_closed) {
        CloseHandle(message); // accepted while closing: nobody wants it
      } else {
        _connections.add(_PipeConnection.start(message));
      }
    });
    // The isolate died (error or exit): before it reported, listen fails
    // (no hang); later, unless we closed it, the connections stream ends
    // with an error so the host notices it stopped accepting.
    _ended.listen((_) {
      if (!_started.isCompleted) {
        _started.completeError(StateError('pipe listener ended'));
      } else if (!_closed && !_connections.isClosed) {
        _connections.addError(StateError('pipe listener ended'));
        unawaited(_connections.close());
      }
      if (!_exited.isCompleted) _exited.complete();
    });
  }

  @override
  final String address;
  final int _stop;
  final Isolate _isolate;
  final ReceivePort _events;
  final ReceivePort _ended;
  final _exited = Completer<void>();
  final _started = Completer<int?>();
  final _connections = StreamController<MuxConnection>.broadcast();
  bool _closed = false;

  @override
  Stream<MuxConnection> get connections => _connections.stream;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    SetEvent(_stop);
    await _exited.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => _isolate.kill(priority: Isolate.immediate),
    );
    _ended.close();
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
      if (message is SendPort && !pipe._writer.isCompleted) {
        pipe._writer.complete(message);
      }
    });
    final readerExit = ReceivePort();
    final writerExit = ReceivePort();
    pipe._ports.addAll([readPort, writePort, readerExit, writerExit]);
    // Awaited only on close (with a bound); never an unhandled error.
    pipe._readerExited = readerExit.first..ignore();
    pipe._writerExited = writerExit.first..ignore();
    pipe._reader = Isolate.spawn(_readLoop, (
      handle,
      pipe._stop,
      readPort.sendPort,
    ), onExit: readerExit.sendPort);
    pipe._writerIsolate = Isolate.spawn(_writeLoop, (
      handle,
      pipe._stop,
      writePort.sendPort,
    ), onExit: writerExit.sendPort);
    return StreamMuxConnection(input.stream, pipe._write, pipe._close);
  }

  static const _bound = Duration(seconds: 1);

  final int _handle;
  final int _stop;
  final _writer = Completer<SendPort>();
  final _ports = <ReceivePort>[];
  late final Future<Isolate> _reader;
  late final Future<Isolate> _writerIsolate;
  late final Future<Object?> _readerExited;
  late final Future<Object?> _writerExited;
  Future<void> _pending = Future<void>.value();

  void _write(Uint8List bytes) {
    final chunk = TransferableTypedData.fromList([bytes]);
    _pending = _pending.then((_) async => (await _writer.future).send(chunk));
  }

  /// Null when the isolate never spawned (nothing to wait for).
  static Future<Isolate?> _spawned(Future<Isolate> isolate) =>
      isolate.then<Isolate?>((i) => i, onError: (Object _) => null);

  Future<void> _close() async {
    final writer = await _spawned(_writerIsolate);
    final reader = await _spawned(_reader);
    // Queued writes go out first (bounded), then the writer ends itself.
    if (writer != null) {
      try {
        await _pending.timeout(_bound);
        (await _writer.future.timeout(_bound)).send(null);
        await _writerExited.timeout(_bound);
      } on TimeoutException {
        // Stuck (peer not reading): the stop event below cancels its I/O.
      }
    }
    // Both loops stop; the handle is closed only once neither uses it.
    SetEvent(_stop);
    try {
      await Future.wait([
        if (reader != null) _readerExited,
        if (writer != null) _writerExited,
      ]).timeout(_bound);
    } on TimeoutException {
      // A writer still waiting for messages (never got its port), or a
      // loop stuck in a call: end both before the handle goes away.
      writer?.kill(priority: Isolate.immediate);
      reader?.kill(priority: Isolate.immediate);
      await Future.wait([
        if (reader != null) _readerExited,
        if (writer != null) _writerExited,
      ]).timeout(_bound, onTimeout: () => const []);
    }
    CloseHandle(_handle);
    CloseHandle(_stop);
    for (final port in _ports) {
      port.close();
    }
  }
}
