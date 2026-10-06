import 'package:equatable/equatable.dart';
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';

/// What one final recognition result asks the composer to do (spec §3.2).
sealed class VoiceCommand extends Equatable {
  const VoiceCommand();
}

/// Plain dictation: add [text] to the composer.
final class VoiceAppend extends VoiceCommand {
  const VoiceAppend(this.text);

  final String text;

  @override
  List<Object?> get props => [text];
}

/// The utterance ended with a send keyword: add [text] (without the keyword), then send.
final class VoiceSend extends VoiceCommand {
  const VoiceSend(this.text);

  final String text;

  @override
  List<Object?> get props => [text];
}

/// The utterance ended with a cancel keyword: clear the composer.
final class VoiceCancel extends VoiceCommand {
  const VoiceCancel();

  @override
  List<Object?> get props => const [];
}

abstract final class VoiceCommandParser {
  /// Punctuation and whitespace the recognizer puts after the words ("Gửi.", "send!").
  static final RegExp _trailing = RegExp(r'[\s\p{P}]+$', unicode: true);
  static final RegExp _space = RegExp(r'\s');

  /// A keyword only counts as the **last** word, so "gửi email cho tôi" stays text.
  static VoiceCommand parse(String heard, VoiceLocale locale) {
    final words = heard.trim().replaceAll(_trailing, '');
    final split = words.lastIndexOf(_space);
    final last = words.substring(split + 1).toLowerCase();
    final before = split < 0 ? '' : words.substring(0, split).replaceAll(_trailing, '');
    if (locale.sendWords.contains(last)) return VoiceSend(before);
    if (locale.cancelWords.contains(last)) return const VoiceCancel();
    return VoiceAppend(heard.trim());
  }
}
