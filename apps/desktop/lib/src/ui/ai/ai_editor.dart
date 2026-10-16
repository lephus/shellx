import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../agent/desktop_services.dart';
import '../../config/config_controller.dart' show shellxConfigProvider;
import '../../platform/editor_links.dart';
import '../terminal/link_layer.dart' show editorDetectorProvider;

/// "Open in editor" (§4.2, §4.4): [path] (relative to [cwd] unless it is
/// absolute) in the editor `link-editor` picks (A10), else shown in the
/// file manager. Never throws; logs only the error's type.
Future<void> aiOpenInEditor(WidgetRef ref, String path, String cwd) async {
  final abs = p.isAbsolute(path) ? path : p.join(cwd, path);
  final opener = ref.read(desktopServicesProvider).urlOpener;
  try {
    final editor = await editorFor(
      ref.read(shellxConfigProvider).config.linkEditor,
      ref.read(editorDetectorProvider),
    );
    if (editor != null) {
      await opener.openInEditor(editor, abs);
    } else {
      await opener.reveal(abs, isDirectory: false);
    }
  } on Object catch (error) {
    debugPrint('ShellX: editor not opened: ${error.runtimeType}');
  }
}
