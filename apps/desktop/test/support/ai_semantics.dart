import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// One node of the semantics tree, for a test to read: how deep it is, what a
/// screen reader says of it, and whether it is a live region.
typedef AiSemNode = ({int depth, String label, bool live});

/// The semantics tree of what [t] shows, top down, flattened. The test
/// calls `t.ensureSemantics()` first.
List<AiSemNode> semanticsDump(WidgetTester t) {
  var root = t.getSemantics(find.byType(Scaffold).first);
  while (root.parent != null) {
    root = root.parent!;
  }
  final out = <AiSemNode>[];
  void walk(SemanticsNode node, int depth) {
    final data = node.getSemanticsData();
    out.add((
      depth: depth,
      label: data.label,
      live: data.flagsCollection.isLiveRegion,
    ));
    node.visitChildren((child) {
      walk(child, depth + 1);
      return true;
    });
  }

  walk(root, 0);
  return out;
}

/// The live regions of [t]'s semantics tree, by what they say.
List<String> liveRegions(WidgetTester t) => [
  for (final n in semanticsDump(t))
    if (n.live) n.label,
];
