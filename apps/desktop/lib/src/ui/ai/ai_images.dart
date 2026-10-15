import 'dart:async';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shellx_ai/remote.dart'
    show aiImageMime, aiTakesNoImages, kAiImageMaxBytes, kAiImagesMax;

import '../../../l10n/app_localizations.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_scope.dart';

// V2-2b B12: the pure image helpers moved where the phone hub reaches them;
// the AI pane keeps using them by these names.
export 'package:shellx_ai/remote.dart'
    show aiImageMime, aiTakesNoImages, kAiImageMaxBytes, kAiImagesMax;

export '../../ai/ai_image_encode.dart'
    show aiEncodeImages, kAiInlineEncodeBytes;

/// ⌘V / Ctrl+V (and Ctrl+Shift+V) in the composer, D16: the files copied in
/// Finder / Explorer first, as in the terminal — the pictures among them
/// attach, as if they were dropped; then the text on the clipboard; an image
/// only when there is no text (a screenshot has none).
class AiPasteIntent extends Intent {
  const AiPasteIntent();
}

/// A BMP or TIFF over this many bytes is not decoded (a 5K screenshot is
/// 45 MB as a BMP).
const int kAiImageConvertMax = 64 << 20;

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

/// D16: [bytes] go with the next message — unless the agent takes no images
/// (the composer says so), there are [kAiImagesMax] already, or they are over
/// [kAiImageMaxBytes] (agents refuse bigger ones): each of these is said in
/// the composer's note, never ignored. A BMP or TIFF goes as a PNG. True: the
/// image is attached. False: it is not (and when that is news to the user,
/// the note says why); a paste that has text never gets here.
///
/// [alive]: false once the widget that asked is gone (the decode of a BMP
/// takes a while): then nothing is touched.
Future<bool> aiAttachImage(
  AiPaneScope scope,
  AppLocalizations l10n,
  Uint8List bytes, {
  bool Function()? alive,
}) async {
  final images = scope.ui.images;
  if (aiTakesNoImages(scope.state)) {
    images.say(l10n.aiImageUnsupported(scope.state.agentName));
    return false;
  }
  // Before any work is done on the bytes.
  if (images.items.length >= kAiImagesMax) {
    images.say(l10n.aiTooManyImages);
    return false;
  }
  var data = bytes;
  var mime = aiImageMime(data);
  if (mime == null && _isBmpOrTiff(data)) {
    if (data.length > kAiImageConvertMax) {
      images.say(l10n.aiImageTooLarge);
      return false;
    }
    final png = await aiPngOf(data);
    if (!(alive?.call() ?? true)) return false;
    if (png != null) {
      data = png;
      mime = 'image/png';
    }
  }
  // Not an image ShellX sends: nothing to say about it.
  if (mime == null) return false;
  if (data.length > kAiImageMaxBytes) {
    images.say(l10n.aiImageTooLarge);
    return false;
  }
  // Another may have come in while this one was decoded.
  if (images.items.length >= kAiImagesMax) {
    images.say(l10n.aiTooManyImages);
    return false;
  }
  images.add(data, mime);
  return true;
}

/// D16 around the composer: a paste attaches the pictures among the files on
/// the clipboard, else pastes the text on it at the cursor, else attaches the
/// image on it; and images dropped on the composer go with the next message. A
/// hidden pane takes no drop (`DropTarget` hears drops while invisible).
class AiImageInput extends StatelessWidget {
  const AiImageInput({super.key, required this.child});
  final Widget child;

  /// What a paste takes from the clipboard, in the terminal's order (A10
  /// D15): files copied in Finder / Explorer first — their name is also on the
  /// clipboard as text, and what someone pasting a copied picture wants is the
  /// picture, as when it is dropped; files that are no pictures leave the
  /// text, their names, to be pasted. Then the text, as Excel, Numbers, Word
  /// and Pages put a picture of what was copied next to its text, and the text
  /// is what someone pasting cells wants. A screenshot carries no file and no
  /// text, so it still attaches. [context] is the widget's: it may be gone
  /// when the clipboard answers.
  Future<void> _paste(BuildContext context) async {
    final scope = AiPaneScope.of(context);
    final l10n = AppLocalizations.of(context);
    final files = await scope.ui.clipboardFiles?.call() ?? const <String>[];
    if (!context.mounted) return;
    final pictures = [
      for (final path in files)
        if (_isImageFile(path)) DropItemFile(path),
    ];
    if (pictures.isNotEmpty) {
      await _attachFiles(context, scope, l10n, pictures);
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!context.mounted) return;
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      scope.ui.paste.value = text;
      return;
    }
    final image = await scope.ui.clipboardImage?.call();
    if (image == null || !context.mounted) return;
    await aiAttachImage(scope, l10n, image, alive: () => context.mounted);
  }

  static const _imageTypes = {
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.bmp',
    '.tif',
    '.tiff',
  };

  /// Whether [path] is named like an image ShellX attaches (a BMP or a TIFF
  /// goes as a PNG).
  static bool _isImageFile(String path) =>
      _imageTypes.contains(p.extension(path).toLowerCase());

  Future<void> _drop(BuildContext context, DropDoneDetails details) =>
      _attachFiles(
        context,
        AiPaneScope.of(context),
        AppLocalizations.of(context),
        details.files,
      );

  /// The files of a drop, or the pictures among those copied (a paste), go
  /// with the next message. A file is read only while it can still be
  /// attached: past [kAiImagesMax] nothing is read (the count is known without
  /// the disk). The reader ([AiPaneUi.readImageFile]) does not read a file
  /// over [kAiImageMaxBytes] either — it looks at its size first and gives
  /// null — and then the user is told why, for an image (by its name): a text
  /// file dropped on a full composer, or one that cannot be read, is just not
  /// attached.
  static Future<void> _attachFiles(
    BuildContext context,
    AiPaneScope scope,
    AppLocalizations l10n,
    Iterable<DropItem> files,
  ) async {
    final images = scope.ui.images;
    for (final f in files) {
      if (f.path.isEmpty) continue;
      final image = _isImageFile(f.path);
      if (images.items.length >= kAiImagesMax) {
        if (!image) continue;
        images.say(l10n.aiTooManyImages);
        return;
      }
      final bytes = await scope.ui.readImageFile?.call(f.path);
      if (!context.mounted) return;
      if (bytes == null) {
        if (image && await _isTooLarge(f)) {
          if (!context.mounted) return;
          images.say(l10n.aiImageTooLarge);
        }
        continue;
      }
      await aiAttachImage(scope, l10n, bytes, alive: () => context.mounted);
      if (!context.mounted) return;
    }
  }

  /// Whether the dropped file is over [kAiImageMaxBytes] (its size is asked
  /// of the file system, the file is not read).
  static Future<bool> _isTooLarge(DropItem file) async {
    try {
      return await file.length() > kAiImageMaxBytes;
    } on Object {
      return false;
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
