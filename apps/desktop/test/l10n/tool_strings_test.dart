import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final vi = lookupAppLocalizations(const Locale('vi'));

  test('V2-3 §4.3: the Vietnamese strings, word for word', () {
    expect(vi.toolsGroup, 'Tool');
    expect(vi.toolAdd, 'Thêm tool');
    expect(vi.toolOpenCommand('Bảng việc'), 'Mở tool: Bảng việc');
    expect(vi.toolLocal, 'Trên máy này');
    expect(vi.toolRemote, 'Ngoài máy này');
    expect(vi.toolUnencrypted, 'không mã hoá');
    expect(vi.toolAway('sso.example.com'), 'Đang ở sso.example.com');
    expect(vi.toolBackToTool, 'Về tool');
    expect(
      [vi.toolPhoneOn, vi.toolPhoneOff],
      ['Điện thoại: bật', 'Điện thoại: tắt'],
    );
    expect(
      vi.toolPhoneOnlyLocal,
      'Chỉ tool http trên máy này mở được trên điện thoại.',
    );
    expect(vi.toolAlsoPhone, '· cả điện thoại');
    expect([vi.toolExpand, vi.toolCollapse], ['Mở rộng', 'Thu về']);
    expect(vi.toolOpenInBrowser, 'Mở bằng trình duyệt');
    expect(
      vi.toolRefused('localhost:5173'),
      'Chưa có gì chạy ở localhost:5173. Chạy server của tool rồi trang sẽ '
      'tự hiện.',
    );
    expect(vi.toolLoadFailed('x'), 'Không tải được trang: x');
    expect(
      vi.toolAtsBlocked,
      'macOS không cho mở trang http này trong ShellX.',
    );
    expect(vi.toolCrashed, 'Trang đã dừng.');
    expect(
      vi.toolDownloadBlocked,
      'Tool muốn tải một tệp. Mở bằng trình duyệt để tải.',
    );
    expect(
      vi.toolDeleteConfirm('Bảng việc'),
      'Xoá tool "Bảng việc"? Trang của nó đóng lại. Dữ liệu web của nó không '
      'bị xoá.',
    );
    expect(vi.toolClearData, 'Xoá dữ liệu của tool…');
    expect(
      vi.toolClearDataConfirm,
      'Đăng xuất mọi tool và xoá cookie, bộ nhớ của chúng?',
    );
    expect(vi.toolEmbedSetting, 'Hiện tool trong ShellX');
    expect(
      [vi.toolEmbedAuto, vi.toolEmbedOn, vi.toolEmbedOff],
      ['Tự động', 'Luôn', 'Không, mở bằng trình duyệt'],
    );
    expect(vi.toolCovered('Bảng việc'), 'Bảng việc — tạm ẩn khi đang mở menu');
    expect(
      vi.toolTooMany('Grafana'),
      'Đã dỡ "Grafana" cho ShellX nhẹ. Bấm để tải lại.',
    );
    expect(vi.toolJsAlertTitle('Bảng việc'), 'Bảng việc nhắn');
    expect(vi.actionToggleTools, 'Hiện hoặc ẩn vùng tool');
    expect(vi.actionAddTool, 'Thêm tool…');
  });

  test('V2-3 §4.2: the dialog, word for word', () {
    expect(
      [vi.toolDialogAddTitle, vi.toolDialogEditTitle],
      ['Thêm tool', 'Sửa tool'],
    );
    expect(
      [en.toolDialogAddTitle, en.toolDialogEditTitle],
      ['Add a tool', 'Edit tool'],
    );
    expect(vi.toolDialogNameHint, 'Bảng việc');
    expect(vi.toolDialogUrlHint, 'http://localhost:4000');
    expect(vi.toolSuggestionsTitle, 'Cổng đang chạy mà ShellX thấy:');
    expect(vi.toolSuggestion(5173, 'node'), 'localhost:5173 · node');
    expect(
      vi.toolSuggestionsNone,
      'Chưa thấy cổng nào. Chạy server của tool trong một terminal hoặc nhờ '
      'agent chạy.',
    );
    expect(vi.toolDialogPhone, 'Cho mở trên điện thoại');
    expect(
      vi.toolDialogPhoneNote,
      'Đi qua relay, mã hoá đầu cuối. Điện thoại chỉ tới được đúng URL này.',
    );
    expect([vi.toolDialogAdd, vi.toolDialogSave], ['Thêm', 'Lưu']);
    expect(vi.toolUrlNotHttp, 'URL phải bắt đầu bằng http:// hoặc https://');
    expect(
      vi.toolUrlUserinfo,
      'URL không được chứa tên đăng nhập hay mật khẩu',
    );
  });

  test('English reads as the spec says', () {
    expect(
      en.toolRefused('localhost:5173'),
      "Nothing is running at localhost:5173. Start your tool's server and "
      'the page will appear.',
    );
    expect(en.toolJsAlertTitle('Board'), 'Board says');
    expect(en.toolEmbedOff, 'No, open in browser');
    expect(en.actionToggleTools, 'Show or hide tools');

    // The rest of §4.3, in the order of the Vietnamese test above.
    expect(en.toolsGroup, 'Tools');
    expect(en.toolAdd, 'Add tool');
    expect(en.toolOpenCommand('Board'), 'Open tool: Board');
    expect(en.toolLocal, 'On this computer');
    expect(en.toolRemote, 'Not on this computer');
    expect(en.toolUnencrypted, 'not encrypted');
    expect(en.toolAway('sso.example.com'), 'On sso.example.com');
    expect(en.toolBackToTool, 'Back to tool');
    expect(en.toolPhoneOn, 'Phone: on');
    expect(en.toolPhoneOff, 'Phone: off');
    expect(
      en.toolPhoneOnlyLocal,
      'Only http tools on this computer can open on a phone.',
    );
    expect(en.toolAlsoPhone, '· on phone too');
    expect(en.toolExpand, 'Expand');
    expect(en.toolCollapse, 'Restore');
    expect(en.toolOpenInBrowser, 'Open in browser');
    expect(en.toolLoadFailed('x'), "The page couldn't load: x");
    expect(
      en.toolAtsBlocked,
      "macOS doesn't allow this http page inside ShellX.",
    );
    expect(en.toolCrashed, 'The page stopped.');
    expect(
      en.toolDownloadBlocked,
      'This tool wants to download a file. Open it in your browser to '
      'download.',
    );
    expect(
      en.toolDeleteConfirm('Board'),
      'Delete the tool "Board"? Its page closes. Its web data stays.',
    );
    expect(en.toolClearData, 'Clear tool data…');
    expect(
      en.toolClearDataConfirm,
      'Sign every tool out and clear its cookies and storage?',
    );
    expect(en.toolEmbedSetting, 'Show tools in ShellX');
    expect(en.toolEmbedAuto, 'Automatic');
    expect(en.toolEmbedOn, 'Always');
    expect(en.toolCovered('Board'), 'Board — hidden while a menu is open');
    expect(
      en.toolTooMany('Grafana'),
      'Closed "Grafana" to keep ShellX light. Click to load it again.',
    );
    expect(en.actionAddTool, 'Add tool…');

    // The rest of §4.2, in the order of the Vietnamese test above.
    expect(en.toolDialogNameHint, 'Task board');
    expect(en.toolDialogUrlHint, 'http://localhost:4000');
    expect(en.toolSuggestionsTitle, 'Running ports ShellX can see:');
    expect(en.toolSuggestion(5173, 'node'), 'localhost:5173 · node');
    expect(
      en.toolSuggestionsNone,
      "No running ports yet. Start your tool's server in a terminal or ask "
      'the agent to.',
    );
    expect(en.toolDialogPhone, 'Allow on phone');
    expect(
      en.toolDialogPhoneNote,
      'Through the relay, end-to-end encrypted. The phone can reach this URL '
      'only.',
    );
    expect(en.toolDialogAdd, 'Add');
    expect(en.toolDialogSave, 'Save');
    expect(en.toolUrlNotHttp, 'The URL must start with http:// or https://');
    expect(en.toolUrlUserinfo, "The URL can't contain a user name or password");
  });

  test('R2 and the bar, menu, reason and data strings, EN + VI', () {
    // The dialog's field labels (§4.2).
    expect(en.toolDialogName, 'Name');
    expect(vi.toolDialogName, 'Tên');
    expect(en.toolDialogUrl, 'URL');
    expect(vi.toolDialogUrl, 'URL');

    // R2: the URL error lines the spec does not list (§4.2 lists not-http and
    // user name or password).
    expect(en.toolUrlBackslash, r"The URL can't contain a backslash (\)");
    expect(vi.toolUrlBackslash, r'URL không được chứa dấu gạch ngược (\)');
    expect(en.toolUrlNoHost, 'The URL needs a host, like localhost:4000');
    expect(vi.toolUrlNoHost, 'URL cần có tên máy, ví dụ localhost:4000');
    expect(en.toolUrlBadPort, 'The port must be a number from 1 to 65535');
    expect(vi.toolUrlBadPort, 'Cổng phải là số từ 1 đến 65535');
    expect(en.toolUrlTooLong, 'The URL is longer than 2048 characters');
    expect(vi.toolUrlTooLong, 'URL dài quá 2048 ký tự');

    // R2: the 50-tool limit.
    expect(en.toolLimitReached(50), 'This project already has 50 tools.');
    expect(vi.toolLimitReached(50), 'Dự án này đã có 50 tool.');

    // R2, D17: the tool bar's buttons and the menu behind More.
    expect(en.toolBack, 'Back');
    expect(vi.toolBack, 'Quay lại');
    expect(en.toolReload, 'Reload');
    expect(vi.toolReload, 'Tải lại');
    expect(en.toolStop, 'Stop');
    expect(vi.toolStop, 'Dừng');
    expect(en.toolMore, 'More');
    expect(vi.toolMore, 'Thêm');
    expect(en.toolEditMenu, 'Edit tool…');
    expect(vi.toolEditMenu, 'Sửa tool…');
    expect(en.toolCopyUrl, 'Copy URL');
    expect(vi.toolCopyUrl, 'Sao chép URL');
    expect(en.toolCloseDock, 'Close tools');
    expect(vi.toolCloseDock, 'Đóng vùng tool');
    expect(en.toolClose, 'Close tool');
    expect(vi.toolClose, 'Đóng tool');

    // R2, D21: the menu labels of a tool row.
    expect(en.toolMenuOpen, 'Open');
    expect(vi.toolMenuOpen, 'Mở');
    expect(en.toolMenuEdit, 'Edit…');
    expect(vi.toolMenuEdit, 'Sửa…');
    expect(en.toolMenuDelete, 'Delete…');
    expect(vi.toolMenuDelete, 'Xoá…');

    // The confirm buttons of the delete and clear-data questions.
    expect(en.toolDeleteAction, 'Delete');
    expect(vi.toolDeleteAction, 'Xoá');
    expect(en.toolClearDataAction, 'Clear');
    expect(vi.toolClearDataAction, 'Xoá');

    // R2: the clear-data note, the body of that question.
    expect(en.toolClearDataNote, 'Your tools stay; you sign in to them again.');
    expect(vi.toolClearDataNote, 'Tool vẫn còn; bạn đăng nhập lại vào chúng.');

    // D22: the label of the Settings row for the tools' data.
    expect(en.toolDataLabel, 'Tool data');
    expect(vi.toolDataLabel, 'Dữ liệu của tool');

    // §8: Windows without the WebView2 Runtime.
    expect(en.toolNeedsWebView2, 'Microsoft Edge WebView2 Runtime is needed.');
    expect(vi.toolNeedsWebView2, 'Cần Microsoft Edge WebView2 Runtime.');

    // R2, D13: the short reasons a page did not load.
    expect(en.toolReasonDns, 'the address was not found');
    expect(vi.toolReasonDns, 'không tìm thấy địa chỉ');
    expect(en.toolReasonTimeout, 'it took too long');
    expect(vi.toolReasonTimeout, 'quá lâu không phản hồi');
    expect(en.toolReasonCertificate, 'the certificate is not valid');
    expect(vi.toolReasonCertificate, 'chứng chỉ không hợp lệ');
    expect(en.toolReasonUnreachable, "the network can't be reached");
    expect(vi.toolReasonUnreachable, 'không tới được mạng');
    expect(en.toolReasonOther, 'something went wrong');
    expect(vi.toolReasonOther, 'có lỗi xảy ra');

    // R2, D18: the accessibility labels of the dock and its handle.
    expect(en.toolDockLabel('Board'), 'Tools: Board');
    expect(vi.toolDockLabel('Bảng việc'), 'Tool: Bảng việc');
    expect(en.toolHandleLabel, 'Tools width');
    expect(vi.toolHandleLabel, 'Độ rộng vùng tool');

    // R2: OK.
    expect(en.toolOk, 'OK');
    expect(vi.toolOk, 'OK');
  });

  test('no V2-3 string says "Claude Code"', () {
    for (final name in ['app_en.arb', 'app_vi.arb']) {
      final arb =
          jsonDecode(File('lib/l10n/$name').readAsStringSync())
              as Map<String, Object?>;
      for (final MapEntry(:key, :value) in arb.entries) {
        if (!key.startsWith('tool') || value is! String) continue;
        expect(value, isNot(contains('Claude Code')), reason: '$name $key');
      }
    }
  });
}
