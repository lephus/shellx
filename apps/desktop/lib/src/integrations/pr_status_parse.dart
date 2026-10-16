import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A12 D16: what ShellX asks `gh pr view` for. Nothing the user typed is
/// ever part of the arguments, and no title or body is requested.
const String kPrFields =
    'number,state,isDraft,url,reviewDecision,statusCheckRollup,headRefName';

enum PrState { open, draft, merged, closed }

enum PrChecks { passing, failing, pending, none }

enum PrReview { approved, changes }

/// A pull request as the sidebar shows it. [toString] hides everything
/// (spec §5): the number and the address are the user's.
@immutable
final class PrInfo {
  const PrInfo({
    required this.number,
    required this.state,
    required this.checks,
    required this.url,
    this.review,
  });

  final int number;
  final PrState state;
  final PrChecks checks;

  /// `https`, no user information (checked by [parsePrJson]).
  final String url;
  final PrReview? review;

  @override
  bool operator ==(Object other) =>
      other is PrInfo &&
      other.number == number &&
      other.state == state &&
      other.checks == checks &&
      other.url == url &&
      other.review == review;

  @override
  int get hashCode => Object.hash(number, state, checks, url, review);

  @override
  String toString() => '…';
}

/// More than this is not a `gh pr view` answer.
const int kPrJsonMaxBytes = 256 * 1024;
const int _maxChecks = 1000;
const int _maxUrl = 2048;

const Set<String> _failing = {
  'FAILURE',
  'ERROR',
  'TIMED_OUT',
  'CANCELLED',
  'ACTION_REQUIRED',
  'STARTUP_FAILURE',
};
const Set<String> _pending = {
  'PENDING',
  'IN_PROGRESS',
  'QUEUED',
  'EXPECTED',
  'WAITING',
  'REQUESTED',
};

String? _word(Object? v) =>
    v is String && v.isNotEmpty ? v.toUpperCase() : null;

/// The CI rollup of a pull request (pure; spec D16): any failing word ⇒
/// failing; else any pending word or a check with no conclusion ⇒ pending;
/// else an empty list ⇒ none; else passing. A check run has `status` and
/// `conclusion`, a status context has `state`.
PrChecks rollupChecks(Iterable<Map<String, Object?>> items) {
  var any = false;
  var pending = false;
  for (final item in items) {
    any = true;
    final conclusion = _word(item['conclusion']);
    final state = _word(item['state']);
    final status = _word(item['status']);
    for (final w in [conclusion, state, status]) {
      if (w != null && _failing.contains(w)) return PrChecks.failing;
    }
    for (final w in [conclusion, state, status]) {
      if (w != null && _pending.contains(w)) pending = true;
    }
    // No verdict yet (a context with a state has one).
    if (conclusion == null && state == null) pending = true;
  }
  if (!any) return PrChecks.none;
  return pending ? PrChecks.pending : PrChecks.passing;
}

bool _safeUrl(String url) {
  if (url.length > _maxUrl || RegExp(r'[\u0000- \u007f]').hasMatch(url)) {
    return false;
  }
  final uri = Uri.tryParse(url);
  return uri != null &&
      uri.isAbsolute &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      !uri.hasFragment;
}

/// The branch the answer is about (`headRefName`); null when absent.
String? parsePrHead(String stdout) {
  try {
    final json = jsonDecode(stdout);
    final head = json is Map<String, Object?> ? json['headRefName'] : null;
    return head is String ? head : null;
  } on FormatException {
    return null;
  }
}

/// The answer of `gh pr view --json [kPrFields]`, read strictly: anything
/// that is not exactly that shape is null (never a partial answer).
PrInfo? parsePrJson(String stdout) {
  if (stdout.length > kPrJsonMaxBytes) return null;
  final Object? json;
  try {
    json = jsonDecode(stdout);
  } on FormatException {
    return null;
  }
  if (json is! Map<String, Object?>) return null;
  final number = json['number'];
  if (number is! int || number < 1 || number > 0x7fffffff) return null;
  final state = json['state'];
  final draft = json['isDraft'];
  if (state is! String || draft is! bool) return null;
  final prState = switch (state) {
    'OPEN' => draft ? PrState.draft : PrState.open,
    'MERGED' => PrState.merged,
    'CLOSED' => PrState.closed,
    _ => null,
  };
  if (prState == null) return null;
  final url = json['url'];
  if (url is! String || !_safeUrl(url)) return null;
  final rollup = json['statusCheckRollup'];
  final items = <Map<String, Object?>>[];
  if (rollup != null) {
    if (rollup is! List || rollup.length > _maxChecks) return null;
    for (final item in rollup) {
      if (item is! Map<String, Object?>) return null;
      items.add(item);
    }
  }
  final review = switch (json['reviewDecision']) {
    'APPROVED' => PrReview.approved,
    'CHANGES_REQUESTED' => PrReview.changes,
    _ => null,
  };
  return PrInfo(
    number: number,
    state: prState,
    checks: rollupChecks(items),
    url: url,
    review: review,
  );
}
