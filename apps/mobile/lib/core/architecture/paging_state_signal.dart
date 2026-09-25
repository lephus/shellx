import 'dart:developer';
import 'package:async/async.dart';
import 'package:shellx_mobile/core/core.dart';

class PagingStateSignal<T extends Equatable> extends ListSignal<T> with StateSignalMixin<List<T>> {
  PagingStateSignal({
    this.limit = 10,
    this.threshold = 5,
    required this.delegateFetchPage,
  }) : super([]);

  final int limit;
  final int threshold;
  final Future<PageDomain<T>> Function(String? cursor, int limit) delegateFetchPage;

  CancelableOperation<PageDomain<T>>? _cancellableFetch;

  String? _cursor;
  bool _hasReachedEnd = false;

  // MARK: - Public Properties

  bool get hasReachedEnd => _hasReachedEnd;

  /// Returns true if loading the first page (list is empty and loading)
  bool get isLoadingFirstPage => isLoading && isEmpty;

  /// Returns true if error occurred on first page
  bool get isErrorFirstPage => hasError && isEmpty;

  // MARK: - Public Methods

  /// Re-initializes the paging handler.
  /// Clears existing data immediately and fetches the first page.
  Future<void> initialize() async {
    reset();
    await _fetchPage();
  }

  /// Refreshes the list.
  /// Does NOT clear current data until new data arrives (seamless refresh).
  Future<void> refresh() async {
    _cursor = null;
    _hasReachedEnd = false;
    await _fetchPage();
  }

  /// Loads the next page if conditions are met.
  Future<void> loadMore() async {
    if (_canLoadMore) {
      await _fetchPage();
    }
  }

  /// Convenience method for UI scroll listeners to trigger load more.
  Future<void> determineLoadMore(int index) async {
    if (index >= length - threshold) {
      await loadMore();
    }
  }

  /// Resets the handler to its initial state, clearing all data.
  void reset() {
    changeStateWithoutImpact(InitState());
    _hasReachedEnd = false;
    _cursor = null;
    _cancellableFetch?.cancel();
    _cancellableFetch = null;
  }

  // MARK: - Private Helpers

  bool get _canLoadMore => !isLoading && !hasReachedEnd;

  Future<void> _fetchPage() async {
    changeStateWithoutImpact(LoadingState());
    await _cancellableFetch?.cancel();
    // Force notify if consumers rely on checking state properties directly after a signal update
    // set(peek(), force: true);
    if (disposed) return;
    final requestedCursor = _cursor;

    try {
      _cancellableFetch = CancelableOperation.fromFuture(
        delegateFetchPage(requestedCursor, limit),
        onCancel: () => log('Fetch operation cancelled'),
      );

      final page = await _cancellableFetch!.value;

      _handleSuccess(page, isFirstPage: requestedCursor == null);
    } catch (e) {
      _handleError(e as AppError);
    }
  }

  void _handleSuccess(PageDomain<T> page, {required bool isFirstPage}) {
    if (disposed) return;
    changeStateWithoutImpact(SuccessState());

    if (page.elements.length < limit || page.nextCursor == null) {
      _hasReachedEnd = true;
    } else {
      _cursor = page.nextCursor;
    }

    if (isFirstPage) {
      set(page.elements, force: true);
    } else {
      addAll(page.elements);
    }
  }

  void _handleError(AppError error) {
    if (disposed) return;
    log(error.toString());
    changeStateWithoutImpact(ErrorState(error));
    set(peek(), force: true); // Notify listeners of error state
  }
}
