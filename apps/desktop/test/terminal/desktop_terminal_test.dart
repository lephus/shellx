import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/desktop_terminal.dart';
import 'package:xterm/xterm.dart';

void main() {
  late DesktopTerminal terminal;
  late List<String> user;
  late List<String> replies;

  setUp(() {
    terminal = DesktopTerminal();
    user = [];
    replies = [];
    terminal
      ..onUserInput = user.add
      ..onReply = replies.add;
  });

  test('keys, text and paste are user input', () {
    terminal.keyInput(TerminalKey.enter);
    terminal.textInput('ls');
    terminal.paste('a\nb');
    expect(user, ['\r', 'ls', 'a\rb']);
    expect(replies, isEmpty);
  });

  test('answers the emulator generates are replies, not user input', () {
    terminal.write('\x1b[6n'); // cursor position report request
    expect(replies, hasLength(1));
    expect(replies.single, matches(RegExp(r'^\x1b\[\d+;\d+R$')));
    expect(user, isEmpty);
  });

  test('arrow keys follow DECCKM (vim, htop, less)', () {
    terminal.keyInput(TerminalKey.arrowUp);
    terminal.write('\x1b[?1h');
    terminal.keyInput(TerminalKey.arrowUp);
    expect(user, ['\x1b[A', '\x1bOA']);
  });

  group('macOS Option+←/→ move by word like Terminal.app and iTerm2', () {
    late DesktopTerminal mac;
    late List<String> typed;

    setUp(() {
      mac = DesktopTerminal(platform: TerminalTargetPlatform.macos);
      typed = [];
      mac.onUserInput = typed.add;
    });

    test('at the shell prompt: ESC b / ESC f (readline, zle, fish)', () {
      mac.keyInput(TerminalKey.arrowLeft, alt: true);
      mac.keyInput(TerminalKey.arrowRight, alt: true);
      expect(typed, ['\x1bb', '\x1bf']);
    });

    test('with Shift or Ctrl too, and in full-screen programs (alternate '
        'screen: vim, micro): the xterm modifier form', () {
      mac.keyInput(TerminalKey.arrowLeft, alt: true, shift: true);
      mac.write('\x1b[?1049h');
      mac.keyInput(TerminalKey.arrowLeft, alt: true);
      expect(typed, ['\x1b[1;4D', '\x1b[1;3D']);
    });

    test('Windows keeps Alt+arrow as the xterm modifier form', () {
      final win = DesktopTerminal(platform: TerminalTargetPlatform.windows);
      final out = <String>[];
      win.onUserInput = out.add;
      win.keyInput(TerminalKey.arrowLeft, alt: true);
      expect(out, ['\x1b[1;3D']);
    });
  });

  test('pasted and IME text never carries escape sequences', () {
    terminal.paste('safe\x1b[201~evil');
    terminal.textInput('x\x1by\n');
    expect(user, ['safe[201~evil', 'xy\r']);
  });

  test('bracketed paste wraps the cleaned text', () {
    terminal.write('\x1b[?2004h');
    terminal.paste('echo hi');
    expect(user, ['\x1b[200~echo hi\x1b[201~']);
  });

  test('a narrower window wraps lines without pushing the first one into '
      'the scrollback while blank rows are left below the cursor (M-1)', () {
    terminal.resize(80, 10);
    terminal.write('${'x' * 60} git status\r\nOn branch\r\n\$ ');
    terminal.resize(40, 10);
    expect(terminal.buffer.scrollBack, 0);
    expect(terminal.buffer.lines[0].getText().trim(), startsWith('xxx'));
    // The cursor is still after the prompt.
    expect(terminal.buffer.cursorX, 2);
    expect(
      terminal.buffer.lines[terminal.buffer.absoluteCursorY].getText().trim(),
      r'$',
    );
  });

  test('a full screen still scrolls into the scrollback on a narrower '
      'window', () {
    terminal.resize(80, 3);
    terminal.write('${'x' * 60}\r\na\r\nb');
    terminal.resize(40, 3);
    expect(terminal.buffer.scrollBack, 1);
    expect(
      terminal.buffer.lines[terminal.buffer.absoluteCursorY].getText().trim(),
      'b',
    );
  });

  test('keeps 10 000 lines of scrollback (spec §3.2)', () {
    expect(terminal.maxLines, 10000);
  });
}
