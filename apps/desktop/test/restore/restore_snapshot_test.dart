import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/restore/restore_snapshot.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';

final k1 = 'a' * 32, k2 = 'b' * 32, k3 = 'c' * 32;

RestoreSnapshot sample() => RestoreSnapshot(
  savedAt: DateTime.utc(2026, 10, 7, 14, 32),
  cleanExit: false,
  selectedTab: k1,
  workspaces: [
    SavedWorkspace(id: 'default', tabs: [k1]),
  ],
  tabs: [
    SavedTab(
      key: k1,
      name: 'server',
      focused: k2,
      zoomed: k2,
      layout: SavedSplit(
        axis: SplitAxis.row,
        ratio: 0.3,
        first: SavedPane(key: k1, cwd: '/Users/a/w', session: 12),
        second: SavedSplit(
          axis: SplitAxis.column,
          ratio: 0.5,
          first: SavedPane(key: k2, session: 15),
          second: SavedPane(key: k3, cwd: '/tmp', session: 16),
        ),
      ),
    ),
  ],
);

void main() {
  test('pane keys are 32 lowercase hex', () {
    final k = newPaneKey();
    expect(isPaneKey(k), isTrue);
    expect(k, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(isPaneKey('../etc/passwd'), isFalse);
    expect(isPaneKey('A' * 32), isFalse);
  });

  test('JSON round trip, v1 shape', () {
    final text = sample().encode();
    final map = jsonDecode(text) as Map<String, Object?>;
    expect(map['v'], 1);
    expect(map['daemon'], isNull);
    final back = RestoreSnapshot.tryParse(text)!;
    expect(back.encode(), text);
    expect(back.paneKeys, {k1, k2, k3});
    expect(savedLeaves(back.tabs.single.layout).map((p) => p.key), [
      k1,
      k2,
      k3,
    ]);
  });

  test('unknown keys are ignored', () {
    final map = jsonDecode(sample().encode()) as Map<String, Object?>;
    map['future'] = {'x': 1};
    expect(RestoreSnapshot.tryParse(jsonEncode(map)), isNotNull);
  });

  group('rejects (D11)', () {
    Map<String, Object?> base() =>
        jsonDecode(sample().encode()) as Map<String, Object?>;
    Map<String, Object?> firstWorkspace(Map<String, Object?> m) =>
        (m['workspaces']! as List).first as Map<String, Object?>;
    Map<String, Object?> firstLeaf(Map<String, Object?> m) =>
        (((m['tabs']! as List).first as Map)['layout'] as Map)['first']
            as Map<String, Object?>;
    String withCwd(Map<String, Object?> m, String cwd) {
      firstLeaf(m)['cwd'] = cwd;
      return jsonEncode(m);
    }

    String withSession(Map<String, Object?> m, Object session) {
      firstLeaf(m)['session'] = session;
      return jsonEncode(m);
    }

    final cases = <String, String Function()>{
      'not JSON': () => '{"v":1,',
      'not a map': () => '[]',
      'version 2': () => jsonEncode(base()..['v'] = 2),
      'bad key': () {
        final m = base();
        ((m['tabs'] as List).first as Map)['key'] = 'nope';
        return jsonEncode(m);
      },
      'ratio out of range': () {
        final m = base();
        (((m['tabs'] as List).first as Map)['layout'] as Map)['ratio'] = 0.99;
        return jsonEncode(m);
      },
      'duplicate pane key': () {
        final m = base();
        final layout = ((m['tabs'] as List).first as Map)['layout'] as Map;
        ((layout['second'] as Map)['first'] as Map)['pane'] = k1;
        return jsonEncode(m);
      },
      'duplicate tab key': () {
        final m = base();
        final other = 'd' * 32;
        (m['tabs'] as List).add({
          'key': k1,
          'focused': other,
          'layout': {'pane': other},
        });
        return jsonEncode(m);
      },
      'focused not in tree': () {
        final m = base();
        ((m['tabs'] as List).first as Map)['focused'] = 'd' * 32;
        return jsonEncode(m);
      },
      'tab without a pane': () {
        final m = base();
        ((m['tabs'] as List).first as Map).remove('layout');
        return jsonEncode(m);
      },
      'name too long': () {
        final m = base();
        ((m['tabs'] as List).first as Map)['name'] = 'x' * 65;
        return jsonEncode(m);
      },
      'workspace id not a string': () {
        final m = base();
        firstWorkspace(m)['id'] = 5;
        return jsonEncode(m);
      },
      'workspace id empty': () {
        final m = base();
        firstWorkspace(m)['id'] = '';
        return jsonEncode(m);
      },
      'workspace id too long': () {
        final m = base();
        firstWorkspace(m)['id'] = 'w' * 65;
        return jsonEncode(m);
      },
      'duplicate workspace id': () {
        final m = base();
        (m['workspaces']! as List).add({'id': 'default', 'tabs': <String>[]});
        return jsonEncode(m);
      },
      'tab key in two workspaces': () {
        final m = base();
        (m['workspaces']! as List).add({
          'id': 'w2',
          'tabs': [k1],
        });
        return jsonEncode(m);
      },
      'tab key twice in one workspace': () {
        final m = base();
        firstWorkspace(m)['tabs'] = [k1, k1];
        return jsonEncode(m);
      },
      'tab key is a pane of another tab': () {
        final m = base();
        final other = 'd' * 32;
        (m['tabs'] as List).add({
          'key': k2, // a leaf of the first tab
          'focused': other,
          'layout': {'pane': other},
        });
        return jsonEncode(m);
      },
      'cwd empty': () => withCwd(base(), ''),
      'cwd relative': () => withCwd(base(), 'work/shellx'),
      'cwd drive-relative': () => withCwd(base(), r'C:work'),
      'cwd with NUL': () => withCwd(base(), '/tmp/a\u0000b'),
      'cwd with a newline': () => withCwd(base(), '/tmp/a\nb'),
      'cwd with ESC': () => withCwd(base(), '/tmp/\u001b[31m'),
      'cwd with DEL': () => withCwd(base(), '/tmp/\u007f'),
      'cwd with a C1 control': () => withCwd(base(), '/tmp/\u009b31m'),
      'session zero': () => withSession(base(), 0),
      'session negative': () => withSession(base(), -4),
      'session not an int': () => withSession(base(), 1.5),
      'session a string': () => withSession(base(), '12'),
      'more than 32 panes': () {
        final m = base();
        final tabs = m['tabs'] as List;
        for (var i = 0; i < 30; i++) {
          final key = i.toRadixString(16).padLeft(32, '0');
          tabs.add({
            'key': key,
            'focused': key,
            'layout': {'pane': key},
          });
        }
        // 33 panes: one over the limit.
        return jsonEncode(m);
      },
      'deeper than 32': () {
        final m = base();
        Object node = {'pane': 'd' * 32};
        for (var i = 0; i < 33; i++) {
          node = {
            'split': 'row',
            'ratio': 0.5,
            'first': node,
            'second': {'pane': i.toRadixString(16).padLeft(32, '0')},
          };
        }
        ((m['tabs'] as List).first as Map)['layout'] = node;
        return jsonEncode(m);
      },
      'cwd too long': () {
        final m = base();
        final layout = ((m['tabs'] as List).first as Map)['layout'] as Map;
        (layout['first'] as Map)['cwd'] = '/' * 4097;
        return jsonEncode(m);
      },
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      test(key, () => expect(RestoreSnapshot.tryParse(value()), isNull));
    }
  });

  test('32 panes and a 64-character name and workspace id are accepted', () {
    final m = jsonDecode(sample().encode()) as Map<String, Object?>;
    final tabs = m['tabs']! as List;
    (tabs.first as Map)['name'] = 'x' * 64;
    ((m['workspaces']! as List).first as Map)['id'] = 'w' * 64;
    for (var i = 0; i < 29; i++) {
      final key = i.toRadixString(16).padLeft(32, '0');
      tabs.add({
        'key': key,
        'focused': key,
        'layout': {'pane': key},
      });
    }
    final back = RestoreSnapshot.tryParse(jsonEncode(m))!;
    expect(back.paneKeys, hasLength(32));
    expect(back.workspaces.single.id, 'w' * 64);
  });

  test('workspace entries and selectedTab naming no saved tab are dropped', () {
    final m = jsonDecode(sample().encode()) as Map<String, Object?>;
    ((m['workspaces']! as List).first as Map)['tabs'] = [k1, 'd' * 32];
    m['selectedTab'] = 'e' * 32;
    final back = RestoreSnapshot.tryParse(jsonEncode(m))!;
    expect(back.workspaces.single.tabs, [k1]);
    expect(back.selectedTab, isNull);
  });

  test('absolute cwds of POSIX and Windows forms are accepted', () {
    for (final cwd in [
      '/',
      '/Users/a/w',
      r'C:\Users\a',
      r'd:\',
      r'\\srv\share\x',
    ]) {
      final m = jsonDecode(sample().encode()) as Map<String, Object?>;
      ((((m['tabs']! as List).first as Map)['layout'] as Map)['first']
              as Map)['cwd'] =
          cwd;
      final back = RestoreSnapshot.tryParse(jsonEncode(m));
      expect(back, isNotNull, reason: cwd);
      expect(savedLeaves(back!.tabs.single.layout).first.cwd, cwd);
    }
  });

  test('a tab keeps its creating pane key whether or not that pane is a '
      'leaf of its own tree', () {
    // Own leaf (the usual case) is in sample(); here the creating pane has
    // closed, so the key is not a leaf anywhere.
    final m = jsonDecode(sample().encode()) as Map<String, Object?>;
    final other = 'd' * 32;
    (m['tabs']! as List).add({
      'key': 'e' * 32,
      'focused': other,
      'layout': {'pane': other, 'session': null},
    });
    expect(RestoreSnapshot.tryParse(jsonEncode(m)), isNotNull);
  });

  test('sameLayoutAs ignores savedAt and cleanExit', () {
    final a = sample();
    final b = a.copyWith(savedAt: DateTime.utc(2030), cleanExit: true);
    expect(a.sameLayoutAs(b), isTrue);
    final renamed = RestoreSnapshot.tryParse(
      a.encode().replaceFirst('"server"', '"api"'),
    )!;
    expect(a.sameLayoutAs(renamed), isFalse);
  });

  test('buildLayout replaces keys by sessions and drops missing panes', () {
    final layout = sample().tabs.single.layout;
    expect(
      buildLayout(layout, {k1: 7, k2: 8, k3: 9}),
      const PaneSplit(
        axis: SplitAxis.row,
        ratio: 0.3,
        first: PaneLeaf(7),
        second: PaneSplit(
          axis: SplitAxis.column,
          ratio: 0.5,
          first: PaneLeaf(8),
          second: PaneLeaf(9),
        ),
      ),
    );
    expect(
      buildLayout(layout, {k1: 7, k3: 9}),
      const PaneSplit(
        axis: SplitAxis.row,
        ratio: 0.3,
        first: PaneLeaf(7),
        second: PaneLeaf(9),
      ),
    );
    expect(buildLayout(layout, const {}), isNull);
  });
}
