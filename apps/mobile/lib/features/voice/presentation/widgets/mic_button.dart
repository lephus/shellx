// apps/mobile/lib/features/voice/presentation/widgets/mic_button.dart
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/voice/presentation/controllers/voice_composer_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// The mic cap at the start of the extra keys row; filled and pulsing while listening.
class MicButton extends StatelessWidget {
  const MicButton({super.key, required this.controller, required this.onTap});

  final VoiceComposerController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Watch((context) {
      final listening = controller.phase.value == VoicePhase.listening;
      final strings = S.of(context);
      return Semantics(
        button: true,
        label: listening ? strings.voiceStopTooltip : strings.voiceMicTooltip,
        child: GestureDetector(
          key: const ValueKey('voice-mic'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              constraints: const BoxConstraints(minWidth: 46),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: listening ? colors.primary : colors.keyboardKey,
                borderRadius: BorderRadius.circular(9),
                boxShadow: const [BoxShadow(color: Color(0x47000000), offset: Offset(0, 1))],
              ),
              child: _Pulse(
                active: listening,
                child: Icon(
                  listening ? Icons.mic : Icons.mic_none,
                  size: 20,
                  color: listening ? colors.onPrimary : colors.keyboardInk,
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// Grows and shrinks the icon while [active]; still when the platform asks for less motion.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
    lowerBound: 0.85,
    upperBound: 1.15,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Pulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final animate = widget.active && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_animation.isAnimating) {
      _animation.repeat(reverse: true);
    } else if (!animate) {
      _animation
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(scale: _animation, child: widget.child);
}
