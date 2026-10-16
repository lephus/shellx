import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/terminal/agent_status_notifier.dart'
    show agentPaneBadgeProvider;
import 'package:shellx_desktop/src/ui/ai/ai_header.dart';
import 'package:shellx_desktop/src/ui/ai/ai_timeline.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';
import '../../support/ai_semantics.dart';

/// The periodic timers created and cancelled while a body pumps: a clock
/// that ticks in a pane nobody sees is a timer too many.
final class _Timers {
  var _created = 0;
  var _cancelled = 0;

  /// Created and not cancelled yet.
  int get live => _created - _cancelled;

  Future<R> watch<R>(Future<R> Function() body) => runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      createPeriodicTimer: (self, parent, zone, period, f) {
        _created++;
        return _Counted(parent.createPeriodicTimer(zone, period, f), this);
      },
    ),
  );
}

final class _Counted implements Timer {
  _Counted(this._timer, this._timers);

  final Timer _timer;
  final _Timers _timers;
  var _done = false;

  @override
  void cancel() {
    if (!_done) {
      _done = true;
      _timers._cancelled++;
    }
    _timer.cancel();
  }

  @override
  bool get isActive => _timer.isActive;

  @override
  int get tick => _timer.tick;
}

/// V2-1 §4.1, smoothness: the header's status and the clocks of the tool
/// cards.
void main() {
  /// [child] in the tab stack of the window: [shown] picks the visible tab.
  Future<ValueNotifier<int>> pumpTab(
    WidgetTester t,
    _Timers timers,
    AiRuntime runtime,
    Widget child,
  ) async {
    final shown = ValueNotifier<int>(0);
    addTearDown(shown.dispose);
    await timers.watch(
      () => pumpAiPart(
        t,
        ValueListenableBuilder<int>(
          valueListenable: shown,
          builder: (context, tab, _) => Semantics(
            container: true,
            label: 'AI pane Claude',
            child: IndexedStack(
              index: tab,
              children: [child, const SizedBox()],
            ),
          ),
        ),
        runtime: runtime,
        overrides: [agentPaneBadgeProvider(-1).overrideWithValue(null)],
      ),
    );
    return shown;
  }

  Widget header({required bool running}) => AiHeader(
    paneId: -1,
    agentName: 'Claude',
    title: 'Fix the login',
    view: (
      phase: running ? AgentPhase.running : AgentPhase.ready,
      needsInput: false,
      started: running
          ? DateTime.now().subtract(const Duration(seconds: 75))
          : null,
      stopping: false,
    ),
    onTerminal: () {},
    onMore: (_) {},
  );

  AiRuntime newRuntime() => partRuntime(FakeAiRuntimes(const FakeScenario()));

  testWidgets('the status is a live region of its own, "Running", read once: '
      'the clock is in no label and the pane is not a live region', (t) async {
    final semantics = t.ensureSemantics();
    final timers = _Timers();
    await pumpTab(t, timers, newRuntime(), header(running: true));
    expect(find.text('Running · 1:15'), findsOneWidget, reason: 'seen');
    expect(liveRegions(t), ['Running']);
    final labels = semanticsDump(t).map((n) => n.label).join('\n');
    expect(labels, isNot(contains('1:15')));
    semantics.dispose();
  });

  testWidgets('the status at rest is a live region of its own too', (t) async {
    final semantics = t.ensureSemantics();
    await pumpTab(t, _Timers(), newRuntime(), header(running: false));
    expect(liveRegions(t), ['Idle']);
    semantics.dispose();
  });

  testWidgets('the 1 Hz clock stops in a hidden pane and runs again when it '
      'shows', (t) async {
    final timers = _Timers();
    final shown = await pumpTab(t, timers, newRuntime(), header(running: true));
    expect(timers.live, 1);
    shown.value = 1;
    await timers.watch(t.pump);
    expect(timers.live, 0, reason: 'hidden');
    await timers.watch(() => t.pump(const Duration(seconds: 5)));
    expect(timers.live, 0);
    shown.value = 0;
    await timers.watch(t.pump);
    expect(timers.live, 1, reason: 'shown again');
  });

  testWidgets('a running tool call ticks only while its pane shows', (t) async {
    final runtime = newRuntime();
    final at = DateTime(2026, 10, 14, 9);
    runtime.state
      ..beginTurn([const TextBlock('go')], at)
      ..applyUpdate(
        ToolCallStarted(
          'x',
          const ToolCallFields(
            title: 'npm test',
            kind: ToolKind.execute,
            status: ToolCallStatus.inProgress,
          ),
        ),
        at,
      );
    final timers = _Timers();
    final shown = await pumpTab(t, timers, runtime, const AiTimeline());
    await timers.watch(t.pump);
    expect(find.textContaining('running · '), findsOneWidget);
    expect(timers.live, 1);
    shown.value = 1;
    await timers.watch(t.pump);
    expect(timers.live, 0, reason: 'hidden');
    shown.value = 0;
    await timers.watch(t.pump);
    expect(timers.live, 1, reason: 'shown again');
  });
}
