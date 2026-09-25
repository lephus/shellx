import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/shared/shared.dart';

import '../support/app_harness.dart';

void main() {
  testWidgets('StatusCircle: decorative next to its text, excluded from semantics', (tester) async {
    await tester.pumpWidget(localized(const Scaffold(body: StatusCircle(icon: Icons.check))));

    expect(find.ancestor(of: find.byType(Icon), matching: find.byType(ExcludeSemantics)), findsOneWidget);
  });
}
