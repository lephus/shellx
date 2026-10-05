import 'package:path/path.dart' as p;

/// Where terminal sharing keeps its files (spec §6.1, §10.4).
final class SharingPaths {
  const SharingPaths({
    required this.windows,
    required this.home,
    required this.binDir,
    required this.binary,
    required this.termDir,
    required this.bundledBinary,
  });

  /// macOS: [executable] is `Platform.resolvedExecutable`,
  /// `…/ShellX.app/Contents/MacOS/ShellX`; the helper ships in
  /// `Contents/Helpers`.
  factory SharingPaths.macos({
    required String home,
    required String executable,
  }) {
    final support = p.posix.join(
      home,
      'Library',
      'Application Support',
      'ShellX',
    );
    final bin = p.posix.join(support, 'bin');
    return SharingPaths(
      windows: false,
      home: home,
      binDir: bin,
      binary: p.posix.join(bin, 'shellx-term'),
      termDir: p.posix.join(support, 'term'),
      bundledBinary: p.posix.normalize(
        p.posix.join(
          p.posix.dirname(executable),
          '..',
          'Helpers',
          'shellx-term',
        ),
      ),
    );
  }

  /// Windows: `shellx-term.exe` ships next to `ShellX.exe`.
  factory SharingPaths.windows({
    required String localAppData,
    required String userProfile,
    required String executable,
  }) {
    final support = p.windows.join(localAppData, 'ShellX');
    final bin = p.windows.join(support, 'bin');
    return SharingPaths(
      windows: true,
      home: userProfile,
      binDir: bin,
      binary: p.windows.join(bin, 'shellx-term.exe'),
      termDir: p.windows.join(support, 'term'),
      bundledBinary: p.windows.join(
        p.windows.dirname(executable),
        'shellx-term.exe',
      ),
    );
  }

  /// Null when the environment lacks `HOME` (macOS) or `LOCALAPPDATA` /
  /// `USERPROFILE` (Windows).
  static SharingPaths? forPlatform({
    required bool windows,
    required Map<String, String> environment,
    required String executable,
  }) {
    String? env(String key) {
      final value = environment[key];
      return value == null || value.isEmpty ? null : value;
    }

    if (windows) {
      final local = env('LOCALAPPDATA');
      final profile = env('USERPROFILE');
      if (local == null || profile == null) return null;
      return SharingPaths.windows(
        localAppData: local,
        userProfile: profile,
        executable: executable,
      );
    }
    final home = env('HOME');
    if (home == null) return null;
    return SharingPaths.macos(home: home, executable: executable);
  }

  final bool windows;
  final String home;
  final String binDir;
  final String binary;
  final String termDir;
  final String bundledBinary;

  p.Context get context => windows ? p.windows : p.posix;
}
