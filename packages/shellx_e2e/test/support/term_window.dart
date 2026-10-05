import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// `term/` relative to this package.
final String termDir = Directory('../../term').absolute.path;

final class TermBinaries {
  const TermBinaries(this.shellxTerm, this.fakeWindow);
  final String shellxTerm;
  final String fakeWindow;
}

/// The environment for running cargo: `$HOME/.cargo/bin` (rustup's default)
/// is prepended to PATH when cargo is not already found there.
Map<String, String> _cargoEnvironment() {
  final env = Map<String, String>.of(Platform.environment);
  final home = env['HOME'];
  if (home != null) {
    env['PATH'] = '$home/.cargo/bin:${env['PATH'] ?? '/usr/bin:/bin'}';
  }
  return env;
}

/// Builds `shellx-term` (with test hooks, so `SHELLX_TERM_TIMING=fast`
/// works) and the `fake_window` example. Fails loudly without cargo: these
/// tests are the proof of spec §11.4 and must not skip silently.
Future<TermBinaries> buildTermBinaries() async {
  final ProcessResult result;
  try {
    result = await Process.run(
      'cargo',
      [
        'build',
        '--features',
        'test-hooks',
        '--bin',
        'shellx-term',
        '--example',
        'fake_window',
      ],
      workingDirectory: termDir,
      environment: _cargoEnvironment(),
    );
  } on ProcessException {
    throw StateError(
      'cargo not found: install Rust (rustup) to run the shellx-term tests '
      '(spec §11.4)',
    );
  }
  if (result.exitCode != 0) {
    throw StateError('cargo build failed:\n${result.stderr}');
  }
  return TermBinaries(
    '$termDir/target/debug/shellx-term',
    '$termDir/target/debug/examples/fake_window',
  );
}

/// A terminal window running `shellx-term wrap -- /bin/sh` with [home] as
/// HOME (so its `endpoint` is the test agent's, never the real one).
final class TermWindow {
  TermWindow._(this._process) {
    _process.stdout.listen(_output.addAll);
    _process.stderr.drain<void>();
  }

  static Future<TermWindow> open(
    TermBinaries bins, {
    required String home,
  }) async => TermWindow._(
    await Process.start(
      bins.fakeWindow,
      [bins.shellxTerm, 'wrap', '--', '/bin/sh'],
      environment: {
        'HOME': home,
        'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
        'PS1': r'$ ',
        'ENV': '',
        // No history file: /bin/sh (bash) would write .bash_history into
        // the temp HOME on SIGHUP, racing the test's tearDown.
        'HISTFILE': '',
        'TERM': 'xterm-256color',
        'SHELLX_TERM_TIMING': 'fast',
      },
      includeParentEnvironment: false,
    ),
  );

  final Process _process;
  final _output = <int>[];

  /// Typing on the computer's keyboard.
  void type(String text) => _process.stdin.add(utf8.encode(text));

  String get text => utf8.decode(_output, allowMalformed: true);

  Future<void> waitFor(
    String needle, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!text.contains(needle)) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('window never showed "$needle":\n$text');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<int> get exitCode => _process.exitCode;

  void kill() => _process.kill(ProcessSignal.sigkill);
}
