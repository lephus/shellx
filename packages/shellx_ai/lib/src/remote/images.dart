import 'dart:typed_data';

import '../model/session_state.dart';

/// The most images one message takes (V2-1 D16, V2-2b B12).
const int kAiImagesMax = 5;

/// The largest image a message takes, pasted, dropped or sent from a phone
/// (agents refuse bigger ones).
const int kAiImageMaxBytes = 10 << 20;

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

/// Whether [state]'s agent has said it takes no images (`promptCapabilities.
/// image`). Before `initialize` has answered it has said nothing: a new tab
/// would otherwise tell its user "Claude does not take images" for the first
/// seconds of every session. Nothing is refused then; the composer asks again
/// when the message is sent.
bool aiTakesNoImages(AiSessionState state) =>
    state.agent != null && !state.capabilities.prompt.image;
