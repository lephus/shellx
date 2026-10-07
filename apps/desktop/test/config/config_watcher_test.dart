import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_watcher.dart';

import '../support/memory_config_fs.dart';

void main() {
  test('a change is reported once, 250 ms after the poll that saw it (D9)', () {
    fakeAsync((async) {
      final fs = MemoryConfigFs();
      var changes = 0;
      final watcher = ConfigWatcher(fs: fs, onChange: () => changes++);
      watcher.watch(['/c/config', '/c/missing']);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      expect(changes, 0);
      fs.write('/c/config', 'font-size = 14');
      async.elapse(const Duration(milliseconds: 1100));
      expect(changes, 0);
      async.elapse(const Duration(milliseconds: 300));
      expect(changes, 1);
      // The controller re-arms after every load; a change already reported
      // is not reported again.
      watcher.watch(['/c/config', '/c/missing']);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      expect(changes, 1);
      fs.write('/c/missing', 'x = 1'); // a file that appears counts
      async.elapse(const Duration(milliseconds: 1300));
      expect(changes, 2);
      watcher.stop();
      fs.write('/c/config', 'font-size = 15');
      async.elapse(const Duration(seconds: 3));
      expect(changes, 2);
    });
  });

  test('a file still being written waits for 250 ms of quiet', () {
    fakeAsync((async) {
      final fs = MemoryConfigFs();
      var changes = 0;
      ConfigWatcher(fs: fs, onChange: () => changes++).watch(['/c/config']);
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 500));
      fs.write('/c/config', 'font-size = 1');
      async.elapse(const Duration(milliseconds: 600)); // seen at 1 s
      fs.write('/c/config', 'font-size = 14'); // within the settle
      async.elapse(const Duration(milliseconds: 200)); // 1.3 s
      expect(changes, 0);
      async.elapse(const Duration(milliseconds: 300)); // 1.6 s
      expect(changes, 1);
    });
  });

  test('a save between the report and the re-arm is not lost', () {
    fakeAsync((async) {
      final fs = MemoryConfigFs();
      var changes = 0;
      final watcher = ConfigWatcher(fs: fs, onChange: () => changes++);
      watcher.watch(['/c/config']);
      async.flushMicrotasks();
      fs.write('/c/config', 'font-size = 14');
      async.elapse(const Duration(milliseconds: 1300));
      expect(changes, 1);
      // The load runs; the user saves again before it re-arms the watcher.
      fs.write('/c/config', 'font-size = 15');
      watcher.watch(['/c/config']);
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 1000));
      expect(changes, 2);
      watcher.stop();
    });
  });

  test('a slow, older watch() never overwrites a newer one (M5)', () {
    fakeAsync((async) {
      final fs = MemoryConfigFs();
      var changes = 0;
      final watcher = ConfigWatcher(fs: fs, onChange: () => changes++);
      final slow = Completer<void>();
      fs.stampGate = slow.future;
      watcher.watch(['/c/old']); // its stat hangs
      fs.stampGate = null;
      watcher.watch(['/c/new']);
      async.flushMicrotasks();
      slow.complete();
      async.flushMicrotasks();
      fs.write('/c/old', 'x = 1');
      async.elapse(const Duration(milliseconds: 1300));
      expect(changes, 0); // /c/old is no longer watched
      fs.write('/c/new', 'x = 1');
      async.elapse(const Duration(milliseconds: 1300));
      expect(changes, 1);
      watcher.stop();
    });
  });

  test('a poll that overlaps watch() keeps the newer file list (M5)', () {
    fakeAsync((async) {
      final fs = MemoryConfigFs();
      var changes = 0;
      final watcher = ConfigWatcher(fs: fs, onChange: () => changes++);
      watcher.watch(['/c/a']);
      async.flushMicrotasks();
      fs.write('/c/a', 'x = 1');
      final slow = Completer<void>();
      fs.stampGate = slow.future;
      async.elapse(const Duration(seconds: 1)); // the poll's stat hangs
      fs.stampGate = null;
      watcher.watch(['/c/b']);
      async.flushMicrotasks();
      slow.complete();
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 300));
      expect(changes, 0); // the stale poll neither reports nor re-arms
      fs.write('/c/b', 'x = 1');
      async.elapse(const Duration(milliseconds: 1300));
      expect(changes, 1);
      watcher.stop();
    });
  });

  test('a change seen just before watch() is still reported once '
      '(re-review)', () {
    fakeAsync((async) {
      final fs = MemoryConfigFs();
      var changes = 0;
      final watcher = ConfigWatcher(fs: fs, onChange: () => changes++);
      watcher.watch(['/c/config']);
      async.flushMicrotasks();
      fs.write('/c/config', 'font-size = 14');
      async.elapse(const Duration(milliseconds: 1100)); // seen at 1 s
      watcher.watch(['/c/config']); // a load re-arms inside the 250 ms
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      expect(changes, 1);
      watcher.stop();
    });
  });

  test('a settle check overlapping watch() still reports (re-review)', () {
    fakeAsync((async) {
      final fs = MemoryConfigFs();
      var changes = 0;
      final watcher = ConfigWatcher(fs: fs, onChange: () => changes++);
      watcher.watch(['/c/config']);
      async.flushMicrotasks();
      fs.write('/c/config', 'font-size = 14');
      async.elapse(const Duration(milliseconds: 1100)); // seen at 1 s
      final slow = Completer<void>();
      fs.stampGate = slow.future;
      async.elapse(const Duration(milliseconds: 200)); // settle check hangs
      fs.stampGate = null;
      watcher.watch(['/c/config']);
      async.flushMicrotasks();
      slow.complete();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      expect(changes, 1);
      watcher.stop();
    });
  });
}
