import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:test/test.dart';

final class Files implements FileProbe {
  Files(this.exe);

  final Set<String> exe;

  @override
  bool isExecutable(String path) => exe.contains(path);

  @override
  bool isFile(String path) => exe.contains(path);

  @override
  String? read(String path) => null;
}

LoginEnv env(String path) =>
    LoginEnv({'PATH': path}, source: LoginEnvSource.interactiveLogin);

ProbeRunner probe(Map<String, ProbeResult?> answers) =>
    (exe, args, {environment}) async => answers['$exe ${args.join(' ')}'];

void main() {
  test('no git on PATH', () async {
    final (git, off) = await GitLocator(
      isMacOS: true,
      isWindows: false,
      files: Files({}),
      probe: probe({}),
    ).locate(env('/usr/bin'));
    expect(git, isNull);
    expect(off, UndoOff.noGit);
  });

  test('macOS /usr/bin/git without Command Line Tools: never run it', () async {
    final asked = <String>[];
    final (git, off) = await GitLocator(
      isMacOS: true,
      isWindows: false,
      files: Files({'/usr/bin/git'}),
      probe: (exe, args, {environment}) async {
        asked.add(exe);
        return exe == '/usr/bin/xcode-select'
            ? const ProbeResult(2, '')
            : fail('git must not run');
      },
    ).locate(env('/usr/bin'));
    expect(off, UndoOff.noCommandLineTools);
    expect(git, isNull);
    expect(asked, ['/usr/bin/xcode-select']);
  });

  test('version: 2.26 or newer', () async {
    Future<(GitTool?, UndoOff?)> with_(String version) => GitLocator(
      isMacOS: false,
      isWindows: false,
      files: Files({'/opt/git/bin/git'}),
      probe: probe({'/opt/git/bin/git --version': ProbeResult(0, version)}),
    ).locate(env('/opt/git/bin'));
    expect((await with_('git version 2.20.1')).$2, UndoOff.gitTooOld);
    final (ok, _) = await with_('git version 2.39.5 (Apple Git-154)');
    expect([ok!.executable, ok.major, ok.minor], ['/opt/git/bin/git', 2, 39]);
  });
}
