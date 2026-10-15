import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// What the phone's tool server answers by itself (V2-4 E16, §7), in the phone's language.
final class AppToolTexts extends ToolHostTexts {
  const AppToolTexts(this._s);

  final S _s;

  @override
  String refused(int port) => _s.toolRefusedPhone(port);

  @override
  String siblingOff(int port) => _s.toolSiblingOff(port);

  @override
  String get disabled => _s.toolDisabled;

  @override
  String get gone => _s.toolGone;

  @override
  String get needsDesktop => _s.toolNeedsDesktop;

  @override
  String get tooLarge => _s.toolResponseTooLarge;
}
