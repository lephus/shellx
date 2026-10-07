import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  final devbox = SshTarget.parse('me@devbox:2222')!;
  const mac = SshCommandOptions(
    sshPath: '/usr/bin/ssh',
    controlPath: '/tmp/shellx-ssh-501/%C',
  );

  test(
    'an SSH pane: -t, control, keepalive, destination, one remote command (D8, D12, D13)',
    () {
      final c = buildSshCommand(SshLaunch(devbox, remoteCwd: '/srv'), mac);
      expect(c.executable, '/usr/bin/ssh');
      expect(c.name, 'ssh');
      expect(c.arguments.sublist(0, c.arguments.length - 1), [
        '-t',
        '-o',
        'ControlMaster=auto',
        '-o',
        'ControlPath=/tmp/shellx-ssh-501/%C',
        '-o',
        'ControlPersist=60',
        '-o',
        'ServerAliveInterval=15',
        '-o',
        'ServerAliveCountMax=3',
        '-l',
        'me',
        '-p',
        '2222',
        '--',
        'devbox',
      ]);
      expect(c.arguments.last, startsWith("/bin/sh -c 'eval"));
    },
  );

  test('Windows / no control, keepalive configured, no hook', () {
    final c = buildSshCommand(
      SshLaunch(devbox, hook: false),
      const SshCommandOptions(
        sshPath: r'C:\Windows\System32\OpenSSH\ssh.exe',
        keepalive: false,
      ),
    );
    expect(c.arguments, ['-t', '-l', 'me', '-p', '2222', '--', 'devbox']);
  });

  test(
    'tmux on a server: bootstrap without hook files; hookless needs a plain name',
    () {
      final withHook = buildSshCommand(TmuxLaunch('my s', host: devbox), mac);
      expect(withHook.arguments.last, startsWith("/bin/sh -c 'eval"));
      final plain = buildSshCommand(
        TmuxLaunch('main', host: devbox, hook: false),
        mac,
      );
      expect(plain.arguments.last, 'tmux attach-session -t main');
      final create = buildSshCommand(
        TmuxLaunch('main', host: devbox, hook: false, create: true),
        mac,
      );
      expect(create.arguments.last, 'tmux new-session -A -s main');
      expect(
        () =>
            buildSshCommand(TmuxLaunch('my s', host: devbox, hook: false), mac),
        throwsArgumentError,
      );
      expect(
        () => buildSshCommand(const TmuxLaunch('main'), mac),
        throwsArgumentError,
      );
    },
  );

  test('local tmux: argv, exact name, no shell', () {
    expect(
      buildLocalTmuxCommand(
        const TmuxLaunch('my s'),
        '/opt/homebrew/bin/tmux',
      ).arguments,
      ['attach-session', '-t', '=my s'],
    );
    expect(
      buildLocalTmuxCommand(
        const TmuxLaunch('n', create: true),
        '/usr/bin/tmux',
      ).arguments,
      ['new-session', '-A', '-s', 'n'],
    );
  });

  test('tool paths (D3, D25)', () async {
    Future<bool> only(Set<String> files, String p) async => files.contains(p);
    expect(
      await sshPathFor(
        operatingSystem: 'macos',
        environment: const {'PATH': '/opt/homebrew/bin'},
        fileExists: (p) => only({'/usr/bin/ssh', '/opt/homebrew/bin/ssh'}, p),
      ),
      '/usr/bin/ssh',
    );
    expect(
      await sshPathFor(
        operatingSystem: 'windows',
        environment: const {
          'SystemRoot': r'C:\Windows',
          'Path': r'D:\Git\usr\bin',
        },
        fileExists: (p) => only({r'D:\Git\usr\bin\ssh.exe'}, p),
      ),
      r'D:\Git\usr\bin\ssh.exe',
    );
    expect(
      await sshPathFor(
        operatingSystem: 'windows',
        environment: const {'SystemRoot': r'C:\Windows'},
        fileExists: (p) => only({r'C:\Windows\System32\OpenSSH\ssh.exe'}, p),
      ),
      r'C:\Windows\System32\OpenSSH\ssh.exe',
    );
    expect(
      await sshPathFor(
        operatingSystem: 'macos',
        environment: const {},
        fileExists: (_) async => false,
      ),
      isNull,
    );
    expect(
      await tmuxPathFor(
        operatingSystem: 'macos',
        environment: const {'PATH': '/x'},
        fileExists: (p) => only({'/usr/local/bin/tmux', '/x/tmux'}, p),
      ),
      '/usr/local/bin/tmux',
    );
    expect(
      await tmuxPathFor(
        operatingSystem: 'windows',
        environment: const {},
        fileExists: (_) async => true,
      ),
      isNull,
    );
  });
}
