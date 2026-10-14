import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// D5: whether [path] is a folder that exists. A seam: widget tests never
/// touch the disk under fake async.
final aiFolderExistsProvider = Provider<Future<bool> Function(String path)>(
  (ref) =>
      (path) => Directory(path).exists(),
);

/// D5: what the user typed as a project folder, made absolute: `~` is the
/// home folder. Null when it is not an absolute path.
String? aiFolderFrom(String typed, {required String home}) {
  var text = typed.trim();
  if (text == '~') text = home;
  if (text.startsWith('~/') || text.startsWith(r'~\')) {
    text = p.join(home, text.substring(2));
  }
  if (text.isEmpty || !p.isAbsolute(text)) return null;
  return p.normalize(text);
}
