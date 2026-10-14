import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/dockerfile.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/scss.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart' show Mode;
import 'package:re_highlight/styles/atom-one-dark.dart';

import '../../../l10n/app_localizations.dart';
import '../../ai/ai_project_files.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_editor.dart';
import 'ai_scope.dart';
import 'ai_theme.dart';

/// D17: how a file is coloured, by its name; null: plain text.
Mode? aiLanguageOf(String path) {
  final name = p.basename(path).toLowerCase();
  if (name == 'dockerfile') return langDockerfile;
  return switch (p.extension(name)) {
    '.dart' => langDart,
    '.js' || '.mjs' || '.cjs' || '.jsx' => langJavascript,
    '.ts' || '.tsx' => langTypescript,
    '.json' => langJson,
    '.yaml' || '.yml' => langYaml,
    '.py' => langPython,
    '.go' => langGo,
    '.rs' => langRust,
    '.java' => langJava,
    '.kt' || '.kts' => langKotlin,
    '.swift' => langSwift,
    '.c' || '.h' => langC,
    '.cc' || '.cpp' || '.hpp' || '.mm' => langCpp,
    '.cs' => langCsharp,
    '.rb' => langRuby,
    '.php' => langPhp,
    '.sh' || '.bash' || '.zsh' => langBash,
    '.md' => langMarkdown,
    '.html' || '.xml' || '.svg' => langXml,
    '.css' => langCss,
    '.scss' => langScss,
    '.sql' => langSql,
    '.toml' || '.ini' || '.cfg' => langIni,
    _ => null,
  };
}

/// §4.4 (Files), §4.2 (`read` cards, "View whole file"): a file of the
/// session folder over the conversation, read-only (D17 `re_editor`), at
/// [line] when given. "Mention in chat" puts `@path` in the composer;
/// "Open in editor" uses `link-editor`. Binary and over-1-MiB files say so.
/// Esc or × closes it.
class AiFileViewer extends ConsumerStatefulWidget {
  const AiFileViewer({super.key, required this.path, this.line});

  /// Relative to the session folder.
  final String path;

  /// 1-based (ACP `locations[].line`).
  final int? line;

  @override
  ConsumerState<AiFileViewer> createState() => _AiFileViewerState();
}

class _AiFileViewerState extends ConsumerState<AiFileViewer> {
  CodeLineEditingController? _code;
  AiFileContent? _content;
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(_load(AiPaneScope.of(context).state.cwd));
  }

  @override
  void dispose() {
    _code?.dispose();
    super.dispose();
  }

  Future<void> _load(String cwd) async {
    final content = await ref
        .read(aiProjectFilesProvider)
        .read(p.join(cwd, widget.path));
    if (!mounted) return;
    setState(() {
      _content = content;
      if (content is AiFileText) {
        _code = CodeLineEditingController.fromText(content.text);
      }
    });
    final code = _code;
    final line = widget.line;
    if (code == null || line == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = (line - 1).clamp(0, code.codeLines.length - 1);
      code.selection = CodeLineSelection.collapsed(index: index, offset: 0);
      code.makeCursorCenterIfInvisible();
    });
  }

  void _mention() {
    final ui = AiPaneScope.of(context).ui;
    ui.insert.value = '@${widget.path} ';
    ui.closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pane = AiPaneScope.of(context);
    final content = _content;
    final code = _code;
    final language = aiLanguageOf(widget.path);
    final Widget body = switch (content) {
      null => const SizedBox.shrink(),
      AiFileBinary() => _Note(l10n.aiBinaryFile),
      AiFileTooLarge() => _Note(l10n.aiFileTooLarge),
      AiFileMissing() => _Note(l10n.aiFileMissing),
      AiFileText() => CodeEditor(
        key: const Key('ai.viewer.code'),
        controller: code,
        readOnly: true,
        autofocus: false,
        showCursorWhenReadOnly: false,
        wordWrap: false,
        style: CodeEditorStyle(
          fontFamily: kAiMono.fontFamily,
          fontSize: kAiMono.fontSize,
          backgroundColor: ShellxDesktopColors.surfaceInset,
          textColor: ShellxDesktopColors.textPrimary,
          codeTheme: CodeHighlightTheme(
            languages: {
              if (language != null)
                'code': CodeHighlightThemeMode(mode: language),
            },
            theme: atomOneDarkTheme,
          ),
        ),
        indicatorBuilder:
            (context, editingController, chunkController, notifier) =>
                DefaultCodeLineNumber(
                  controller: editingController,
                  notifier: notifier,
                ),
      ),
    };
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): pane.ui.closeOverlay,
      },
      child: Focus(
        autofocus: true,
        child: Container(
          key: const Key('ai.viewer'),
          margin: const EdgeInsets.all(ShellxSpace.s16),
          padding: const EdgeInsets.all(ShellxSpace.s12),
          decoration: BoxDecoration(
            color: ShellxDesktopColors.surface,
            borderRadius: BorderRadius.circular(ShellxRadius.r8),
            border: Border.all(color: ShellxDesktopColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ShellxText.bodyStrong.copyWith(
                            color: ShellxDesktopColors.textPrimary,
                          ),
                        ),
                        Text(
                          l10n.aiReadOnly,
                          style: ShellxText.caption.copyWith(
                            color: ShellxDesktopColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('ai.viewer.mention'),
                    tooltip: l10n.aiMentionInChat,
                    iconSize: 16,
                    onPressed: _mention,
                    icon: const Icon(Icons.alternate_email),
                  ),
                  IconButton(
                    tooltip: l10n.aiOpenInEditor,
                    iconSize: 16,
                    onPressed: () => unawaited(
                      aiOpenInEditor(ref, widget.path, pane.state.cwd),
                    ),
                    icon: const Icon(Icons.open_in_new),
                  ),
                  IconButton(
                    key: const Key('ai.viewer.close'),
                    tooltip: l10n.actionClose,
                    iconSize: 16,
                    onPressed: pane.ui.closeOverlay,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: ShellxSpace.s8),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    key: const Key('ai.viewer.note'),
    style: ShellxText.body.copyWith(color: ShellxDesktopColors.textSecondary),
  );
}
