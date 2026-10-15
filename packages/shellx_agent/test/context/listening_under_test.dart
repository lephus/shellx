import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

final class _Probe implements PortProbe, ProcessTableProbe {
  _Probe(this.ports, this.rows);
  final Map<int, Set<int>> ports;
  final Map<int, ProgramRow> rows;
  int calls = 0;

  @override
  Future<Map<int, Set<int>>> listening() async {
    calls++;
    return ports;
  }

  @override
  Future<Map<int, int>> parents() async => {
    for (final e in rows.entries) e.key: e.value.parent,
  };

  @override
  Future<Map<int, ProgramRow>> processTable() async {
    calls++;
    return rows;
  }
}

void main() {
  test('ps / CIM "pid ppid command": the base name, without .exe; spaces, '
      'controls and bad lines (V2-3 D12)', () {
    final table = parseProcessTable(
      '  612   500 /usr/local/bin/node\n'
      ' 700 612 /Applications/Visual Studio Code.app/Contents/MacOS/Electron\n'
      '4321 100 node.exe\n'
      '4400 100 C:\\Program Files\\Py\\python.EXE\n'
      '9 1 a\u0007b\n'
      'bad line\n'
      '12 x y\n',
    );
    expect(table, {
      612: (parent: 500, name: 'node'),
      700: (parent: 612, name: 'Electron'),
      4321: (parent: 100, name: 'node'),
      4400: (parent: 100, name: 'python'),
      9: (parent: 1, name: 'ab'),
    });
    expect(parseProcessTable('1 0 ${'x' * 100}')[1]!.name, hasLength(64));
  });

  test('MacPortProbe.processTable runs ps with the command column', () async {
    final calls = <String>[];
    final probe = MacPortProbe(
      run: (exe, args, {required timeout}) async {
        calls.add('$exe ${args.join(' ')} ${timeout.inSeconds}');
        return const ProbeOutput(0, '100 1 /bin/zsh\n');
      },
    );
    expect(await probe.processTable(), {100: (parent: 1, name: 'zsh')});
    expect(calls, ['/bin/ps -axo pid=,ppid=,comm= 2']);
  });

  test('WindowsPortProbe.processTable asks CIM for the name too', () async {
    final calls = <List<Object>>[];
    final probe = WindowsPortProbe(
      environment: const {'SystemRoot': r'D:\Win'},
      run: (exe, args, {required timeout}) async {
        calls.add([exe, args, timeout.inSeconds]);
        return const ProbeOutput(0, '4321 100 node.exe\n');
      },
    );
    expect(await probe.processTable(), {4321: (parent: 100, name: 'node')});
    expect(
      calls.single[0],
      r'D:\Win\System32\WindowsPowerShell\v1.0\powershell.exe',
    );
    expect((calls.single[1] as List).last, contains('ParentProcessId,Name'));
    expect(calls.single[2], 5);
  });

  test('ListeningScan.under: ports of processes under the roots, the '
      'roots included; others never (V2-3 D12)', () async {
    // claude (900) → node adapter (901) → npm (902) → vite (903) :5173
    // claude (900) itself :7777; an unrelated server (50) :8080.
    final probe = _Probe(
      {
        903: {5173},
        900: {7777},
        50: {8080},
      },
      {
        900: (parent: 1, name: 'claude'),
        901: (parent: 900, name: 'node'),
        902: (parent: 901, name: 'npm'),
        903: (parent: 902, name: 'node'),
        50: (parent: 1, name: 'nginx'),
      },
    );
    final scan = await ListeningScan.read(probe, probe);
    expect(scan.under({900}), [
      (port: 5173, root: 900, name: 'node'),
      (port: 7777, root: 900, name: 'claude'),
    ]);
    expect(scan.under({}), isEmpty);
    expect(scan.nameOf(8080), 'nginx');
    expect(scan.nameOf(9), '');
    expect(scan.toString(), 'ListeningScan(3)');
  });

  test('ListeningScan.read reads no table when nothing listens', () async {
    final none = _Probe({}, {});
    final scan = await ListeningScan.read(none, none);
    expect(scan.under({1}), isEmpty);
    expect(none.calls, 1);
  });
}
