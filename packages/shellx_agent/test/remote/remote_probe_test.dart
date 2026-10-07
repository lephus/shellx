import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  const ps = '''
#ps
    1     0
  100     1
  200   100
  201   200
  300     1
  400   300
''';

  test('Linux ss: ports of each shell\'s descendants (D18)', () {
    final ports = parseRemoteProbe(
      '$ps#ss\n'
      'State  Recv-Q Send-Q Local Address:Port Peer Address:Port Process\n'
      'LISTEN 0      4096   127.0.0.1:8000     0.0.0.0:*    users:(("python3",pid=201,fd=3))\n'
      'LISTEN 0      511    [::]:5173          [::]:*       users:(("node",pid=201,fd=20),("node",pid=200,fd=20))\n'
      'LISTEN 0      128    0.0.0.0:22         0.0.0.0:*\n'
      'LISTEN 0      128    *:9000             *:*          users:(("x",pid=400,fd=1))\n',
      [100, 300, 999],
    );
    expect(ports, {
      100: [5173, 8000],
      300: [9000],
      999: <int>[],
    });
  });

  test('macOS/BSD lsof -F pn', () {
    final ports = parseRemoteProbe(
      '$ps#lsof\np201\nf3\nn*:3000\nn127.0.0.1:3000\nn[::1]:3001\np400\nn10.0.0.2:5000->10.0.0.3:41000\n',
      [100, 300],
    );
    expect(ports, {
      100: [3000, 3001],
      300: <int>[],
    });
  });

  test('no listing tool, garbage, a pid cycle: no ports, no hang', () {
    expect(parseRemoteProbe('#ps\n1 1\n2 1\nnonsense\n', [1]), {1: <int>[]});
    expect(parseRemoteProbe('', [5]), {5: <int>[]});
  });

  test('the script lists processes and one listener source', () {
    expect(remoteProbeScript, contains('ps -A -o pid= -o ppid='));
    expect(remoteProbeScript, contains('ss -ltnp'));
    expect(remoteProbeScript, contains('lsof -nP -iTCP -sTCP:LISTEN -F pn'));
  });
}
