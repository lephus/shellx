import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/auth/presentation/widgets/password_text_field.dart';

import '../../../../support/app_harness.dart';

void main() {
  testWidgets('password toggle: the tooltip/semantics label switches after a tap', (tester) async {
    await tester.pumpWidget(localized(Scaffold(body: PasswordTextField(label: 'Mật khẩu'))));

    final toggle = find.byType(IconButton);

    // Hidden by default: the button offers to show the password.
    expect(tester.getSemantics(toggle).tooltip, 'Hiện mật khẩu');

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();

    // Now visible: the button offers to hide it.
    expect(tester.getSemantics(toggle).tooltip, 'Ẩn mật khẩu');
  });
}
