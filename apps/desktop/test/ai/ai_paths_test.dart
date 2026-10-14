import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shellx_desktop/src/ai/ai_paths.dart';
import 'package:shellx_desktop/src/ai/ai_startup.dart';

void main() {
  const roaming = r'C:\Users\me\AppData\Roaming\pro.shellx\ShellX';
  const macSupport = '/Users/me/Library/Application Support/pro.shellx.desktop';

  test('macOS: the app support folder, as before', () {
    expect(
      aiSupportDirectoryPath(
        windows: false,
        environment: const {'LOCALAPPDATA': r'C:\ignored'},
        appSupportPath: macSupport,
      ),
      macSupport,
    );
  });

  test(
    r'Windows: %LOCALAPPDATA%\ShellX, never the roaming folder (D6, D12)',
    () {
      final path = aiSupportDirectoryPath(
        windows: true,
        environment: const {
          'LOCALAPPDATA': r'C:\Users\me\AppData\Local',
          'APPDATA': r'C:\Users\me\AppData\Roaming',
        },
        appSupportPath: roaming,
      );
      expect(path, r'C:\Users\me\AppData\Local\ShellX');
      expect(path, isNot(contains('Roaming')));
    },
  );

  test('Windows without LOCALAPPDATA: the app support folder, so the AI '
      'tab still works', () {
    for (final environment in [
      const <String, String>{},
      const {'LOCALAPPDATA': ''},
    ]) {
      expect(
        aiSupportDirectoryPath(
          windows: true,
          environment: environment,
          appSupportPath: roaming,
        ),
        roaming,
      );
    }
  });

  test('the host keeps agents, restore points and running.json under '
      '<folder>/ai', () {
    const folder = '/data/ShellX';
    final host = buildAiHost(supportDir: folder, version: '2.0.0');
    expect(host.supportDir, folder);
    expect(host.resolver.agentsDir, p.join(folder, 'ai', 'agents'));
    expect(host.checkpoints.root, p.join(folder, 'ai', 'checkpoints'));
    expect(host.running.file.path, p.join(folder, 'ai', 'running.json'));
  });
}
