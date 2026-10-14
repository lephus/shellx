import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_scope.dart';

/// ⌘V / Ctrl+V (and Ctrl+Shift+V) in the composer, D16: an image on the
/// clipboard first, else the text.
class AiPasteIntent extends Intent {
  const AiPasteIntent();
}

/// The most images one message takes.
const int kAiImagesMax = 5;

/// The image type of [bytes] by their first bytes (PNG, JPEG, GIF, WebP);
/// null: not an image ShellX sends.
String? aiImageMime(Uint8List bytes) {
  bool starts(List<int> sig, [int at = 0]) {
    if (bytes.length < at + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (bytes[at + i] != sig[i]) return false;
    }
    return true;
  }

  if (starts([0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (starts([0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (starts([0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (starts([0x52, 0x49, 0x46, 0x46]) && starts([0x57, 0x45, 0x42, 0x50], 8)) {
    return 'image/webp';
  }
  return null;
}

/// D16: [bytes] go with the next message — when the agent takes images
/// (`promptCapabilities.image`); otherwise the composer says it does not.
void aiAttachImage(AiPaneScope scope, AppLocalizations l10n, Uint8List bytes) {
  final images = scope.ui.images;
  if (!scope.state.capabilities.prompt.image) {
    images.say(l10n.aiImageUnsupported(scope.state.agentName));
    return;
  }
  final mime = aiImageMime(bytes);
  if (mime == null || images.items.length >= kAiImagesMax) return;
  images.add(bytes, mime);
}

/// D16 around the composer: a paste looks for an image on the clipboard
/// first (else pastes the text at the cursor), and images dropped on it go
/// with the next message. A hidden pane takes no drop (`DropTarget` hears
/// drops while invisible).
class AiImageInput extends StatelessWidget {
  const AiImageInput({super.key, required this.child});
  final Widget child;

  Future<void> _paste(BuildContext context) async {
    final scope = AiPaneScope.of(context);
    final l10n = AppLocalizations.of(context);
    final image = await scope.ui.clipboardImage?.call();
    if (image != null) {
      aiAttachImage(scope, l10n, image);
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) scope.ui.insert.value = text;
  }

  Future<void> _drop(BuildContext context, DropDoneDetails details) async {
    final scope = AiPaneScope.of(context);
    final l10n = AppLocalizations.of(context);
    for (final f in details.files) {
      if (f.path.isEmpty) continue;
      final bytes = await scope.ui.readImageFile?.call(f.path);
      if (bytes != null) aiAttachImage(scope, l10n, bytes);
    }
  }

  @override
  Widget build(BuildContext context) => Actions(
    actions: {
      AiPasteIntent: CallbackAction<AiPasteIntent>(
        onInvoke: (_) {
          unawaited(_paste(context));
          return null;
        },
      ),
    },
    child: DropTarget(
      enable: TickerMode.valuesOf(context).enabled,
      onDragDone: (details) => unawaited(_drop(context, details)),
      child: child,
    ),
  );
}

/// The images going with the next message, each with "Remove image", and
/// what the composer has to say about images.
class AiAttachments extends StatelessWidget {
  const AiAttachments({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final images = AiPaneScope.of(context).ui.images;
    return ListenableBuilder(
      listenable: images,
      builder: (context, _) {
        if (images.items.isEmpty && images.note == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            ShellxSpace.s8,
            ShellxSpace.s8,
            ShellxSpace.s8,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: ShellxSpace.s6,
                children: [
                  for (final (i, image) in images.items.indexed)
                    Row(
                      key: Key('ai.image.$i'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(ShellxRadius.r6),
                          child: Image.memory(
                            image.bytes,
                            height: 40,
                            gaplessPlayback: true,
                          ),
                        ),
                        IconButton(
                          key: Key('ai.image.remove.$i'),
                          tooltip: l10n.aiRemoveImage,
                          iconSize: 12,
                          visualDensity: VisualDensity.compact,
                          onPressed: () => images.remove(i),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                ],
              ),
              if (images.note case final note?)
                Text(
                  note,
                  key: const Key('ai.image.note'),
                  style: ShellxText.caption.copyWith(
                    color: ShellxDesktopColors.warn,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
