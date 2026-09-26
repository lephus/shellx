import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/shared/shared.dart';

import '../../support/fake_popup_handler.dart';

class _Probe extends Controller {}

void main() {
  late FakePopupHandler popups;
  late List<String?> logs;
  late DebugPrintCallback originalDebugPrint;

  setUp(() async {
    await S.load(const Locale('vi'));
    popups = FakePopupHandler();
    getIt.registerSingleton<PopupHandler>(popups);
    logs = [];
    originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message);
  });

  tearDown(() async {
    debugPrint = originalDebugPrint;
    await getIt.reset();
  });

  test('guard shows the spec §12 text and never logs the error itself', () async {
    await _Probe().guard(
      () async =>
          throw const ApiException(status: 401, code: 'invalid_credentials', message: 'token=abc123 password=hunter2'),
    );

    expect(popups.errors, ['Email hoặc mật khẩu không đúng.']);
    expect(logs.join('\n'), isNot(contains('hunter2')));
    expect(logs.join('\n'), isNot(contains('abc123')));
  });

  test('ErrorFactory keeps the original error for code and maps the title', () {
    final error = ErrorFactory().fromException(const ApiException(status: 429, code: 'rate_limited', message: 'slow'));
    expect(error.title, 'Thử lại sau ít phút.');
    expect(error.originalError, isA<ApiException>());
    expect(
      ErrorFactory().fromException(const ApiException(status: 0, code: 'network', message: 'x')),
      isA<NetworkError>(),
    );
    expect(ErrorFactory().fromException(StateError('boom')).title, 'Đã có lỗi xảy ra (StateError).');
  });
}
