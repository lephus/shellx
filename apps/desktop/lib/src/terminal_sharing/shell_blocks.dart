/// The integration blocks the installer writes (spec §5.2, §5.3), copied
/// byte for byte from `term/shell/` (`shell_blocks_test.dart` checks).
/// ASCII only, LF line endings, ending with a newline.
library;

/// `term/shell/block.zsh`.
const String zshBlock = r'''
# >>> ShellX >>>
# Lets your paired phone see this terminal. Managed by ShellX: turn it off from the ShellX menu instead of editing it.
if [[ -o interactive && -z "${ZSH_EXECUTION_STRING-}" && -z "${ZSH_SCRIPT-}" \
      && $ZSH_EVAL_CONTEXT != toplevel* && -t 0 && -t 1 \
      && -z "${SHELLX-}${TMUX-}${STY-}" && "${SHELLX_TERM-}" != "$TTY" \
      && "${TERM_PROGRAM-}" != WarpTerminal \
      && -f "$HOME/Library/Application Support/ShellX/bin/shellx-term" \
      && -x "$HOME/Library/Application Support/ShellX/bin/shellx-term" ]]; then
  # One run: proves the binary works (zsh exits if exec fails) and names this exact shell binary.
  __shellx_shell=$("$HOME/Library/Application Support/ShellX/bin/shellx-term" probe </dev/null 2>/dev/null)
  if [[ $__shellx_shell == /* ]]; then
    # VS Code/Cursor and JetBrains start zsh with ZDOTDIR pointing at their own dir; point it back
    # there so the inner shell re-runs their integration.
    if [[ -n "${VSCODE_ZDOTDIR-}" ]]; then export ZDOTDIR=$VSCODE_ZDOTDIR
    elif [[ -n "${_INTELLIJ_ZDOTDIR-}" ]]; then export ZDOTDIR=$_INTELLIJ_ZDOTDIR; fi
    [[ -o login ]] && export SHELLX_TERM_LOGIN=1
    export SHELLX_TERM_WRAP=$__shellx_shell
    exec -a "$ZSH_ARGZERO" "$HOME/Library/Application Support/ShellX/bin/shellx-term"
  fi
  unset __shellx_shell
elif [[ -n "${SHELLX_TERM-}" && "$SHELLX_TERM" == "$TTY" ]]; then
  # Inside the wrapped shell: act as the login shell this window started (zsh then reads ~/.zlogin).
  if [[ -n "${SHELLX_TERM_LOGIN-}" ]]; then
    unset SHELLX_TERM_LOGIN
    setopt login
  fi
  # Command notifications for the paired phone: report each command line, its start and its exit code
  # (OSC 633;E, 133;C, 133;D), installed at the first prompt, after the rest of the startup files.
  # Not where VS Code's own shell integration runs (it already reports commands, as OSC 633).
  if [[ -z "${VSCODE_SHELL_INTEGRATION-}" ]]; then
    if (( ! ${+functions[__shellx_precmd]} )); then
      __shellx_osc7() {
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
  fi
fi
# <<< ShellX <<<
''';

/// `term/shell/block.bash`.
const String bashBlock = r'''
# >>> ShellX >>>
# Lets your paired phone see this terminal. Managed by ShellX: turn it off from the ShellX menu instead of editing it.
if [[ $- == *i* && -z "${BASH_EXECUTION_STRING-}" && "${BASH_LINENO[0]-0}" == 0 && -t 0 && -t 1 \
      && -z "${SHELLX-}${TMUX-}${STY-}" \
      && "${TERM_PROGRAM-}" != WarpTerminal \
      && "${TERM_PROGRAM-}" != vscode \
      && "${TERMINAL_EMULATOR-}" != JetBrains-JediTerm \
      && -f "$HOME/Library/Application Support/ShellX/bin/shellx-term" \
      && -x "$HOME/Library/Application Support/ShellX/bin/shellx-term" ]] \
   && { [[ -z "${SHELLX_TERM-}" ]] || [[ "$SHELLX_TERM" != "$(tty)" ]]; }; then
  __shellx_shell=$("$HOME/Library/Application Support/ShellX/bin/shellx-term" probe </dev/null 2>/dev/null)
  if [[ $__shellx_shell == /* ]]; then
    export SHELLX_TERM_WRAP=$__shellx_shell
    if shopt -q login_shell; then export SHELLX_TERM_WRAP_LOGIN=1; fi
    exec -a "$0" "$HOME/Library/Application Support/ShellX/bin/shellx-term"
    unset SHELLX_TERM_WRAP SHELLX_TERM_WRAP_LOGIN
  fi
  unset __shellx_shell
elif [[ $- == *i* && -n "${SHELLX_TERM-}" && -z "${VSCODE_SHELL_INTEGRATION-}" ]] \
     && [[ "$SHELLX_TERM" == "$(tty 2>/dev/null)" ]]; then
  # Inside the wrapped shell: command notifications for the paired phone (each command line, its start
  # and its exit code as OSC 633;E, 133;C, 133;D). Not where VS Code's own shell integration runs.
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
fi
# <<< ShellX <<<
''';

/// `term/shell/block.ps1`.
const String powerShellBlock = r'''
# >>> ShellX >>>
# Lets your paired phone see this terminal. Managed by ShellX: turn it off from the ShellX menu instead of editing it.
if (-not $env:SHELLX_TERM -and -not $env:SHELLX -and $env:LOCALAPPDATA -and $Host.Name -eq 'ConsoleHost' `
    -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected `
    -and $null -eq (Get-History -Count 1)) {
  # Only a plain interactive start: any other argument (-Command, -File, a script...) means no.
  $__shellxPlain = -not ([Environment]::GetCommandLineArgs() | Select-Object -Skip 1 |
      Where-Object { $_ -notmatch '^-(nologo|noprofile|noprofileloadtime|noexit|login|l)$' })
  $__shellxExe = Join-Path $env:LOCALAPPDATA 'ShellX\bin\shellx-term.exe'
  if ($__shellxPlain -and (Test-Path -LiteralPath $__shellxExe -PathType Leaf)) {
    # 222, or a negative code (a crash, a loader failure), means carry on here. A binary that cannot start leaves 222.
    $global:LASTEXITCODE = 222
    try { & $__shellxExe wrap -- (Get-Process -Id $PID).Path -NoLogo } catch { }
    if ($LASTEXITCODE -ne 222 -and $LASTEXITCODE -ge 0) { [Environment]::Exit($LASTEXITCODE) }
    Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
  }
  Remove-Variable -Name __shellxPlain, __shellxExe -ErrorAction SilentlyContinue
} elseif ($env:SHELLX_TERM -and -not $env:SHELLX -and $Host.Name -eq 'ConsoleHost' `
    -and -not $env:VSCODE_SHELL_INTEGRATION -and -not $Global:__VSCodeOriginalPrompt) {
  # Inside the wrapped shell: command notifications for the paired phone (each command line, its start
  # and its exit code as OSC 633;E, 133;C, 133;D). Not where VS Code's own shell integration runs.
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
}
# <<< ShellX <<<
''';
