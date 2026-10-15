import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/ai/domain/ai_words.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// V2-2b: the words of what V2-2b adds to failures and strips.
void main() {
  test('a feature the computer cannot do yet asks to update ShellX there (B1)', () async {
    final vi = await S.load(const Locale('vi'));
    expect(AiWords.failure(vi, 'unsupported'), 'Cập nhật ShellX trên máy tính để dùng phiên AI từ điện thoại.');
  });

  test('B22 strings in both languages', () async {
    final vi = await S.load(const Locale('vi'));
    expect(vi.aiReattached, 'Đã nối lại sau khi ShellX khởi động lại.');
    expect(vi.aiOpenList, 'Mở danh sách phiên');
    final en = await S.load(const Locale('en'));
    expect(en.aiReattached, 'Reconnected after ShellX restarted.');
    expect(en.aiOpenList, 'Open the session list');
  });
}
