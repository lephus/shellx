import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:test/test.dart';

final _root =
    jsonDecode(File('test/fixtures/acp-schema-1.25.0.json').readAsStringSync())
        as Map<String, Object?>;
final _schemas = <String, JsonSchema>{};

/// One `$defs` entry of the ACP schema as a schema of its own.
JsonSchema def(String name) => _schemas.putIfAbsent(
  name,
  () => JsonSchema.create({
    for (final e in _root.entries)
      if (e.key != 'anyOf' && e.key != 'title') e.key: e.value,
    r'$ref': '#/\$defs/$name',
  }),
);

void valid(String name, Object? json) {
  final r = def(name).validate(json);
  expect(r.isValid, isTrue, reason: '$name: ${r.errors.take(3).join(' | ')}');
}

/// A sample an agent could send: valid against [name], then parsed.
T sample<T>(String name, JsonMap json, T Function(JsonMap) parse) {
  valid(name, json);
  return parse(json);
}

void main() {
  test('the fixture is ACP schema v1 (draft 2020-12)', () {
    expect(_root[r'$schema'], contains('2020-12'));
    expect((_root[r'$defs']! as Map).containsKey('InitializeRequest'), isTrue);
  });

  group('what ShellX sends is valid ACP', () {
    test('initialize (spec D1)', () {
      final p = initializeParams(clientVersion: '2.0.0');
      valid('InitializeRequest', p);
      expect(p, {
        'protocolVersion': 1,
        'clientCapabilities': {
          'fs': {'readTextFile': false, 'writeTextFile': false},
          'terminal': false,
          'auth': {'terminal': true},
          'elicitation': {'form': {}, 'url': {}},
        },
        'clientInfo': {'name': 'shellx', 'title': 'ShellX', 'version': '2.0.0'},
      });
    });

    test('session requests', () {
      valid('AuthenticateRequest', authenticateParams('console-login'));
      valid('NewSessionRequest', newSessionParams(cwd: '/p'));
      valid(
        'NewSessionRequest',
        newSessionParams(
          cwd: '/p',
          mcpServers: const [
            McpServerStdio(
              name: 'fs',
              command: '/bin/fs',
              args: ['-v'],
              env: {'K': 'V'},
            ),
          ],
        ),
      );
      valid('LoadSessionRequest', loadSessionParams(sessionId: 's', cwd: '/p'));
      valid('ListSessionsRequest', listSessionsParams());
      valid('ListSessionsRequest', listSessionsParams(cwd: '/p', cursor: 'c'));
      valid('CancelNotification', cancelParams('s'));
      valid('SetSessionModeRequest', setModeParams('s', 'plan'));
      valid(
        'SetSessionConfigOptionRequest',
        setConfigOptionParams('s', 'model', 'opus'),
      );
      valid(
        'SetSessionConfigOptionRequest',
        setConfigOptionParams('s', 'fast', true),
      );
      expect(setConfigOptionParams('s', 'fast', true)['type'], 'boolean');
    });

    test('prompt with text, image and a resource link', () {
      valid(
        'PromptRequest',
        promptParams('s', const [
          TextBlock('Fix the bug in '),
          ResourceLinkBlock(
            uri: 'file:///p/lib/a.dart',
            name: 'a.dart',
            mimeType: 'text/x-dart',
          ),
          ImageBlock(data: 'iVBORw0KGgo=', mimeType: 'image/png'),
        ]),
      );
    });

    test('answers to the agent', () {
      valid(
        'RequestPermissionResponse',
        const PermissionSelected('allow-once').toJson(),
      );
      valid('RequestPermissionResponse', const PermissionCancelled().toJson());
      valid(
        'CreateElicitationResponse',
        const ElicitAccept({
          'name': 'a',
          'n': 2,
          'ok': true,
          'tags': ['x'],
        }).toJson(),
      );
      valid('CreateElicitationResponse', const ElicitAccept().toJson());
      valid('CreateElicitationResponse', const ElicitDecline().toJson());
      valid('CreateElicitationResponse', const ElicitCancel().toJson());
    });
  });

  group('what agents send parses', () {
    test('initialize result (Claude adapter 0.90.0 shape)', () {
      final r = sample('InitializeResponse', {
        'protocolVersion': 1,
        'agentCapabilities': {
          'loadSession': true,
          'promptCapabilities': {'image': true, 'embeddedContext': true},
          'mcpCapabilities': {'http': true, 'sse': true},
          // Typed: an untyped `{}` here is a Map<dynamic, dynamic>, which
          // jsonDecode (what the connection delivers) never produces.
          'sessionCapabilities': {
            'list': <String, Object?>{},
            'close': <String, Object?>{},
            'resume': <String, Object?>{},
          },
        },
        'authMethods': [
          {
            'id': 'claude-ai-login',
            'name': 'Claude Subscription',
            'type': 'terminal',
            'args': ['--cli', 'auth', 'login', '--claudeai'],
          },
          {
            'id': 'console-login',
            'name': 'Anthropic Console',
            'type': 'terminal',
            'args': ['--cli', 'auth', 'login', '--console'],
          },
        ],
        'agentInfo': {
          'name': '@agentclientprotocol/claude-agent-acp',
          'title': 'Claude Agent',
          'version': '0.90.0',
        },
      }, InitializeResult.fromJson);
      expect(r.protocolVersion, 1);
      expect(r.capabilities.loadSession, isTrue);
      expect(r.capabilities.prompt.image, isTrue);
      expect(r.capabilities.listSessions, isTrue);
      expect(r.authMethods.map((m) => m.id), [
        'claude-ai-login',
        'console-login',
      ]);
      expect(
        (r.authMethods.first as AuthMethodTerminal).args.last,
        '--claudeai',
      );
      expect(r.agentInfo!.title, 'Claude Agent');
    });

    test('new session with config options and modes', () {
      final r = sample('NewSessionResponse', {
        'sessionId': 'sess-1',
        'modes': {
          'currentModeId': 'default',
          'availableModes': [
            {'id': 'default', 'name': 'Manual'},
            {'id': 'plan', 'name': 'Plan'},
          ],
        },
        'configOptions': [
          {
            'id': 'mode',
            'name': 'Mode',
            'category': 'mode',
            'type': 'select',
            'currentValue': 'default',
            'options': [
              {'value': 'default', 'name': 'Manual'},
              {'value': 'acceptEdits', 'name': 'Accept edits'},
            ],
          },
          {
            'id': 'model',
            'name': 'Model',
            'category': 'model',
            'type': 'select',
            'currentValue': 'opus',
            'options': [
              {
                'group': 'a',
                'name': 'Anthropic',
                'options': [
                  {'value': 'opus', 'name': 'Opus'},
                ],
              },
            ],
          },
          {
            'id': 'fast',
            'name': 'Fast',
            'type': 'boolean',
            'currentValue': false,
          },
        ],
      }, NewSessionResult.fromJson);
      expect(r.sessionId, 'sess-1');
      expect(r.modes!.available.map((m) => m.id), ['default', 'plan']);
      expect(r.configOptions!.map((o) => o.kind), [
        ConfigKind.select,
        ConfigKind.select,
        ConfigKind.boolean,
      ]);
    });

    JsonMap note(JsonMap update) => {'sessionId': 's', 'update': update};
    SessionUpdate update(JsonMap u) => sample(
      'SessionNotification',
      note(u),
      (n) => SessionUpdate.fromJson(n['update']! as JsonMap),
    );

    test('every update kind ShellX draws', () {
      expect(
        update({
          'sessionUpdate': 'user_message_chunk',
          'content': {'type': 'text', 'text': 'hi'},
        }),
        isA<UserMessageChunk>().having(
          (u) => (u.content as TextBlock).text,
          'text',
          'hi',
        ),
      );
      expect(
        update({
          'sessionUpdate': 'agent_message_chunk',
          'messageId': 'm1',
          'content': {'type': 'text', 'text': 'Hello'},
        }),
        isA<AgentMessageChunk>().having((u) => u.messageId, 'messageId', 'm1'),
      );
      expect(
        update({
          'sessionUpdate': 'agent_thought_chunk',
          'content': {'type': 'text', 'text': '…'},
        }),
        isA<AgentThoughtChunk>(),
      );
      final call =
          update({
                'sessionUpdate': 'tool_call',
                'toolCallId': 'toolu_1',
                'title': 'Edit src/cart.js',
                'kind': 'edit',
                'status': 'pending',
                'content': [
                  {
                    'type': 'diff',
                    'path': '/p/src/cart.js',
                    'oldText': 'a',
                    'newText': 'b',
                  },
                ],
                'locations': [
                  {'path': '/p/src/cart.js', 'line': 12},
                ],
                'rawInput': {'file_path': '/p/src/cart.js'},
              })
              as ToolCallStarted;
      expect(call.toolCallId, 'toolu_1');
      expect(call.fields.kind, ToolKind.edit);
      expect((call.fields.content!.single as ToolDiff).newText, 'b');
      final done =
          update({
                'sessionUpdate': 'tool_call_update',
                'toolCallId': 'toolu_1',
                'status': 'completed',
                'content': [
                  {
                    'type': 'content',
                    'content': {'type': 'text', 'text': 'ok'},
                  },
                ],
              })
              as ToolCallUpdated;
      expect(done.fields.status, ToolCallStatus.completed);
      expect(done.fields.title, isNull);
      expect(
        update({
          'sessionUpdate': 'plan',
          'entries': [
            {'content': 'Read', 'priority': 'high', 'status': 'in_progress'},
          ],
        }),
        isA<PlanUpdated>().having(
          (u) => u.entries.single.status,
          'status',
          PlanStatus.inProgress,
        ),
      );
      expect(
        update({
          'sessionUpdate': 'available_commands_update',
          'availableCommands': [
            {
              'name': 'review',
              'description': 'Review code',
              'input': {'hint': 'files'},
            },
          ],
        }),
        isA<CommandsUpdated>().having(
          (u) => u.commands.single.hint,
          'hint',
          'files',
        ),
      );
      expect(
        update({
          'sessionUpdate': 'current_mode_update',
          'currentModeId': 'plan',
        }),
        isA<ModeUpdated>(),
      );
      expect(
        update({
          'sessionUpdate': 'config_option_update',
          'configOptions': [
            {
              'id': 'mode',
              'name': 'Mode',
              'type': 'select',
              'currentValue': 'plan',
              'options': [
                {'value': 'plan', 'name': 'Plan'},
              ],
            },
          ],
        }),
        isA<ConfigUpdated>().having(
          (u) => u.options.single.currentValue,
          'value',
          'plan',
        ),
      );
      expect(
        update({'sessionUpdate': 'session_info_update', 'title': 'Fix cart'}),
        isA<SessionInfoUpdated>()
            .having((u) => u.title, 'title', 'Fix cart')
            .having((u) => u.hasTitle, 'has', isTrue),
      );
      expect(
        update({
          'sessionUpdate': 'usage_update',
          'used': 32000,
          'size': 200000,
          'cost': {'amount': 0.12, 'currency': 'USD'},
        }),
        isA<UsageUpdated>().having((u) => u.usage.percent, 'percent', 16),
      );
    });

    test('permission request with the Claude options', () {
      final r = sample('RequestPermissionRequest', {
        'sessionId': 's',
        'toolCall': {
          'toolCallId': 'toolu_1',
          'title': 'Edit src/cart.js',
          'kind': 'edit',
        },
        'options': [
          {'optionId': 'allow-once', 'name': 'Yes', 'kind': 'allow_once'},
          {
            'optionId': 'allow-with-updates',
            'name': 'Yes, allow all edits during this session',
            'kind': 'allow_always',
          },
          {'optionId': 'reject', 'name': 'No', 'kind': 'reject_once'},
        ],
      }, PermissionRequest.fromJson);
      expect(r.toolCallId, 'toolu_1');
      expect(r.toolCall.title, 'Edit src/cart.js');
      expect(r.options.map((o) => o.kind), [
        PermissionKind.allowOnce,
        PermissionKind.allowAlways,
        PermissionKind.rejectOnce,
      ]);
    });

    test('elicitation requests', () {
      final f =
          sample('CreateElicitationRequest', {
                'sessionId': 's',
                'toolCallId': 't',
                'mode': 'form',
                'message': 'Which approach?',
                'requestedSchema': {
                  'type': 'object',
                  'properties': {
                    'approach': {
                      'type': 'string',
                      'title': 'Approach',
                      'oneOf': [
                        {'const': 'a', 'title': 'Patch'},
                        {'const': 'b', 'title': 'Rewrite'},
                      ],
                    },
                  },
                  'required': ['approach'],
                },
              }, ElicitationRequest.fromJson)
              as ElicitationForm;
      expect(f.toolCallId, 't');
      expect(f.fields.single, isA<ElicitChoiceField>());
      final u =
          sample('CreateElicitationRequest', {
                'sessionId': 's',
                'mode': 'url',
                'message': 'Sign in to the MCP server',
                'elicitationId': 'e1',
                'url': 'https://example.com/oauth',
              }, ElicitationRequest.fromJson)
              as ElicitationUrl;
      expect(u.elicitationId, 'e1');
    });

    test('session list and prompt response', () {
      final l = sample('ListSessionsResponse', {
        'sessions': [
          {
            'sessionId': 'a',
            'cwd': '/p',
            'title': 'Fix cart',
            'updatedAt': '2026-10-14T09:00:00Z',
          },
        ],
        'nextCursor': 'n',
      }, ListSessionsResult.fromJson);
      expect(l.sessions.single.title, 'Fix cart');
      expect(l.nextCursor, 'n');
      for (final r in StopReason.values.where((r) => r != StopReason.other)) {
        valid('PromptResponse', {'stopReason': r.wire});
      }
    });
  });
}
