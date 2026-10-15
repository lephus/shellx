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
