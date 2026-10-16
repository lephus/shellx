import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/mux/mux_paths.dart';

void main() {
  test('macOS: the endpoint string the CLI reads (A7 D30, A5b D5)', () {
    final mux = muxDirectoryPath(
      windows: false,
      environment: const {'HOME': '/Users/u'},
    );
    final paths = MuxPaths(
      muxDirectory: mux,
      tmpDirectory: '/var/folders/x/T/',
      uid: 501,
      windows: false,
    );
    // Pinned: term/ (Rust) builds the same path from $HOME.
    expect(
      paths.endpoint,
      '/Users/u/Library/Application Support/pro.shellx.desktop/mux/endpoint',
    );
    expect(
      paths.lock,
      '/Users/u/Library/Application Support/pro.shellx.desktop/mux/mux.lock',
    );
    expect(
      paths.address,
      '/Users/u/Library/Application Support/pro.shellx.desktop/mux/mux.sock',
    );
    expect(
      () => muxDirectoryPath(windows: false, environment: const {}),
      throwsStateError,
    );
  });

  test(r'Windows: %LOCALAPPDATA%\ShellX\mux\endpoint; address = pipe', () {
    final mux = muxDirectoryPath(
      windows: true,
      environment: const {'LOCALAPPDATA': r'C:\Users\u\AppData\Local'},
    );
    final paths = MuxPaths(
      muxDirectory: mux,
      tmpDirectory: r'C:\Temp',
      uid: 0,
      windows: true,
      pipeName: r'\\.\pipe\shellx-mux-0123456789abcdef',
    );
    expect(paths.endpoint, r'C:\Users\u\AppData\Local\ShellX\mux\endpoint');
    expect(paths.lock, r'C:\Users\u\AppData\Local\ShellX\mux\mux.lock');
    expect(paths.address, r'\\.\pipe\shellx-mux-0123456789abcdef');
    expect(
      () => muxDirectoryPath(windows: true, environment: const {}),
      throwsStateError,
    );
  });

  test('macOS: a socket path over 103 bytes falls back to TMPDIR', () {
    final paths = MuxPaths(
      muxDirectory: '/Users/${'u' * 100}/mux',
      tmpDirectory: '/var/folders/x/T/',
      uid: 501,
      windows: false,
    );
    expect(paths.address, '/var/folders/x/T/shellx-mux-501.sock');
    expect(paths.endpoint, '/Users/${'u' * 100}/mux/endpoint');
  });
}
