import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shellx_ai/remote.dart' show aiImageMime, kAiImageMaxBytes, kAiImagesMax;
import 'package:shellx_core/shellx_core.dart' show kAiMaxBlobPartBytes, kAiMaxPromptFiles;

/// V2-2b B12: where the photos of a message come from.
enum AiImageOrigin { library, camera }

/// What the computer holds of a phone's images at once (V2-2b B12): past it the computer drops the message's
/// earliest images and the prompt that names them is refused, on every retry. So one message carries no more.
const int kAiMessageImageBytes = 20 << 20;

/// V2-2b B12: an image picked for the next message, as it will be sent: its bytes (made by the picker, at most
/// 2048 px a side, JPEG 85) and their type by their first bytes. Identity is the object: the same bytes picked
/// twice are two images. Never logged.
final class AiPickedImage {
  AiPickedImage(this.bytes, this.mime);

  final Uint8List bytes;
  final String mime;

  /// The `ai.blob` parts it takes (`MachineAi.uploadImage` sends it in pieces of [kAiMaxBlobPartBytes]).
  int get parts => bytes.isEmpty ? 1 : (bytes.length + kAiMaxBlobPartBytes - 1) ~/ kAiMaxBlobPartBytes;

  @override
  String toString() => 'AiPickedImage(…)';
}

/// Why a picked image did not join the message.
enum AiImageProblem {
  /// Not PNG, JPEG, GIF or WebP (a HEIC the picker did not convert, say).
  type,

  /// Over [kAiImageMaxBytes].
  size,

  /// Would bring the images of the message past what is left of [kAiMessageImageBytes] (F34).
  total,
}

/// V2-2b B12: what of [picked] can go with the next message, [room] places left (of [kAiImagesMax]) and
/// [bytesLeft] bytes left of [kAiMessageImageBytes] (what the images already in the message left): the images
/// of a type a computer takes, by their first bytes, of at most [kAiImageMaxBytes], in order, together within
/// [bytesLeft] (F34: a photo that would pass it stays out, a smaller one after it may still join). [problem]
/// says why one was left out (the last reason met); null when none was. Images beyond [room] are left out
/// silently (the picker was asked for no more).
({List<AiPickedImage> images, AiImageProblem? problem}) aiTakePicked(
  List<Uint8List> picked, {
  required int room,
  int bytesLeft = kAiMessageImageBytes,
}) {
  final images = <AiPickedImage>[];
  AiImageProblem? problem;
  var taken = 0;
  for (final bytes in picked) {
    if (images.length >= room) break;
    final mime = aiImageMime(bytes);
    if (mime == null) {
      problem = AiImageProblem.type;
      continue;
    }
    if (bytes.length > kAiImageMaxBytes) {
      problem = AiImageProblem.size;
      continue;
    }
    if (taken + bytes.length > bytesLeft) {
      problem = AiImageProblem.total;
      continue;
    }
    taken += bytes.length;
    images.add(AiPickedImage(bytes, mime));
  }
  return (images: images, problem: problem);
}

/// V2-2b B13: a file mention being typed — the `@` at [start] and the [query] after it, up to the cursor.
typedef AiMentionToken = ({int start, String query});

/// V2-2b B13: `@` mentions in the AI composer, as the desktop's composer has them (D16): the token being typed
/// at the cursor, the path that replaces it, and the paths still mentioned when the message goes.
abstract final class AiMentions {
  /// The longest query sent to the computer, in UTF-8 bytes; a longer one asks nothing.
  static const int maxQueryBytes = 200;

  /// The most suggestions shown.
  static const int maxSuggestions = 8;

  /// The `@query` that ends at the cursor of [value]: an `@` at the start of the text or after a space, then at
  /// least one character and no space up to the cursor. Null for anything else: no collapsed cursor, no `@`
  /// (or one inside a word: `me@host`), an empty or too long query.
  static AiMentionToken? tokenAt(TextEditingValue value) {
    final selection = value.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final text = value.text;
    final end = selection.baseOffset;
    if (end <= 0 || end > text.length) return null;
    var at = end - 1;
    while (at >= 0 && text[at] != '@') {
      if (text[at].trim().isEmpty) return null;
      at--;
    }
    if (at < 0) return null;
    if (at > 0 && text[at - 1].trim().isNotEmpty) return null;
    final query = text.substring(at + 1, end);
    if (query.isEmpty || utf8.encode(query).length > maxQueryBytes) return null;
    return (start: at, query: query);
  }

  /// [value] with [token] replaced by `@path ` and the cursor after it.
  static TextEditingValue insert(TextEditingValue value, AiMentionToken token, String path) {
    final mention = '@$path ';
    final end = token.start + 1 + token.query.length;
    final text = value.text.replaceRange(token.start, end, mention);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: token.start + mention.length),
    );
  }

  /// The paths of [remembered] whose `@path` is still in [text], at most [kAiMaxPromptFiles]: a mention deleted
  /// from the text does not go.
  static List<String> stillMentioned(String text, Iterable<String> remembered) => [
    for (final path in remembered)
      if (text.contains('@$path')) path,
  ].take(kAiMaxPromptFiles).toList();
}
