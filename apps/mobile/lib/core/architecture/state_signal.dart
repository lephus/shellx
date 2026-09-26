import 'package:signals_flutter/signals_core.dart';
import 'error.dart';
import 'state.dart';

mixin StateSignalMixin<T> on Signal<T> {
  IState _state = InitState();
  IState get state => _state;

  bool get isLoading => state.isLoading;
  bool get hasError => state.hasError;
  bool get available => state.available;
  bool get unavailable => !available;
  AppError? get error => state.error;

  @override
  set value(T val) {
    if (disposed) return;
    set(val);
  }

  void changeStateWithoutImpact(IState state) {
    _state = state;
  }

  void complete(T data) {
    if (disposed) return;
    if (data == peek() && state is SuccessState) return;
    _state = SuccessState();
    set(data, force: true);
  }

  void failure(AppError error) {
    if (disposed) return;
    if (error == state.error && state is ErrorState) return;
    _state = ErrorState(error);
    set(peek(), force: true);
  }

  void loading() {
    if (disposed) return;
    if (state is LoadingState) return;
    _state = LoadingState();
    set(peek(), force: true);
  }

  void init() {
    if (disposed) return;
    if (state is InitState) return;
    _state = InitState();
  }
}

class StateSignal<T> extends Signal<T> with StateSignalMixin<T> {
  StateSignal(super.value);
}
