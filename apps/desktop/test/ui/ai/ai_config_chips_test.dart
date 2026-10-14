import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_agents.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart'
    show settingsStoreProvider;
import 'package:shellx_desktop/src/ui/ai/ai_dock.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';

/// Claude's own `configOptions` (adapter 0.90.0, trimmed).
const _claudeOptions = <Map<String, Object?>>[
  {
    'id': 'mode',
    'name': 'Mode',
    'category': 'mode',
    'type': 'select',
    'currentValue': 'default',
    'options': [
      {'value': 'default', 'name': 'Manual'},
      {'value': 'acceptEdits', 'name': 'Accept edits'},
      {'value': 'plan', 'name': 'Plan'},
      {'value': 'bypassPermissions', 'name': 'Bypass permissions'},
    ],
  },
  {
    'id': 'model',
    'name': 'Model',
    'category': 'model',
    'type': 'select',
    'currentValue': 'opus',
    'options': [
      {'value': 'opus', 'name': 'Opus 5.5'},
      {'value': 'sonnet', 'name': 'Sonnet 5.5'},
    ],
  },
  {
    'id': 'effort',
    'name': 'Effort',
    'category': 'thought_level',
    'type': 'select',
    'currentValue': 'high',
    'options': [
      {'value': 'low', 'name': 'Low'},
      {'value': 'high', 'name': 'High'},
    ],
  },
];

/// V2-1 D11: mode, model and thinking chips.
void main() {
  Future<(FakeAiRuntimes, AiRuntime, ProviderContainer)> dock(
    WidgetTester t,
    FakeScenario scenario,
  ) async {
    final fakes = FakeAiRuntimes(scenario);
    final runtime = partRuntime(fakes);
    await runtime.start();
    final part = await pumpAiPart(t, const AiDock(), runtime: runtime);
    return (fakes, runtime, part.container);
  }

  Future<void> pick(WidgetTester t, String chip, String value) async {
    await t.tap(find.byKey(Key('ai.config.$chip')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key('ai.config.$chip.$value')).last);
    await t.pumpAndSettle();
  }

  testWidgets('Claude\'s mode in the app\'s words, the model, the thinking; '
      'a choice goes to the agent and is remembered', (t) async {
    final (fakes, runtime, c) = await dock(
      t,
      const FakeScenario(configOptions: _claudeOptions),
    );
    expect(find.text('Ask first'), findsOneWidget);
    expect(find.text('Model: Opus 5.5'), findsOneWidget);
    expect(find.text('Thinking: High'), findsOneWidget);
    await pick(t, 'model', 'sonnet');
    expect(
      fakes.agent().received,
      contains('session/set_config_option:model=sonnet'),
    );
    expect(find.text('Model: Sonnet 5.5'), findsOneWidget);
    expect(rememberedConfig(c.read(settingsStoreProvider), 'claude'), {
      'model': 'sonnet',
    });
    await runtime.dispose();
  });

  testWidgets('"Bypass permissions" asks first (Cancel changes nothing), '
      'and is never remembered (R6)', (t) async {
    final (fakes, runtime, c) = await dock(
      t,
      const FakeScenario(configOptions: _claudeOptions),
    );
    await pick(t, 'mode', 'bypassPermissions');
    expect(find.text('Turn on “Bypass permissions”?'), findsOneWidget);
    expect(
      find.text('Claude will edit files and run commands without asking.'),
      findsOneWidget,
    );
    await t.tap(find.byKey(const Key('ai.bypass.cancel')));
    await t.pumpAndSettle();
    expect(
      fakes.agent().received.where((r) => r.startsWith('session/set_config')),
      isEmpty,
    );
    await pick(t, 'mode', 'bypassPermissions');
    await t.tap(find.byKey(const Key('ai.bypass.on')));
    await t.pumpAndSettle();
    expect(
      fakes.agent().received,
      contains('session/set_config_option:mode=bypassPermissions'),
    );
    expect(find.text('Bypass permissions'), findsOneWidget);
    expect(rememberedConfig(c.read(settingsStoreProvider), 'claude'), isEmpty);
    await runtime.dispose();
  });

  testWidgets('an agent with legacy modes only: session/set_mode', (t) async {
    final (fakes, runtime, _) = await dock(
      t,
      const FakeScenario(
        modes: {
          'currentModeId': 'ask',
          'availableModes': [
            {'id': 'ask', 'name': 'Ask'},
            {'id': 'code', 'name': 'Code'},
          ],
        },
      ),
    );
    expect(find.text('Ask'), findsOneWidget);
    await pick(t, 'mode', 'code');
    expect(fakes.agent().received, contains('session/set_mode:code'));
    expect(find.text('Code'), findsOneWidget);
    await runtime.dispose();
  });
}
