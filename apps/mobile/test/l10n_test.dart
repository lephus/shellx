import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/shared/shared.dart';

import 'support/app_harness.dart';

Set<String> messageKeys(String path) {
  final json = jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
  return json.keys.where((key) => !key.startsWith('@')).toSet();
}

void main() {
  test('Vietnamese and English ARB files define the same messages', () {
    expect(messageKeys('lib/l10n/intl_vi.arb'), messageKeys('lib/l10n/intl_en.arb'));
  });

  test('the generated strings are fresh: every ARB key has a getter in S', () {
    final generated = File('lib/shared/src/l10n.dart').readAsStringSync();
    for (final key in messageKeys('lib/l10n/intl_en.arb')) {
      expect(generated, contains("name: '$key'"), reason: key);
    }
  });

  test('exactly English and Vietnamese are supported', () {
    expect(S.delegate.supportedLocales.map((locale) => locale.languageCode), unorderedEquals(['en', 'vi']));
  });

  test('spec texts and plurals in both languages', () async {
    final vi = await S.load(const Locale('vi'));
    expect(vi.bannerReconnecting, 'Mất kết nối, đang thử lại…');
    expect(vi.lastSeenMinutes(5), '5 phút trước');
    final en = await S.load(const Locale('en'));
    expect(en.bannerReconnecting, 'Connection lost, retrying…');
    expect(en.lastSeenMinutes(1), '1 minute ago');
    expect(en.lastSeenMinutes(5), '5 minutes ago');
  });

  test('terminal sharing texts (spec §9) in both languages', () async {
    final vi = await S.load(const Locale('vi'));
    expect(vi.pickerDesktopGroup, 'Terminal trên máy tính');
    expect(vi.pickerShellxGroup, 'Phiên ShellX');
    expect(vi.pickerNewSession, 'Phiên mới');
    expect(
      vi.pickerHintSharingOff,
      "Bật 'Chia sẻ terminal với điện thoại' trong menu ShellX trên máy tính để xem các terminal đang mở ở đây.",
    );
    expect(vi.pickerHintUpdateDesktop, 'Cập nhật ShellX trên máy tính để xem các terminal đang mở.');
    expect(
      vi.pickerHintOpenNewWindow,
      'Chỉ các cửa sổ terminal mở sau khi bật chia sẻ mới hiện ở đây. Mở một cửa sổ terminal mới trên máy tính.',
    );
    expect(vi.desktopStillRunning, 'Terminal vẫn chạy trên máy tính.');
    expect(vi.desktopDriverBanner, 'Máy tính đang dùng terminal này');
    expect(vi.desktopWindowClosed, 'Cửa sổ terminal trên máy tính đã đóng.');
    expect(vi.desktopTerminalGone, 'Mất kết nối với terminal này trên máy tính.');
    expect(vi.desktopClosedByHost, 'Máy tính đã ngắt điện thoại khỏi terminal này.');
    expect(vi.desktopTerminalLabel, 'Terminal trên máy tính');
    final en = await S.load(const Locale('en'));
    expect(en.pickerDesktopGroup, 'Terminals on the computer');
    expect(en.pickerShellxGroup, 'ShellX sessions');
    expect(en.pickerNewSession, 'New session');
    expect(
      en.pickerHintSharingOff,
      "Turn on 'Share terminals with phone' in the ShellX menu on the computer to see its open terminals here.",
    );
    expect(en.pickerHintUpdateDesktop, 'Update ShellX on the computer to see its open terminals.');
    expect(
      en.pickerHintOpenNewWindow,
      'Only terminal windows opened after sharing was turned on show up here. '
      'Open a new terminal window on the computer.',
    );
    expect(en.desktopTerminalLabel, 'Terminal on the computer');
    expect(en.desktopStillRunning, 'The terminal is still running on the computer.');
    expect(en.desktopDriverBanner, 'The computer is using this terminal');
    expect(en.desktopWindowClosed, 'The terminal window on the computer was closed.');
    expect(en.desktopTerminalGone, 'Lost the connection to this terminal on the computer.');
    expect(en.desktopClosedByHost, 'The computer disconnected this phone from this terminal.');
  });

  test('the picker hint names the desktop switch as its tray item does (P4)', () async {
    final vi = await S.load(const Locale('vi'));
    expect(vi.pickerHintSharingOff, contains("'Chia sẻ terminal với điện thoại'"));
    final en = await S.load(const Locale('en'));
    expect(en.pickerHintSharingOff, contains("'Share terminals with phone'"));
  });

  test('push notification texts (push spec §6) in both languages', () async {
    final vi = await S.load(const Locale('vi'));
    expect(vi.settingsNotificationsGroup, 'Thông báo');
    expect(vi.settingsNotificationsOff, 'Đang tắt');
    expect(vi.settingsNotificationsOpenSystem, 'Mở Cài đặt hệ thống');
    final en = await S.load(const Locale('en'));
    expect(en.settingsNotificationsGroup, 'Notifications');
    expect(en.settingsNotificationsOff, 'Off');
    expect(en.settingsNotificationsOpenSystem, 'Open system settings');
  });

  test('AI session texts (V2-2 §5.5) in Vietnamese', () async {
    final vi = await S.load(const Locale('vi'));
    expect(vi.aiGroup, 'Phiên AI');
    expect([vi.aiNewSession, vi.aiUntitled], ['Phiên AI mới', 'Phiên AI mới']);
    expect(vi.aiUnavailable, 'Mở ShellX trên máy tính để dùng phiên AI.');
    expect(vi.aiUpdateDesktop, 'Cập nhật ShellX trên máy tính để dùng phiên AI từ điện thoại.');
    expect(vi.aiComposerHint('Claude'), 'Nhắn cho Claude…');
    expect(
      [vi.aiSend, vi.aiQueue, vi.aiStop, vi.aiStopping, vi.aiForceStop],
      ['Gửi', 'Xếp hàng', 'Dừng', 'Đang dừng…', 'Dừng hẳn'],
    );
    expect(vi.aiReconnecting, 'Đang kết nối lại… nội dung có thể chưa mới nhất.');
    expect(vi.aiClosedGone, 'Phiên AI này đã đóng trên máy tính.');
    expect(vi.aiClosedDesktop, 'ShellX trên máy tính đã thoát. Mở ShellX trên máy tính rồi mở lại phiên.');
    expect(vi.aiClosedUnreadable, 'Điện thoại không đọc được phiên AI này. Xem trên máy tính.');
    expect(vi.aiPermTitle('Claude'), 'Claude xin quyền:');
    expect(
      [vi.aiPermAllowOnce, vi.aiPermAllowAlways, vi.aiPermRejectOnce, vi.aiPermRejectAlways],
      ['Cho phép', 'Luôn cho phép', 'Từ chối', 'Luôn từ chối'],
    );
    expect(vi.aiPermOnComputer, 'Trả lời yêu cầu này trên máy tính.');
    expect(vi.aiAnsweredElsewhere, 'Đã được trả lời ở thiết bị khác.');
    expect(vi.aiYouChose('Cho phép (Yes)'), 'Bạn chọn: Cho phép (Yes)');
    expect(vi.aiAskOnComputer, 'Trả lời câu hỏi này trên máy tính.');
    expect(vi.aiTurnSummary(3, '0:41'), 'Lượt 3 · 0:41');
    expect([vi.aiTurnFiles(1), vi.aiTurnFiles(2)], ['1 tệp đổi', '2 tệp đổi']);
    expect(vi.aiFromComputerOnly, 'Quá lớn để xem trên điện thoại. Xem trên máy tính.');
    expect(vi.aiItemOnComputer, 'Điện thoại chưa hỗ trợ loại mục này. Xem trên máy tính.');
    expect(vi.aiTooLong(32), 'Quá dài để gửi từ điện thoại (tối đa 32 KB).');
    expect(vi.aiRowSubtitle('Claude', 'Đang chạy'), 'Claude · Đang chạy');
    expect(vi.aiCutLines(120), '120 dòng; phần giữa xem trên máy tính');
    expect([vi.aiMoreDiffs(1), vi.aiMoreDiffs(2)], ['+1 tệp nữa', '+2 tệp nữa']);
    expect(vi.aiPermMore(2), 'còn 2 yêu cầu');
    expect(vi.aiContext(16), 'Ngữ cảnh 16%');
    expect(vi.aiPlan(2, 5), 'Kế hoạch · 2/5');
    expect(vi.aiToolRunningFor('2:05'), 'đang chạy · 2:05');
    expect(vi.aiNoticeNode('Claude', 20), 'Claude cần máy tính có Node.js 20 trở lên.');
    expect(vi.aiToolDelete('old.ts'), 'Xóa old.ts');
    expect(vi.aiAskCancelled, 'Đã hủy');
    // The desktop's own page names: Cài đặt › Agent, Cài đặt › Dự án (and no "workspace", which it never shows).
    expect(vi.aiNewNoAgents, 'Chưa có agent nào sẵn sàng trên máy tính. Hãy thiết lập trong Cài đặt › Agent.');
    expect(vi.aiNewNoFolders, 'Hãy đặt thư mục cho một dự án trên máy tính trước (Cài đặt › Dự án).');
    expect([vi.aiStateClosed, vi.aiToolDone], ['Đã đóng', 'xong']);
    expect(
      vi.aiOpenOutcomeUnknown,
      'Có thể phiên mới chưa được tạo. Hãy xem lại danh sách trước khi thử lại.',
    );
    expect(vi.aiNoticeExited('Claude', 1), 'Claude dừng bất ngờ (mã thoát 1).');
    expect(vi.aiRequestFailed('refused'), 'Máy tính không nhận (refused).');
    expect(vi.aiRefused, 'Máy tính không nhận yêu cầu này.');
    expect(vi.aiBusy, 'Quá nhiều yêu cầu cùng lúc. Chờ một lát rồi thử lại.');
    expect(vi.aiPermOption, 'Lựa chọn');
    expect(vi.aiNoticeUndoOff, 'Hoàn tác đang tắt cho dự án này.');
    expect(vi.aiNoticeUndoOffReason('không tìm thấy git'), 'Hoàn tác đang tắt cho dự án này (không tìm thấy git).');
    expect(vi.aiNoticeUndoOffTurn('git cũ hơn 2.26'), 'Hoàn tác đang tắt cho lượt này (git cũ hơn 2.26).');
    expect(vi.aiUndoBroadFolder, 'thư mục này là thư mục home hoặc gốc ổ đĩa');
  });

  test('AI session texts (V2-2 §5.5) in English', () async {
    final en = await S.load(const Locale('en'));
    expect(en.aiGroup, 'AI sessions');
    expect([en.aiNewSession, en.aiUntitled], ['New AI session', 'New AI session']);
    expect(en.aiUnavailable, 'Open ShellX on the computer to use AI sessions.');
    expect(en.aiUpdateDesktop, 'Update ShellX on the computer to use AI sessions from your phone.');
    expect(en.aiComposerHint('Claude'), 'Message Claude…');
    expect(
      [en.aiSend, en.aiQueue, en.aiStop, en.aiStopping, en.aiForceStop],
      ['Send', 'Queue', 'Stop', 'Stopping…', 'Force stop'],
    );
    expect(en.aiReconnecting, 'Reconnecting… what you see may be behind.');
    expect(en.aiClosedGone, 'This AI session was closed on the computer.');
    expect(
      en.aiClosedDesktop,
      'ShellX was closed on the computer. Open ShellX on the computer, then open the session again.',
    );
    expect(en.aiClosedUnreadable, 'The phone cannot read this AI session. See it on the computer.');
    expect(en.aiPermTitle('Claude'), 'Claude asks:');
    expect(
      [en.aiPermAllowOnce, en.aiPermAllowAlways, en.aiPermRejectOnce, en.aiPermRejectAlways],
      ['Allow', 'Always allow', 'Reject', 'Always reject'],
    );
    expect(en.aiPermOnComputer, 'Answer this request on the computer.');
    expect(en.aiAnsweredElsewhere, 'Already answered on another device.');
    expect(en.aiYouChose('Allow (Yes)'), 'You chose: Allow (Yes)');
    expect(en.aiAskOnComputer, 'Answer this question on the computer.');
    expect(en.aiTurnSummary(3, '0:41'), 'Turn 3 · 0:41');
    expect([en.aiTurnFiles(1), en.aiTurnFiles(2)], ['1 file changed', '2 files changed']);
    expect(en.aiFromComputerOnly, 'Too large for the phone. Open it on the computer.');
    expect(en.aiItemOnComputer, 'This kind of item is not supported on the phone yet. See it on the computer.');
    expect(en.aiTooLong(32), 'Too long to send from the phone (32 KB at most).');
    expect(en.aiRowSubtitle('Claude', 'Running'), 'Claude · Running');
    expect(en.aiCutLines(120), '120 lines in all; the middle is on the computer');
    expect([en.aiMoreDiffs(1), en.aiMoreDiffs(2)], ['+1 more file', '+2 more files']);
    expect(en.aiPermMore(2), '2 more waiting');
    expect(en.aiContext(16), 'Context 16%');
    expect(en.aiPlan(2, 5), 'Plan · 2/5');
    expect(en.aiToolRunningFor('2:05'), 'running · 2:05');
    expect(en.aiNoticeNode('Claude', 20), 'Claude needs Node.js 20 or newer on the computer.');
    expect(en.aiToolDelete('old.ts'), 'Delete old.ts');
    expect(en.aiAskCancelled, 'Cancelled');
    expect(en.aiNewNoAgents, 'No agent is ready on the computer. Set one up in Settings › Agents.');
    expect(en.aiNewNoFolders, 'Set a folder for a project on the computer first (Settings › Projects).');
    expect([en.aiStateClosed, en.aiToolDone], ['Closed', 'done']);
    expect(en.aiOpenOutcomeUnknown, 'The new session may not have been created. Check the list before trying again.');
    expect(en.aiNoticeExited('Claude', 1), 'Claude stopped unexpectedly (exit 1).');
    expect(en.aiRequestFailed('refused'), 'The computer did not take it (refused).');
    expect(en.aiRefused, 'The computer did not accept this request.');
    expect(en.aiBusy, 'Too many requests at once. Wait a moment, then try again.');
    expect(en.aiPermOption, 'Option');
    expect(en.aiNoticeUndoOff, 'Undo is off for this project.');
    expect(en.aiNoticeUndoOffReason('git was not found'), 'Undo is off for this project (git was not found).');
    expect(en.aiNoticeUndoOffTurn('git is older than 2.26'), 'Undo is off for this turn (git is older than 2.26).');
    expect(en.aiUndoBroadFolder, 'this folder is your home folder or a disk root');
  });

  // M6: English counts one request in the singular; Vietnamese has one form.
  test('the tool page counts its requests in both languages', () async {
    final en = await S.load(const Locale('en'));
    expect(
      [en.toolSlow(1), en.toolSlow(2)],
      ['Loading through your computer… (1 request)', 'Loading through your computer… (2 requests)'],
    );
    final vi = await S.load(const Locale('vi'));
    expect(
      [vi.toolSlow(1), vi.toolSlow(2)],
      ['Đang tải qua máy tính… (1 request)', 'Đang tải qua máy tính… (2 request)'],
    );
  });

  test('the AI texts call the agent Claude, never "Claude Code"', () {
    for (final path in ['lib/l10n/intl_en.arb', 'lib/l10n/intl_vi.arb']) {
      final json = jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
      final ai = {
        for (final entry in json.entries)
          if (RegExp(r'^ai[A-Z]').hasMatch(entry.key)) entry.key: entry.value,
      };
      expect(ai.length, greaterThan(100), reason: path);
      for (final entry in ai.entries) {
        expect(entry.value.toString(), isNot(contains('Claude Code')), reason: '${entry.key} in $path');
      }
    }
  });

  test(
    'the Vietnamese AI texts put the tone of an open oa, oe, uy on its first vowel ("Xóa", "Hủy"), like the app',
    () {
      // Old style ("xoá", "huỷ", "hoạ", "khoẻ", "thuỷ") writes it on the second vowel. A syllable that ends in a
      // consonant ("hoàn", "hoạch", "thoát") has its tone on the a in both styles, and "qu" is a consonant ("quý").
      final json = jsonDecode(File('lib/l10n/intl_vi.arb').readAsStringSync()) as Map<String, Object?>;
      final oldStyle = RegExp(r'(?:o[àáạảãèéẹẻẽ]|(?<!q)u[ỳýỵỷỹ])$');
      final combining = RegExp(r'[\u0300-\u036f]');
      final offenders = <String>[];
      var checked = 0;
      for (final entry in json.entries) {
        final value = entry.value;
        if (!RegExp(r'^ai[A-Z]').hasMatch(entry.key) || value is! String) continue;
        checked++;
        // One piece (NFC): a tone mark typed apart from its letter would slip through the check below.
        if (combining.hasMatch(value)) offenders.add('${entry.key}: not NFC');
        for (final word in RegExp(r'\p{L}+', unicode: true).allMatches(value.toLowerCase())) {
          if (oldStyle.hasMatch(word[0]!)) offenders.add('${entry.key}: ${word[0]}');
        }
      }
      expect(checked, greaterThan(100));
      expect(offenders, isEmpty);
    },
  );

  test('that check knows the two styles apart', () {
    final oldStyle = RegExp(r'(?:o[àáạảãèéẹẻẽ]|(?<!q)u[ỳýỵỷỹ])$');
    for (final old in ['xoá', 'huỷ', 'hoà', 'hoạ', 'khoẻ', 'thuỷ', 'tuỳ', 'toả']) {
      expect(oldStyle.hasMatch(old), isTrue, reason: old);
    }
    for (final fine in [
      'xóa',
      'hủy',
      'hòa',
      'họa',
      'khỏe',
      'thủy',
      'tùy',
      'hoàn',
      'hoạch',
      'thoát',
      'quý',
      'quỳ',
      'tuyệt',
    ]) {
      expect(oldStyle.hasMatch(fine), isFalse, reason: fine);
    }
  });

  testWidgets('S.of(context) resolves Vietnamese inside the design system', (tester) async {
    await tester.pumpWidget(localized(Builder(builder: (context) => Text(S.of(context).machinesTitle))));
    await tester.pumpAndSettle();
    expect(find.text('Máy của bạn'), findsOneWidget);
  });
}
