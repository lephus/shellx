import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/restore/restore_snapshot.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';

final k1 = '1' * 32, k2 = '2' * 32;

RestoreSnapshot snap(SavedPaneNode layout, {String? key}) => RestoreSnapshot(
  savedAt: DateTime.utc(2026, 10, 7, 14, 32),
  cleanExit: false,
  selectedTab: key ?? k1,
  workspaces: [
    SavedWorkspace(id: 'default', tabs: [key ?? k1]),
  ],
  tabs: [SavedTab(key: key ?? k1, focused: k1, layout: layout)],
);

/// The A11 reader of a pane, copied before this change: it knows no
/// `agent` key (an older build reading a newer file).
SavedPaneNode legacyRead(Object? raw) {
  final m = raw! as Map<String, Object?>;
  if (m.containsKey('pane')) {
    final key = m['pane']! as String;
    final cwd = m['cwd'] as String?;
    if (!isPaneKey(key)) throw const FormatException('pane key');
    if (cwd != null && !isRestorableCwd(cwd)) {
      throw const FormatException('cwd');
    }
    return SavedPane(key: key, cwd: cwd, session: m['session'] as int?);
  }
  return SavedSplit(
    axis: SplitAxis.values.byName(m['split']! as String),
    ratio: (m['ratio']! as num).toDouble(),
    first: legacyRead(m['first']),
    second: legacyRead(m['second']),
  );
}

Map<String, Object?> paneJson(RestoreSnapshot s) {
  final root = jsonDecode(s.encode()) as Map<String, Object?>;
  final tab = (root['tabs']! as List<Object?>).single! as Map<String, Object?>;
  return tab['layout']! as Map<String, Object?>;
}

String withAgent(Object? agent) => jsonEncode({
  'v': 1,
  'savedAt': '2026-10-07T14:32:00.000Z',
  'cleanExit': true,
  'selectedTab': k1,
  'workspaces': [
    {
      'id': 'default',
      'tabs': [k1],
    },
  ],
  'tabs': [
    {
      'key': k1,
      'focused': k1,
      'layout': {'pane': k1, 'cwd': '/w', 'agent': ?agent},
    },
  ],
});

SavedPane loadedPane(String text) =>
    RestoreSnapshot.tryParse(text)!.tabs.single.layout as SavedPane;

void main() {
  test('agent round-trips as {"k","s"}', () {
    final s = snap(
      SavedPane(
        key: k1,
        cwd: '/w',
        agent: (kind: AgentKind.codex, session: 'ses_abc-1'),
      ),
    );
    expect(paneJson(s)['agent'], {'k': 'codex', 's': 'ses_abc-1'});
    final back = RestoreSnapshot.tryParse(s.encode())!;
    final pane = back.tabs.single.layout as SavedPane;
    expect(pane.agent, (kind: AgentKind.codex, session: 'ses_abc-1'));
    expect(back.encode(), s.encode());
  });

  test('a pane without an agent writes no key and loads as before', () {
    final s = snap(SavedPane(key: k1, cwd: '/w'));
    expect(paneJson(s).containsKey('agent'), isFalse);
    expect(loadedPane(s.encode()).agent, isNull);
    expect(loadedPane(withAgent(null)).agent, isNull);
  });

  test('unknown extra keys inside agent are ignored', () {
    final p = loadedPane(
      withAgent({'k': 'claude', 's': 'abc', 'x': 1, 'future': [], 'v': 2}),
    );
    expect(p.agent, (kind: AgentKind.claude, session: 'abc'));
  });

  test('a bad agent object is dropped; the pane still loads', () {
    for (final bad in <Object?>[
      {'k': 'claude', 's': 'a; rm -rf ~'},
      {'k': 'claude', 's': '-r'},
      {'k': 'claude', 's': ''},
      {'k': 'claude', 's': 'a' * 129},
      {'k': 'claude', 's': 7},
      {'k': 'nope', 's': 'abc'},
      {'k': 3, 's': 'abc'},
      {'k': 'claude'},
      {'s': 'abc'},
      'claude',
      7,
      <Object?>[],
    ]) {
      final p = loadedPane(withAgent(bad));
      expect(p.agent, isNull, reason: '$bad');
      expect(p.cwd, '/w', reason: '$bad');
    }
  });

  test('an invalid id is never written either', () {
    final s = snap(
      SavedPane(
        key: k1,
        cwd: '/w',
        agent: (kind: AgentKind.claude, session: 'a b'),
      ),
    );
    expect(paneJson(s).containsKey('agent'), isFalse);
  });

  test('the A11 reader loads a new file (unknown key ignored)', () {
    final s = snap(
      SavedSplit(
        axis: SplitAxis.row,
        ratio: 0.5,
        first: SavedPane(
          key: k1,
          cwd: '/w',
          agent: (kind: AgentKind.gemini, session: 'abc'),
        ),
        second: SavedPane(key: k2, cwd: '/x'),
      ),
    );
    final layout = paneJson(s);
    final old = legacyRead(layout) as SavedSplit;
    expect((old.first as SavedPane).cwd, '/w');
    expect((old.second as SavedPane).key, k2);
  });

  test('negative tab keys (A11 D20) and generations still round-trip with '
      'an agent', () {
    // A displaced tab key is a pane key no leaf carries.
    final other = '3' * 32;
    final s = RestoreSnapshot(
      savedAt: DateTime.utc(2026, 10, 7, 14, 32),
      cleanExit: false,
      daemon: 'i1',
      selectedTab: other,
      workspaces: [
        SavedWorkspace(id: 'default', tabs: [other]),
      ],
      tabs: [
        SavedTab(
          key: other,
          focused: k1,
          layout: SavedPane(
            key: k1,
            cwd: '/w',
            session: 4,
            agent: (kind: AgentKind.opencode, session: 'ses_1'),
          ),
        ),
      ],
    );
    final back = RestoreSnapshot.tryParse(s.encode())!;
    expect(back.tabs.single.key, other);
    final pane = back.tabs.single.layout as SavedPane;
    expect(pane.session, 4);
    expect(pane.agent, (kind: AgentKind.opencode, session: 'ses_1'));
    // A different agent is a different layout: it is written again.
    final changed = snap(SavedPane(key: k1, cwd: '/w'));
    expect(s.sameLayoutAs(back), isTrue);
    expect(s.sameLayoutAs(changed), isFalse);
  });
}
