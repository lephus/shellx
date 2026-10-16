import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'fake_agent.dart';

/// Arguments for `Platform.resolvedExecutable` (the Dart VM running the
/// test) that start `bin/fake_agent.dart` with [scenarioFile].
List<String> fakeAgentArgs(String scenarioFile) {
  final lib = Isolate.resolvePackageUriSync(
    Uri.parse('package:shellx_acp/testing.dart'),
  );
  if (lib == null) throw StateError('package:shellx_acp cannot be resolved');
  final config = Isolate.packageConfigSync;
  return [
    if (config != null) '--packages=${config.toFilePath()}',
    lib.resolve('../bin/fake_agent.dart').toFilePath(),
    scenarioFile,
  ];
}

/// Writes [scenario] as JSON into [dir]; returns the file's path.
String writeScenario(
  FakeScenario scenario,
  Directory dir, [
  String name = 'scenario.json',
]) => (File(
  '${dir.path}${Platform.pathSeparator}$name',
)..writeAsStringSync(jsonEncode(scenario.toJson()))).path;
