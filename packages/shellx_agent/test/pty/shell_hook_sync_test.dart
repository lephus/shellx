@TestOn('vm')
library;

import 'dart:io';

import 'package:shellx_agent/src/pty/shell_hook_scripts.dart';
import 'package:test/test.dart';

/// The lines of [text] without indentation or blank lines.
List<String> _lines(String text) => [
  for (final line in text.split('\n'))
    if (line.trim().isNotEmpty) line.trim(),
];

bool _containsInOrder(List<String> haystack, List<String> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var j = 0;
    while (j < needle.length && haystack[i + j] == needle[j]) {
      j++;
    }
    if (j == needle.length) return true;
  }
  return false;
}

/// The inner-shell branch of each `term/shell/block.*` carries the same hook
/// code as ShellX sessions (push spec §4.5), so both behave alike.
void main() {
  final shellDir = '${Directory.current.path}/../../term/shell';
  final cases = {
    'block.zsh': zshHookBody,
    'block.bash': bashHookBody,
    'block.ps1': powerShellHookBody,
  };
  for (final MapEntry(key: file, value: body) in cases.entries) {
    test('$file contains the session hook code', () {
      final block = File('$shellDir/$file').readAsStringSync();
      expect(_containsInOrder(_lines(block), _lines(body)), isTrue);
    });
  }
}
