import 'dart:async';

import 'package:shellx_ai/remote.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/ai/domain/ai_words.dart';
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_session_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// V2-2b B17 "Lịch sử phiên": the agent's earlier sessions in this session's folder, a page at a time ("Tải thêm"),
/// as the agent lists them; the session open here is not offered. Asked while the agent does not run, it says so
/// and asks again once the header shows it running. A tap returns that session's id (the agent's); null when
/// dismissed.
Future<String?> showAiHistorySheet(BuildContext context, AiSessionController controller) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (context) => _HistorySheet(controller: controller),
  );
}

class _HistorySheet extends StatefulWidget {
  const _HistorySheet({required this.controller});

  final AiSessionController controller;

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  final _sessions = <AiPastSession>[];
  String? _current;
  String? _next;

  /// Why the last page did not come (`not_ready`, …); null when it came.
  String? _code;
  var _loading = false;
  var _loaded = false;
  void Function()? _stopWatching;

  @override
  void initState() {
    super.initState();
    unawaited(_load(null));
    // A history asked while the agent did not run comes once it runs (the header says when).
    _stopWatching = effect(() {
      widget.controller.version.value;
      if (_code != 'not_ready' || _loading || !_runs(widget.controller.head)) return;
      scheduleMicrotask(() {
        if (mounted) unawaited(_load(null));
      });
    });
  }

  @override
  void dispose() {
    _stopWatching?.call();
    super.dispose();
  }

  static bool _runs(MirrorHead? head) => head?.phase == 'ready' || head?.phase == 'running';

  Future<void> _load(String? cursor) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _code = null;
    });
    final result = await widget.controller.history(cursor: cursor);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loaded = true;
      final page = result.page;
      if (page == null) {
        _code = result.code;
        return;
      }
      if (cursor == null) _sessions.clear();
      _sessions.addAll(page.sessions);
      _current = page.current;
      _next = page.next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = context.colors;
    final code = _code;
    final shown = [
      for (final p in _sessions)
        if (p.acp != _current) p,
    ];
    Widget line(Key key, String text) => Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(text, style: context.typo.paragraph.copyWith(color: colors.secondaryText)),
    );
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.aiHistory, style: context.typo.heading20.heavy),
              8.sizedHeight,
              if (code == 'not_ready')
                line(const Key('ai.history.notReady'), s.aiHistoryNotReady)
              else if (code != null)
                line(const Key('ai.history.error'), AiWords.failure(s, code) ?? s.somethingWentWrong)
              else if (!_loaded)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (shown.isEmpty && _next == null)
                line(const Key('ai.history.empty'), s.aiHistoryEmpty),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in shown)
                      ListTile(
                        key: ValueKey('ai.history.${p.acp}'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(p.title ?? s.aiUntitled, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: p.at == null ? null : Text(AiWords.historyWhen(p.at)),
                        onTap: () => Navigator.pop(context, p.acp),
                      ),
                  ],
                ),
              ),
              if (_next != null && code == null)
                TextButton(
                  key: const Key('ai.history.more'),
                  onPressed: _loading ? null : () => unawaited(_load(_next)),
                  child: Text(s.aiHistoryMore),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
