import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/shared/shared.dart';

ApiException apiError(int status, String code) => ApiException(status: status, code: code, message: code);

void main() {
  // intl_utils' S reads the process-wide locale set by the last S.load, so each group loads its own.
  group('Vietnamese', () {
    late ErrorText vi;
    setUp(() async => vi = ErrorText(await S.load(const Locale('vi'))));

    test('spec §5.3/§12 pairing texts, verbatim', () {
      expect(
        vi.pairing(PairingFailure.notInAccount),
        'Máy này không thuộc tài khoản của bạn. Hãy đăng nhập cùng tài khoản trên máy tính.',
      );
      expect(
        vi.pairing(PairingFailure.invalidOrExpired),
        'Mã QR không hợp lệ hoặc đã hết hạn. Hãy tạo mã mới trên máy tính.',
      );
      expect(vi.pairing(PairingFailure.protocolUnsupported), 'Cần cập nhật app');
    });

    test('spec §12 machine connection texts', () {
      expect(vi.machine(MachineConnectionFailure.untrusted), 'Máy không còn tin cậy điện thoại này. Hãy ghép nối lại.');
      expect(vi.machine(MachineConnectionFailure.protocolUnsupported), 'Cần cập nhật app');
      expect(vi.machine(MachineConnectionFailure.agentOffline), 'Máy đang offline.');
    });

    test('spec §12 session errors; spawn_failed shows the reason', () {
      expect(vi.appError(AppErrorCode.sessionLimit, 'x'), 'Máy đã mở tối đa 10 phiên. Hãy đóng bớt phiên.');
      expect(vi.appError(AppErrorCode.sessionNotFound, 'x'), 'Phiên đã kết thúc');
      expect(vi.appError(AppErrorCode.spawnFailed, 'pwsh.exe not found'), 'Không mở được shell: pwsh.exe not found');
    });

    test('HTTP 429 always maps to "Thử lại sau ít phút."', () {
      expect(vi.api(apiError(429, 'rate_limited')), 'Thử lại sau ít phút.');
      expect(vi.api(apiError(429, 'anything')), 'Thử lại sau ít phút.');
    });

    test('account error codes of spec §10.2', () {
      expect(vi.api(apiError(401, 'invalid_credentials')), 'Email hoặc mật khẩu không đúng.');
      expect(vi.api(apiError(409, 'email_taken')), 'Email này đã được đăng ký.');
      expect(vi.api(apiError(400, 'invalid_email')), 'Email không hợp lệ.');
      expect(vi.api(apiError(400, 'disposable_email')), 'Email tạm thời không dùng được. Hãy dùng email thật.');
      expect(vi.api(apiError(400, 'weak_password')), 'Mật khẩu phải có 8–128 ký tự.');
      expect(vi.api(apiError(0, 'network')), 'Không kết nối được máy chủ. Hãy kiểm tra mạng rồi thử lại.');
      expect(vi.api(apiError(401, 'unauthorized')), 'Phiên đăng nhập đã hết hiệu lực. Hãy đăng nhập lại.');
      expect(vi.api(apiError(500, 'internal')), 'Đã có lỗi xảy ra (internal).');
    });

    test('describe dispatches on the error type', () {
      expect(vi.describe(const PairingException(PairingFailure.timeout)), 'Máy tính không phản hồi. Hãy thử lại.');
      expect(
        vi.describe(const AppErrorException(AppErrorCode.sessionLimit, 'limit')),
        'Máy đã mở tối đa 10 phiên. Hãy đóng bớt phiên.',
      );
      expect(
        vi.describe(const MachineFailed(MachineConnectionFailure.untrusted)),
        'Máy không còn tin cậy điện thoại này. Hãy ghép nối lại.',
      );
      expect(vi.describe(const MachineConnectionException(MachineConnectionFailure.agentOffline)), 'Máy đang offline.');
      expect(vi.describe(StateError('boom')), 'Đã có lỗi xảy ra (StateError).');
    });
  });

  group('English', () {
    late ErrorText en;
    setUp(() async => en = ErrorText(await S.load(const Locale('en'))));

    test('equivalent texts', () {
      expect(
        en.pairing(PairingFailure.invalidOrExpired),
        'The QR code is invalid or has expired. Create a new code on your computer.',
      );
      expect(
        en.machine(MachineConnectionFailure.untrusted),
        'This computer no longer trusts this phone. Please pair again.',
      );
      expect(en.appError(AppErrorCode.sessionNotFound, 'x'), 'Session ended');
      expect(en.api(apiError(429, 'rate_limited')), 'Try again in a few minutes.');
    });
  });
}
