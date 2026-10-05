// Shell hooks of ShellX sessions (push spec §4.4). They emit `OSC 633;E`
// (command line, VS Code escaping), `OSC 133;C` (start) and `OSC 133;D;<code>`
// (end) and define `shellx notify` when no `shellx` command exists. The same
// hook code is in the inner-shell branch of `term/shell/block.{zsh,bash,ps1}`
// (§4.5); the function names and the "already hooked" guard are shared so a
// shell never installs them twice. ASCII only.

/// zsh: `$ZDOTDIR/.zshenv` of the hook directory. zsh reads it first; it
/// puts `ZDOTDIR` back to what the user had (from `SHELLX_USER_ZDOTDIR`, or
/// unset), defines the hooks, then sources the user's own `.zshenv`. Every
/// later startup file (`.zprofile`, `.zshrc`, `.zlogin`, and macOS's
/// `/etc/zshrc`, which derives `HISTFILE` from `ZDOTDIR`) is then the user's.
/// The hooks are installed by a one-shot `precmd` at the first prompt, after
/// all of them, so they come first in `precmd_functions` and see `$?`.
const zshHookEnv =
    r'''
# ShellX session hook (written by the ShellX agent; safe to delete).
if [[ -n ${SHELLX_USER_ZDOTDIR+x} ]]; then
  ZDOTDIR=$SHELLX_USER_ZDOTDIR
else
  builtin unset ZDOTDIR
fi
builtin unset SHELLX_USER_ZDOTDIR
if [[ -o interactive ]]; then
''' +
    zshHookBody +
    r'''
fi
if [[ -r ${ZDOTDIR:-$HOME}/.zshenv ]]; then
  builtin source "${ZDOTDIR:-$HOME}/.zshenv"
fi
''';

/// The zsh hooks (shared with `term/shell/block.zsh`).
const zshHookBody = r'''
  if (( ! ${+functions[__shellx_precmd]} )); then
    __shellx_preexec() {
      local s=$1
      s=${s//\\/\\\\}; s=${s//;/\\x3b}; s=${s//$'\n'/\\x0a}
      s=${s//$'\r'/\\x0d}; s=${s//$'\a'/\\x07}; s=${s//$'\e'/\\x1b}
      builtin printf '\e]633;E;%s\a\e]133;C\a' "$s"
      __shellx_running=1
    }
    __shellx_precmd() {
      local ret=$?
      if [[ -n ${__shellx_running-} ]]; then
        builtin printf '\e]133;D;%s\a' "$ret"
        builtin unset __shellx_running
      fi
      return ret
    }
    __shellx_install() {
      precmd_functions=(${precmd_functions:#__shellx_install})
      if (( ! ${precmd_functions[(Ie)__shellx_precmd]} )); then
        precmd_functions=(__shellx_precmd $precmd_functions)
      fi
      if (( ! ${preexec_functions[(Ie)__shellx_preexec]} )); then
        preexec_functions+=(__shellx_preexec)
      fi
      if ! builtin whence -w shellx >/dev/null 2>&1; then
        shellx() {
          if [[ ${1-} == notify && $# -gt 1 ]]; then
            builtin shift
            local t="$*"
            t=${t//$'\e'/}; t=${t//$'\a'/}
            builtin printf '\e]777;notify;;%s\a' "$t"
          else
            builtin print -u2 'usage: shellx notify <text>'
            return 2
          fi
        }
      fi
    }
    typeset -ga precmd_functions preexec_functions
    precmd_functions+=(__shellx_install)
  fi
''';

/// bash: the `--rcfile` of a ShellX session. It reads what bash itself
/// would have read — the login files (`/etc/profile`, then the first of
/// `~/.bash_profile`, `~/.bash_login`, `~/.profile`) when the session was
/// meant to be a login shell (`SHELLX_BASH_LOGIN=1`), else `~/.bashrc` —
/// then installs the hooks.
const bashHookRc =
    r'''
# ShellX session hook (written by the ShellX agent; safe to delete).
if [ -n "${SHELLX_BASH_LOGIN-}" ]; then
  builtin unset SHELLX_BASH_LOGIN
  if [ -r /etc/profile ]; then builtin source /etc/profile; fi
  if [ -r ~/.bash_profile ]; then builtin source ~/.bash_profile
  elif [ -r ~/.bash_login ]; then builtin source ~/.bash_login
  elif [ -r ~/.profile ]; then builtin source ~/.profile
  fi
else
  if [ -r ~/.bashrc ]; then builtin source ~/.bashrc; fi
fi
''' +
    bashHookBody;

/// The bash hooks (shared with `term/shell/block.bash`; bash 3.2+). A
/// `DEBUG` trap emits E and C once per command line (gated by
/// `__shellx_at_prompt`, which `PROMPT_COMMAND` sets last); the first part
/// of `PROMPT_COMMAND` emits D with `$?`. If the user's startup files later
/// replace or append to `PROMPT_COMMAND`, the trap wraps it again (a
/// fork-free check before every command: start must come first and end
/// last); the next command line after such a re-wrap is still reported. An
/// array `PROMPT_COMMAND` (bash 5.1+) gets start and end as its first and
/// last elements. Not installed when a
/// `DEBUG` trap already exists (bash-preexec and friends): no command
/// notifications then, nothing else changes.
const bashHookBody = r'''
if [[ $- == *i* && -z "${__shellx_hooked-}" && -z "$(builtin trap -p DEBUG)" ]]; then
  __shellx_hooked=1
  __shellx_unwrap() {
    local nl=$'\n' ws=$' \t\n;'
    __shellx_s=${1//"__shellx_prompt_start${nl}"/}
    __shellx_s=${__shellx_s//"${nl}__shellx_prompt_end"/}
    __shellx_s=${__shellx_s//__shellx_prompt_start/:}
    __shellx_s=${__shellx_s//__shellx_prompt_end/:}
    while :; do case "$__shellx_s" in [$ws]*) __shellx_s=${__shellx_s#?} ;; *) break ;; esac; done
  }
  __shellx_wrap_prompt() {
    local e n=${#PROMPT_COMMAND[@]}
    if [ "$n" -gt 1 ]; then
      if [ "${PROMPT_COMMAND[0]}" = __shellx_prompt_start ] && [ "${PROMPT_COMMAND[$n-1]}" = __shellx_prompt_end ]; then return 1; fi
      local -a a=()
      for e in "${PROMPT_COMMAND[@]}"; do
        case "$e" in
          __shellx_prompt_start|__shellx_prompt_end) ;;
          *) __shellx_unwrap "$e"; a+=("$__shellx_s") ;;
        esac
      done
      PROMPT_COMMAND=(__shellx_prompt_start "${a[@]}" __shellx_prompt_end)
    else
      case "${PROMPT_COMMAND-}" in __shellx_prompt_start*__shellx_prompt_end) return 1 ;; esac
      __shellx_unwrap "${PROMPT_COMMAND-}"
      PROMPT_COMMAND="__shellx_prompt_start"$'\n'"$__shellx_s"$'\n'"__shellx_prompt_end"
    fi
    return 0
  }
  __shellx_prompt_start() {
    local ret=$?
    if [ -n "${__shellx_running-}" ]; then
      builtin printf '\033]133;D;%s\007' "$ret"
      __shellx_running=
    fi
    return $ret
  }
  __shellx_prompt_end() {
    local ret=$? re='^ *([0-9]+)'
    if [ -n "${__shellx_skip_end-}" ]; then
      # This run of PROMPT_COMMAND began before the re-wrap: our end was not last in it.
      __shellx_skip_end=
      return $ret
    fi
    if [[ "$(HISTTIMEFORMAT= builtin history 1)" =~ $re ]]; then __shellx_hist=${BASH_REMATCH[1]}; fi
    __shellx_at_prompt=1
    return $ret
  }
  __shellx_debug() {
    local s re='^ *([0-9]+)[* ] *(.*)$' nl=$'\n' cr=$'\r' bel=$'\a' esc=$'\e'
    if __shellx_wrap_prompt; then
      # Our start/end were missing, or no longer first/last: the next command line typed is still a
      # command even if this prompt never reaches __shellx_prompt_end (the first line that adds a
      # history entry).
      if [[ "$(HISTTIMEFORMAT= builtin history 1)" =~ $re ]]; then __shellx_hist=${BASH_REMATCH[1]}; fi
      __shellx_pending=1
      __shellx_at_prompt=
      if [ "$BASH_COMMAND" = __shellx_prompt_start ]; then __shellx_skip_end=1; fi
      return
    fi
    if [ "$BASH_COMMAND" = __shellx_prompt_start ]; then
      __shellx_at_prompt=
      __shellx_pending=
      return
    fi
    [ -n "${COMP_LINE-}" ] && return
    if [ -z "${__shellx_at_prompt-}" ]; then
      [ -z "${__shellx_pending-}" ] && return
      [[ "$(HISTTIMEFORMAT= builtin history 1)" =~ $re ]] || return
      [ "${BASH_REMATCH[1]}" != "${__shellx_hist-}" ] || return
      __shellx_pending=
    fi
    __shellx_at_prompt=
    if [[ "$(HISTTIMEFORMAT= builtin history 1)" =~ $re ]] && [ "${BASH_REMATCH[1]}" != "${__shellx_hist-}" ]; then
      s=${BASH_REMATCH[2]}
    else
      s=$BASH_COMMAND
    fi
    s=${s//\\/\\\\}; s=${s//;/\\x3b}; s=${s//$nl/\\x0a}; s=${s//$cr/\\x0d}; s=${s//$bel/\\x07}; s=${s//$esc/\\x1b}
    builtin printf '\033]633;E;%s\007\033]133;C\007' "$s"
    __shellx_running=1
  }
  __shellx_wrap_prompt
  builtin trap '__shellx_debug' DEBUG
  if ! builtin type shellx >/dev/null 2>&1; then
    shellx() {
      if [ "${1-}" = notify ] && [ $# -gt 1 ]; then
        builtin shift
        local t="$*" bel=$'\a' esc=$'\e'
        t=${t//$esc/}; t=${t//$bel/}
        builtin printf '\033]777;notify;;%s\007' "$t"
      else
        builtin echo 'usage: shellx notify <text>' >&2
        return 2
      fi
    }
  fi
fi
''';

/// PowerShell: dot-sourced by `-NoExit -Command` after the profiles
/// (PowerShell loads them before `-Command` runs, unless `-NoProfile`).
/// Wraps `prompt` (D with `$?` / `$LASTEXITCODE`) and PSReadLine's
/// `PSConsoleHostReadLine` (E and C once a line is accepted), as VS Code's
/// shell integration does. Without PSReadLine there are no command
/// notifications.
const powerShellHook =
    r'''
# ShellX session hook (written by the ShellX agent; safe to delete).
''' +
    powerShellHookBody;

/// The PowerShell hooks (shared with `term/shell/block.ps1`). A profile
/// that sets its own `prompt` after the hook (the block sits at the top of
/// the profile) is wrapped again at the next line read.
const powerShellHookBody = r'''
if (-not $global:__ShellxHooked) {
  $global:__ShellxHooked = $true
  $global:__ShellxRunning = $false
  $global:__ShellxUserPrompt = $function:prompt
  $global:__ShellxFirstPrompt = $function:prompt
  $global:__ShellxPromptDepth = 0
  $global:__ShellxPrompt = {
    $ok = $global:?
    $code = $global:LASTEXITCODE
    if ($global:__ShellxPromptDepth -gt 0) {
      # Called again from inside (a prompt wrapped after ours that calls ours): no recursion.
      if ($global:__ShellxPromptDepth -eq 1 -and $global:__ShellxFirstPrompt) {
        $global:__ShellxPromptDepth = 2
        try { return & $global:__ShellxFirstPrompt } finally { $global:__ShellxPromptDepth = 1 }
      }
      return 'PS> '
    }
    $global:__ShellxPromptDepth = 1
    try {
      $mark = ''
      if ($global:__ShellxRunning) {
        $global:__ShellxRunning = $false
        $n = if ($ok) { 0 } elseif ($code -is [int] -and $code -ne 0) { $code } else { 1 }
        $mark = "$([char]27)]133;D;$n$([char]7)"
      }
      $text = if ($global:__ShellxUserPrompt) { & $global:__ShellxUserPrompt } else { "PS $($executionContext.SessionState.Path.CurrentLocation)> " }
      $global:LASTEXITCODE = $code
      "$mark$text"
    } finally {
      $global:__ShellxPromptDepth = 0
    }
  }
  Set-Item -Path function:global:prompt -Value $global:__ShellxPrompt
  if (Get-Command PSConsoleHostReadLine -CommandType Function -ErrorAction SilentlyContinue) {
    $global:__ShellxReadLine = $function:PSConsoleHostReadLine
    function global:PSConsoleHostReadLine {
      if ("$function:prompt" -ne "$global:__ShellxPrompt") {
        $global:__ShellxUserPrompt = $function:prompt
        Set-Item -Path function:global:prompt -Value $global:__ShellxPrompt
      }
      $line = & $global:__ShellxReadLine
      if ($line -and $line.Trim()) {
        $global:__ShellxRunning = $true
        $s = $line.Replace('\', '\\').Replace(';', '\x3b').Replace("`n", '\x0a').Replace("`r", '\x0d').Replace([string][char]7, '\x07').Replace([string][char]27, '\x1b')
        [Console]::Write("$([char]27)]633;E;$s$([char]7)$([char]27)]133;C$([char]7)")
      }
      $line
    }
  }
  if (-not (Get-Command shellx -ErrorAction SilentlyContinue)) {
    function global:shellx {
      if ($args.Count -ge 2 -and $args[0] -eq 'notify') {
        $t = ($args[1..($args.Count - 1)] -join ' ').Replace([string][char]27, '').Replace([string][char]7, '')
        [Console]::Write("$([char]27)]777;notify;;$t$([char]7)")
      } else {
        [Console]::Error.WriteLine('usage: shellx notify <text>')
      }
    }
  }
}
''';
