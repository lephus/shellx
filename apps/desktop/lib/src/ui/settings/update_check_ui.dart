import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/agent_controller.dart';
import '../../agent/update_check.dart';

/// What the "Check for updates" row shows: nothing yet, a check under way,
/// or its result.
final class UpdateCheckUi {
  const UpdateCheckUi({this.checking = false, this.result});
  final bool checking;
  final UpdateCheckResult? result;
}

final updateCheckUiProvider =
    NotifierProvider<UpdateCheckUiNotifier, UpdateCheckUi>(
      UpdateCheckUiNotifier.new,
    );

/// A12 D20: one manual check at a time, shared by the Settings row and the
/// palette entry. The answer stays until the next check.
class UpdateCheckUiNotifier extends Notifier<UpdateCheckUi> {
  @override
  UpdateCheckUi build() => const UpdateCheckUi();

  Future<void> check() async {
    if (state.checking) return;
    state = const UpdateCheckUi(checking: true);
    UpdateCheckResult result;
    try {
      result = await ref
          .read(agentControllerProvider.notifier)
          .checkForUpdateNow();
    } on Object {
      result = const Failed();
    }
    if (!ref.mounted) return;
    state = UpdateCheckUi(result: result);
  }
}
