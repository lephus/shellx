import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  test('Host names without patterns, in order; Include values (D6)', () {
    final file = parseSshConfig('''
# comment
Host devbox dev-db *.corp !bastion
  HostName 10.0.0.5
  User me
host=staging
HOST "quoted name" plain
Include config.d/*
  Include ~/.ssh/extra "other file"
Host -oProxyCommand=x
''');
    expect(file.hosts, ['devbox', 'dev-db', 'staging', 'plain']);
    expect(file.includes, ['config.d/*', '~/.ssh/extra', 'other file']);
  });

  test('includes: relative to ~/.ssh, ~ expanded, globs sorted, cycles and '
      'depth bounded, missing files skipped', () async {
    final files = {
      '/h/.ssh/config': 'Host a\nInclude config.d/*.conf\nInclude ~/.ssh/loop',
      '/h/.ssh/config.d/2.conf': 'Host c',
      '/h/.ssh/config.d/1.conf': 'Host b\nInclude /abs/deep1',
      '/h/.ssh/config.d/notes.txt': 'Host ignored',
      '/h/.ssh/loop': 'Host d\nInclude config',
      '/abs/deep1': 'Host e\nInclude /abs/deep2',
      '/abs/deep2': 'Host f\nInclude /abs/deep3',
      '/abs/deep3': 'Host g\nInclude /abs/deep4',
      '/abs/deep4': 'Host h\nInclude /abs/deep5',
      '/abs/deep5': 'Host too_deep',
    };
    final hosts = await readSshConfigHosts(
      home: '/h',
      read: (path) async => files[path],
      list: (dir) async => [
        for (final p in files.keys)
          if (p.startsWith('$dir/') &&
              !p.substring(dir.length + 1).contains('/'))
            p.substring(dir.length + 1),
      ],
    );
    // deep4 is depth 5: skipped (≤ 4 levels of Include).
    expect(hosts, ['a', 'b', 'e', 'f', 'g', 'c', 'd']);
  });

  test('at most 256 names, duplicates once', () async {
    final text = [for (var i = 0; i < 300; i++) 'Host h$i\nHost h0'].join('\n');
    final hosts = await readSshConfigHosts(
      home: '/h',
      read: (path) async => path == '/h/.ssh/config' ? text : null,
      list: (_) async => const [],
    );
    expect(hosts, hasLength(kMaxConfigHosts));
    expect(hosts.first, 'h0');
    expect(hosts.toSet(), hasLength(kMaxConfigHosts));
  });

  test('Windows paths', () async {
    final hosts = await readSshConfigHosts(
      home: r'C:\Users\me',
      windows: true,
      read: (path) async =>
          path == r'C:\Users\me\.ssh\config' ? 'Host winbox' : null,
      list: (_) async => const [],
    );
    expect(hosts, ['winbox']);
  });
}
