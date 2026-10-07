import 'dart:convert';

import '../pty/shell_hook_scripts.dart';
import 'tmux_sessions.dart' show tmuxListFormat;

/// A8 D39.
const int kMaxBootstrapBytes = 24 * 1024;

/// The encoded command stays under the Windows command line limit (32,767)
/// with a margin.
const int kMaxBootstrapCommandChars = 30767;

/// One sh word holding exactly [value].
String shQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";

/// D15: the branch of `$PWD` from `.git/HEAD` (or a `.git` file's
/// `gitdir:`), with builtins only — no fork, no git. Printed as
/// `OSC 6973;branch=` only when it changed ('' = not a repository).
/// The same text runs in bash and zsh.
const String remoteMetaFunction = r'''
__shellx_remote_meta() {
  local d="$PWD" h= b= g=
  while :; do
    if [ -f "$d/.git/HEAD" ]; then h="$d/.git/HEAD"; break; fi
    if [ -f "$d/.git" ]; then
      IFS= read -r g < "$d/.git"
      g="${g#gitdir: }"
      case "$g" in /*) ;; *) g="$d/$g" ;; esac
      if [ -f "$g/HEAD" ]; then h="$g/HEAD"; fi
      break
    fi
    if [ -z "$d" ] || [ "$d" = / ]; then break; fi
    d="${d%/*}"
  done
  if [ -n "$h" ]; then
    IFS= read -r b < "$h"
    case "$b" in
      "ref: refs/heads/"*) b="${b#ref: refs/heads/}" ;;
      *) b="${b:0:7}" ;;
    esac
    b="${b:0:200}"
    case "$b" in *[![:print:]]*) b= ;; esac
  fi
  if [ -z "${__shellx_branch_set-}" ] || [ "$b" != "$__shellx_branch" ]; then
    __shellx_branch_set=1
    __shellx_branch="$b"
    builtin printf '\033]6973;branch=%s\007' "$b"
  fi
}
''';

/// zsh: wraps the hook's `__shellx_osc7` (called at every prompt) once.
const String _zshAddon =
    r'''
# ShellX remote add-on (A8): branch of the server's folder.
if [[ -o interactive ]] && (( ${+functions[__shellx_osc7]} )) && (( ! ${+functions[__shellx_osc7_base]} )); then
''' +
    remoteMetaFunction +
    r'''
  functions[__shellx_osc7_base]=${functions[__shellx_osc7]}
  __shellx_osc7() { __shellx_osc7_base; __shellx_remote_meta; }
fi
''';

/// bash: the same wrap through `declare -f` (one fork, at startup only).
const String _bashAddon =
    r'''
# ShellX remote add-on (A8): branch of the server's folder.
if [[ $- == *i* ]] && declare -F __shellx_osc7 >/dev/null && ! declare -F __shellx_osc7_base >/dev/null; then
''' +
    remoteMetaFunction +
    r'''
  __shellx_def=$(declare -f __shellx_osc7)
  eval "__shellx_osc7_base${__shellx_def#__shellx_osc7}"
  unset __shellx_def
  __shellx_osc7() { __shellx_osc7_base; __shellx_remote_meta; }
fi
''';

/// The files written on the server (D10): the local hooks unchanged, then
/// the add-on.
const String remoteZshHook = '$zshHookEnv\n$_zshAddon';
const String remoteBashHook = '$bashHookRc\n$_bashAddon';

/// First 12 hex digits of FNV-1a 64 over both files: a new ShellX with new
/// hooks writes a new folder; an unchanged one reuses the old.
final String remoteHookVersion = _fnv64Hex(
  '$remoteZshHook\u0000$remoteBashHook',
);

String _fnv64Hex(String text) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(text)) {
    hash ^= byte;
    hash *= 0x100000001b3; // wraps at 64 bits on the VM
  }
  return hash
      .toUnsigned(64)
      .toRadixString(16)
      .padLeft(16, '0')
      .substring(0, 12);
}

final class RemoteBootstrap {
  const RemoteBootstrap({
    this.cwd,
    this.tmuxSession,
    this.tmuxCreate = false,
    this.writeHooks = true,
  });

  /// `/…`, `~` or `~/…` (checked by the caller with `isValidRemoteCwd`).
  final String? cwd;

  /// Non-null: `exec tmux` instead of the login shell (D25).
  final String? tmuxSession;
  final bool tmuxCreate;
  final bool writeHooks;
}

const String _prelude = r'''
printf '\033]6973;hello=1\007'
printf '\033]6973;pid=%s\007' "$$"
case "$HOME" in
  /*[![:print:]]*) ;;
  /*) printf '\033]6973;home=%s\007' "$HOME" ;;
esac
SHELLX=1; SHELLX_REMOTE=1; export SHELLX SHELLX_REMOTE
s=${SHELL:-/bin/sh}
d=
''';

const String _hooksTemplate = r'''
c="${XDG_CACHE_HOME:-$HOME/.cache}/shellx/remote-@VERSION@"
if [ -f "$c/.ok" ] && [ -f "$c/zsh/.zshenv" ] && [ -f "$c/bash/rc.bash" ]; then
  d=$c
elif (umask 077 && mkdir -p "$c/zsh" "$c/bash") 2>/dev/null; then
  o=$(umask)
  umask 077
  w=1
  cat >"$c/zsh/.zshenv.$$" <<'__SHELLX_EOF_ZSH__' || w=
@ZSH@
__SHELLX_EOF_ZSH__
  cat >"$c/bash/rc.bash.$$" <<'__SHELLX_EOF_BASH__' || w=
@BASH@
__SHELLX_EOF_BASH__
  if [ -n "$w" ] && mv -f "$c/zsh/.zshenv.$$" "$c/zsh/.zshenv" && mv -f "$c/bash/rc.bash.$$" "$c/bash/rc.bash" && : >"$c/.ok"; then
    d=$c
  else
    rm -f "$c/zsh/.zshenv.$$" "$c/bash/rc.bash.$$" 2>/dev/null
  fi
  umask "$o"
fi
''';

const String _shellExec = r'''
case "${s##*/}" in
  zsh)
    if [ -n "$d" ]; then
      if [ -n "${ZDOTDIR+x}" ]; then SHELLX_USER_ZDOTDIR=$ZDOTDIR; export SHELLX_USER_ZDOTDIR; fi
      ZDOTDIR="$d/zsh"; export ZDOTDIR
    fi
    exec "$s" -l ;;
  bash)
    if [ -n "$d" ]; then SHELLX_BASH_LOGIN=1; export SHELLX_BASH_LOGIN; exec "$s" --rcfile "$d/bash/rc.bash" -i; fi
    exec "$s" -l ;;
  *) exec "$s" -l ;;
esac
''';

const String _tmuxExec = r'''
case "${s##*/}" in
  sh|dash) exec "$s" -c 'exec tmux @TMUX@' ;;
  bash|zsh|ksh|mksh|fish) exec "$s" -l -c 'exec tmux @TMUX@' ;;
  *) PATH="$PATH:/usr/local/bin:/opt/homebrew/bin:/opt/local/bin"; export PATH; exec tmux @TMUX@ ;;
esac
''';

/// D10: the POSIX sh text the server runs. Only [RemoteBootstrap.cwd] and
/// [RemoteBootstrap.tmuxSession] come from the user, through [shQuote].
String remoteBootstrapScript(RemoteBootstrap b) {
  final script = _bootstrapScript(b);
  if (b.cwd == null ||
      (utf8.encode(script).length <= kMaxBootstrapBytes &&
          remoteExecCommand(script).length <= kMaxBootstrapCommandChars)) {
    return script;
  }
  // A huge or quote-heavy folder: start in home rather than not at all.
  return _bootstrapScript(
    RemoteBootstrap(
      cwd: '~',
      tmuxSession: b.tmuxSession,
      tmuxCreate: b.tmuxCreate,
      writeHooks: b.writeHooks,
    ),
  );
}

String _bootstrapScript(RemoteBootstrap b) {
  final out = StringBuffer(_prelude);
  if (b.writeHooks && b.tmuxSession == null) {
    out.write(
      _hooksTemplate
          .replaceAll('@VERSION@', remoteHookVersion)
          // Both hooks end with a newline: the files hold them byte for byte.
          .replaceAll('@ZSH@\n', remoteZshHook)
          .replaceAll('@BASH@\n', remoteBashHook),
    );
  }
  final cwd = b.cwd;
  if (cwd != null) {
    if (cwd == '~') {
      out.write('cd\n');
    } else if (cwd.startsWith('~/')) {
      out.write(
        'cd -- "\$HOME"/${shQuote(cwd.substring(2))} 2>/dev/null || cd\n',
      );
    } else {
      out.write('cd -- ${shQuote(cwd)} 2>/dev/null || cd\n');
    }
  }
  final session = b.tmuxSession;
  if (session == null) {
    out.write(_shellExec);
  } else {
    out
      ..write('SHELLX_TMUX=${shQuote(session)}; export SHELLX_TMUX\n')
      ..write(
        _tmuxExec.replaceAll(
          '@TMUX@',
          b.tmuxCreate
              ? r'new-session -A -s "$SHELLX_TMUX"'
              : r'attach-session -t "=$SHELLX_TMUX"',
        ),
      );
  }
  return out.toString();
}

/// D25: `tmux list-sessions` through the login shell's PATH.
String remoteTmuxListScript() =>
    'SHELLX_FMT=${shQuote(tmuxListFormat)}; export SHELLX_FMT\n'
    r'''
s=${SHELL:-/bin/sh}
case "${s##*/}" in
  sh|dash) exec "$s" -c 'exec tmux list-sessions -F "$SHELLX_FMT"' ;;
  bash|zsh|ksh|mksh|fish) exec "$s" -l -c 'exec tmux list-sessions -F "$SHELLX_FMT"' ;;
  *) PATH="$PATH:/usr/local/bin:/opt/homebrew/bin:/opt/local/bin"; export PATH; exec tmux list-sessions -F "$SHELLX_FMT" ;;
esac
''';

/// D10: the one remote command. The server's login shell (sh, bash, zsh,
/// fish, csh…) only sees a single-quoted word of base64 and fixed syntax;
/// `/bin/sh` decodes the script with the first decoder that exists.
String remoteExecCommand(String script) {
  final b64 = base64.encode(utf8.encode(script));
  return "/bin/sh -c 'eval \"\$(b=$b64; "
      'printf %s "\$b" | base64 -d 2>/dev/null || '
      'printf %s "\$b" | base64 -D 2>/dev/null || '
      'printf %s "\$b" | openssl base64 -d -A)"'
      "'";
}
