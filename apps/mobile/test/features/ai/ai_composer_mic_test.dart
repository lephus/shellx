import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_dock.dart';

import '../../support/app_harness.dart';

/// V2-2b B14: the mic of the AI composer.
void main() {
  late TextEditingController text;
  late int taps;

  setUp(() {
    text = TextEditingController();
    taps = 0;
  });

  tearDown(() => text.dispose());

  Future<void> pump(WidgetTester tester, {bool mic = true, bool listening = false, bool canSend = true}) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      localized(
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: AiComposer(
              controller: text,
              agentName: 'Claude',
              canSend: canSend,
              running: false,
              stopping: false,
              canForceStop: false,
              sending: false,
              onSend: () {},
              onStop: () {},
              onForceStop: () {},
              listening: listening,
              onMic: mic ? () => taps++ : null,
            ),
          ),
        ),
      ),
    );
  }

  IconButton micButton(WidgetTester tester) => tester.widget<IconButton>(find.byKey(const Key('ai.mic')));

  testWidgets('no mic without a dictation', (tester) async {
    await pump(tester, mic: false);
    expect(find.byKey(const Key('ai.mic')), findsNothing);
  });

  testWidgets('the mic, plain while it does not hear, filled while it hears; a tap is the page\'s', (tester) async {
    await pump(tester);
    expect(micButton(tester).tooltip, 'Nói tin nhắn');
    await tester.tap(find.byKey(const Key('ai.mic')));
    expect(taps, 1);
    await pump(tester, listening: true);
    expect(micButton(tester).tooltip, 'Dừng nghe');
    expect(find.descendant(of: find.byKey(const Key('ai.mic')), matching: find.byIcon(Icons.mic)), findsOneWidget);
  });

  testWidgets('the mic works while sending is not possible: words wait in the field', (tester) async {
    await pump(tester, canSend: false);
    expect(micButton(tester).onPressed, isNotNull);
  });
}
