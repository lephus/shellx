import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal_sharing/powershell.dart';

String output(String profile, String effective, Map<String, String> scopes) => [
  profile,
  effective,
  for (final e in scopes.entries) '${e.key}=${e.value}',
].join('\r\n');

const Map<String, String> undefinedScopes = {
  'MachinePolicy': 'Undefined',
  'UserPolicy': 'Undefined',
  'Process': 'Undefined',
  'CurrentUser': 'Undefined',
  'LocalMachine': 'Undefined',
};

void main() {
  group('parse', () {
    test('RemoteSigned: profiles run', () {
      final install = PowerShellProbe.parse(
        'PowerShell 7',
        'pwsh.exe',
        output(
          r'C:\Users\Phú\OneDrive\Documents\PowerShell\profile.ps1',
          'RemoteSigned',
          undefinedScopes,
        ),
      )!;
      expect(
        install.profilePath,
        r'C:\Users\Phú\OneDrive\Documents\PowerShell\profile.ps1',
      );
      expect(install.policy, ScriptPolicy.allowed);
    });

    for (final effective in ['Restricted', 'AllSigned']) {
      test('$effective without Group Policy: fixable', () {
        final install = PowerShellProbe.parse(
          'Windows PowerShell',
          'powershell.exe',
          output(
            r'C:\Users\a\Documents\WindowsPowerShell\profile.ps1',
            effective,
            undefinedScopes,
          ),
        )!;
        expect(install.policy, ScriptPolicy.blocked);
      });
    }

    test('Restricted set by Group Policy: cannot be changed', () {
      final install = PowerShellProbe.parse(
        'Windows PowerShell',
        'powershell.exe',
        output(
          r'C:\Users\a\Documents\WindowsPowerShell\profile.ps1',
          'AllSigned',
          {...undefinedScopes, 'MachinePolicy': 'AllSigned'},
        ),
      )!;
      expect(install.policy, ScriptPolicy.blockedByGroupPolicy);
    });

    test('unexpected output is ignored', () {
      expect(PowerShellProbe.parse('x', 'x', ''), isNull);
      expect(PowerShellProbe.parse('x', 'x', 'garbage\nRemoteSigned'), isNull);
    });
  });

  group('find / allowLocalScripts', () {
    test('asks each installed PowerShell, skips a missing one', () async {
      final calls = <(String, List<String>)>[];
      final probe = PowerShellProbe(
        environment: {'SystemRoot': r'C:\Windows'},
        run: (exe, args) async {
          calls.add((exe, args));
          if (exe == 'pwsh.exe') {
            throw const ProcessException('pwsh.exe', [], 'not found');
          }
          return ProcessResult(
            1,
            0,
            output(
              r'C:\Users\a\Documents\WindowsPowerShell\profile.ps1',
              'Restricted',
              undefinedScopes,
            ),
            '',
          );
        },
      );
      final found = await probe.find();
      expect(found.single.name, 'Windows PowerShell');
      expect(
        found.single.executable,
        r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
      );
      expect(found.single.policy, ScriptPolicy.blocked);
      expect(
        calls.first.$2,
        containsAll(['-NoProfile', '-NonInteractive', '-Command']),
      );
      // Never changes the policy on its own.
      expect(
        calls.any((c) => c.$2.last.contains('Set-ExecutionPolicy')),
        isFalse,
      );
    });

    test('a PowerShell that fails is left out', () async {
      final probe = PowerShellProbe(
        environment: const {},
        run: (exe, args) async => ProcessResult(1, 1, '', 'boom'),
      );
      expect(await probe.find(), isEmpty);
    });

    test(
      'allowLocalScripts sets RemoteSigned for the current user only',
      () async {
        final calls = <List<String>>[];
        final probe = PowerShellProbe(
          environment: const {},
          run: (exe, args) async {
            calls.add(args);
            return ProcessResult(1, 0, '', '');
          },
        );
        const install = PowerShellInstall(
          name: 'Windows PowerShell',
          executable: 'powershell.exe',
          profilePath: r'C:\p.ps1',
          policy: ScriptPolicy.blocked,
        );
        expect(await probe.allowLocalScripts(install), isTrue);
        expect(
          calls.single.last,
          'Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force',
        );
      },
    );
  });
}
