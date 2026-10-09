import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/integrations/pr_status.dart';
import 'package:shellx_desktop/src/integrations/pr_status_parse.dart';
import 'package:shellx_desktop/src/ui/terminal/session_tab_row.dart'
    show prChecksLook;

import '../support/config_workspace.dart';
import '../support/fakes.dart';

String prJson({
  int number = 12,
  String state = 'OPEN',
  bool draft = false,
  String conclusion = 'SUCCESS',
  String url = 'https://github.com/o/r/pull/12',
}) => jsonEncode({
  'number': number,
  'state': state,
  'isDraft': draft,
  'url': url,
  'reviewDecision': '',
  'statusCheckRollup': [
    {'status': 'COMPLETED', 'conclusion': conclusion},
  ],
});

final class _Runner implements GhRunner {
  _Runner(this.answer);
  String answer;
  int calls = 0;

  @override
  Future<GhResult> run(
    String exe,
    List<String> args, {
    required String cwd,
    required Duration timeout,
  }) async {
    calls++;
    return GhResult(0, answer, '');
  }
}

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  Future<({dynamic c, dynamic local, _Runner runner})> boot(
    WidgetTester t, {
    String config = 'pr-status = true\n',
    String answer = '',
    Locale locale = const Locale('en'),
    String? gh = '/bin/gh',
    String branch = 'main',
  }) async {
    final runner = _Runner(answer.isEmpty ? prJson() : answer);
    final w = await pumpConfiguredWorkspace(
      t,
      config: config,
      locale: locale,
      extra: [
        ghRunnerProvider.overrideWithValue(runner),
        ghFinderProvider.overrideWithValue(() async => gh),
        repoRootFinderProvider.overrideWithValue((_) async => '/repo'),
      ],
    );
    w.local.replace(
      w.local.summary(
        w.local.summaries.first.id,
        origin: SessionOrigin.desktop,
        cwd: '/repo',
        gitBranch: branch,
      ),
    );
    await t.pump();
    await t.pump();
    await t.pump();
    return (c: w.container, local: w.local, runner: runner);
  }

  testWidgets('shows #12 and a glyph after the branch; a tap opens the PR', (
    t,
  ) async {
    final r = await boot(t);
    expect(find.byKey(const Key('row.pr')), findsOneWidget);
    expect(find.text('#12'), findsOneWidget);
    expect(
      t.widget<Icon>(find.byKey(const Key('row.pr.glyph'))).icon,
      prChecksLook(PrChecks.passing).icon,
    );
    await t.tap(find.byKey(const Key('row.pr')));
    await t.pump();
    final opener = r.c.read(desktopServicesProvider).urlOpener;
    expect((opener as RecordingUrlOpener).opened, [
      Uri.parse('https://github.com/o/r/pull/12'),
    ]);
    await disposeWorkspace(t, r.c);
  }, variant: mac);

  testWidgets('the row speaks the whole sentence (EN)', (t) async {
    final sem = t.ensureSemantics();
    final r = await boot(t, answer: prJson(conclusion: 'FAILURE'));
    expect(
      find.bySemanticsLabel(RegExp(r'Pull request #12: open, checks failing')),
      findsWidgets,
    );
    sem.dispose();
    await disposeWorkspace(t, r.c);
  }, variant: mac);

  testWidgets('and in Vietnamese', (t) async {
    final sem = t.ensureSemantics();
    final r = await boot(
      t,
      locale: const Locale('vi'),
      answer: prJson(state: 'MERGED', conclusion: 'FAILURE'),
    );
    expect(
      find.bySemanticsLabel(RegExp(r'Pull request #12: đã merge, CI lỗi')),
      findsWidgets,
    );
    sem.dispose();
    await disposeWorkspace(t, r.c);
  }, variant: mac);

  testWidgets('pr-status off (the default): gh is never run, no chip', (
    t,
  ) async {
    final r = await boot(t, config: '');
    await t.pump(const Duration(minutes: 3));
    expect(r.runner.calls, 0);
    expect(find.byKey(const Key('row.pr')), findsNothing);
    await disposeWorkspace(t, r.c);
  }, variant: mac);

  testWidgets('no gh on this computer: nothing runs, nothing shows', (t) async {
    final r = await boot(t, gh: null);
    expect(r.runner.calls, 0);
    expect(find.byKey(const Key('row.pr')), findsNothing);
    await disposeWorkspace(t, r.c);
  }, variant: mac);

  testWidgets('a row too narrow for the branch and the chip drops the chip', (
    t,
  ) async {
    final r = await boot(t, branch: 'feature/a-very-long-branch-name');
    expect(r.runner.calls, 1); // it was looked up
    expect(find.byKey(const Key('row.pr')), findsNothing);
    await disposeWorkspace(t, r.c);
  }, variant: mac);

  testWidgets('privacy: the log never has the branch, number or address', (
    t,
  ) async {
    final lines = <String>[];
    final old = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => lines.add(m ?? '');
    final r = await boot(t, branch: 'zqx');
    final opener = r.c.read(desktopServicesProvider).urlOpener;
    (opener as RecordingUrlOpener).fail = true;
    await t.tap(find.byKey(const Key('row.pr')));
    await t.pump();
    debugPrint = old;
    final all = lines.join('\n');
    expect(all, isNot(contains('zqx')));
    expect(all, isNot(contains('github.com')));
    expect(all, isNot(contains('#12')));
    await disposeWorkspace(t, r.c);
  }, variant: mac);
}
