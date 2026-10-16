import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/restore/restore_snapshot.dart';
import 'package:shellx_desktop/src/terminal/closed_items.dart';

ClosedPane pane(String text, {int tab = 1}) =>
    ClosedPane(tabId: tab, cwd: '/tmp', launch: null, text: text, label: 'x');

ClosedTab tabOf(String key, String text) => ClosedTab(
  tab: SavedTab(
    key: key,
    focused: key,
    layout: SavedPane(key: key, cwd: '/tmp'),
  ),
  textByKey: {key: text},
  workspaceId: 'default',
  index: 0,
  label: 'tab $key',
);

void main() {
  test('pop returns the newest first', () {
    final r = ClosedItems();
    r.push(tabOf('a', 'one'));
    r.push(tabOf('b', 'two'));
    expect((r.pop() as ClosedTab).tab.key, 'b');
    expect((r.pop() as ClosedTab).tab.key, 'a');
    expect(r.pop(), isNull);
  });

  test('keeps at most ten items: the oldest go first (criterion 4)', () {
    final r = ClosedItems();
    for (var i = 0; i < 12; i++) {
      r.push(tabOf('k$i', 'x'));
    }
    expect(r.length, 10);
    var last = '';
    while (r.length > 0) {
      last = (r.pop() as ClosedTab).tab.key;
    }
    expect(last, 'k2');
  });

  test('keeps at most 2 MiB of text: the oldest go first', () {
    final big = 'x' * (900 * 1024);
    final r = ClosedItems();
    r.push(tabOf('a', big));
    r.push(tabOf('b', big));
    r.push(tabOf('c', big));
    expect(r.totalBytes <= 2 * 1024 * 1024, isTrue);
    expect(r.length, 2);
    expect((r.peek() as ClosedTab).tab.key, 'c');
  });

  test('the budget counts UTF-8 bytes, not characters', () {
    // 400 K of "ệ" is 1.2 MB: two of them pass 2 MiB.
    final wide = 'ệ' * (400 * 1024);
    final r = ClosedItems();
    r.push(tabOf('a', wide));
    r.push(tabOf('b', wide));
    expect(r.length, 1);
    expect(r.totalBytes <= 2 * 1024 * 1024, isTrue);
  });

  test('one item larger than the whole budget is kept without its text', () {
    final r = ClosedItems(maxBytes: 100);
    r.push(pane('y' * 500));
    expect(r.length, 1);
    expect((r.peek() as ClosedPane).text, isEmpty);
  });

  test('an item with neither text nor folder is not worth keeping', () {
    final r = ClosedItems();
    r.push(ClosedPane(tabId: 1, cwd: null, launch: null, text: '', label: 'x'));
    expect(r.length, 0);
  });

  test('toString never shows what was in the terminal (privacy)', () {
    expect(pane('secret-token').toString(), '…');
    expect(tabOf('a', 'secret-token').toString(), '…');
    final r = ClosedItems()..push(tabOf('a', 'secret-token'));
    expect(r.toString(), '…');
  });
}
