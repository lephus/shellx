// Downloads the official cacophony Noise test vectors and keeps only the two
// protocols ShellX uses. Run from packages/shellx_core:
//
//   dart run tool/fetch_noise_vectors.dart
//
// Writes test/fixtures/noise_vectors.json (committed; tests never download).
import 'dart:convert';
import 'dart:io';

const String sourceUrl =
    'https://raw.githubusercontent.com/haskell-cryptography/'
    'cacophony/18b7348c54fd61fcd0c220298883de0d09c8364d/vectors/cacophony.txt';

const Set<String> protocols = {
  'Noise_IK_25519_ChaChaPoly_BLAKE2s',
  'Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s',
};

Future<void> main() async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(sourceUrl));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      stderr.writeln('Download failed: HTTP ${response.statusCode}');
      exitCode = 1;
      return;
    }
    final body = await response.transform(utf8.decoder).join();
    final all =
        (jsonDecode(body) as Map<String, dynamic>)['vectors'] as List<dynamic>;
    final selected = [
      for (final vector in all)
        if (protocols.contains(
          (vector as Map<String, dynamic>)['protocol_name'],
        ))
          vector,
    ];
    if (selected.length != protocols.length) {
      stderr.writeln(
        'Expected ${protocols.length} vectors, found ${selected.length}',
      );
      exitCode = 1;
      return;
    }
    final file = File('test/fixtures/noise_vectors.json');
    file.parent.createSync(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    file.writeAsStringSync(
      '${encoder.convert({'source': sourceUrl, 'vectors': selected})}\n',
    );
    stdout.writeln('Wrote ${selected.length} vectors to ${file.path}');
  } finally {
    client.close();
  }
}
