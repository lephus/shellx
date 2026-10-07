import 'package:fake_async/fake_async.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/find_session.dart';
import 'package:xterm/xterm.dart';

const _dim = Color(0x405FD4E2);
const _hot = Color(0x8C5FD4E2);

(Terminal, TerminalController, FindSession) rig(String text) {
  final t = Terminal(maxLines: 500)..resize(30, 5);
  t.write(text);
  final c = TerminalController();
  return (
    t,
    c,
    FindSession(
      terminal: t,
      controller: c,
      matchColor: _dim,
      currentColor: _hot,
    ),
  );
}

void main() {
  test(
    'typing finds matches, picks the last, paints one hot and the rest dim',
    () {
      final (_, c, s) = rig('one error\r\ntwo error\r\nthree error');
      s.setQuery('error');
      expect(s.matches, hasLength(3));
      expect(s.current, 2);
      expect(c.highlights, hasLength(3));
      expect(c.highlights.where((h) => h.color == _hot), hasLength(1));
      expect(c.highlights.where((h) => h.color == _dim), hasLength(2));
      s.close();
    },
  );

  test('next and previous wrap around and move the hot highlight', () {
    final (_, c, s) = rig('a\r\na\r\na');
    s.setQuery('a');
    expect(s.current, 2);
    s.next();
    expect(s.current, 0);
    s.previous();
    expect(s.current, 2);
    s.previous();
    expect(s.current, 1);
    expect(c.highlights.where((h) => h.color == _hot), hasLength(1));
    s.close();
  });

  test('every step reveals the match it lands on', () {
    final (_, _, s) = rig('a\r\nb\r\na');
    final seen = <int>[];
    s.reveal = (m) => seen.add(m.startRow);
    s.setQuery('a');
    s.next();
    expect(seen, [2, 0]);
    s.close();
  });

  test('no match: no highlight, current -1, steps do nothing', () {
    final (_, c, s) = rig('hello');
    s.setQuery('zzz');
    expect(s.current, -1);
    expect(c.highlights, isEmpty);
    s.next();
    s.previous();
    expect(s.current, -1);
    s.close();
  });

  test('match case narrows the matches', () {
    final (_, _, s) = rig('Error error');
    s.setQuery('error');
    expect(s.matches, hasLength(2));
    s.toggleMatchCase();
    expect(s.matches, hasLength(1));
    s.close();
  });

  test('line breaks never enter the query; it is cut at 200', () {
    final (_, _, s) = rig('x');
    s.setQuery('a\r\nb');
    expect(s.query, 'ab');
    s.setQuery('q' * 500);
    expect(s.query.length, kMaxFindQuery);
    s.close();
  });

  test('new output refreshes the matches after 150 ms, keeping the place', () {
    fakeAsync((async) {
      final (t, _, s) = rig('err 1\r\nerr 2');
      s.setQuery('err');
      s.previous(); // on match 0
      expect(s.current, 0);
      t.write('\r\nerr 3');
      expect(s.matches, hasLength(2), reason: 'not at once');
      async.elapse(const Duration(milliseconds: 151));
      expect(s.matches, hasLength(3));
      expect(s.current, 0, reason: 'the user stays where they were');
      s.close();
    });
  });

  test('close leaves no highlight and no anchor, and stops listening', () {
    fakeAsync((async) {
      final (t, c, s) = rig('a a a');
      s.setQuery('a');
      expect(c.highlights, hasLength(3));
      final lineAnchors = t.buffer.lines[0].anchors.length;
      expect(lineAnchors, greaterThan(0));
      s.close();
      expect(c.highlights, isEmpty);
      expect(t.buffer.lines[0].anchors, isEmpty);
      t.write('\r\na');
      async.elapse(const Duration(seconds: 1)); // would search if listening
      expect(c.highlights, isEmpty);
    });
  });

  test('changing the query replaces the highlights, never piling them up', () {
    final (_, c, s) = rig('ab ab ab');
    s.setQuery('ab');
    s.setQuery('b');
    expect(c.highlights, hasLength(3));
    s.setQuery('');
    expect(c.highlights, isEmpty);
    s.close();
  });

  test('toString never shows the query', () {
    final (_, _, s) = rig('x');
    s.setQuery('secret');
    expect(s.toString(), isNot(contains('secret')));
    s.close();
  });
}
