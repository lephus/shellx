import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../acp_content.dart';
import '../acp_json.dart';
import '../json_rpc.dart';

/// What a [FakeAgent] does. Plain JSON, so one scenario drives the agent in
/// process and as a process (`bin/fake_agent.dart`).
final class FakeScenario {
  const FakeScenario({
    this.protocolVersion = 1,
    this.loadSession = true,
    this.listSessions = true,
    this.image = true,
    this.authMethods = const [],
    this.requireAuth = false,
    this.authFile,
    this.sessionId = 'sess-1',
    this.configOptions,
    this.modes,
    this.turns = const [],
    this.history = const [],
    this.sessions = const [],
    this.newSessionError,
    this.loadSessionError,
  });

  factory FakeScenario.fromJson(JsonMap j) => FakeScenario(
    protocolVersion: readInt(j, 'protocolVersion') ?? 1,
    loadSession: readBool(j, 'loadSession') ?? true,
    listSessions: readBool(j, 'listSessions') ?? true,
    image: readBool(j, 'image') ?? true,
    authMethods: readMaps(j, 'authMethods').toList(),
    requireAuth: readBool(j, 'requireAuth') ?? false,
    authFile: readString(j, 'authFile'),
    sessionId: readString(j, 'sessionId') ?? 'sess-1',
    configOptions: readList(j, 'configOptions')?.whereType<JsonMap>().toList(),
    modes: readMap(j, 'modes'),
    turns: [
      for (final t in readList(j, 'turns') ?? const <Object?>[])
        if (t is List) t.whereType<JsonMap>().toList(),
    ],
    history: readMaps(j, 'history').toList(),
    sessions: readMaps(j, 'sessions').toList(),
    newSessionError: readMap(j, 'newSessionError'),
    loadSessionError: readMap(j, 'loadSessionError'),
  );

  final int protocolVersion;
  final bool loadSession;
  final bool listSessions;
  final bool image;

  /// Raw ACP `authMethods`.
  final List<JsonMap> authMethods;

  /// `session/new` and `session/load` answer -32000 until signed in.
  final bool requireAuth;

  /// Signed in once this file exists (what a terminal login leaves).
  final String? authFile;
  final String sessionId;
  final List<JsonMap>? configOptions;
  final JsonMap? modes;

  /// Steps per `session/prompt` ([FakeSteps]); the last list repeats.
  final List<List<JsonMap>> turns;

  /// Updates `session/load` replays.
  final List<JsonMap> history;

  /// `session/list` entries.
  final List<JsonMap> sessions;

  /// `{code, message}`: `session/new` fails with it.
  final JsonMap? newSessionError;

  /// `{code, message}`: `session/load` fails with it (e.g. -32002).
  final JsonMap? loadSessionError;

  JsonMap toJson() => {
    'protocolVersion': protocolVersion,
    'loadSession': loadSession,
    'listSessions': listSessions,
    'image': image,
    'authMethods': authMethods,
    'requireAuth': requireAuth,
    if (authFile != null) 'authFile': authFile,
    'sessionId': sessionId,
    if (configOptions != null) 'configOptions': configOptions,
    if (modes != null) 'modes': modes,
    'turns': turns,
    'history': history,
    'sessions': sessions,
    if (newSessionError != null) 'newSessionError': newSessionError,
    if (loadSessionError != null) 'loadSessionError': loadSessionError,
  };
}

/// A scripted ACP agent for tests (spec §7).
final class FakeAgent {
  FakeAgent(
    this.scenario, {
    required Stream<List<int>> input,
    required StreamSink<List<int>> output,
    String? cwd,
    void Function(String line)? stderr,
    void Function(int code)? onExit,
  }) : _output = output,
       _cwd = cwd ?? Directory.current.path,
       _stderr = stderr ?? _ignore,
       _onExit = onExit {
    connection = JsonRpcConnection(
      input: input,
      output: output,
      maxLineChars: 1 << 30,
    );
    _config = [
      for (final o in scenario.configOptions ?? const <JsonMap>[]) {...o},
    ];
    _modes = scenario.modes == null ? null : {...scenario.modes!};
    connection
      ..onRequest('initialize', _initialize)
      ..onRequest('authenticate', _authenticate)
      ..onRequest('session/new', _newSession)
      ..onRequest('session/load', _loadSession)
      ..onRequest('session/list', _list)
      ..onRequest('session/prompt', _prompt)
      ..onRequest('session/set_config_option', _setConfig)
      ..onRequest('session/set_mode', _setMode)
      ..onNotification('session/cancel', _onCancel);
  }

  static void _ignore(String _) {}

  final FakeScenario scenario;
  late final JsonRpcConnection connection;

  /// What arrived, in order (see the task's list of entries).
  final List<String> received = [];

  /// The last params of each method.
  final Map<String, JsonMap> params = {};

  final StreamSink<List<int>> _output;
  final String _cwd;
  final void Function(String) _stderr;
  final void Function(int code)? _onExit;
  late List<JsonMap> _config;
  JsonMap? _modes;
  var _turn = 0;
  var _authenticated = false;
  var _cancelled = false;
  var _cancel = Completer<void>();

  bool get _signedIn {
    final file = scenario.authFile;
    return _authenticated || (file != null && File(file).existsSync());
  }

  void _record(String entry, [String? method, JsonMap? p]) {
    received.add(entry);
    if (method != null && p != null) params[method] = p;
    _stderr('RECV $entry');
  }

  JsonMap _initialize(JsonMap p) {
    _record('initialize', 'initialize', p);
    return {
      'protocolVersion': scenario.protocolVersion,
      'agentCapabilities': {
        'loadSession': scenario.loadSession,
        'promptCapabilities': {
          'image': scenario.image,
          'embeddedContext': true,
        },
        'sessionCapabilities': {
          if (scenario.listSessions) 'list': <String, Object?>{},
        },
      },
      'authMethods': scenario.authMethods,
      'agentInfo': {
        'name': 'fake-agent',
        'title': 'Fake Agent',
        'version': '1.0.0',
      },
    };
  }

  JsonMap _authenticate(JsonMap p) {
    _record('authenticate:${readString(p, 'methodId')}', 'authenticate', p);
    _authenticated = true;
    return {};
  }

  JsonMap _sessionConfig() => {
    if (scenario.configOptions != null) 'configOptions': _config,
    if (_modes != null) 'modes': _modes,
  };

  JsonMap _newSession(JsonMap p) {
    _record('session/new', 'session/new', p);
    final error = scenario.newSessionError;
    if (error != null) {
      throw JsonRpcError(
        readInt(error, 'code') ?? JsonRpcError.internalError,
        readString(error, 'message') ?? '',
      );
    }
    if (scenario.requireAuth && !_signedIn) {
      throw const JsonRpcError(
        JsonRpcError.authRequired,
        'Authentication required',
      );
    }
    return {'sessionId': scenario.sessionId, ..._sessionConfig()};
  }

  JsonMap _loadSession(JsonMap p) {
    final id = readString(p, 'sessionId') ?? '';
    _record('session/load:$id', 'session/load', p);
    if (scenario.requireAuth && !_signedIn) {
      throw const JsonRpcError(
        JsonRpcError.authRequired,
        'Authentication required',
      );
    }
    if (!scenario.loadSession) {
      throw const JsonRpcError(JsonRpcError.methodNotFound, 'Method not found');
    }
    final error = scenario.loadSessionError;
    if (error != null) {
      throw JsonRpcError(
        readInt(error, 'code') ?? JsonRpcError.internalError,
        readString(error, 'message') ?? '',
      );
    }
    for (final u in scenario.history) {
      connection.notify('session/update', {'sessionId': id, 'update': u});
    }
    return _sessionConfig();
  }

  JsonMap _list(JsonMap p) {
    _record('session/list', 'session/list', p);
    return {'sessions': scenario.sessions};
  }

  Future<JsonMap> _prompt(JsonMap p) async {
    final sessionId = readString(p, 'sessionId') ?? '';
    final text = blockText(readMaps(p, 'prompt').map(ContentBlock.fromJson));
    _record('session/prompt:$text', 'session/prompt', p);
    final steps = scenario.turns.isEmpty
        ? const <JsonMap>[]
        : scenario.turns[math.min(_turn, scenario.turns.length - 1)];
    _turn++;
    _cancelled = false;
    _cancel = Completer<void>();
    for (final step in steps) {
      if (_cancelled) return {'stopReason': 'cancelled'};
      final reason = await _run(step, sessionId);
      if (reason != null) return {'stopReason': reason};
    }
    return {'stopReason': _cancelled ? 'cancelled' : 'end_turn'};
  }

  void _onCancel(JsonMap p) {
    _record('session/cancel', 'session/cancel', p);
    _cancelled = true;
    if (!_cancel.isCompleted) _cancel.complete();
  }

  JsonMap _setConfig(JsonMap p) {
    final id = readString(p, 'configId');
    final value = p['value'];
    _record(
      'session/set_config_option:$id=$value',
      'session/set_config_option',
      p,
    );
    _config = [
      for (final o in _config)
        o['id'] == id ? {...o, 'currentValue': value} : o,
    ];
    return {'configOptions': _config};
  }

  JsonMap _setMode(JsonMap p) {
    final id = readString(p, 'modeId') ?? '';
    _record('session/set_mode:$id', 'session/set_mode', p);
    final modes = _modes;
    if (modes != null) {
      modes['currentModeId'] = id;
      connection.notify('session/update', {
        'sessionId': readString(p, 'sessionId'),
        'update': {'sessionUpdate': 'current_mode_update', 'currentModeId': id},
      });
    }
    return {};
  }

  /// Runs one step; a non-null result ends the turn with that stop reason.
  Future<String?> _run(JsonMap step, String sessionId) async {
    final value = step.values.first;
    switch (step.keys.first) {
      case 'update':
        connection.notify('session/update', {
          'sessionId': sessionId,
          'update': value,
        });
      case 'permission':
        final s = value! as JsonMap;
        final r = await connection.request('session/request_permission', {
          'sessionId': sessionId,
          'toolCall': s['toolCall'],
          'options': s['options'],
        });
        final outcome =
            readMap(r is JsonMap ? r : const {}, 'outcome') ??
            const <String, Object?>{};
        final kind = readString(outcome, 'outcome');
        _record(
          'permission:${kind == 'selected' ? readString(outcome, 'optionId') : kind}',
        );
        if (kind == 'cancelled') return 'cancelled';
      case 'ask':
        final r = await connection.request('elicitation/create', {
          'sessionId': sessionId,
          ...value! as JsonMap,
        });
        final answer = r is JsonMap ? r : const <String, Object?>{};
        final content = readMap(answer, 'content');
        _record(
          'ask:${readString(answer, 'action')}${content == null ? '' : '=${jsonEncode(content)}'}',
        );
        if (_cancelled) return 'cancelled';
      case 'completeAsk':
        connection.notify('elicitation/complete', {'elicitationId': value});
      case 'sleep':
        await Future.any([
          Future<void>.delayed(Duration(milliseconds: value! as int)),
          _cancel.future,
        ]);
        if (_cancelled) return 'cancelled';
      case 'waitCancel':
        await _cancel.future;
        return 'cancelled';
      case 'hang':
        await Completer<void>().future;
      case 'exit':
        final onExit = _onExit;
        if (onExit != null) {
          onExit(value! as int);
        } else {
          await connection.close();
        }
        await Completer<void>().future;
      case 'raw':
        try {
          _output.add(utf8.encode('$value\n'));
        } on Object {
          // Closed.
        }
      case 'bigText':
        connection.notify('session/update', {
          'sessionId': sessionId,
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': 'x' * (value! as int)},
          },
        });
      case 'stderr':
        _stderr(value! as String);
      case 'write':
        final w = value! as JsonMap;
        File('$_cwd/${w['path']}')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(w['text']! as String);
      case 'delete':
        final f = File('$_cwd/$value');
        if (f.existsSync()) f.deleteSync();
      case 'stop':
        return value! as String;
      case 'error':
        final e = value! as JsonMap;
        throw JsonRpcError(
          readInt(e, 'code') ?? JsonRpcError.internalError,
          readString(e, 'message') ?? '',
        );
    }
    return null;
  }
}
