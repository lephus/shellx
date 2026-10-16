import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// V2-5a A32, §6.2 rule 1: SF Mono is never in the repository and never
/// declared as a font. Runs from `packages/shellx_design`; the workspace
/// root is two levels up.
void main() {
  final root = Directory('../..').absolute;

  // Build output, dependencies, tools' caches and other worktrees: not the
  // repository's own files.
  const skipped = {
    '.git',
    '.dart_tool',
    '.claude',
    '.gradle',
    '.symlinks',
    'build',
    'ephemeral',
    'node_modules',
    'Pods',
    'target',
  };

  Iterable<File> files(Directory dir) sync* {
    for (final entity in dir.listSync(followLinks: false)) {
      final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (entity is Directory) {
        if (!skipped.contains(name)) yield* files(entity);
      } else if (entity is File) {
        yield entity;
      }
    }
  }

  test('the workspace root is the repository', () {
    expect(File('${root.path}/pubspec.yaml').existsSync(), isTrue);
    expect(Directory('${root.path}/apps/desktop').existsSync(), isTrue);
    expect(Directory('${root.path}/apps/mobile').existsSync(), isTrue);
  });

  test('no SF Mono file anywhere in the repository', () {
    final named = RegExp(r'SF-?Mono|SFNSMono', caseSensitive: false);
    final found = [
      for (final f in files(root))
        if (named.hasMatch(f.uri.pathSegments.last)) f.path,
    ];
    expect(found, isEmpty);
  });

  test('no pubspec declares an "SF Mono" font', () {
    final family = RegExp(
      r'''family:\s*["']?SF\s*Mono''',
      caseSensitive: false,
    );
    final pubspecs = [
      for (final f in files(root))
        if (f.uri.pathSegments.last == 'pubspec.yaml') f,
    ];
    expect(pubspecs.length, greaterThanOrEqualTo(10));
    final declaring = [
      for (final f in pubspecs)
        if (family.hasMatch(f.readAsStringSync())) f.path,
    ];
    expect(declaring, isEmpty);
  });
}
