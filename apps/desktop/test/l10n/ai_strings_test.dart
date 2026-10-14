import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final vi = lookupAppLocalizations(const Locale('vi'));

  test('V2-1 §4.6: the main strings, word for word', () {
    expect(vi.aiNewSession, 'Phiên AI mới');
    expect(vi.aiNewTabKindLabel, 'Tab mới mở dạng');
    expect(vi.aiNewTabKindAi, 'Giao diện AI');
    expect(vi.aiNewTabKindTerminal, 'Terminal');
    expect(vi.aiOnboardingTitle, 'Bạn muốn làm việc theo kiểu nào?');
    expect(
      vi.aiComposerHint('Claude'),
      'Nhắn cho Claude… (@ nhắc tệp, / gọi lệnh)',
    );
    expect(vi.aiPermTitle('Claude', 'Sửa a.ts'), 'Claude xin quyền: Sửa a.ts');
    expect(
      [
        vi.aiPermAllowOnce,
        vi.aiPermAllowAlways,
        vi.aiPermRejectOnce,
        vi.aiPermRejectAlways,
      ],
      ['Cho phép', 'Luôn cho phép', 'Từ chối', 'Luôn từ chối'],
    );
    expect(vi.aiTurnSummary(3, '0:41', 2), 'Lượt 3 · 0:41 · 2 tệp đổi');
    expect(vi.aiRevertTurn, 'Hoàn tác lượt');
    expect(vi.aiRevertSession, 'Hoàn tác cả phiên');
    expect(vi.aiChangedAfterTurn, 'đã sửa sau lượt');
    expect(vi.aiLoginNeeded('Claude'), 'Claude cần đăng nhập');
    expect(vi.aiRunSheetLogin('Claude'), 'Đăng nhập Claude');
    expect(vi.aiRunSheetInstall('Claude'), 'Cài Claude');
    expect(vi.aiNodeMissing('Claude', 22), 'Claude cần Node.js 22 trở lên');
    expect(vi.aiAgentExited('Claude', 1), 'Claude dừng bất ngờ (mã thoát 1)');
    expect(vi.aiForceStop, 'Dừng hẳn');
    expect(vi.aiResumeSession, 'Tiếp tục phiên');
    expect(vi.aiHistory, 'Lịch sử phiên');
    expect(
      vi.aiNoUndo('không tìm thấy git'),
      'Hoàn tác đang tắt cho dự án này (không tìm thấy git)',
    );
    expect(
      vi.aiBypassConfirm('Claude'),
      'Claude sẽ sửa tệp và chạy lệnh mà không hỏi.',
    );
  });

  test('English counts read right', () {
    expect(en.aiTurnSummary(1, '0:05', 1), 'Turn 1 · 0:05 · 1 file changed');
    expect(en.aiTurnSummary(2, '0:41', 3), 'Turn 2 · 0:41 · 3 files changed');
    expect(en.aiReverted(1), 'Reverted 1 file.');
    expect(en.aiNodeMissing('Codex', 20), 'Codex needs Node.js 20 or newer');
  });

  test('the run sheet note uses the typographic apostrophe', () {
    expect(
      en.aiRunSheetNote,
      'This is the agent’s own program; ShellX does not read or keep what '
      'happens here.',
    );
    expect(en.aiRunSheetNote, isNot(contains("'")));
  });

  test('feature names say Claude, never Claude Code (D21)', () {
    for (final l in [en, vi]) {
      for (final s in [
        l.aiNewSession,
        l.aiSettingClaude,
        l.aiMenuAgentsSettings,
        l.actionNewAiSession,
      ]) {
        expect(s, isNot(contains('Claude Code')));
      }
    }
  });
}
