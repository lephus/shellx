import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/integrations/pr_status_parse.dart';

String pr({
  Object? number = 12,
  Object? state = 'OPEN',
  Object? isDraft = false,
  Object? url = 'https://github.com/o/r/pull/12',
  Object? review = '',
  Object? checks = const [],
}) => jsonEncode({
  'number': number,
  'state': state,
  'isDraft': isDraft,
  'url': url,
  'reviewDecision': review,
  'statusCheckRollup': checks,
});

Map<String, Object?> run(String conclusion, [String status = 'COMPLETED']) => {
  '__typename': 'CheckRun',
  'status': status,
  'conclusion': conclusion,
};

void main() {
  test('open with green checks and an approval', () {
    final p = parsePrJson(
      pr(review: 'APPROVED', checks: [run('SUCCESS'), run('SKIPPED')]),
    )!;
    expect(p.number, 12);
    expect(p.state, PrState.open);
    expect(p.checks, PrChecks.passing);
    expect(p.review, PrReview.approved);
    expect(p.url, 'https://github.com/o/r/pull/12');
  });

  test('draft, merged, closed', () {
    expect(parsePrJson(pr(isDraft: true))!.state, PrState.draft);
    expect(parsePrJson(pr(state: 'MERGED'))!.state, PrState.merged);
    // A merged or closed PR is never "draft".
    expect(
      parsePrJson(pr(state: 'MERGED', isDraft: true))!.state,
      PrState.merged,
    );
    expect(parsePrJson(pr(state: 'CLOSED'))!.state, PrState.closed);
  });

  test('no checks at all', () {
    expect(parsePrJson(pr())!.checks, PrChecks.none);
    expect(parsePrJson(pr(checks: null))!.checks, PrChecks.none);
  });

  test('review decisions', () {
    expect(
      parsePrJson(pr(review: 'CHANGES_REQUESTED'))!.review,
      PrReview.changes,
    );
    expect(parsePrJson(pr(review: 'REVIEW_REQUIRED'))!.review, isNull);
    expect(parsePrJson(pr(review: null))!.review, isNull);
    expect(parsePrJson(pr(review: 'WHATEVER'))!.review, isNull);
  });

  group('CI rollup', () {
    PrChecks of(List<Map<String, Object?>> items) => rollupChecks(items);

    test('every failing word wins over everything', () {
      for (final bad in [
        'FAILURE',
        'ERROR',
        'TIMED_OUT',
        'CANCELLED',
        'ACTION_REQUIRED',
        'STARTUP_FAILURE',
      ]) {
        expect(
          of([run('SUCCESS'), run(bad), run('', 'IN_PROGRESS')]),
          PrChecks.failing,
          reason: bad,
        );
      }
    });

    test('pending words, and a null conclusion', () {
      for (final status in [
        'PENDING',
        'IN_PROGRESS',
        'QUEUED',
        'EXPECTED',
        'WAITING',
        'REQUESTED',
      ]) {
        expect(
          of([run('SUCCESS'), run('', status)]),
          PrChecks.pending,
          reason: status,
        );
      }
      expect(
        of([
          run('SUCCESS'),
          {'status': 'COMPLETED'},
        ]),
        PrChecks.pending,
      );
      expect(
        of([
          {'status': 'COMPLETED', 'conclusion': null},
        ]),
        PrChecks.pending,
      );
    });

    test('status contexts use their state', () {
      Map<String, Object?> ctx(String s) => {
        '__typename': 'StatusContext',
        'state': s,
      };
      expect(of([ctx('SUCCESS')]), PrChecks.passing);
      expect(of([ctx('FAILURE')]), PrChecks.failing);
      expect(of([ctx('ERROR')]), PrChecks.failing);
      expect(of([ctx('PENDING')]), PrChecks.pending);
      expect(of([ctx('EXPECTED'), ctx('SUCCESS')]), PrChecks.pending);
    });

    test('empty is none; passing needs every item done', () {
      expect(of([]), PrChecks.none);
      expect(
        of([run('SUCCESS'), run('NEUTRAL'), run('SKIPPED')]),
        PrChecks.passing,
      );
    });

    test('lower case is read like upper case', () {
      expect(of([run('failure')]), PrChecks.failing);
      expect(of([run('success')]), PrChecks.passing);
    });
  });

  test('an unknown state is not a PR', () {
    expect(parsePrJson(pr(state: 'WEIRD')), isNull);
    expect(parsePrJson(pr(state: null)), isNull);
    expect(parsePrJson(pr(state: 1)), isNull);
  });

  test('the url must be https without userinfo, host and control chars', () {
    expect(parsePrJson(pr(url: 'http://github.com/o/r/pull/1')), isNull);
    expect(
      parsePrJson(pr(url: 'https://user:pw@github.com/o/r/pull/1')),
      isNull,
    );
    expect(parsePrJson(pr(url: 'https://user@github.com/o/r/pull/1')), isNull);
    expect(parsePrJson(pr(url: 'javascript:alert(1)')), isNull);
    expect(parsePrJson(pr(url: 'file:///etc/passwd')), isNull);
    expect(parsePrJson(pr(url: 'https:///x')), isNull);
    expect(parsePrJson(pr(url: 'https://github.com/o/r\n/pull/1')), isNull);
    expect(parsePrJson(pr(url: 'https://github.com/${'a' * 3000}')), isNull);
    expect(parsePrJson(pr(url: 12)), isNull);
    expect(parsePrJson(pr(url: null)), isNull);
  });

  test('the number must be a positive integer', () {
    expect(parsePrJson(pr(number: 0)), isNull);
    expect(parsePrJson(pr(number: -3)), isNull);
    expect(parsePrJson(pr(number: '12')), isNull);
    expect(parsePrJson(pr(number: 1.5)), isNull);
    expect(parsePrJson(pr(number: 99999999999)), isNull);
  });

  test('garbage in, null out', () {
    for (final text in [
      '',
      'not json',
      '[]',
      '12',
      'null',
      '{',
      '{"number": 1}',
      pr(checks: 'x'),
      pr(checks: [1, 2]),
      pr(isDraft: 'yes'),
      '\u0000' * 10,
    ]) {
      expect(parsePrJson(text), isNull, reason: text);
    }
  });

  test('a huge answer is refused before it is parsed', () {
    expect(
      parsePrJson(pr(checks: List.filled(200000, run('SUCCESS')))),
      isNull,
    );
  });

  test('toString hides everything', () {
    expect(parsePrJson(pr())!.toString(), '…');
  });
}
