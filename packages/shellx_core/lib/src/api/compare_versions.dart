final RegExp _semver = RegExp(
  r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
  r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?'
  r'(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
);

/// Compares two semantic versions (`x.y.z`, optional `-prerelease`,
/// optional `+build` which is ignored). Returns a negative number, zero or a
/// positive number. Throws [FormatException] for anything else.
int compareVersions(String a, String b) {
  final left = _parse(a);
  final right = _parse(b);
  for (var i = 0; i < 3; i++) {
    final diff = left.core[i].compareTo(right.core[i]);
    if (diff != 0) {
      return diff;
    }
  }
  return _comparePrerelease(left.prerelease, right.prerelease);
}

final class _Version {
  _Version(this.core, this.prerelease);
  final List<int> core;
  final List<String> prerelease;
}

_Version _parse(String input) {
  final match = _semver.firstMatch(input.trim());
  if (match == null) {
    throw FormatException('Not a semantic version', input);
  }
  return _Version([
    int.parse(match[1]!),
    int.parse(match[2]!),
    int.parse(match[3]!),
  ], match[4]?.split('.') ?? const []);
}

int _comparePrerelease(List<String> a, List<String> b) {
  if (a.isEmpty || b.isEmpty) {
    // A release is greater than any pre-release of the same core version.
    return (a.isEmpty ? 1 : 0) - (b.isEmpty ? 1 : 0);
  }
  for (var i = 0; i < a.length && i < b.length; i++) {
    final x = int.tryParse(a[i]);
    final y = int.tryParse(b[i]);
    final int diff;
    if (x != null && y != null) {
      diff = x.compareTo(y);
    } else if (x != null) {
      diff = -1; // numeric identifiers sort before alphanumeric ones
    } else if (y != null) {
      diff = 1;
    } else {
      diff = a[i].compareTo(b[i]);
    }
    if (diff != 0) {
      return diff;
    }
  }
  return a.length.compareTo(b.length);
}
