import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/shared/shared.dart';

import '../support/app_harness.dart';

void main() {
  testWidgets('ShellxLogo: one semantics node labelled "ShellX"; the glyph is not read character by character', (
    tester,
  ) async {
    await tester.pumpWidget(localized(const Scaffold(body: ShellxLogo())));

    expect(find.bySemanticsLabel('ShellX'), findsOneWidget);
    expect(find.bySemanticsLabel('›_'), findsNothing);
  });
}
