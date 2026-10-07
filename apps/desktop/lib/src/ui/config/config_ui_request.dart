import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ConfigUiRequest { palette, problems, shortcuts, settings }

/// The tray (and the CLI, later) asks the window to open an A9 surface;
/// the counter makes two equal requests distinct.
final configUiRequestProvider =
    NotifierProvider<ConfigUiRequests, (ConfigUiRequest, int)?>(
      ConfigUiRequests.new,
    );

class ConfigUiRequests extends Notifier<(ConfigUiRequest, int)?> {
  int _n = 0;

  @override
  (ConfigUiRequest, int)? build() => null;

  void request(ConfigUiRequest kind) => state = (kind, ++_n);
}
