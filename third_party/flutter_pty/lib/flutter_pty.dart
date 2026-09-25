import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_pty/src/flutter_pty_bindings_generated.dart';

const _libName = 'flutter_pty';

final DynamicLibrary _dylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

final _bindings = FlutterPtyBindings(_dylib);

// ShellX: native functions added by the ShellX patches (SHELLX_PATCHES.md).
// Looked up on first use; pty_kill and pty_job_error exist on Windows only.
final _ptyRelease = _dylib.lookupFunction<Void Function(Pointer<PtyHandle>),
    void Function(Pointer<PtyHandle>)>('pty_release');

// ShellX: pty_write returns whether the input was accepted (the generated
// binding still declares upstream's void).
final _ptyWrite = _dylib.lookupFunction<
    Int Function(Pointer<PtyHandle>, Pointer<Char>, Int),
    int Function(Pointer<PtyHandle>, Pointer<Char>, int)>('pty_write');

final _ptyKill = _dylib.lookupFunction<Int Function(Pointer<PtyHandle>),
    int Function(Pointer<PtyHandle>)>('pty_kill');

final _ptyJobError = _dylib.lookupFunction<Int Function(Pointer<PtyHandle>),
    int Function(Pointer<PtyHandle>)>('pty_job_error');

final _ptyDebugFail = _dylib.lookupFunction<Void Function(Int),
    void Function(int)>('pty_debug_fail');

final _init = () {
  return _bindings.Dart_InitializeApiDL(NativeApi.initializeApiDLData);
}();

void _ensureInitialized() {
  if (_init != 0) {
    throw StateError('Failed to initialize native bindings');
  }
}

/// Pty represents a process running in a pseudo-terminal.
///
/// To create a Pty, use [Pty.start].
class Pty {
  final String executable;

  final List<String> arguments;

  /// Spawns a process in a pseudo-terminal. The arguments have the same meaning
  /// as in [Process.start].
  /// [ackRead] indicates if the pty should wait for a call to [Pty.ackRead] before sending the next data.
  Pty.start(
    this.executable, {
    this.arguments = const [],
    String? workingDirectory,
    Map<String, String>? environment,
    int rows = 25,
    int columns = 80,
    bool ackRead = false,
  }) {
    _ensureInitialized();

    final effectiveEnv = <String, String>{};

    effectiveEnv['TERM'] = 'xterm-256color';
    // Without this, tools like "vi" produce sequences that are not UTF-8 friendly
    effectiveEnv['LANG'] = 'en_US.UTF-8';

    const envValuesToCopy = {
      'LOGNAME',
      'USER',
      'DISPLAY',
      'LC_TYPE',
      'HOME',
      'PATH'
    };

    for (var entry in Platform.environment.entries) {
      if (envValuesToCopy.contains(entry.key)) {
        effectiveEnv[entry.key] = entry.value;
      }
    }

    if (environment != null) {
      for (var entry in environment.entries) {
        effectiveEnv[entry.key] = entry.value;
      }
    }

    // build argv
    final argv = calloc<Pointer<Utf8>>(arguments.length + 2);
    argv.elementAt(0).value = executable.toNativeUtf8();
    for (var i = 0; i < arguments.length; i++) {
      argv.elementAt(i + 1).value = arguments[i].toNativeUtf8();
    }
    argv.elementAt(arguments.length + 1).value = nullptr;

    //build env
    final envp = calloc<Pointer<Utf8>>(effectiveEnv.length + 1);
    for (var i = 0; i < effectiveEnv.length; i++) {
      final entry = effectiveEnv.entries.elementAt(i);
      envp.elementAt(i).value = '${entry.key}=${entry.value}'.toNativeUtf8();
    }
    envp.elementAt(effectiveEnv.length).value = nullptr;

    final options = calloc<PtyOptions>();
    options.ref.rows = rows;
    options.ref.cols = columns;
    options.ref.executable = executable.toNativeUtf8().cast();
    options.ref.arguments = argv.cast();
    options.ref.environment = envp.cast();
    options.ref.stdout_port = _stdoutPort.sendPort.nativePort;
    options.ref.exit_port = _exitPort.sendPort.nativePort;
    options.ref.ackRead = ackRead;

    if (workingDirectory != null) {
      options.ref.working_directory = workingDirectory.toNativeUtf8().cast();
    } else {
      options.ref.working_directory = nullptr;
    }

    _handle = _bindings.pty_create(options);

    // ShellX: pty_create has copied what it needs (the POSIX child has its
    // own copy since fork), so free the native strings instead of leaking
    // them on every spawn.
    for (var i = 0; i <= arguments.length; i++) {
      malloc.free(argv[i]);
    }
    calloc.free(argv);
    for (var i = 0; i < effectiveEnv.length; i++) {
      malloc.free(envp[i]);
    }
    calloc.free(envp);
    malloc.free(options.ref.executable);
    if (options.ref.working_directory != nullptr) {
      malloc.free(options.ref.working_directory);
    }

    calloc.free(options);

    if (_handle == nullptr) {
      // ShellX: nothing will ever arrive on the ports.
      _stdoutPort.close();
      _exitPort.close();
      throw StateError('Failed to create PTY: ${_getPtyError()}');
    }

    pid = _bindings.pty_getpid(_handle);
    jobError = Platform.isWindows ? _ptyJobError(_handle) : 0;

    // ShellX: the native reader posts a null once the output has ended; the
    // stream closes then, not when the exit code arrives, so the tail of the
    // output is not dropped.
    _stdoutPort.listen(_onOutput);
    _exitPort.first.then(_onExitCode);
  }

  /// ShellX, tests only (POSIX): the next [Pty.start] fails as if [step]
  /// had failed natively (see `pty_debug_fail` in `src/flutter_pty.h`).
  @visibleForTesting
  static void debugFailNextStart(int step) => _ptyDebugFail(step);

  final _stdoutPort = ReceivePort();

  final _exitPort = ReceivePort();

  final _exitCodeCompleter = Completer<int>();

  late final Pointer<PtyHandle> _handle;

  final _output = StreamController<Uint8List>();

  bool _exited = false;

  bool _outputEnded = false;

  bool _released = false;

  /// The output stream from the pseudo-terminal. Note that pseudo-terminals
  /// do not distinguish between stdout and stderr.
  ///
  /// ShellX: closes once every process that had the terminal open has closed
  /// it (end of file), which is normally right after the process exits.
  Stream<Uint8List> get output => _output.stream;

  /// A `Future` which completes with the exit code of the process
  /// when the process completes.
  ///
  /// The handling of exit codes is platform specific.
  ///
  /// On Linux and OS X a normal exit code will be a positive value in
  /// the range `[0..255]`. If the process was terminated due to a signal
  /// the exit code will be a negative value in the range `[-255..-1]`,
  /// where the absolute value of the exit code is the signal
  /// number. For example, if a process crashes due to a segmentation
  /// violation the exit code will be -11, as the signal SIGSEGV has the
  /// number 11.
  ///
  /// On Windows a process can report any 32-bit value as an exit
  /// code. When returning the exit code this exit code is turned into
  /// a signed value. Some special values are used to report
  /// termination due to some system event. E.g. if a process crashes
  /// due to an access violation the 32-bit exit code is `0xc0000005`,
  /// which will be returned as the negative number `-1073741819`. To
  /// get the original 32-bit value use `(0x100000000 + exitCode) &
  /// 0xffffffff`.
  ///
  /// There is no guarantee that [output] have finished reporting the buffered
  /// output of the process when the returned future completes.
  /// To be sure that all output is captured, wait for the done event on the
  /// streams.
  Future<int> get exitCode => _exitCodeCompleter.future;

  /// The process id of the process running in the pseudo-terminal.
  ///
  /// ShellX: read once at start, so it stays valid after the native handle
  /// is released.
  late final int pid;

  /// ShellX, Windows: 0 when the process runs in a job object, so [kill]
  /// ends it and every process it started; otherwise the Win32 error that
  /// prevented the job, and [kill] ends the process only. 0 on POSIX.
  late final int jobError;

  /// Write data to the pseudo-terminal.
  ///
  /// ShellX: never blocks the calling isolate, even when the process does
  /// not read its input (upstream wrote synchronously: a few KB to e.g.
  /// `sleep` froze the isolate). POSIX: the data is queued for a writer
  /// thread, at most 1 MiB waiting; Windows: written to conhost's input
  /// pipe, without a flush. Returns false when the data was dropped (the
  /// queue is full, or the write failed) and once the pty is released.
  bool write(Uint8List data) {
    if (_released) return false;
    if (data.isEmpty) return true;
    final buf = malloc<Int8>(data.length);
    buf.asTypedList(data.length).setAll(0, data);
    final accepted = _ptyWrite(_handle, buf.cast(), data.length) != 0;
    malloc.free(buf);
    return accepted;
  }

  /// Resize the pseudo-terminal.
  void resize(int rows, int cols) {
    if (_released) return;
    _bindings.pty_resize(_handle, rows, cols);
  }

  /// Kill the process running in the pseudo-terminal.
  ///
  /// When possible, [signal] will be sent to the process. This includes
  /// Linux and OS X. The default signal is [ProcessSignal.sigterm]
  /// which will normally terminate the process.
  ///
  /// ShellX: on Windows this terminates the job object the process was
  /// started in: the process and every process it started ([signal] is
  /// ignored); without a job (see [jobError]) it terminates the process only.
  /// It returns false without signalling once the process has exited, on
  /// both platforms: POSIX, its pid may have been reused; Windows, what the
  /// process left behind is not killed, as on POSIX.
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (_exited || _released) return false;
    if (Platform.isWindows) {
      return _ptyKill(_handle) != 0;
    }
    return Process.killPid(pid, signal);
  }

  /// indicates that a data chunk has been processed.
  /// This is needed when ackRead is set to true as the pty will wait for this signal to happen
  /// before any additional data is sent.
  void ackRead() {
    if (_released) return;
    _bindings.pty_ack_read(_handle);
  }

  void _onOutput(dynamic message) {
    if (message is Uint8List) {
      _output.add(message);
      return;
    }
    // ShellX: null from the native reader: end of output.
    _stdoutPort.close();
    _output.close();
    _outputEnded = true;
    _releaseWhenDone();
  }

  void _onExitCode(dynamic exitCode) {
    _exitPort.close();
    _exited = true;
    _exitCodeCompleter.complete(exitCode);
    _releaseWhenDone();
  }

  /// ShellX: frees the native handle (POSIX: the master fd; Windows: the job
  /// object and pipes) once neither native thread can touch it any more.
  void _releaseWhenDone() {
    if (_released || !_exited || !_outputEnded) return;
    _released = true;
    _ptyRelease(_handle);
  }
}

String? _getPtyError() {
  final error = _bindings.pty_error();

  if (error == nullptr) {
    return null;
  }

  return error.cast<Utf8>().toDartString();
}
