import 'dart:io';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:test/test.dart';

void main() {
  group('tolerant parsing', () {
    test('wrong types read as absent, never throw', () {
      final r = InitializeResult.fromJson({
        'protocolVersion': '1',
        'agentCapabilities': 'yes',
        'authMethods': [
          1,
          null,
          {'id': 'x'},
          {'id': 'a', 'name': 'A'},
        ],
      });
      expect(r.protocolVersion, 0);
      expect(r.capabilities.loadSession, isFalse);
      expect(
        r.authMethods.single,
        isA<AuthMethodAgent>().having((m) => m.id, 'id', 'a'),
      );
    });

    test('an update without its id or content is UnknownUpdate', () {
      expect(
        SessionUpdate.fromJson({'sessionUpdate': 'tool_call', 'title': 'x'}),
        isA<UnknownUpdate>(),
      );
      expect(
        SessionUpdate.fromJson({'sessionUpdate': 'agent_message_chunk'}),
        isA<UnknownUpdate>(),
      );
      expect(
        SessionUpdate.fromJson({'sessionUpdate': 'usage_update', 'used': 1}),
        isA<UnknownUpdate>(),
      );
      expect(
        SessionUpdate.fromJson({}),
        isA<UnknownUpdate>().having((u) => u.kind, 'kind', isNull),
      );
      expect(
        SessionUpdate.fromJson({
          'sessionUpdate': 'notice',
          'severity': 'info',
          'title': 't',
        }),
        isA<UnknownUpdate>().having((u) => u.kind, 'kind', 'notice'),
      );
    });

    test('unknown enum values', () {
      expect(StopReason.parse('end_turn'), StopReason.endTurn);
      expect(StopReason.parse('paused_for_lunch'), StopReason.other);
      expect(StopReason.parse(null), StopReason.other);
      expect(ToolKind.parse('switch_mode'), ToolKind.switchMode);
      expect(ToolKind.parse('teleport'), ToolKind.other);
      expect(ToolKind.parse(null), isNull);
      expect(ToolCallStatus.parse('in_progress'), ToolCallStatus.inProgress);
      expect(ToolCallStatus.parse('weird'), isNull);
      expect(
        PermissionKind.parse('reject_always'),
        PermissionKind.rejectAlways,
      );
      expect(PermissionKind.parse('maybe'), PermissionKind.other);
      expect(PermissionKind.rejectOnce.isReject, isTrue);
      expect(PermissionKind.allowAlways.isReject, isFalse);
    });

    test('an auth method of an unknown type is kept as AuthMethodOther', () {
      final m = AuthMethod.fromJson({
        'id': 'e',
        'name': 'Env',
        'type': 'env_var',
      });
      expect(
        m,
        isA<AuthMethodOther>().having((m) => m.type, 'type', 'env_var'),
      );
    });

    test('terminal auth keeps args and string env values only', () {
      final m =
          AuthMethod.fromJson({
                'id': 'claude-ai-login',
                'name': 'Claude Subscription',
                'type': 'terminal',
                'args': ['--cli', 'auth', 'login', '--claudeai', 7],
                'env': {'A': '1', 'B': 2},
              })!
              as AuthMethodTerminal;
      expect(m.args, ['--cli', 'auth', 'login', '--claudeai']);
      expect(m.env, {'A': '1'});
    });
  });

  group('tool calls', () {
    test('merge: sent fields replace, absent fields stay', () {
      final start = ToolCallFields.fromJson({
        'title': 'Edit a.txt',
        'kind': 'edit',
        'status': 'pending',
        'content': [
          {'type': 'diff', 'path': '/p/a.txt', 'oldText': 'a', 'newText': 'b'},
        ],
        'locations': [
          {'path': '/p/a.txt', 'line': 3},
        ],
      });
      final merged = start.merge(
        ToolCallFields.fromJson({'status': 'completed', 'content': []}),
      );
      expect(merged.title, 'Edit a.txt');
      expect(merged.kind, ToolKind.edit);
      expect(merged.status, ToolCallStatus.completed);
      expect(merged.content, isEmpty);
      expect(merged.locations!.single.line, 3);
    });

    test('diff without oldText is a new file', () {
      final d =
          ToolContent.fromJson({
                'type': 'diff',
                'path': 'n.txt',
                'newText': 'x',
              })
              as ToolDiff;
      expect(d.oldText, isNull);
      expect(
        ToolContent.fromJson({'type': 'terminal', 'terminalId': 't'}),
        isA<ToolTerminal>(),
      );
      expect(
        ToolContent.fromJson({'type': 'hologram'}),
        isA<ToolContentOther>(),
      );
    });
  });

  group('config options', () {
    test('groups are flattened and keep their group name', () {
      final o = ConfigOption.fromJson({
        'id': 'model',
        'name': 'Model',
        'category': 'model',
        'type': 'select',
        'currentValue': 'opus',
        'options': [
          {
            'group': 'g1',
            'name': 'Anthropic',
            'options': [
              {'value': 'opus', 'name': 'Opus'},
              {'value': 'sonnet', 'name': 'Sonnet'},
            ],
          },
          {
            'group': 'g2',
            'name': 'Other',
            'options': [
              {'value': 'x', 'name': 'X'},
            ],
          },
        ],
      })!;
      expect(o.kind, ConfigKind.select);
      expect(o.choices.map((c) => '${c.group}/${c.value}'), [
        'Anthropic/opus',
        'Anthropic/sonnet',
        'Other/x',
      ]);
      expect(o.currentValue, 'opus');
      expect(o.withValue('sonnet').currentValue, 'sonnet');
    });

    test('boolean options read a bool value', () {
      final o = ConfigOption.fromJson({
        'id': 'fast',
        'name': 'Fast',
        'type': 'boolean',
        'currentValue': true,
      })!;
      expect(o.kind, ConfigKind.boolean);
      expect(o.currentValue, true);
    });

    test('an option without id or name is dropped', () {
      expect(
        readConfigOptions({
          'c': [
            {'name': 'x'},
            {
              'id': 'y',
              'name': 'Y',
              'type': 'select',
              'currentValue': 'a',
              'options': [],
            },
          ],
        }, 'c').single.id,
        'y',
      );
    });
  });

  group('elicitation', () {
    final form =
        ElicitationRequest.fromJson({
              'sessionId': 's',
              'mode': 'form',
              'message': 'Pick',
              'requestedSchema': {
                'type': 'object',
                'properties': {
                  'name': {'type': 'string', 'minLength': 1, 'maxLength': 5},
                  'color': {
                    'type': 'string',
                    'oneOf': [
                      {'const': 'r', 'title': 'Red'},
                      {'const': 'g', 'title': 'Green'},
                    ],
                  },
                  'size': {
                    'type': 'string',
                    'enum': ['s', 'm'],
                  },
                  'count': {'type': 'integer', 'minimum': 1, 'maximum': 3},
                  'ratio': {'type': 'number'},
                  'ok': {'type': 'boolean', 'default': true},
                  'tags': {
                    'type': 'array',
                    'minItems': 1,
                    'items': {
                      'type': 'string',
                      'enum': ['a', 'b'],
                    },
                  },
                  'labels': {
                    'type': 'array',
                    'items': {
                      'anyOf': [
                        {'const': 'x', 'title': 'X'},
                      ],
                    },
                  },
                },
                'required': ['name', 'tags'],
              },
            })
            as ElicitationForm;

    test('fields by type', () {
      expect(form.fields.map((f) => f.runtimeType.toString()), [
        'ElicitTextField',
        'ElicitChoiceField',
        'ElicitChoiceField',
        'ElicitNumberField',
        'ElicitNumberField',
        'ElicitBoolField',
        'ElicitMultiChoiceField',
        'ElicitMultiChoiceField',
      ]);
      expect(
        (form.fields[1] as ElicitChoiceField).options.map((o) => o.title),
        ['Red', 'Green'],
      );
      expect((form.fields[3] as ElicitNumberField).integer, isTrue);
      expect(form.supported, isTrue);
    });

    test('accepts checks required fields, bounds and unknown keys', () {
      expect(
        form.accepts({
          'name': 'abc',
          'tags': ['a'],
        }),
        isTrue,
      );
      expect(
        form.accepts({'name': 'abc'}),
        isFalse,
        reason: 'tags is required',
      );
      expect(
        form.accepts({
          'name': '',
          'tags': ['a'],
        }),
        isFalse,
        reason: 'minLength',
      );
      expect(
        form.accepts({
          'name': 'abcdef',
          'tags': ['a'],
        }),
        isFalse,
        reason: 'maxLength',
      );
      expect(
        form.accepts({
          'name': 'a',
          'tags': ['c'],
        }),
        isFalse,
        reason: 'not an option',
      );
      expect(
        form.accepts({
          'name': 'a',
          'tags': ['a', 'a'],
        }),
        isFalse,
        reason: 'duplicates',
      );
      expect(
        form.accepts({
          'name': 'a',
          'tags': ['a'],
          'count': 4,
        }),
        isFalse,
        reason: 'maximum',
      );
      expect(
        form.accepts({
          'name': 'a',
          'tags': ['a'],
          'count': 2.5,
        }),
        isFalse,
        reason: 'integer',
      );
      expect(
        form.accepts({
          'name': 'a',
          'tags': ['a'],
          'ratio': 2.5,
          'color': 'g',
        }),
        isTrue,
      );
      expect(
        form.accepts({
          'name': 'a',
          'tags': ['a'],
          'extra': 1,
        }),
        isFalse,
        reason: 'unknown key',
      );
    });

    test('an unknown field type makes the form unsupported (spec D22)', () {
      final f =
          ElicitationRequest.fromJson({
                'mode': 'form',
                'message': 'm',
                'requestedSchema': {
                  'type': 'object',
                  'properties': {
                    'file': {'type': 'blob'},
                  },
                },
              })
              as ElicitationForm;
      expect(f.supported, isFalse);
    });

    test('url mode: only http(s) with a host may be opened', () {
      ElicitationUrl url(String u) =>
          ElicitationRequest.fromJson({
                'mode': 'url',
                'message': 'm',
                'elicitationId': 'e',
                'url': u,
              })
              as ElicitationUrl;
      expect(url('https://example.com/a').isWebUrl, isTrue);
      expect(url('http://localhost:8080').isWebUrl, isTrue);
      expect(url('javascript:alert(1)').isWebUrl, isFalse);
      expect(url('file:///etc/passwd').isWebUrl, isFalse);
      expect(url('https://').isWebUrl, isFalse);
      // The two above fail the host check; these have a host and fail only
      // the scheme check.
      expect(url('ftp://example.com/a').isWebUrl, isFalse, reason: 'scheme');
      expect(url('myapp://open/x').isWebUrl, isFalse, reason: 'scheme');
      expect(
        ElicitationRequest.fromJson({'mode': 'url', 'message': 'm'}),
        isA<ElicitationOther>(),
      );
      expect(
        ElicitationRequest.fromJson({'mode': 'telepathy', 'message': 'm'}),
        isA<ElicitationOther>(),
      );
    });

    test('responses', () {
      expect(const ElicitAccept({'a': 1}).toJson(), {
        'action': 'accept',
        'content': {'a': 1},
      });
      expect(const ElicitAccept().toJson(), {'action': 'accept'});
      expect(const ElicitDecline().toJson(), {'action': 'decline'});
      expect(const ElicitCancel().toJson(), {'action': 'cancel'});
    });
  });

  test('blockText joins text and names resource links', () {
    expect(
      blockText(const [
        TextBlock('Fix '),
        ResourceLinkBlock(uri: 'file:///p/a.dart', name: 'a.dart'),
        ImageBlock(data: '', mimeType: 'image/png'),
      ]),
      'Fix @a.dart',
    );
  });

  test('permission outcomes', () {
    expect(const PermissionSelected('allow-once').toJson(), {
      'outcome': {'outcome': 'selected', 'optionId': 'allow-once'},
    });
    expect(const PermissionCancelled().toJson(), {
      'outcome': {'outcome': 'cancelled'},
    });
  });

  test(
    'setConfigOptionParams rejects values that are neither String nor bool',
    () {
      expect(() => setConfigOptionParams('s', 'c', 3), throwsArgumentError);
    },
  );

  test('listSessionsParams sends only the keys it is given', () {
    expect(listSessionsParams(), isEmpty);
    expect(listSessionsParams(cwd: '/p'), {'cwd': '/p'});
    expect(listSessionsParams(cursor: 'c'), {'cursor': 'c'});
    expect(listSessionsParams(cwd: '/p', cursor: 'c'), {
      'cwd': '/p',
      'cursor': 'c',
    });
  });

  test('toString never shows content (spec D20)', () {
    final values = <Object>[
      const TextBlock('secret'),
      const ToolCallFields(title: 'cat secret.txt'),
      SessionUpdate.fromJson({
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'secret'},
      }),
      PermissionRequest.fromJson({
        'sessionId': 's',
        'toolCall': {'toolCallId': 't', 'title': 'secret'},
        'options': [],
      }),
      ElicitationRequest.fromJson({
        'mode': 'form',
        'message': 'secret',
        'requestedSchema': {},
      }),
      const ElicitAccept({'k': 'secret'}),
      const Implementation(name: 'n', version: '1'),
      const McpServerStdio(name: 'n', command: '/secret'),
    ];
    for (final v in values) {
      expect(v.toString(), '…', reason: v.runtimeType.toString());
    }
  });

  test('every ACP class is Redacted (spec D20)', () {
    // The classes of lib/src/acp_*.dart, read from the source, so that a class
    // added later is covered without touching this test. Tests run from the
    // package root, as in conformance_test.dart.
    final source = [
      for (final f in Directory('lib/src').listSync().whereType<File>())
        if (RegExp(r'^acp_\w+\.dart$').hasMatch(f.uri.pathSegments.last))
          f.readAsStringSync(),
    ].join('\n');
    final classes = declaredClasses(source);
    expect(
      classes,
      isNotEmpty,
      reason: 'no class found in lib/src/acp_*.dart: the scan is broken',
    );

    bool redacted(String? name) {
      final c = classes[name];
      return c != null &&
          (c.mixins.contains('Redacted') || redacted(c.superclass));
    }

    final offenders = [
      for (final name in classes.keys)
        if (!redacted(name)) name,
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'toString() of these would show content; add `with Redacted`: '
          '${offenders.join(', ')}',
    );
  });

  test('the Redacted scan reads class headers as Dart writes them', () {
    final classes = declaredClasses(r'''
      /// class InADocComment extends Nothing {
      /* class InABlockComment {} */
      sealed class A with Redacted {}
      final class B extends A {}
      abstract interface class C<T extends A> implements Redacted {}
      final class D<T extends Object>
          extends A
          with Other, Redacted
          implements C<T> {}
      class E {}
    ''');
    expect(classes.keys, ['A', 'B', 'C', 'D', 'E']);
    expect(classes['A']!.mixins, {'Redacted'});
    expect(classes['B']!.superclass, 'A');
    expect(
      classes['C']!.mixins,
      isEmpty,
      reason: 'implements brings no toString',
    );
    expect(
      classes['C']!.superclass,
      isNull,
      reason: '`T extends A` is a bound',
    );
    expect(classes['D']!.superclass, 'A');
    expect(classes['D']!.mixins, {'Other', 'Redacted'});
    expect(classes['E']!.superclass, isNull);
  });
}

/// The superclass and the mixins in the header of a `class` declaration.
typedef ClassHeader = ({String? superclass, Set<String> mixins});

/// The classes declared in the Dart text [source], by name. Only the header
/// after the name is read, as `extends X` and `with A, B`; `implements` names
/// no mixin and brings no `toString`.
Map<String, ClassHeader> declaredClasses(String source) {
  final code = source
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'//[^\n]*'), '');
  final classes = <String, ClassHeader>{};
  for (final m in RegExp(r'\bclass\s+([\w$]+)([^{;]*)').allMatches(code)) {
    // Type arguments go first, innermost out, so that `<T extends X>` is not
    // read as `extends X`.
    var header = m[2]!;
    for (var before = ''; before != header;) {
      before = header;
      header = header.replaceAll(RegExp(r'<[^<>]*>'), '');
    }
    String? superclass;
    final mixins = <String>{};
    var keyword = '';
    for (final word in header.split(RegExp(r'[\s,]+')).where((w) => w != '')) {
      if (word == 'extends' || word == 'with' || word == 'implements') {
        keyword = word;
      } else if (keyword == 'extends') {
        superclass ??= word;
      } else if (keyword == 'with') {
        mixins.add(word);
      }
    }
    classes[m[1]!] = (superclass: superclass, mixins: mixins);
  }
  return classes;
}
