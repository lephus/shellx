// Run with `dart test/fixtures/lock_probe.dart <lock file>`; prints
// "acquired" or "busy". Used by single_instance_test.dart because file locks
// are per process on macOS.
import 'dart:io';

Future<void> main(List<String> args) async {
  final file = await File(args.single).open(mode: FileMode.append);
  try {
    await file.lock(FileLock.exclusive);
    stdout.write('acquired');
  } on FileSystemException {
    stdout.write('busy');
  }
  await file.close();
}
