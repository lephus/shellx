import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/ai/domain/ai_drafts.dart';

/// V2-2 §5.2: what the user typed in a session's text field is kept, in memory and per session, so a page
/// left and opened again finds it.
void main() {
  test('a draft is found again for the same session, and only for it', () {
    final drafts = AiDrafts();
    expect(drafts.of('e.-1'), isEmpty);
    drafts.keep('e.-1', 'Thêm nút đăng xuất');
    drafts.keep('e.-2', 'việc khác');
    expect(drafts.of('e.-1'), 'Thêm nút đăng xuất');
    expect(drafts.of('e.-2'), 'việc khác');
    expect(drafts.of('e.-3'), isEmpty);
  });

  test('the latest text replaces the draft; an empty one (a message sent) removes it', () {
    final drafts = AiDrafts();
    drafts.keep('e.-1', 'một');
    drafts.keep('e.-1', 'một hai');
    expect(drafts.of('e.-1'), 'một hai');
    drafts.keep('e.-1', '');
    expect(drafts.of('e.-1'), isEmpty);
    drafts.keep('e.-1', '  \n ');
    expect(drafts.of('e.-1'), isEmpty, reason: 'spaces are not a draft');
  });

  test('a few drafts are kept, the least recently written goes first', () {
    final drafts = AiDrafts();
    for (var i = 0; i < AiDrafts.capacity; i++) {
      drafts.keep('s$i', 'bản nháp $i');
    }
    drafts.keep('s0', 'bản nháp 0, viết lại'); // the oldest is written again: it is the newest now
    drafts.keep('new', 'một phiên nữa');
    expect(drafts.of('s0'), 'bản nháp 0, viết lại');
    expect(drafts.of('s1'), isEmpty, reason: 'the least recently written was dropped');
    expect(drafts.of('s2'), 'bản nháp 2');
    expect(drafts.of('new'), 'một phiên nữa');
  });

  test('a text far beyond what a phone may send (a 1 MB paste) is not kept', () {
    final drafts = AiDrafts();
    drafts.keep('e.-1', 'x' * AiDrafts.maxChars);
    expect(drafts.of('e.-1').length, AiDrafts.maxChars);
    drafts.keep('e.-1', 'x' * (AiDrafts.maxChars + 1));
    expect(drafts.of('e.-1'), isEmpty);
  });
}
