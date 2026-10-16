import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_client/shellx_client.dart' show MachineConnectionFailure;
import 'package:shellx_core/shellx_core.dart' show kAiMaxBodyBytes, kAiMaxPromptBytes;
import 'package:shellx_mobile/features/ai/domain/ai_words.dart';
import 'package:shellx_mobile/shared/shared.dart';

import '../../support/fakes.dart';

MirrorTool _tool(ToolKind kind, {String? title, String? path, MirrorDiff? diff}) => MirrorTool(
  0,
  0,
  1,
  toolCallId: 't',
  kind: kind,
  title: title,
  locations: [if (path != null) ToolLocation(path)],
  diffs: [?diff],
);

final _t0 = DateTime(2026, 10, 14, 9);

/// A tool call the agent sent, on the computer's side.
void _call(AiSessionState desktop, String id, Map<String, Object?> fields) => desktop.applyUpdate(
  SessionUpdate.fromJson({'sessionUpdate': 'tool_call', 'toolCallId': id, ...fields}),
  _t0,
);

PermissionRequest _request(List<Map<String, Object?>> options) => PermissionRequest.fromJson({
  'sessionId': 's',
  'toolCall': {'toolCallId': 'c1', 'title': 'Edit src/main.ts', 'kind': 'edit'},
  'options': options,
});

MirrorHead _head(String phase, {String? modeId, String? modeName}) =>
    MirrorHead(phase: phase, agentId: 'claude', agentName: 'Claude', modeId: modeId, modeName: modeName);

/// V2-2 §5: the phone says what the desktop says (V2-1 §4.2, D10, D11), in Vietnamese and English.
/// The strings follow the last loaded locale (intl_utils): load right before use.
void main() {
  test('tool cards: a verb and what it acts on', () async {
    final vi = await S.load(const Locale('vi'));
    expect(AiWords.toolTitle(vi, _tool(ToolKind.read, title: 'Read File', path: '/p/src/main.ts')), 'Đọc main.ts');
    expect(
      AiWords.toolTitle(
        vi,
        _tool(
          ToolKind.edit,
          diff: const MirrorDiff(path: 'C:\\p\\a.ts', newText: 'x'),
        ),
      ),
      'Tạo a.ts',
    );
    expect(
      AiWords.toolTitle(
        vi,
        _tool(
          ToolKind.edit,
          diff: const MirrorDiff(path: '/p/a.ts', oldText: 'a', newText: 'b'),
        ),
      ),
      'Sửa a.ts',
    );
    expect(AiWords.toolTitle(vi, _tool(ToolKind.execute, title: 'npm test')), 'Chạy npm test');
    final en = await S.load(const Locale('en'));
    expect(AiWords.toolTitle(en, _tool(ToolKind.other, title: 'mcp__github__create_issue')), 'github · create_issue');
  });

  test('permission options by kind; the agent\'s words for an unknown kind', () async {
    final vi = await S.load(const Locale('vi'));
    PermissionOption o(PermissionKind kind) => PermissionOption(optionId: 'x', name: 'Agent words', kind: kind);
    expect(AiWords.option(vi, o(PermissionKind.allowOnce)), 'Cho phép');
    expect(AiWords.option(vi, o(PermissionKind.allowAlways)), 'Luôn cho phép');
    expect(AiWords.option(vi, o(PermissionKind.rejectOnce)), 'Từ chối');
    expect(AiWords.option(vi, o(PermissionKind.rejectAlways)), 'Luôn từ chối');
    expect(AiWords.option(vi, o(PermissionKind.other)), 'Agent words');
  });

  test('an unknown kind the agent gave no words for is still a button with a label', () async {
    PermissionOption other(String name) => PermissionOption(optionId: 'x', name: name, kind: PermissionKind.other);
    final vi = await S.load(const Locale('vi'));
    for (final blank in ['', ' ', '  \t\n']) {
      expect(AiWords.option(vi, other(blank)), 'Lựa chọn', reason: 'name: "$blank"');
    }
    expect(AiWords.option(vi, other('Agent words')), 'Agent words');
    final en = await S.load(const Locale('en'));
    expect(AiWords.option(en, other('')), 'Option');
    expect(AiWords.option(en, other('Agent words')), 'Agent words');
    // The kinds that have words of their own never need the fallback, whatever name the agent sent.
    const named = PermissionOption(optionId: 'x', name: '', kind: PermissionKind.allowOnce);
    expect(AiWords.option(en, named), 'Allow');
  });

  test('modes, states, clock and failures', () async {
    final vi = await S.load(const Locale('vi'));
    const head = MirrorHead(phase: 'running', agentId: 'claude', agentName: 'Claude', modeId: 'acceptEdits');
    expect(AiWords.mode(vi, head), 'Tự sửa tệp');
    expect(AiWords.headState(head), AiRemoteState.running);
    expect(AiWords.state(vi, AiRemoteState.needsInput), 'Cần bạn trả lời');
    expect(AiWords.clock(const Duration(seconds: 72)), '1:12');
    expect(AiWords.clock(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    expect(AiWords.failure(vi, 'stale', answer: true), 'Đã được trả lời ở thiết bị khác.');
    expect(AiWords.failure(vi, 'stale'), isNull);
    expect(AiWords.failure(vi, 'too_large'), 'Quá dài để gửi từ điện thoại (tối đa 32 KB).');
  });

  group('tool cards, edges', () {
    test('a verb for every kind, in both languages', () async {
      final vi = await S.load(const Locale('vi'));
      expect(AiWords.toolTitle(vi, _tool(ToolKind.delete, path: '/p/old.ts')), 'Xóa old.ts');
      expect(AiWords.toolTitle(vi, _tool(ToolKind.move, path: '/p/src/a.ts')), 'Đổi tên a.ts');
      expect(AiWords.toolTitle(vi, _tool(ToolKind.search, title: 'TODO')), 'Tìm TODO');
      expect(AiWords.toolTitle(vi, _tool(ToolKind.fetch, title: 'https://example.com')), 'Tải https://example.com');
      expect(AiWords.toolTitle(vi, _tool(ToolKind.think)), 'Suy nghĩ');
      expect(AiWords.toolTitle(vi, _tool(ToolKind.switchMode, title: 'plan')), 'Đổi chế độ');
      expect(AiWords.toolTitle(vi, _tool(ToolKind.other, title: 'Task')), 'Task');
      final en = await S.load(const Locale('en'));
      expect(AiWords.toolTitle(en, _tool(ToolKind.read, path: '/p/src/main.ts')), 'Read main.ts');
      expect(AiWords.toolTitle(en, _tool(ToolKind.delete, path: '/p/old.ts')), 'Delete old.ts');
      expect(AiWords.toolTitle(en, _tool(ToolKind.move, path: '/p/src/a.ts')), 'Rename a.ts');
      expect(AiWords.toolTitle(en, _tool(ToolKind.search, title: 'TODO')), 'Search TODO');
      expect(AiWords.toolTitle(en, _tool(ToolKind.fetch, title: 'https://example.com')), 'Fetch https://example.com');
      expect(AiWords.toolTitle(en, _tool(ToolKind.execute, title: 'npm test')), 'Run npm test');
      expect(AiWords.toolTitle(en, _tool(ToolKind.think)), 'Thinking');
      expect(AiWords.toolTitle(en, _tool(ToolKind.switchMode)), 'Switch mode');
      expect(AiWords.toolTitle(en, _tool(ToolKind.edit, path: '/p/a.ts')), 'Edit a.ts');
    });

    test('a call without a kind is its title', () async {
      final vi = await S.load(const Locale('vi'));
      const call = MirrorTool(0, 0, 1, toolCallId: 't', title: 'mcp__github__create_issue');
      expect(AiWords.toolTitle(vi, call), 'github · create_issue');
      expect(AiWords.toolTitle(vi, const MirrorTool(0, 0, 1, toolCallId: 't', title: 'Fetch docs')), 'Fetch docs');
    });

    test('the cards the real wire carries', () async {
      final ai = FakeAiSession('s1');
      ai.desktop.beginTurn(const [TextBlock('go')], _t0);
      _call(ai.desktop, 'c1', {
        'kind': 'read',
        'title': 'Read File',
        'locations': [
          {'path': '/p/src/main.ts'},
        ],
      });
      _call(ai.desktop, 'c2', {
        'kind': 'edit',
        'title': 'Edit',
        'content': [
          {'type': 'diff', 'path': '/p/src/a.ts', 'oldText': 'a', 'newText': 'b'},
        ],
      });
      _call(ai.desktop, 'c3', {
        'kind': 'edit',
        'title': 'Write',
        'content': [
          {'type': 'diff', 'path': 'C:\\p\\new.ts', 'newText': 'x'},
        ],
      });
      _call(ai.desktop, 'c4', {'kind': 'execute', 'title': 'npm test'});
      _call(ai.desktop, 'c5', {'title': 'mcp__github__create_issue'});
      ai.sync();
      final vi = await S.load(const Locale('vi'));
      expect(
        [for (final t in ai.mirror.items.whereType<MirrorTool>()) AiWords.toolTitle(vi, t)],
        [
          'Đọc main.ts',
          'Sửa a.ts',
          'Tạo new.ts',
          'Chạy npm test',
          'github · create_issue',
        ],
      );
    });

    test('file names and MCP names', () {
      expect(AiWords.fileName('/p/src/main.ts'), 'main.ts');
      expect(AiWords.fileName('C:\\p\\src\\main.ts'), 'main.ts');
      expect(AiWords.fileName('main.ts'), 'main.ts');
      expect(AiWords.fileName('/p/src/'), 'src');
      expect(AiWords.fileName(''), '');
      expect(AiWords.fileName('/'), '/');
      expect(AiWords.toolName('mcp__github__create_issue'), 'github · create_issue');
      expect(AiWords.toolName('mcp__my_server__do_it'), 'my_server · do_it');
      expect(AiWords.toolName('Task'), 'Task');
      expect(AiWords.toolName('mcp__github'), 'mcp__github');
    });
  });

  group('states', () {
    test('a state for every state, in both languages', () async {
      final vi = await S.load(const Locale('vi'));
      expect(
        {for (final state in AiRemoteState.values) state: AiWords.state(vi, state)},
        {
          AiRemoteState.running: 'Đang chạy',
          AiRemoteState.needsInput: 'Cần bạn trả lời',
          AiRemoteState.idle: 'Đang chờ',
          AiRemoteState.starting: 'Đang khởi động',
          AiRemoteState.stopped: 'Chưa chạy',
          AiRemoteState.needsAuth: 'Cần đăng nhập trên máy tính',
          AiRemoteState.failed: 'Lỗi',
          AiRemoteState.noFolder: 'Chọn thư mục trên máy tính',
          AiRemoteState.agentOff: 'Agent đang tắt trên máy tính',
        },
      );
      final en = await S.load(const Locale('en'));
      expect(
        {for (final state in AiRemoteState.values) state: AiWords.state(en, state)},
        {
          AiRemoteState.running: 'Running',
          AiRemoteState.needsInput: 'Needs your answer',
          AiRemoteState.idle: 'Waiting',
          AiRemoteState.starting: 'Starting',
          AiRemoteState.stopped: 'Not started',
          AiRemoteState.needsAuth: 'Sign in on the computer',
          AiRemoteState.failed: 'Error',
          AiRemoteState.noFolder: 'Choose a folder on the computer',
          AiRemoteState.agentOff: 'Agent off on the computer',
        },
      );
    });

    test('the header says what the computer\'s own list says for the same session', () {
      for (final phase in AgentPhase.values) {
        for (final waiting in ['nothing', 'a permission', 'a question']) {
          final desktop = AiSessionState(agentId: 'claude', agentName: 'Claude', cwd: '/p')..setPhase(phase);
          switch (waiting) {
            case 'a permission':
              desktop.addPermission(
                _request([
                  {'optionId': 'allow', 'name': 'Yes', 'kind': 'allow_once'},
                ]),
                _t0,
              );
            case 'a question':
              desktop.addAsk(
                ElicitationRequest.fromJson({
                  'mode': 'form',
                  'message': 'Which?',
                  'requestedSchema': {
                    'type': 'object',
                    'properties': {
                      'pick': {'type': 'string'},
                    },
                  },
                }),
              );
          }
          final ai = FakeAiSession('s1', desktop: desktop)..sync();
          expect(AiWords.headState(ai.mirror.head!), aiRemoteStateOf(desktop), reason: '$phase, $waiting');
        }
      }
    });

    test('a session that cannot run says why, whatever else the header holds', () {
      MirrorHead unavailable(String word) => MirrorHead.fromJson({
        'phase': 'running',
        'agent': 'claude',
        'name': 'Claude',
        'unavailable': word,
        'perm': {'id': 1, 'title': 'x', 'options': <Object?>[]},
      });
      expect(AiWords.headState(unavailable('no_folder')), AiRemoteState.noFolder);
      expect(AiWords.headState(unavailable('agent_off')), AiRemoteState.agentOff);
    });

    test('a phase the phone does not know reads as not started', () {
      expect(AiWords.headState(_head('hibernating')), AiRemoteState.stopped);
    });
  });

  group('modes and the clock', () {
    test('Claude\'s modes in the app\'s words, another agent\'s as sent', () async {
      final vi = await S.load(const Locale('vi'));
      expect(AiWords.mode(vi, _head('ready', modeId: 'default')), 'Hỏi trước');
      expect(AiWords.mode(vi, _head('ready', modeId: 'acceptEdits')), 'Tự sửa tệp');
      expect(AiWords.mode(vi, _head('ready', modeId: 'plan')), 'Lập kế hoạch');
      expect(AiWords.mode(vi, _head('ready', modeId: 'auto')), 'Tự động');
      expect(AiWords.mode(vi, _head('ready', modeId: 'bypassPermissions')), 'Bỏ qua mọi quyền');
      expect(AiWords.mode(vi, _head('ready', modeId: 'read-only', modeName: 'Read Only')), 'Read Only');
      expect(AiWords.mode(vi, _head('ready')), isNull);
      final en = await S.load(const Locale('en'));
      expect(AiWords.mode(en, _head('ready', modeId: 'default')), 'Ask first');
      expect(AiWords.mode(en, _head('ready', modeId: 'bypassPermissions')), 'Bypass permissions');
    });

    test('the clock', () {
      expect(AiWords.clock(Duration.zero), '0:00');
      expect(AiWords.clock(const Duration(seconds: 12)), '0:12');
      expect(AiWords.clock(const Duration(minutes: 3, seconds: 5)), '3:05');
      expect(AiWords.clock(const Duration(minutes: 59, seconds: 59)), '59:59');
      expect(AiWords.clock(const Duration(hours: 10, seconds: 1)), '10:00:01');
      expect(AiWords.clock(const Duration(milliseconds: 1999)), '0:01');
      // The phone's clock can run behind the computer's: never a minus sign.
      expect(AiWords.clock(const Duration(seconds: -5)), '0:00');
    });
  });

  group('notice cards', () {
    List<MirrorNotice> everyNotice() {
      final ai = FakeAiSession('s1');
      ai.desktop
        ..addNotice(const LoginNeeded([]))
        ..addNotice(const NodeMissing(required: 20, found: '18.2.0'))
        ..addNotice(const AgentNotInstalled())
        ..addNotice(const AgentMissing('claude-agent-acp'))
        ..addNotice(const AgentExited(1))
        ..addNotice(const AgentOutputInvalid(ConnectionCloseReason.tooManyBadLines))
        ..addNotice(const StartFailed(StartFailure.spawn))
        ..addNotice(const CannotResume())
        ..addNotice(const FolderMissing())
        ..addNotice(const UndoUnavailable(UndoOff.noGit));
      ai.sync();
      return ai.mirror.items.whereType<MirrorNotice>().toList();
    }

    test('every notice of the computer, read from the real wire, in Vietnamese', () async {
      final notices = everyNotice();
      expect(notices, hasLength(10));
      final vi = await S.load(const Locale('vi'));
      expect(
        [for (final n in notices) AiWords.notice(vi, n, 'Claude')],
        [
          'Claude cần đăng nhập, trên máy tính.',
          'Claude cần máy tính có Node.js 20 trở lên.',
          'Claude chưa được cài trên máy tính.',
          'Không tìm thấy Claude trên máy tính.',
          'Claude dừng bất ngờ (mã thoát 1).',
          'Claude gửi dữ liệu ShellX không đọc được nên đã bị dừng.',
          'Claude không khởi động được.',
          'Agent này không khôi phục được phiên cũ; đã mở phiên mới.',
          'Thư mục của phiên không còn. Chọn thư mục trên máy tính.',
          'Hoàn tác đang tắt cho dự án này (không tìm thấy git).',
        ],
      );
    });

    test('and in English', () async {
      final notices = everyNotice();
      final en = await S.load(const Locale('en'));
      expect(
        [for (final n in notices) AiWords.notice(en, n, 'Claude')],
        [
          'Claude needs you to sign in, on the computer.',
          'Claude needs Node.js 20 or newer on the computer.',
          'Claude is not installed on the computer.',
          'Claude was not found on the computer.',
          'Claude stopped unexpectedly (exit 1).',
          'Claude sent output ShellX cannot read and was stopped.',
          'Claude could not start.',
          'This agent cannot reopen the old session; a new one was started.',
          "The session's folder is gone. Choose one on the computer.",
          'Undo is off for this project (git was not found).',
        ],
      );
    });

    test('a notice a newer computer sends is a notice from the computer', () async {
      final vi = await S.load(const Locale('vi'));
      const future = MirrorNotice(0, 0, 1, kind: 'quota_exceeded', args: {'k': 'quota_exceeded'});
      expect(AiWords.notice(vi, future, 'Claude'), 'Thông báo từ máy tính.');
      // A number that did not arrive is not a crash.
      const bare = MirrorNotice(0, 0, 1, kind: 'exited');
      expect(AiWords.notice(vi, bare, 'Claude'), 'Claude dừng bất ngờ (mã thoát 0).');
    });

    group('undo is off, and why', () {
      // `reason` on the wire is `UndoOff.name`. broadFolder is a newer computer's: this version of
      // shellx_ai may not have it in the enum yet, so it is listed by name as well.
      final names = {...UndoOff.values.map((r) => r.name), 'broadFolder'};
      const vi = {
        'noGit': 'không tìm thấy git',
        'noCommandLineTools': 'chưa cài Command Line Tools',
        'gitTooOld': 'git cũ hơn 2.26',
        'tooManyFiles': 'hơn 200 000 tệp',
        'tooSlow': 'lần chụp đầu quá 30 s',
        'failed': 'chụp điểm khôi phục lỗi',
        'broadFolder': 'thư mục này là thư mục home hoặc gốc ổ đĩa',
      };
      const en = {
        'noGit': 'git was not found',
        'noCommandLineTools': 'the Command Line Tools are not installed',
        'gitTooOld': 'git is older than 2.26',
        'tooManyFiles': 'more than 200,000 files',
        'tooSlow': 'the first snapshot took over 30 s',
        'failed': 'a snapshot failed',
        'broadFolder': 'this folder is your home folder or a disk root',
      };

      MirrorNotice undoOff(String? reason, {bool turnOnly = false}) => MirrorNotice(
        0,
        0,
        1,
        kind: 'undo_off',
        args: {'k': 'undo_off', 'reason': ?reason, if (turnOnly) 'turn_only': true},
      );

      test('every reason the computer can give has words, in both languages, the desktop\'s own', () async {
        expect(names, containsAll(vi.keys));
        expect(vi.keys, containsAll(names));
        final viS = await S.load(const Locale('vi'));
        expect({for (final name in names) name: AiWords.undoReason(viS, name)}, vi);
        final enS = await S.load(const Locale('en'));
        expect({for (final name in names) name: AiWords.undoReason(enS, name)}, en);
      });

      test('the card says why undo is off, for the project or for one turn only', () async {
        final viS = await S.load(const Locale('vi'));
        expect(
          AiWords.notice(viS, undoOff('broadFolder'), 'Claude'),
          'Hoàn tác đang tắt cho dự án này (thư mục này là thư mục home hoặc gốc ổ đĩa).',
        );
        expect(
          AiWords.notice(viS, undoOff('tooSlow', turnOnly: true), 'Claude'),
          'Hoàn tác đang tắt cho lượt này (lần chụp đầu quá 30 s).',
        );
        final enS = await S.load(const Locale('en'));
        expect(
          AiWords.notice(enS, undoOff('broadFolder'), 'Claude'),
          'Undo is off for this project (this folder is your home folder or a disk root).',
        );
        expect(
          AiWords.notice(enS, undoOff('tooSlow', turnOnly: true), 'Claude'),
          'Undo is off for this turn (the first snapshot took over 30 s).',
        );
      });

      test('read from the real wire, whatever the reason', () async {
        final ai = FakeAiSession('s1');
        ai.desktop
          ..addNotice(const UndoUnavailable(UndoOff.noCommandLineTools))
          ..addNotice(const UndoUnavailable(UndoOff.failed, turnOnly: true));
        ai.sync();
        final notices = ai.mirror.items.whereType<MirrorNotice>().toList();
        final viS = await S.load(const Locale('vi'));
        expect(
          [for (final n in notices) AiWords.notice(viS, n, 'Claude')],
          [
            'Hoàn tác đang tắt cho dự án này (chưa cài Command Line Tools).',
            'Hoàn tác đang tắt cho lượt này (chụp điểm khôi phục lỗi).',
          ],
        );
      });

      test('a reason this version does not know, or none, leaves the card without one', () async {
        final viS = await S.load(const Locale('vi'));
        for (final notice in [undoOff('somethingNew'), undoOff(null), undoOff('somethingNew', turnOnly: true)]) {
          expect(AiWords.notice(viS, notice, 'Claude'), 'Hoàn tác đang tắt cho dự án này.');
        }
        // A reason that is no word at all is no reason.
        const odd = MirrorNotice(0, 0, 1, kind: 'undo_off', args: {'k': 'undo_off', 'reason': 7});
        expect(AiWords.notice(viS, odd, 'Claude'), 'Hoàn tác đang tắt cho dự án này.');
        expect(AiWords.undoReason(viS, null), isNull);
        expect(AiWords.undoReason(viS, 7), isNull);
      });
    });
  });

  group('failures', () {
    test('every code a request can end with, in Vietnamese', () async {
      final vi = await S.load(const Locale('vi'));
      expect(AiWords.failure(vi, 'queue_full'), 'Đã có 5 tin đang chờ.');
      expect(AiWords.failure(vi, 'offline'), 'Đang kết nối lại… nội dung có thể chưa mới nhất.');
      expect(AiWords.failure(vi, 'unavailable'), 'Mở ShellX trên máy tính để dùng phiên AI.');
      expect(AiWords.failure(vi, 'not_found'), 'Phiên AI này đã đóng trên máy tính.');
      expect(AiWords.failure(vi, 'gone'), 'Phiên AI này đã đóng trên máy tính.');
      expect(AiWords.failure(vi, 'refused'), 'Máy tính không nhận yêu cầu này.');
      expect(AiWords.failure(vi, 'busy'), 'Quá nhiều yêu cầu cùng lúc. Chờ một lát rồi thử lại.');
      // A code of a newer computer is still a sentence.
      expect(AiWords.failure(vi, 'quota'), 'Máy tính không nhận (quota).');
    });

    test('and in English', () async {
      final en = await S.load(const Locale('en'));
      expect(AiWords.failure(en, 'stale', answer: true), 'Already answered on another device.');
      expect(AiWords.failure(en, 'queue_full'), '5 messages are already waiting.');
      expect(AiWords.failure(en, 'too_large'), 'Too long to send from the phone (32 KB at most).');
      expect(AiWords.failure(en, 'offline'), 'Reconnecting… what you see may be behind.');
      expect(AiWords.failure(en, 'unavailable'), 'Open ShellX on the computer to use AI sessions.');
      expect(AiWords.failure(en, 'not_found'), 'This AI session was closed on the computer.');
      expect(AiWords.failure(en, 'refused'), 'The computer did not accept this request.');
      expect(AiWords.failure(en, 'busy'), 'Too many requests at once. Wait a moment, then try again.');
      expect(AiWords.failure(en, 'quota'), 'The computer did not take it (quota).');
    });

    test('no code the computer sends shows as a code in a sentence', () async {
      // `ai.result` codes of the hub (and the client): the user reads words, not "busy" or "queue_full".
      const codes = ['stale', 'refused', 'queue_full', 'too_large', 'busy', 'not_found', 'unavailable', 'on_computer'];
      for (final locale in ['vi', 'en']) {
        final s = await S.load(Locale(locale));
        for (final code in codes) {
          final text = AiWords.failure(s, code, answer: true);
          expect(text, isNotNull, reason: '$code in $locale');
          expect(text, isNot(contains(code)), reason: '$code in $locale');
        }
      }
    });

    test('an answer to a question may be 48 KB, a prompt 32 KB: each says its own limit', () async {
      final vi = await S.load(const Locale('vi'));
      expect(AiWords.failure(vi, 'too_large'), 'Quá dài để gửi từ điện thoại (tối đa 32 KB).');
      expect(AiWords.failure(vi, 'too_large', answer: true), 'Quá dài để gửi từ điện thoại (tối đa 48 KB).');
      final en = await S.load(const Locale('en'));
      expect(AiWords.failure(en, 'too_large'), 'Too long to send from the phone (32 KB at most).');
      expect(AiWords.failure(en, 'too_large', answer: true), 'Too long to send from the phone (48 KB at most).');
      expect(AiWords.kAiMaxAnswerKb * 1024, kAiMaxBodyBytes);
    });

    test('a request in flight when the window quits or the session closes is worded, answers included', () async {
      // Task 6: `ai.closed` (gone → not_found, else unavailable) and `available: false` end the requests
      // in flight with these two codes, whatever the request was.
      final vi = await S.load(const Locale('vi'));
      for (final answer in [false, true]) {
        expect(AiWords.failure(vi, 'not_found', answer: answer), isNotNull, reason: 'answer: $answer');
        expect(AiWords.failure(vi, 'unavailable', answer: answer), isNotNull, reason: 'answer: $answer');
      }
    });

    test('the limit shown is the limit the client enforces', () {
      expect(AiWords.kAiMaxPromptKb * 1024, kAiMaxPromptBytes);
    });
  });

  group('closed sessions', () {
    test('each reason has its words, the unreadable one too', () async {
      final vi = await S.load(const Locale('vi'));
      expect(AiWords.closed(vi, 'gone'), 'Phiên AI này đã đóng trên máy tính.');
      expect(
        AiWords.closed(vi, 'desktop_closed'),
        'ShellX trên máy tính đã thoát. Mở ShellX trên máy tính rồi mở lại phiên.',
      );
      expect(AiWords.closed(vi, 'unavailable'), 'Mở ShellX trên máy tính để dùng phiên AI.');
      expect(AiWords.closed(vi, 'unreadable'), 'Điện thoại không đọc được phiên AI này. Xem trên máy tính.');
      // The reason of a newer computer, and no reason at all: the session is closed there.
      expect(AiWords.closed(vi, 'archived'), 'Phiên AI này đã đóng trên máy tính.');
      expect(AiWords.closed(vi, null), 'Phiên AI này đã đóng trên máy tính.');
      final en = await S.load(const Locale('en'));
      expect(AiWords.closed(en, 'gone'), 'This AI session was closed on the computer.');
      expect(
        AiWords.closed(en, 'desktop_closed'),
        'ShellX was closed on the computer. Open ShellX on the computer, then open the session again.',
      );
      expect(AiWords.closed(en, 'unavailable'), 'Open ShellX on the computer to use AI sessions.');
      expect(AiWords.closed(en, 'unreadable'), 'The phone cannot read this AI session. See it on the computer.');
    });

    test('the reasons the client can give are all worded', () async {
      final vi = await S.load(const Locale('vi'));
      final words = {
        for (final reason in ['gone', 'desktop_closed', 'unavailable', 'detached', 'unreadable'])
          reason: AiWords.closed(vi, reason),
      };
      expect(words.values.every((w) => w.isNotEmpty), isTrue);
      expect(words['unreadable'], isNot(words['gone']));
    });
  });

  group('on the computer', () {
    test('a permission that came without options is answered there', () async {
      // The computer drops a permission's options when its header would not fit a message.
      final ai = FakeAiSession('s1');
      ai.desktop.beginTurn(const [TextBlock('go')], _t0);
      ai.desktop.addPermission(
        _request([
          for (var i = 0; i < 200; i++) {'optionId': 'o$i', 'name': 'n' * 300, 'kind': 'allow_once'},
        ]),
        _t0,
      );
      ai.sync();
      final permission = ai.mirror.head!.permission!;
      expect(permission.options, isEmpty);
      expect(permission.title, 'Edit src/main.ts');
      final vi = await S.load(const Locale('vi'));
      expect(AiWords.permissionOnComputer(vi, permission), 'Trả lời yêu cầu này trên máy tính.');
      final en = await S.load(const Locale('en'));
      expect(AiWords.permissionOnComputer(en, permission), 'Answer this request on the computer.');
    });

    test('a permission with buttons has nothing to say', () async {
      final ai = FakeAiSession('s1');
      ai.desktop.beginTurn(const [TextBlock('go')], _t0);
      ai.desktop.addPermission(
        _request([
          {'optionId': 'allow', 'name': 'Yes', 'kind': 'allow_once'},
        ]),
        _t0,
      );
      ai.sync();
      final vi = await S.load(const Locale('vi'));
      expect(AiWords.permissionOnComputer(vi, ai.mirror.head!.permission!), isNull);
    });

    test('a card too large is read there; so is a card the phone does not know', () async {
      final mirror = AiMirror();
      expect(
        mirror.apply({
          'g': 1,
          'from': 0,
          'n': 2,
          'reset': true,
          'items': [
            {'i': 0, 'r': 0, 'turn': 1, 'k': 'big'},
            {'i': 1, 'r': 0, 'turn': 1, 'k': 'hologram'},
          ],
        }, snapshot: true),
        isTrue,
      );
      final cards = mirror.items.whereType<MirrorUnknown>().toList();
      expect([for (final c in cards) c.kind], ['big', 'hologram']);
      final vi = await S.load(const Locale('vi'));
      expect(AiWords.itemOnComputer(vi, cards[0]), 'Quá lớn để xem trên điện thoại. Xem trên máy tính.');
      expect(AiWords.itemOnComputer(vi, cards[1]), 'Điện thoại chưa hỗ trợ loại mục này. Xem trên máy tính.');
      final en = await S.load(const Locale('en'));
      expect(AiWords.itemOnComputer(en, cards[0]), 'Too large for the phone. Open it on the computer.');
      expect(
        AiWords.itemOnComputer(en, cards[1]),
        'This kind of item is not supported on the phone yet. See it on the computer.',
      );
      expect(AiWords.itemOnComputer(en, const MirrorUnknown(2, 0, 1, null)), AiWords.itemOnComputer(en, cards[1]));
    });
  });

  group('how long a call has been running', () {
    test('seconds with a decimal below a minute (comma in Vietnamese), minutes after', () {
      expect(AiWords.elapsed(const Duration(milliseconds: 2100), locale: 'vi'), '2,1 s');
      expect(AiWords.elapsed(const Duration(milliseconds: 2100), locale: 'en'), '2.1 s');
      expect(AiWords.elapsed(const Duration(milliseconds: 59900), locale: 'vi'), '59,9 s');
      expect(AiWords.elapsed(const Duration(seconds: 60), locale: 'vi'), '1:00');
      expect(AiWords.elapsed(const Duration(seconds: 3725), locale: 'vi'), '1:02:05');
      expect(AiWords.elapsed(const Duration(seconds: -4), locale: 'vi'), '0,0 s'); // the clocks differ
    });
  });

  group('a request that failed on the way (V2-2 D13)', () {
    test('one that may have landed says so, in both languages', () async {
      final vi = await S.load(const Locale('vi'));
      expect(
        AiWords.failure(vi, 'outcome_unknown'),
        'Có thể chưa gửi được — kết nối bị gián đoạn. Hãy xem lại phiên trước khi thử lại.',
      );
      expect(AiWords.failure(vi, 'outcome_unknown', answer: true), AiWords.failure(vi, 'outcome_unknown'));
      final en = await S.load(const Locale('en'));
      expect(
        AiWords.failure(en, 'outcome_unknown'),
        'This may not have been sent — the connection dropped. Check the session before trying again.',
      );
    });

    test('a handshake that failed sent nothing: the machine\'s own words', () async {
      final vi = await S.load(const Locale('vi'));
      expect(AiWords.failure(vi, 'untrusted'), 'Máy không còn tin cậy điện thoại này. Hãy ghép nối lại.');
      expect(AiWords.failure(vi, 'update_required'), 'Cần cập nhật app');
      final en = await S.load(const Locale('en'));
      expect(AiWords.failure(en, 'untrusted'), 'This computer no longer trusts this phone. Please pair again.');
      expect(AiWords.failure(en, 'update_required'), 'App update required');
    });

    test('a new session that may have been created says so, and to look in the list first (D13)', () async {
      final vi = await S.load(const Locale('vi'));
      expect(
        AiWords.failure(vi, 'open_unknown'),
        'Có thể phiên mới chưa được tạo. Hãy xem lại danh sách trước khi thử lại.',
      );
      final en = await S.load(const Locale('en'));
      expect(
        AiWords.failure(en, 'open_unknown'),
        'The new session may not have been created. Check the list before trying again.',
      );
    });

    test('an option the computer keeps for itself is answered there', () async {
      // The computer refuses an answer that would turn on a mode without approval (V2-2 D13); the
      // request stays open for it.
      final vi = await S.load(const Locale('vi'));
      expect(AiWords.failure(vi, 'on_computer', answer: true), 'Trả lời yêu cầu này trên máy tính.');
      final en = await S.load(const Locale('en'));
      expect(AiWords.failure(en, 'on_computer', answer: true), 'Answer this request on the computer.');
    });

    test('a request already on its way says nothing; anything else is a sentence', () async {
      final vi = await S.load(const Locale('vi'));
      expect(AiWords.failure(vi, 'in_flight'), isNull);
      expect(AiWords.failure(vi, 'error'), 'Đã có lỗi xảy ra'); // no "(error)" after it
      final en = await S.load(const Locale('en'));
      expect(AiWords.failure(en, 'error'), 'Something went wrong');
    });

    test('a computer that cannot be reached is worded by the machine, the offline one at length', () async {
      final vi = await S.load(const Locale('vi'));
      expect(
        AiWords.machineFailure(vi, MachineConnectionFailure.agentOffline),
        'Máy tính đang offline. Hãy mở ShellX trên máy tính rồi thử lại.',
      );
      expect(AiWords.machineFailure(vi, MachineConnectionFailure.timeout), 'Máy tính không phản hồi. Hãy thử lại.');
      expect(
        AiWords.machineFailure(vi, MachineConnectionFailure.untrusted),
        'Máy không còn tin cậy điện thoại này. Hãy ghép nối lại.',
      );
      expect(AiWords.machineFailure(vi, MachineConnectionFailure.protocolUnsupported), 'Cần cập nhật app');
      final en = await S.load(const Locale('en'));
      expect(
        AiWords.machineFailure(en, MachineConnectionFailure.agentOffline),
        'The computer is offline. Open ShellX on the computer and try again.',
      );
      expect(
        AiWords.machineFailure(en, MachineConnectionFailure.timeout),
        "The computer didn't respond. Please try again.",
      );
    });
  });
}
