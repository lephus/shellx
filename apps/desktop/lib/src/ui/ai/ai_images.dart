import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../ai/ai_off_thread.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_scope.dart';

/// ⌘V / Ctrl+V (and Ctrl+Shift+V) in the composer, D16: an image on the
/// clipboard first, else the text.
class AiPasteIntent extends Intent {
  const AiPasteIntent();
}

/// The most images one message takes.
const int kAiImagesMax = 5;

/// The largest image a message takes, pasted or dropped (agents refuse
/// bigger ones).
const int kAiImageMaxBytes = 10 << 20;

/// A BMP or TIFF over this many bytes is not decoded (a 5K screenshot is
/// 45 MB as a BMP).
const int kAiImageConvertMax = 64 << 20;

/// Above this many bytes of images in a message, base64 runs off the UI
/// isolate (smoothness: 10 MiB is ~100 ms of it).
const int kAiInlineEncodeBytes = 256 << 10;

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

/// A BMP (what Windows puts a screenshot on the clipboard as) or a TIFF:
/// formats agents do not take.
bool _isBmpOrTiff(Uint8List bytes) {
  bool starts(List<int> sig) {
    if (bytes.length < sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (bytes[i] != sig[i]) return false;
    }
    return true;
  }

  return starts([0x42, 0x4D]) ||
      starts([0x49, 0x49, 0x2A, 0x00]) ||
      starts([0x4D, 0x4D, 0x00, 0x2A]);
}

/// [bytes], an image the engine can decode (a BMP, a TIFF…), as a PNG; null
/// when they are none.
Future<Uint8List?> aiPngOf(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  } on Object {
    return null;
  }
}

/// D16: [bytes] go with the next message — when the agent takes images
/// (`promptCapabilities.image`); otherwise the composer says it does not.
/// A BMP or TIFF goes as a PNG. False: these bytes are not an image ShellX
/// can send (or are over [kAiImageMaxBytes]); the paste then falls back to
/// the text on the clipboard.
Future<bool> aiAttachImage(
  AiPaneScope scope,
  AppLocalizations l10n,
  Uint8List bytes,
) async {
  final images = scope.ui.images;
  if (!scope.state.capabilities.prompt.image) {
    images.say(l10n.aiImageUnsupported(scope.state.agentName));
    return true;
  }
  var data = bytes;
  var mime = aiImageMime(data);
  if (mime == null && _isBmpOrTiff(data) && data.length <= kAiImageConvertMax) {
    final png = await aiPngOf(data);
    if (png != null) {
      data = png;
      mime = 'image/png';
    }
  }
  if (mime == null || data.length > kAiImageMaxBytes) return false;
  if (images.items.length >= kAiImagesMax) return true;
  images.add(data, mime);
  return true;
}

String _base64(Uint8List bytes) => base64Encode(bytes);

/// [images] as base64 for the `image` blocks, off the UI isolate when they
/// are many bytes.
Future<List<String>> aiEncodeImages(OffThread run, List<Uint8List> images) {
  final bytes = images.fold<int>(0, (n, b) => n + b.length);
  return bytes > kAiInlineEncodeBytes
      ? Future.wait([for (final b in images) run(_base64, b)])
      : Future.value([for (final b in images) _base64(b)]);
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
    if (image != null && await aiAttachImage(scope, l10n, image)) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) scope.ui.paste.value = text;
  }

  Future<void> _drop(BuildContext context, DropDoneDetails details) async {
    final scope = AiPaneScope.of(context);
    final l10n = AppLocalizations.of(context);
    for (final f in details.files) {
      if (f.path.isEmpty) continue;
      final bytes = await scope.ui.readImageFile?.call(f.path);
      if (bytes != null) await aiAttachImage(scope, l10n, bytes);
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
      enable: aiPaneShown(context),
      onDragDone: (details) => unawaited(_drop(context, details)),
      child: child,
    ),
  );
}

/// The images going with the next message, each with "Remove image", and
/// what the composer has to say about images. [focus] is the composer's: a
/// removed image leaves the keyboard where it was.
class AiAttachments extends StatelessWidget {
  const AiAttachments({super.key, this.focus});

  final FocusNode? focus;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final images = AiPaneScope.of(context).ui.images;
    final dpr = MediaQuery.devicePixelRatioOf(context);
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
                          // Decoded at its own size, not the whole image.
                          child: Image.memory(
                            image.bytes,
                            height: 40,
                            cacheHeight: (40 * dpr).ceil(),
                            gaplessPlayback: true,
                            errorBuilder: (context, error, stack) => const Icon(
                              Icons.broken_image_outlined,
                              size: 20,
                              color: ShellxDesktopColors.textSecondary,
                            ),
                          ),
                        ),
                        IconButton(
                          key: Key('ai.image.remove.$i'),
                          tooltip: l10n.aiRemoveImage,
                          iconSize: 12,
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            images.remove(i);
                            focus?.requestFocus();
                          },
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
