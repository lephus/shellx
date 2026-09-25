import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/src/l10n.dart';

class LoadMoreRetryItem extends StatefulWidget {
  const LoadMoreRetryItem({
    super.key,
    required this.onRetry,
  });

  final Future<void> Function() onRetry;

  @override
  State<LoadMoreRetryItem> createState() => _LoadMoreRetryItemState();
}

class _LoadMoreRetryItemState extends State<LoadMoreRetryItem> {
  bool isLoading = false;

  Future<void> retry() async {
    setState(() {
      isLoading = true;
    });
    await widget.onRetry();
    setState(() {
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            S.of(context).loadMoreFailPleaseTryAgain,
            textAlign: TextAlign.center,
          ),
          SizedBox(
            height: 12,
          ),
          Material(
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: retry,
              borderRadius: BorderRadius.circular(12),
              child: Ink(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: context.colors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    Opacity(
                      opacity: isLoading ? 0 : 1,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh,
                            color: context.colors.white,
                          ),
                          SizedBox(
                            width: 8,
                          ),
                          Text(
                            S.of(context).retry,
                            style: TextStyle(
                              color: context.colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned.fill(
                      child: Visibility(
                        visible: isLoading,
                        child: Center(
                          child: CircularProgressIndicator.adaptive(
                            valueColor: AlwaysStoppedAnimation<Color>(context.colors.white),
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
