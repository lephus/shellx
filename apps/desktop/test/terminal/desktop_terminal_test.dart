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

  test('keeps 10 000 lines of scrollback (spec §3.2)', () {
    expect(terminal.maxLines, 10000);
  });
}
