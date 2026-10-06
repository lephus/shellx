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
    __shellx_osc7() {
      builtin emulate -L zsh
      local url_path= i ch hexch LC_CTYPE=C LC_COLLATE=C LC_ALL= LANG=
      for (( i = 1; i <= ${#PWD}; ++i )); do
        ch=${PWD[i]}
        if [[ $ch == [-/._~A-Za-z0-9] ]]; then
          url_path+=$ch
        else
          builtin printf -v hexch '%02X' "'$ch"
          url_path+="%${hexch: -2:2}"
        fi
      done
      builtin printf '\e]7;file://%s%s\a' "${HOST-}" "$url_path"
    }
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
      __shellx_osc7
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
      __shellx_osc7
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

/// The bash hooks (shared with `term/shell/block.bash`; bash 3.2+, safe
/// under `set -u` and `shopt -s extdebug`).
///
/// - Without bash-preexec: a `DEBUG` trap emits E and C once per command
///   line (gated by `__shellx_at_prompt`, which `PROMPT_COMMAND` sets last);
///   the first part of `PROMPT_COMMAND` emits D with `$?`. If the startup
///   files later replace or append to `PROMPT_COMMAND`, the trap wraps it
///   again (a fork-free check before every command: our start first, our
///   end last); the next command line after such a re-wrap is still
///   reported. An array `PROMPT_COMMAND` (bash 5.1+) gets start and end as
///   its first and last elements. The trap always returns 0 (under
///   `extdebug` a non-zero return would skip the user's command) and does
///   nothing when it fires inside a function.
/// - With bash-preexec (atuin, iTerm2's integration, ...; loaded before the
///   hook, or detected later by the trap or the prompt functions): our
///   functions go into `preexec_functions` (E and C from the command line in
///   `$1`) and first into `precmd_functions` (D with `$?`), our entries leave
///   `PROMPT_COMMAND` and our trap does nothing more. bash-preexec's trap is
///   never touched.
/// - Not installed when some other `DEBUG` trap already exists: no command
///   notifications then, nothing else changes.
const bashHookBody = r'''
if [[ $- == *i* && -z "${__shellx_hooked-}" ]] \
   && { [[ -n "${__bp_imported-}${bash_preexec_imported-}" ]] || [[ -z "$(builtin trap -p DEBUG)" ]]; }; then
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
    local e first= last= __shellx_s
    if [ -n "${PROMPT_COMMAND[1]+x}" ]; then
      for e in "${PROMPT_COMMAND[@]}"; do [ -n "$first" ] || first=$e; last=$e; done
      if [ "$first" = __shellx_prompt_start ] && [ "$last" = __shellx_prompt_end ]; then return 1; fi
      local -a a=()
      for e in "${PROMPT_COMMAND[@]}"; do
        case "$e" in
          __shellx_prompt_start|__shellx_prompt_end) ;;
          *) __shellx_unwrap "$e"; a+=("$__shellx_s") ;;
        esac
      done
      PROMPT_COMMAND=(__shellx_prompt_start ${a[@]+"${a[@]}"} __shellx_prompt_end)
    else
      case "${PROMPT_COMMAND-}" in __shellx_prompt_start*__shellx_prompt_end) return 1 ;; esac
      __shellx_unwrap "${PROMPT_COMMAND-}"
      PROMPT_COMMAND="__shellx_prompt_start"$'\n'"$__shellx_s"$'\n'"__shellx_prompt_end"
    fi
    return 0
  }
  __shellx_esc() {
    local nl=$'\n' cr=$'\r' bel=$'\a' esc=$'\e'
    __shellx_s=$1
    __shellx_s=${__shellx_s//\\/\\\\}; __shellx_s=${__shellx_s//;/\\x3b}; __shellx_s=${__shellx_s//$nl/\\x0a}
    __shellx_s=${__shellx_s//$cr/\\x0d}; __shellx_s=${__shellx_s//$bel/\\x07}; __shellx_s=${__shellx_s//$esc/\\x1b}
  }
  __shellx_osc7() {
    local LC_ALL=C s=$PWD out= c h i
    for ((i = 0; i < ${#s}; i++)); do
      c=${s:i:1}
      case "$c" in
        [-/._~A-Za-z0-9]) out+=$c ;;
        *) builtin printf -v h '%02X' "'$c"; out+="%${h: -2:2}" ;;
      esac
    done
    builtin printf '\033]7;file://%s%s\007' "${HOSTNAME-}" "$out"
  }
  __shellx_bp_preexec() {
    local __shellx_s
    __shellx_esc "${1-}"
    builtin printf '\033]633;E;%s\007\033]133;C\007' "$__shellx_s"
    __shellx_running=1
    return 0
  }
  __shellx_bp_precmd() {
    local ret=$?
    if [ -n "${__shellx_running-}" ]; then
      builtin printf '\033]133;D;%s\007' "$ret"
      __shellx_running=
    fi
    __shellx_osc7
    return $ret
  }
  __shellx_use_bash_preexec() {
    local e __shellx_s
    __shellx_bp=1
    if [ -n "${PROMPT_COMMAND[1]+x}" ]; then
      local -a a=()
      for e in "${PROMPT_COMMAND[@]}"; do
        case "$e" in
          __shellx_prompt_start|__shellx_prompt_end) ;;
          *) __shellx_unwrap "$e"; a+=("$__shellx_s") ;;
        esac
      done
      PROMPT_COMMAND=(${a[@]+"${a[@]}"})
    else
      __shellx_unwrap "${PROMPT_COMMAND-}"
      PROMPT_COMMAND=$__shellx_s
    fi
    for e in ${precmd_functions[@]+"${precmd_functions[@]}"}; do [ "$e" = __shellx_bp_precmd ] && return 0; done
    precmd_functions=(__shellx_bp_precmd ${precmd_functions[@]+"${precmd_functions[@]}"})
    preexec_functions+=(__shellx_bp_preexec)
    return 0
  }
  __shellx_prompt_start() {
    local ret=$?
    if [ -n "${__shellx_running-}" ]; then
      builtin printf '\033]133;D;%s\007' "$ret"
      __shellx_running=
    fi
    __shellx_osc7
    if [ -z "${__shellx_bp-}" ] && [ -n "${__bp_imported-}${bash_preexec_imported-}" ]; then __shellx_use_bash_preexec; fi
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
    [ -z "${__shellx_bp-}" ] || return 0
    if [ -n "${__bp_imported-}${bash_preexec_imported-}" ]; then
      __shellx_use_bash_preexec
      return 0
    fi
    # Under extdebug the trap also fires inside functions (ours included): only top-level commands count.
    [ -z "${FUNCNAME[1]-}" ] || return 0
    local re='^ *([0-9]+)[* ] *(.*)$' __shellx_s
    if __shellx_wrap_prompt; then
      # Our start/end were missing, or no longer first/last: the next command line typed is still a
      # command even if this prompt never reaches __shellx_prompt_end (the first line that adds a
      # history entry).
      if [[ "$(HISTTIMEFORMAT= builtin history 1)" =~ $re ]]; then __shellx_hist=${BASH_REMATCH[1]}; fi
      __shellx_pending=1
      __shellx_at_prompt=
      if [ "$BASH_COMMAND" = __shellx_prompt_start ]; then __shellx_skip_end=1; fi
      return 0
    fi
    if [ "$BASH_COMMAND" = __shellx_prompt_start ]; then
      __shellx_at_prompt=
      __shellx_pending=
      return 0
    fi
    if [ -n "${COMP_LINE-}" ]; then return 0; fi
    if [ -z "${__shellx_at_prompt-}" ]; then
      if [ -z "${__shellx_pending-}" ]; then return 0; fi
      if ! [[ "$(HISTTIMEFORMAT= builtin history 1)" =~ $re ]]; then return 0; fi
      if [ "${BASH_REMATCH[1]}" = "${__shellx_hist-}" ]; then return 0; fi
      __shellx_pending=
    fi
    __shellx_at_prompt=
    if [[ "$(HISTTIMEFORMAT= builtin history 1)" =~ $re ]] && [ "${BASH_REMATCH[1]}" != "${__shellx_hist-}" ]; then
      __shellx_esc "${BASH_REMATCH[2]}"
    else
      __shellx_esc "$BASH_COMMAND"
    fi
    builtin printf '\033]633;E;%s\007\033]133;C\007' "$__shellx_s"
    __shellx_running=1
    return 0
  }
  if [ -n "${__bp_imported-}${bash_preexec_imported-}" ]; then
    __shellx_use_bash_preexec
  else
    __shellx_wrap_prompt
    builtin trap '__shellx_debug' DEBUG
  fi
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
      $loc = $executionContext.SessionState.Path.CurrentLocation
      if ($loc.Provider.Name -eq 'FileSystem') {
        try { $mark += "$([char]27)]7;$(([System.Uri]$loc.ProviderPath).AbsoluteUri)$([char]7)" } catch { }
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
