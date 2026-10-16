import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/agent/whats_new.dart';

void main() {
  test('notes are chosen by locale with English as the fallback and at most '
      '5 lines', () {
    final w = WhatsNew.parse(
      '{"1.2.0":{"en":["a","b","c","d","e","f"],"vi":["x"]}}',
    );
    expect(w.notes('1.2.0', 'vi'), ['x']);
    expect(w.notes('1.2.0', 'fr'), ['a', 'b', 'c', 'd', 'e']);
    expect(w.notes('9.9.9', 'en'), isNull);
  });

  test('the build number after + does not matter', () {
    final w = WhatsNew.parse('{"1.2.0":{"en":["a"]}}');
    expect(w.notes('1.2.0+7', 'en'), ['a']);
  });

  test('garbage JSON gives no notes and never throws', () {
    expect(WhatsNew.parse('not json').notes('1.0.0', 'en'), isNull);
    expect(WhatsNew.parse('[1,2]').notes('1.0.0', 'en'), isNull);
    expect(WhatsNew.parse('{"1.0.0":5}').notes('1.0.0', 'en'), isNull);
    expect(
      WhatsNew.parse('{"1.0.0":{"en":[1,"",null]}}').notes('1.0.0', 'en'),
      isNull,
    );
  });

  test('an empty file (the shipped default) has no notes', () {
    expect(WhatsNew.parse('{}').notes('1.0.0', 'en'), isNull);
  });
}
