import 'package:shellx_mobile/core/core.dart';

class AvailableStateView<T extends Equatable> extends StatelessWidget {
  final StateSignal<T> state;
  final Widget Function(T data) builder;
  const AvailableStateView({super.key, required this.state, required this.builder});

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      return Visibility(
        visible: state.available,
        child: builder(state.value),
      );
    });
  }
}
