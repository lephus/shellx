import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'agent_catalog.dart';
import 'login_shell_env.dart';
import 'probe.dart';

/// Finds out whether an agent can start, and with which command (spec D6).
final class AgentResolver {
  AgentResolver({
    required this.agentsDir,
    bool? isWindows,
    ProbeRunner? probe,
    this.files = const RealFileProbe(),
  }) : isWindows = isWindows ?? Platform.isWindows,
       _probe = probe ?? runProbe;

  /// `<app support>/ai/agents`.
  final String agentsDir;
  final bool isWindows;
  final FileProbe files;
  final ProbeRunner _probe;

  p.Context get _p =>
      p.Context(style: isWindows ? p.Style.windows : p.Style.posix);

  /// Where [spec]'s npm package is installed (one prefix per agent).
  String prefixFor(AgentSpec spec) => _p.join(agentsDir, spec.id);

  Future<AgentReadiness> resolve(AgentSpec spec, LoginEnv env) async =>
      switch (spec.launch) {
        final NpmLaunch l => await _npm(spec, l, env.vars),
        PathLaunch(:final command, :final args) => _path(
          command,
          args,
          env.vars,
        ),
        CustomLaunch(:final command, :final args, env: final extra) => _path(
          command,
          args,
          {...env.vars, ...extra},
        ),
      };

  Future<AgentReadiness> _npm(
    AgentSpec spec,
    NpmLaunch l,
    Map<String, String> vars,
  ) async {
    final node = findExecutable(
      'node',
      vars,
      isWindows: isWindows,
      files: files,
    );
    if (node == null) return AgentNeedsNode(required: l.minNode);
    final found = (await _probe(node, const [
      '--version',
    ], environment: vars))?.stdout.trim();
    final major = int.tryParse(
      RegExp(r'^v?(\d+)\.').firstMatch(found ?? '')?.group(1) ?? '',
    );
    if (major == null || major < l.minNode) {
      return AgentNeedsNode(required: l.minNode, found: found);
    }
    final prefix = prefixFor(spec);
    final pkgDir = _p.joinAll([
      prefix,
      'node_modules',
      ...l.package.split('/'),
    ]);
    final pkg = _json(files.read(_p.join(pkgDir, 'package.json')));
    if (pkg?['version'] == l.version) {
      final entry = _p.normalize(_p.join(pkgDir, _bin(pkg!, l)));
      if (files.isFile(entry)) {
        return AgentReady(
          AgentCommand(
            executable: node,
            args: [entry, ...l.args],
            environment: vars,
          ),
        );
      }
    }
    return AgentNeedsInstall(_install(node, prefix, l, vars));
  }

  AgentReadiness _path(
    String command,
    List<String> args,
    Map<String, String> vars,
  ) {
    final exe = findExecutable(
      command,
      vars,
      isWindows: isWindows,
      files: files,
    );
    if (exe != null) {
      return AgentReady(
        AgentCommand(executable: exe, args: args, environment: vars),
      );
    }
    final shim =
        isWindows &&
        findExecutable(
              command,
              vars,
              isWindows: true,
              files: files,
              shims: true,
            ) !=
            null;
    return AgentNotFound(command, shimOnly: shim);
  }

  AgentCommand? _install(
    String node,
    String prefix,
    NpmLaunch l,
    Map<String, String> vars,
  ) {
    final args = [
      'install',
      '--prefix',
      prefix,
      '--no-audit',
      '--no-fund',
      '--save-exact',
      '${l.package}@${l.version}',
    ];
    if (isWindows) {
      // npm.cmd would need cmd.exe; npm-cli.js ships next to node.
      final cli = _p.join(
        _p.dirname(node),
        'node_modules',
        'npm',
        'bin',
        'npm-cli.js',
      );
      if (!files.isFile(cli)) return null;
      return AgentCommand(
        executable: node,
        args: [cli, ...args],
        environment: vars,
        workingDirectory: prefix,
      );
    }
    final npm = findExecutable('npm', vars, isWindows: false, files: files);
    if (npm == null) return null;
    return AgentCommand(
      executable: npm,
      args: args,
      environment: vars,
      workingDirectory: prefix,
    );
  }

  static Map<String, Object?>? _json(String? text) {
    if (text == null) return null;
    try {
      final j = jsonDecode(text);
      return j is Map<String, Object?> ? j : null;
    } on FormatException {
      return null;
    }
  }

  static String _bin(Map<String, Object?> pkg, NpmLaunch l) {
    final bin = pkg['bin'];
    if (bin is String) return bin;
    if (bin is Map) {
      final named = bin[l.package.split('/').last];
      if (named is String) return named;
      if (bin.length == 1 && bin.values.first is String) {
        return bin.values.first as String;
      }
    }
    return l.bin;
  }
}
