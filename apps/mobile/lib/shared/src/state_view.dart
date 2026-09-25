import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/shared.dart';

class StateView<T extends Equatable> extends StatelessWidget {
  final Widget? loading;
  final Widget Function(AppError?)? errorBuilder;
  final Widget Function(T data) builder;
  final StateSignal<T> state;
  final Future Function()? retry;
  const StateView({
    super.key,
    required this.builder,
    required this.state,
    this.loading,
    this.errorBuilder,
    this.retry,
  });

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final value = state.value;
      if (state.isLoading) {
        return loading ?? AppCircularProgress();
      }
      if (state.hasError) {
        return errorBuilder?.call(state.error) ??
            AppErrorWidget(
              error: state.error,
              retry: retry,
            );
      }
      return builder(value);
    });
  }
}
