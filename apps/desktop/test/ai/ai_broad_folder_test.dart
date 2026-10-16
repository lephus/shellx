import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_off_thread.dart';
import 'package:shellx_desktop/src/ai/ai_open.dart';
import 'package:shellx_desktop/src/ai/ai_project_files.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart'
    show homeDirectoryProvider;
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../cli/support/cli_container.dart';
import '../support/ai_fakes.dart';
import '../support/ai_tabs.dart';
import '../support/fake_local_sessions.dart';

/// V2-1b final review I-1: a home folder, a folder above it and a disk root
/// are no project. "New AI session" never takes one from the tab in front,
/// and `@` never walks one.
void main() {
  const home = '/Users/phu';

  group('"New AI session" from the tab in front', () {
    late ProviderContainer c;
    late FakeLocalSessions local;
    late FakeAiRuntimes fakes;

    void boot() {
      fakes = FakeAiRuntimes(const FakeScenario());
      local = FakeLocalSessions();
      c = cliContainer(
        local,
        overrides: [
          ...fakes.overrides,
          homeDirectoryProvider.overrideWithValue(home),
        ],
      );
    }

    /// A shell tab in front whose directory is [cwd].
    Future<void> shellAt(String cwd) async {
      await c.read(terminalTabsProvider.notifier).openTab();
      local.setCwd(local.summaries.last.id, cwd);
      await pumpEventQueue();
    }

    String? newSessionFolder({String? workspaceId}) {
      final id = c.read(aiOpenerProvider).newSession(workspaceId: workspaceId)!;
      return c
          .read(terminalTabsProvider)
          .tabs
          .firstWhere((t) => t.id == id)
          .ai!
          .cwd;
    }

    test('a shell sitting in the home folder is no project: the pane asks '
        'for a folder', () async {
      boot();
      await shellAt(home);
      expect(newSessionFolder(), isNull);
    });

    test('nor is the home folder written another way, a folder above it or '
        'a disk root', () async {
      boot();
      for (final folder in ['/Users/phu/', '/Users/phu/./', '/Users', '/']) {
        await shellAt(folder);
        expect(newSessionFolder(), isNull, reason: folder);
      }
    });

    test('a project inside the home folder is kept', () async {
      boot();
      await shellAt('/Users/phu/code/app');
      expect(newSessionFolder(), '/Users/phu/code/app');
      // A folder beside home (a name that merely starts alike) is a project.
      await shellAt('/Users/phuong/app');
      expect(newSessionFolder(), '/Users/phuong/app');
    });

    test('an AI tab in front that works in the home folder is no project '
        'either', () async {
      boot();
      openTestAiTab(c, cwd: home);
      expect(newSessionFolder(), isNull);
      openTestAiTab(c, cwd: '/Users/phu/code/app');
      expect(newSessionFolder(), '/Users/phu/code/app');
    });

    test('a workspace\'s own project root is the user\'s choice and is '
        'kept, even the home folder', () async {
      boot();
      await shellAt('/Users/phu/code/app');
      c
          .read(sidebarWorkspacesProvider.notifier)
          .setRoot(kDefaultWorkspaceId, home);
      expect(newSessionFolder(), home);
    });

    test('a new session for another workspace does not take the front '
        'tab\'s folder: that tab belongs to a different project', () async {
      boot();
      await shellAt('/Users/phu/code/app');
      // The front tab's own workspace takes it.
      expect(newSessionFolder(), '/Users/phu/code/app');
      final other = c.read(sidebarWorkspacesProvider.notifier).createFor();
      expect(
        newSessionFolder(workspaceId: other),
        isNull,
        reason: 'a tab of another workspace is not this workspace\'s project',
      );
    });
  });

  group('the "@" index', () {
    late Directory tmp;
    late String homeDir;
    var runs = 0;

    Future<R> counted<Q, R>(R Function(Q input) work, Q input) async {
      runs++;
      // Even a broken guard must not crawl this computer's disk.
      if (input == '/') throw StateError('the disk root was walked');
      return work(input);
    }

    setUp(() {
      runs = 0;
      tmp = Directory.systemTemp.createTempSync('ai_broad');
      addTearDown(() => tmp.deleteSync(recursive: true));
      homeDir = p.join(tmp.path, 'home');
      for (final rel in [
        'home/notes.txt',
        'home/Documents/report.txt',
        'home/code/app/lib/main.dart',
        'home/code/app/README.md',
        'other/readme.md',
      ]) {
        File(p.join(tmp.path, rel))
          ..createSync(recursive: true)
          ..writeAsStringSync('x');
      }
    });

    DiskProjectFiles files() =>
        DiskProjectFiles(counted, home: homeDir, isWindows: false);

    test('the home folder is not walked: the picker offers nothing, and '
        'nothing even runs', () async {
      expect(await files().index(homeDir), isEmpty);
      expect(runs, 0, reason: 'skipped, not walked and thrown away');
    });

    test('a folder above the home folder, and a disk root, are not walked '
        'either', () async {
      expect(await files().index(tmp.path), isEmpty);
      expect(await files().index('/'), isEmpty);
      expect(runs, 0);
    });

    test('a project inside the home folder is indexed as before', () async {
      final index = await files().index(p.join(homeDir, 'code', 'app'));
      expect(index, ['README.md', 'lib/main.dart']);
      expect(runs, 1);
    });

    test('a folder beside the home folder is indexed', () async {
      expect(await files().index(p.join(tmp.path, 'other')), ['readme.md']);
    });

    test('the Files panel still lists the home folder, one level at a time '
        '(the user opens it)', () async {
      final entries = await files().list(homeDir, '');
      expect(entries.map((e) => e.path), ['code', 'Documents', 'notes.txt']);
    });

    test(
      'the app\'s provider walks nothing in the home folder it is given',
      () async {
        final c = ProviderContainer.test(
          overrides: [
            aiOffThreadProvider.overrideWithValue(counted),
            homeDirectoryProvider.overrideWithValue(homeDir),
          ],
        );
        final files = c.read(aiProjectFilesProvider);
        expect(await files.index(homeDir), isEmpty);
        expect(runs, 0);
        expect(await files.index(p.join(homeDir, 'code', 'app')), isNotEmpty);
      },
    );
  });
}
