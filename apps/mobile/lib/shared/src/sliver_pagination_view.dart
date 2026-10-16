import 'package:sliver_tools/sliver_tools.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/src/interface_pagination_view.dart';
import 'package:shellx_mobile/shared/src/load_more_retry_item.dart';

class SliverPaginationView extends InterfacePaginationView {
  final Widget? loading;
  const SliverPaginationView({
    this.loading,
    super.key,
    required super.pagingState,
    required super.itemBuilder,
    super.separatorBuilder,
    super.emptyView,
    super.padding,
    super.noMoreItemsView,
    super.refresh,
  });

  @override
  State<SliverPaginationView> createState() => _SliverPaginationViewState();
}

class _SliverPaginationViewState extends State<SliverPaginationView> with PagingStateMixin<SliverPaginationView> {
  @override
  Widget build(BuildContext context) {
    return Watch(
      (context) {
        return SliverAnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _buildStateContent(context),
        );
      },
    );
  }

  Widget _buildStateContent(BuildContext context) {
    if (pagingState.isLoadingFirstPage) {
      return _buildFillRemaining(widget.loading ?? const FirstPageProgress());
    }

    if (pagingState.isErrorFirstPage) {
      return _buildFillRemaining(
        FirstPageError(
          error: pagingState.state.error,
          onTryAgain: widget.refresh ?? pagingState.refresh,
        ),
      );
    }

    final items = pagingState.value;

    if (items.isEmpty && pagingState.hasReachedEnd) {
      return _buildFillRemaining(widget.emptyView ?? const SizedBox());
    }

    return _buildList(items);
  }

  Widget _buildList(List items) {
    return SliverPadding(
      key: ValueKey('SliverPadding'),
      padding: widget.padding ?? const EdgeInsets.all(0),
      sliver: SliverList.separated(
        key: ValueKey('SliverList'),
        itemCount: items.length + 1,
        itemBuilder: (context, index) => _buildItem(context, index, items),
        separatorBuilder: (context, index) => _buildSeparator(context, index, items),
      ),
    );
  }

  Widget _buildItem(BuildContext context, int index, List items) {
    if (index == items.length) {
      if (pagingState.hasError) {
        return LoadMoreRetryItem(
          onRetry: pagingState.loadMore,
        );
      }
      if (pagingState.hasReachedEnd) {
        return widget.noMoreItemsView ?? const NoMoreItems();
      }
      if (pagingState.isLoading) {
        return const NewPageProgress();
      }
    }
    if (!pagingState.isLoading && !pagingState.hasError) {
      pagingState.determineLoadMore(index);
    }
    return widget.itemBuilder(context, index);
  }

  Widget _buildSeparator(BuildContext context, int index, List items) {
    if (index == items.length - 1) {
      return const SizedBox();
    }
    return widget.separatorBuilder?.call(context, index) ?? const SizedBox();
  }

  Widget _buildFillRemaining(Widget child) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: child,
    );
  }
}
