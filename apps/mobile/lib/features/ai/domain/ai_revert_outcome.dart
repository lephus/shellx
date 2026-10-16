import 'package:shellx_ai/remote.dart' show AiRevertConfirm;

/// V2-2b B20: how a revert the user asked for on the phone ended. Nothing of it is printed.
sealed class AiRevertOutcome {
  const AiRevertOutcome();
}

/// [count] files went back.
final class AiRevertDone extends AiRevertOutcome {
  const AiRevertDone(this.count);

  final int count;

  @override
  String toString() => 'AiRevertDone(…)';
}

/// The computer asks first: some files changed after the turn ([question], the desktop's B14 question).
final class AiRevertAsk extends AiRevertOutcome {
  const AiRevertAsk(this.question);

  final AiRevertConfirm question;

  @override
  String toString() => 'AiRevertAsk(…)';
}

/// Nothing went back, for [code] (`AiWords.failure` words it).
final class AiRevertFailed extends AiRevertOutcome {
  const AiRevertFailed(this.code);

  final String code;

  @override
  String toString() => 'AiRevertFailed(…)';
}
