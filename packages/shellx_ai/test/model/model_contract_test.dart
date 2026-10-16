import 'dart:convert';
import 'dart:io';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:test/test.dart';

// What a view or the runtime relies on and the three test files of the brief
// leave open: rev, listeners and version, the end-of-turn card, defaults,
// redaction, the platform-free rule and one whole recorded turn.

final t0 = DateTime.utc(2026, 10, 14, 9);
final t1 = t0.add(const Duration(seconds: 3));
final t2 = t0.add(const Duration(seconds: 9));

SessionUpdate update(JsonMap j) => SessionUpdate.fromJson(j);

JsonMap chunk(String kind, String text, {String? id}) => {
  'sessionUpdate': kind,
  'messageId': ?id,
  'content': {'type': 'text', 'text': text},
};

JsonMap toolCall(String id, {String? status}) => {
  'sessionUpdate': 'tool_call',
  'toolCallId': id,
  'title': 'Tool $id',
  'status': ?status,
};

JsonMap toolUpdate(String id, String status) => {
  'sessionUpdate': 'tool_call_update',
  'toolCallId': id,
  'status': status,
};

AiSessionState fresh() =>
    AiSessionState(agentId: 'claude', agentName: 'Claude', cwd: '/p');

PermissionRequest perm(String toolCallId, {String? title}) =>
    PermissionRequest.fromJson({
      'sessionId': 's',
      'toolCall': {'toolCallId': toolCallId, 'title': ?title},
      'options': [
        {'optionId': 'allow-once', 'name': 'Yes', 'kind': 'allow_once'},
        {'optionId': 'reject', 'name': 'No', 'kind': 'reject_once'},
      ],
    });

ElicitationRequest urlAsk(String elicitationId) => ElicitationRequest.fromJson({
  'mode': 'url',
  'message': 'Sign in',
  'elicitationId': elicitationId,
  'url': 'https://x.test',
});

void main() {
  group('Timeline', () {
    test('items before the first prompt are turn 0; the prompt is turn 1', () {
      final tl = Timeline();
      tl.apply(update(chunk('agent_message_chunk', 'hi')), t0);
      final prompt = tl.startTurn(const [TextBlock('go')]);
      expect(tl.items.first.turn, 0);
      expect(prompt.turn, 1);
      expect(tl.turn, 1);
    });

    test('apply says true for message, thought and tool updates', () {
      final tl = Timeline();
      for (final j in [
        chunk('user_message_chunk', 'q'),
        chunk('agent_message_chunk', 'a'),
        chunk('agent_thought_chunk', 't'),
        toolCall('c1'),
        toolUpdate('c1', 'completed'),
      ]) {
        expect(
          tl.apply(update(j), t0),
          isTrue,
          reason: '${j['sessionUpdate']}',
        );
      }
    });

    test('the chunks of one user message merge; another id is a new turn', () {
      final tl = Timeline();
      tl.apply(update(chunk('user_message_chunk', 'Fix ', id: 'u1')), t0);
      final item = tl.items.single as UserItem;
      final rev = item.rev;
      tl.apply(update(chunk('user_message_chunk', 'it', id: 'u1')), t0);
      expect(tl.items, [same(item)]);
      expect(item.text, 'Fix it');
      expect(item.rev, greaterThan(rev));
      tl.apply(update(chunk('user_message_chunk', 'Then', id: 'u2')), t0);
      expect(tl.items.whereType<UserItem>().map((i) => '${i.turn}:${i.text}'), [
        '1:Fix it',
        '2:Then',
      ]);
    });

    test('every chunk of agent text bumps rev', () {
      final tl = Timeline();
      tl.apply(update(chunk('agent_message_chunk', 'a')), t0);
      final item = tl.items.whereType<AgentTextItem>().single;
      final rev = item.rev;
      tl.apply(update(chunk('agent_message_chunk', 'b')), t0);
      expect(item.text, 'ab');
      expect(item.rev, greaterThan(rev));
    });

    test('a thought of another message id is another thought', () {
      final tl = Timeline();
      tl.apply(update(chunk('agent_thought_chunk', 'a', id: 'm1')), t0);
      tl.apply(update(chunk('agent_thought_chunk', 'b', id: 'm1')), t0);
      tl.apply(update(chunk('agent_thought_chunk', 'c', id: 'm2')), t0);
      expect(tl.items.whereType<ThoughtItem>().map((i) => i.text), ['ab', 'c']);
    });

    test('a card keeps its first start, its first end and its turn', () {
      for (final status in ['completed', 'failed']) {
        final tl = Timeline()..startTurn(const [TextBlock('go')]);
        tl.apply(update(toolCall('a', status: 'in_progress')), t0);
        tl.apply(update(toolUpdate('a', status)), t1);
        tl.apply(update(toolUpdate('a', status)), t2);
        final card = tl.tool('a')!;
        expect(card.startedAt, t0, reason: status);
        expect(card.endedAt, t1, reason: status);
        expect(card.turn, 1, reason: status);
      }
    });

    test('a prompt is copied: the caller keeps its own list', () {
      final blocks = <ContentBlock>[const TextBlock('a')];
      final item = Timeline().startTurn(blocks);
      blocks.add(const TextBlock('b'));
      expect(item.text, 'a');
    });
  });

  group('AiSessionState', () {
    test('a removed listener is not called; the same phase is no change', () {
      final s = fresh();
      var calls = 0;
      void listener() => calls++;
      s.addListener(listener);
      s.setPhase(AgentPhase.starting);
      expect(calls, 1);
      final version = s.version;
      s.setPhase(AgentPhase.starting);
      expect(calls, 1);
      expect(s.version, version);
      s.removeListener(listener);
      s.setPhase(AgentPhase.ready);
      expect(calls, 1);
      expect(s.version, version + 1);
    });

    test('a listener may remove itself while it is being called', () {
      final s = fresh();
      var first = 0;
      var second = 0;
      late void Function() once;
      once = () {
        first++;
        s.removeListener(once);
      };
      s.addListener(once);
      s.addListener(() => second++);
      s
        ..touch()
        ..touch();
      expect(first, 1);
      expect(second, 2);
    });

    test('the agent answer gives capabilities and sign-in methods', () {
      final s = fresh();
      expect(s.capabilities.loadSession, isFalse);
      expect(s.authMethods, isEmpty);
      final version = s.version;
      s.setAgent(
        InitializeResult.fromJson({
          'protocolVersion': 1,
          'agentCapabilities': {'loadSession': true},
          'authMethods': [
            {'id': 'login', 'name': 'Sign in'},
          ],
        }),
      );
      expect(s.capabilities.loadSession, isTrue);
      expect(s.authMethods.single.id, 'login');
      expect(s.version, version + 1);
    });

    test(
      'setSession sets the id and keeps the options and modes not given',
      () {
        final s = fresh();
        const modes = SessionModes(currentModeId: 'default', available: []);
        s.setSession('s1', modes: modes, configOptions: const []);
        final version = s.version;
        s.setSession('s2');
        expect(s.sessionId, 's2');
        expect(s.modes, same(modes));
        expect(s.configOptions, isNotNull);
        expect(s.version, version + 1);
      },
    );

    test('our own prompt echoed by the agent changes nothing', () {
      final s = fresh()..beginTurn(const [TextBlock('hi')], t0);
      final version = s.version;
      s.applyUpdate(update(chunk('user_message_chunk', 'hi')), t0);
      expect(s.timeline.items.whereType<UserItem>().single.text, 'hi');
      expect(s.version, version);
      s.applyUpdate(
        update(chunk('user_message_chunk', 'old', id: 'u0')),
        t0,
        history: true,
      );
      expect(s.timeline.items.whereType<UserItem>().map((i) => i.text), [
        'hi',
        'old',
      ]);
    });

    test('session_info_update without a title keeps the title', () {
      final s = fresh();
      s.applyUpdate(
        update({'sessionUpdate': 'session_info_update', 'title': 'T'}),
        t0,
      );
      s.applyUpdate(
        update({
          'sessionUpdate': 'session_info_update',
          'updatedAt': '2026-10-14T09:00:00Z',
        }),
        t0,
      );
      expect(s.title, 'T');
    });

    group('label', () {
      test('a prompt of exactly 40 characters is kept whole', () {
        final s = fresh()..beginTurn([TextBlock('a' * 40)], t0);
        expect(s.label, 'a' * 40);
      });

      test('a blank title falls back to the prompt; a title is trimmed', () {
        final s = fresh()..beginTurn(const [TextBlock('first')], t0);
        s.title = '   ';
        expect(s.label, 'first');
        s.title = '  Named  ';
        expect(s.label, 'Named');
      });

      test('a prompt without text is skipped for the next one with text', () {
        final s = fresh()
          ..beginTurn(const [ImageBlock(data: '', mimeType: 'image/png')], t0);
        expect(s.label, isNull);
        s.endTurn(outcome: TurnOutcome.finished, at: t0);
        s.beginTurn(const [TextBlock('second')], t1);
        expect(s.label, 'second');
      });
    });

    group('turns', () {
      test('the end card closes the timeline and carries what it is given', () {
        final s = fresh()..beginTurn(const [TextBlock('go')], t0);
        final changes = [
          const FileChange(
            path: 'a.txt',
            kind: ChangeKind.modified,
            added: 1,
            removed: 2,
          ),
        ];
        final end = s.endTurn(
          outcome: TurnOutcome.failed,
          at: t1,
          stopReason: StopReason.refusal,
          error: 'boom',
          afterTree: 'tr2',
          changes: changes,
        )!;
        expect(s.timeline.items.last, same(end));
        expect(end.outcome, TurnOutcome.failed);
        expect(end.stopReason, StopReason.refusal);
        expect(end.error, 'boom');
        expect(end.afterTree, 'tr2');
        expect(end.changes, same(changes));
        expect(end.checkpoint, isNull);
      });

      test('every outcome but finished stops the calls still open', () {
        for (final outcome in TurnOutcome.values) {
          final s = fresh()..beginTurn(const [TextBlock('go')], t0);
          s.applyUpdate(update(toolCall('a', status: 'in_progress')), t0);
          s.endTurn(outcome: outcome, at: t1);
          expect(
            s.timeline.tool('a')!.end,
            outcome == TurnOutcome.finished ? isNull : ToolEnd.stopped,
            reason: outcome.name,
          );
        }
      });

      test('the phase goes back to ready only from running', () {
        final s = fresh()..beginTurn(const [TextBlock('go')], t0);
        s.setPhase(AgentPhase.failed); // the agent died during the turn
        s.endTurn(outcome: TurnOutcome.interrupted, at: t1);
        expect(s.phase, AgentPhase.failed);
        expect(s.turn, isNull);
      });

      test('turns count up and each end card belongs to its own', () {
        final s = fresh();
        s.beginTurn(const [TextBlock('one')], t0);
        s.endTurn(outcome: TurnOutcome.finished, at: t0);
        final second = s.beginTurn(const [TextBlock('two')], t1);
        expect(second.index, 2);
        expect(s.endTurn(outcome: TurnOutcome.finished, at: t2)!.turn, 2);
      });

      test('stopOpenTools stamps the stop and ends the permission wait', () {
        final s = fresh()..beginTurn(const [TextBlock('go')], t0);
        final card = s.addPermission(perm('a'), t0).item;
        final rev = card.rev;
        s.timeline.stopOpenTools(t1);
        expect(card.end, ToolEnd.stopped);
        expect(card.endedAt, t1);
        expect(card.awaitingPermission, isFalse);
        expect(card.rev, greaterThan(rev));
      });
    });

    group('permissions', () {
      test('two requests for one card: it waits until both are answered', () {
        final s = fresh()..beginTurn(const [TextBlock('go')], t0);
        final a = s.addPermission(perm('c1'), t0);
        final b = s.addPermission(perm('c1'), t0);
        expect(b.item, same(a.item));
        final rev = a.item.rev;
        s.resolvePermission(a.id, const PermissionSelected('allow-once'));
        expect(a.item.awaitingPermission, isTrue);
        expect(a.item.rev, greaterThan(rev));
        s.resolvePermission(b.id, const PermissionSelected('reject'));
        expect(a.item.awaitingPermission, isFalse);
        expect(a.item.permissionAnswer!.name, 'No');
      });

      test('the title follows the card when an update refines it', () {
        final s = fresh()..beginTurn(const [TextBlock('go')], t0);
        final p = s.addPermission(perm('c1', title: 'Edit'), t0);
        expect(p.title, 'Edit');
        s.applyUpdate(
          update({
            'sessionUpdate': 'tool_call_update',
            'toolCallId': 'c1',
            'title': 'Edit a.txt',
          }),
          t0,
        );
        expect(p.title, 'Edit a.txt');
      });

      test('an unknown request or option answers nothing', () {
        final s = fresh()..beginTurn(const [TextBlock('go')], t0);
        final p = s.addPermission(perm('c1'), t0);
        final version = s.version;
        s.resolvePermission(p.id + 100, const PermissionCancelled());
        expect(s.permissions, [same(p)]);
        expect(s.version, version);
        s.resolvePermission(p.id, const PermissionSelected('nope'));
        expect(p.item.permissionAnswer, isNull);
        expect(p.item.permissionCancelled, isFalse);
      });
    });

    group('questions', () {
      test('an unknown question answers nothing; a URL completes its own', () {
        final s = fresh()..beginTurn(const [TextBlock('go')], t0);
        final a = s.addAsk(urlAsk('e1'))!;
        final b = s.addAsk(urlAsk('e2'))!;
        expect(s.currentAsk, same(a));
        expect(a.request, isA<ElicitationUrl>());
        final version = s.version;
        s.resolveAsk(a.id + 100, const ElicitCancel());
        s.completeUrlAsk('nope');
        expect(s.asks, [same(a), same(b)]);
        expect(s.version, version);

        var rev = b.item.rev;
        s.completeUrlAsk('e2');
        expect(a.item.completed, isFalse);
        expect(b.item.completed, isTrue);
        expect(b.item.rev, greaterThan(rev));

        rev = a.item.rev;
        s.resolveAsk(a.id, const ElicitAccept());
        expect(a.item.rev, greaterThan(rev));
        expect(s.currentAsk, same(b));
      });
    });

    group('notices', () {
      test('a notice belongs to the current turn and ends the timeline', () {
        final s = fresh()..beginTurn(const [TextBlock('go')], t0);
        final version = s.version;
        final notice = s.addNotice(const FolderMissing());
        expect(notice.turn, 1);
        expect(s.timeline.items.last, same(notice));
        expect(s.version, version + 1);
      });

      test(
        'resolveNotices folds an open notice once and tells no one else',
        () {
          final s = fresh();
          final login = s.addNotice(const LoginNeeded([]));
          final rev = login.rev;
          s.resolveNotices((n) => n is LoginNeeded);
          expect(login.resolved, isTrue);
          expect(login.rev, greaterThan(rev));
          final version = s.version;
          s.resolveNotices((n) => n is LoginNeeded); // already folded
          s.resolveNotices((n) => false);
          expect(s.version, version);
        },
      );
    });

    test('the queue copies the blocks and counts only real changes', () {
      expect(AiSessionState.maxQueue, 5);
      final s = fresh();
      final blocks = <ContentBlock>[const TextBlock('a')];
      var version = s.version;
      final a = s.enqueue(blocks)!;
      final b = s.enqueue(const [TextBlock('b')])!;
      expect(s.version, version + 2);
      blocks.add(const TextBlock('x'));
      expect(a.text, 'a');

      version = s.version;
      s.removeQueued(b.id + 100);
      expect(s.version, version);
      s.removeQueued(b.id);
      expect(s.version, version + 1);
      expect(s.takeQueued(), same(a));
      expect(s.version, version + 2);
      expect(s.takeQueued(), isNull);
      expect(s.version, version + 2);
    });
  });

  group('types', () {
    test('a file change without line counts is binary', () {
      const png = FileChange(path: 'a.png', kind: ChangeKind.added);
      const text = FileChange(
        path: 'a.txt',
        kind: ChangeKind.modified,
        added: 0,
        removed: 0,
      );
      expect(png.binary, isTrue);
      expect(text.binary, isFalse);
    });

    test('notices default to installable, not shim-only, not turn-only', () {
      expect(const AgentNotInstalled().canInstall, isTrue);
      expect(const AgentMissing('claude').shimOnly, isFalse);
      expect(const UndoUnavailable(UndoOff.noGit).turnOnly, isFalse);
    });

    test('every model type prints as … (spec D20)', () {
      final s = fresh()..beginTurn(const [TextBlock('secret')], t0);
      final ask = s.addAsk(urlAsk('e1'))!;
      final values = <Object>[
        const FileChange(path: 'secret', kind: ChangeKind.added),
        const Checkpoint(commit: 'secret', tree: 'secret'),
        const LoginNeeded([]),
        const NodeMissing(required: 20, found: 'secret'),
        const AgentNotInstalled(),
        const AgentMissing('secret'),
        const AgentExited(1),
        const AgentOutputInvalid(ConnectionCloseReason.lineTooLong),
        const StartFailed(StartFailure.spawn),
        const CannotResume(),
        const FolderMissing(),
        const UndoUnavailable(UndoOff.noGit),
        UserItem(1, const [TextBlock('secret')]),
        AgentTextItem(1),
        ThoughtItem(1),
        ToolItem(1, 't', const ToolCallFields(), startedAt: t0),
        ask.item,
        TurnEndItem(1, outcome: TurnOutcome.finished, elapsed: Duration.zero),
        NoticeItem(1, const FolderMissing()),
        Timeline(),
        s,
        s.turn!,
        s.addPermission(perm('a'), t0),
        ask,
        s.enqueue(const [TextBlock('secret')])!,
      ];
      for (final v in values) {
        expect(v.toString(), '…', reason: v.runtimeType.toString());
      }
    });

    test('every class of the model mixes in Redacted or extends one', () {
      // Read from the source, so a class added later is covered: a root class
      // says `with Redacted`, any other `extends` a class of the model.
      final headers = <String, String>{};
      final declaration = RegExp(
        r'^(?:(?:sealed|final|abstract|base|interface) )*class (\w+)([^{]*)\{',
        multiLine: true,
      );
      for (final f in Directory('lib/src/model').listSync().whereType<File>()) {
        for (final m in declaration.allMatches(f.readAsStringSync())) {
          headers[m[1]!] = m[2]!;
        }
      }
      expect(
        headers.keys,
        containsAll(['FileChange', 'AiNotice', 'Timeline', 'AiSessionState']),
        reason: 'the scan is broken',
      );
      final offenders = [
        for (final e in headers.entries)
          if (!e.value.contains('Redacted') && !e.value.contains('extends'))
            e.key,
      ];
      expect(offenders, isEmpty, reason: 'add `with Redacted` to these');
    });

    test('the model uses no dart:io: the phone shares it', () {
      final files = [
        File('lib/shellx_ai.dart'),
        ...Directory('lib/src/model').listSync().whereType<File>(),
      ];
      expect(files, hasLength(greaterThan(1)));
      final platform = RegExp(
        r'''^\s*(?:import|export)\s+['"](?:dart:io|package:shellx_acp/testing\.dart)['"]''',
        multiLine: true,
      );
      for (final f in files) {
        expect(
          platform.hasMatch(f.readAsStringSync()),
          isFalse,
          reason: f.path,
        );
      }
    });
  });

  group('the recorded Claude session', () {
    final file = File(
      '../shellx_acp/test/fixtures/sessions/claude-agent-acp-0.90.0.jsonl',
    );
    final lines = file.existsSync()
        ? [for (final l in file.readAsLinesSync()) jsonDecode(l) as JsonMap]
        : <JsonMap>[];
    final skip = lines.isEmpty ? 'no recorded session (ledger)' : false;
    // Two runs: the live turn, then a restart that loads the session.
    final restart = lines.indexWhere(
      (l) =>
          l['dir'] == 'out' && (l['msg']! as JsonMap)['method'] == 'initialize',
      1,
    );
    final live = lines.take(restart < 0 ? lines.length : restart);
    final reload = lines.skip(restart < 0 ? lines.length : restart);

    AiSessionState newState() =>
        AiSessionState(agentId: 'claude', agentName: 'Claude', cwd: '/project');

    // The live turn as the runtime would drive it: updates go to the state,
    // the permission request is queued and answered as the recording shows.
    AiSessionState playLive() {
      final s = newState()..beginTurn(const [TextBlock('Read hello.txt…')], t0);
      for (final l in live) {
        if (l['dir'] != 'in') continue;
        final msg = l['msg']! as JsonMap;
        final params = msg['params'];
        switch (msg['method']) {
          case 'session/update':
            final u = (params! as JsonMap)['update']! as JsonMap;
            s.applyUpdate(update(u), t0);
          case 'session/request_permission':
            final p = s.addPermission(
              PermissionRequest.fromJson(params! as JsonMap),
              t0,
            );
            expect(p.item.awaitingPermission, isTrue);
            s.resolvePermission(p.id, const PermissionSelected('allow-once'));
        }
      }
      return s;
    }

    List<String> cards(AiSessionState s) => [
      for (final i in s.timeline.items)
        switch (i) {
          ToolItem(:final fields, :final end) =>
            '${fields.kind?.name}:${fields.title}:${end?.name}',
          _ => i.runtimeType.toString(),
        },
    ];

    test('a whole turn: refined card titles, the permission on its card', () {
      final s = playLive();
      expect(cards(s), [
        'UserItem',
        'read:Read hello.txt:completed',
        'edit:Edit hello.txt:completed',
        'execute:ls:completed',
        'AgentTextItem',
      ]);
      final edit = s.timeline.items.whereType<ToolItem>().elementAt(1);
      expect(edit.permissionAnswer!.name, 'Yes');
      expect(edit.awaitingPermission, isFalse);
      expect(s.needsInput, isFalse);
      expect(s.title, 'Hello.txt world to ShellX');
      expect(s.label, 'Hello.txt world to ShellX');
      expect(s.commands, isNotEmpty);
      expect(s.usage!.size, 1000000);
      final text = s.timeline.items.whereType<AgentTextItem>().single.text;
      expect(text, contains('hello ShellX'));

      final end = s.endTurn(
        outcome: TurnOutcome.finished,
        at: t1,
        stopReason: StopReason.endTurn,
      )!;
      expect(end.turn, 1);
      expect(s.phase, AgentPhase.ready);
    }, skip: skip);

    test('session/load draws the same cards as the live turn', () {
      final loaded = newState();
      for (final l in reload) {
        final msg = l['msg']! as JsonMap;
        if (l['dir'] == 'in' && msg['method'] == 'session/update') {
          final u = (msg['params']! as JsonMap)['update']! as JsonMap;
          loaded.applyUpdate(update(u), t0, history: true);
        }
      }
      expect(cards(loaded), cards(playLive()));
      expect(loaded.timeline.turn, 1);
    }, skip: skip);

    test('a restart that keeps the timeline repeats nothing', () {
      final s = playLive();
      final before = cards(s);
      final version = s.version;
      for (final l in reload) {
        final msg = l['msg']! as JsonMap;
        if (l['dir'] == 'in' && msg['method'] == 'session/update') {
          final u = (msg['params']! as JsonMap)['update']! as JsonMap;
          s.applyUpdate(update(u), t0, history: true, timelineToo: false);
        }
      }
      expect(cards(s), before);
      expect(s.version, version);
    }, skip: skip);
  });
}
