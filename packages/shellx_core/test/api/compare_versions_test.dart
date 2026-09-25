import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

void main() {
  test('orders versions by semver precedence', () {
    const ordered = [
      '0.9.9',
      '1.0.0-alpha',
      '1.0.0-alpha.1',
      '1.0.0-alpha.beta',
      '1.0.0-beta',
      '1.0.0-beta.2',
      '1.0.0-beta.11',
      '1.0.0-rc.1',
      '1.0.0',
      '1.0.1',
      '1.2.0',
      '1.9.0',
      '1.10.0',
      '2.0.0',
    ];
    for (var i = 0; i < ordered.length; i++) {
      for (var j = 0; j < ordered.length; j++) {
        final result = compareVersions(ordered[i], ordered[j]);
        expect(
          result.sign,
          (i - j).sign,
          reason: '${ordered[i]} vs ${ordered[j]}',
        );
      }
    }
  });

  test('build metadata and surrounding whitespace are ignored', () {
    expect(compareVersions('1.0.0+5', '1.0.0'), 0);
    expect(compareVersions('1.0.0+5', '1.0.0+9'), 0);
    expect(compareVersions(' 1.2.3 ', '1.2.3'), 0);
  });

  test('rejects non-semver strings', () {
    for (final bad in [
      '',
      '1',
      '1.0',
      'v1.0.0',
      '1.0.0.0',
      '01.0.0',
      '1.0.0-',
      'latest',
    ]) {
      expect(
        () => compareVersions(bad, '1.0.0'),
        throwsFormatException,
        reason: bad,
      );
    }
  });
}
