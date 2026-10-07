import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  group('SshTarget.parse (A8 D4)', () {
    test('alias, host, user, port, ssh:// URL', () {
      final a = SshTarget.parse('devbox')!;
      expect((a.host, a.user, a.port), ('devbox', null, null));
      final b = SshTarget.parse(' me@dev.example.com:2222 ')!;
      expect((b.host, b.user, b.port), ('dev.example.com', 'me', 2222));
      final c = SshTarget.parse('host_1:22')!;
      expect((c.host, c.port), ('host_1', 22));
      final d = SshTarget.parse('SSH://ops@10.0.0.5:2200/')!;
      expect((d.host, d.user, d.port), ('10.0.0.5', 'ops', 2200));
    });

    test('IPv6 with and without a port', () {
      final a = SshTarget.parse('[fe80::1%en0]:2222')!;
      expect((a.host, a.port), ('fe80::1%en0', 2222));
      expect(a.key, '[fe80::1%en0]:2222');
      final b = SshTarget.parse('me@::1')!;
      expect((b.host, b.user, b.port), ('::1', 'me', null));
      expect(b.key, 'me@::1');
    });

    test('anything that could read as an ssh option is refused', () {
      for (final bad in [
        '-oProxyCommand=touch /tmp/x',
        '-p',
        'me@-oProxyCommand=x',
        '-host',
        '.hidden',
        'a b',
        'ho\tst',
        'host\nother',
        'me@@host',
        '@host',
        'host:',
        'host:0',
        'host:65536',
        'host:22a',
        'devbox:22:33',
        '[::1',
        '[::1]x',
        '',
        ' ',
        'x' * 256,
        'us er@host',
        'ü@host',
        'host;rm -rf ~',
        "host'",
        r'host$(id)',
        'ho\u0085st',
        'ho\u0000st',
        'ho\nst',
        'ho\x7fst',
      ]) {
        expect(SshTarget.parse(bad), isNull, reason: bad);
      }
    });

    test('the key is canonical and parses back to the same target (D5)', () {
      for (final text in [
        'devbox',
        'me@devbox',
        'devbox:2222',
        'me@devbox:2222',
        '[::1]:22',
        '::1',
      ]) {
        final target = SshTarget.parse(text)!;
        expect(target.key, text);
        expect(SshTarget.parse(target.key), target);
      }
    });

    test('ssh arguments never put user text before --', () {
      expect(SshTarget.parse('me@devbox:2222')!.destinationArgs, [
        '-l',
        'me',
        '-p',
        '2222',
        '--',
        'devbox',
      ]);
      expect(SshTarget.parse('devbox')!.destinationArgs, ['--', 'devbox']);
    });

    test('toString never shows the host (D37)', () {
      expect('${SshTarget.parse('devbox')}', isNot(contains('devbox')));
    });
  });

  test('parseKey accepts only the canonical form (preflight T1)', () {
    expect(
      SshTarget.parseKey('me@devbox:2222'),
      SshTarget.parse('me@devbox:2222'),
    );
    expect(SshTarget.parseKey('[::1]:22'), isNotNull);
    expect(SshTarget.parseKey(' devbox'), isNull);
    expect(SshTarget.parseKey('ssh://devbox'), isNull);
    expect(SshTarget.parseKey('-oProxyCommand=x'), isNull);
  });
}
