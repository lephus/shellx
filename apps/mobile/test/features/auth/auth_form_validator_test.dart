import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/auth/domain/auth_form_validator.dart';
import 'package:shellx_mobile/shared/shared.dart';

void main() {
  final validator = AuthFormValidator();

  setUpAll(() => S.load(const Locale('vi')));

  test('email: format only, with the spec text', () {
    expect(validator.validateEmail('  me@example.com '), isNull);
    expect(validator.validateEmail('not-an-email'), 'Email không hợp lệ.');
    expect(validator.validateEmail(''), 'Email không hợp lệ.');
  });

  test('new password: 8–128 characters and no other rule (spec §5.2)', () {
    expect(validator.validateNewPassword('a' * 7), 'Mật khẩu phải có 8–128 ký tự.');
    expect(validator.validateNewPassword('a' * 8), isNull);
    expect(validator.validateNewPassword('long enough'), isNull); // no case or digit rules
    expect(validator.validateNewPassword('a' * 128), isNull);
    expect(validator.validateNewPassword('a' * 129), 'Mật khẩu phải có 8–128 ký tự.');
    expect(validator.validateNewPassword(null), 'Mật khẩu phải có 8–128 ký tự.');
  });

  test('sign-in password: only required', () {
    expect(validator.validatePassword('x'), isNull);
    expect(validator.validatePassword(''), 'Cần nhập mật khẩu');
  });
}
