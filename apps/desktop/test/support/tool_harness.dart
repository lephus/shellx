import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import 'package:shellx_desktop/src/tools/tool_embed.dart';
import 'package:shellx_desktop/src/tools/tool_entry.dart';
import 'package:shellx_desktop/src/tools/tool_pages.dart';
import 'package:shellx_desktop/src/tools/tool_ports.dart';
import 'package:shellx_desktop/src/tools/tool_registry.dart';

import 'config_workspace.dart';
import 'fake_browser_engine.dart';
import 'fakes.dart';
import 'memory_config_fs.dart';

/// V2-3: scans that find [ports] (pid → ports) and [table].
final class FakeToolProbe implements PortProbe, ProcessTableProbe {
  /// What the scans find; tests fill them.
  final Map<int, Set<int>> ports = {};
  final Map<int, ProgramRow> table = {};
  int scans = 0;

  @override
  Future<Map<int, Set<int>>> listening() async {
    scans++;
    return ports;
  }

  @override
  Future<Map<int, int>> parents() async => const {};

  @override
  Future<Map<int, ProgramRow>> processTable() async => table;
}

final class FakeToolData implements BrowserDataStore {
  int clears = 0;
  @override
  Future<void> clearAll() async => clears++;
}

/// The workspace page with tools: every page's engine is a
/// [FakeBrowserEngine] in [engines] (by tool id; [made] counts them).
final class ToolRig {
  ToolRig({this.coversFlutter = false, this.platform = TargetPlatform.macOS});

  final bool coversFlutter;
  final TargetPlatform platform;
  final engines = <String, FakeBrowserEngine>{};
  final dialogs = <String, BrowserDialogPresenter>{};
  int made = 0;
  final probe = FakeToolProbe();
  final data = FakeToolData();
  final harness = TestHarness(settings: {'onboarding_done': true});
  var _next = 0;

  late ProviderContainer container;

  /// The configuration files (A9): a test writes one and reloads.
  late MemoryConfigFs fs;

  List<Override> get overrides => [
    toolEngineFactoryProvider.overrideWithValue((tool, presenter) {
      made++;
      dialogs[tool.id] = presenter;
      return engines[tool.id] = FakeBrowserEngine(
        key: tool.id,
        coversFlutter: coversFlutter,
      );
    }),
    toolKnockProvider.overrideWithValue((_, _) async => false),
    toolPortProbeProvider.overrideWithValue((ports: probe, table: probe)),
    toolDataStoreProvider.overrideWithValue(data),
    toolPlatformProvider.overrideWithValue(platform),
    toolIdSourceProvider.overrideWithValue(
      () => 'tool${(_next++).toString().padLeft(6, '0')}',
    ),
  ];

  /// The workspace with one tab; [extra] goes with the rig's overrides (an
  /// AI tab's runtimes, say).
  Future<void> pump(
    WidgetTester tester, {
    String config = '',
    List<Override> extra = const [],
  }) async {
    final r = await pumpConfiguredWorkspace(
      tester,
      config: config,
      harness: harness,
      extra: [...overrides, ...extra],
    );
    container = r.container;
    fs = r.fs;
  }

  ToolEntry add(String ws, String url, {String name = ''}) => container
      .read(toolRegistryProvider.notifier)
      .add(ws: ws, name: name, url: url)!;
}
