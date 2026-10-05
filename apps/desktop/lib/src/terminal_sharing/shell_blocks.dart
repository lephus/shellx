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
  # Not inside VS Code with its own shell integration (it already reports commands, as OSC 633).
  if [[ "${TERM_PROGRAM-}" != vscode || -z "${VSCODE_INJECTION-}${VSCODE_SHELL_INTEGRATION-}" ]]; then
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
elif [[ $- == *i* && -n "${SHELLX_TERM-}" ]] && [[ "$SHELLX_TERM" == "$(tty 2>/dev/null)" ]] \
     && [[ "${TERM_PROGRAM-}" != vscode || -z "${VSCODE_INJECTION-}${VSCODE_SHELL_INTEGRATION-}" ]]; then
  # Inside the wrapped shell: command notifications for the paired phone (each command line, its start
  # and its exit code as OSC 633;E, 133;C, 133;D). Not inside VS Code with its own shell integration.
  if [[ $- == *i* && -z "${__shellx_hooked-}" && -z "$(builtin trap -p DEBUG)" ]]; then
    __shellx_hooked=1
    __shellx_wrap_prompt() {
      case "${PROMPT_COMMAND[*]-}" in
        *__shellx_prompt_end*) ;;
        *)
          if [[ "$(builtin declare -p PROMPT_COMMAND 2>/dev/null)" == "declare -a"* ]]; then
            PROMPT_COMMAND=(__shellx_prompt_start "${PROMPT_COMMAND[@]}" __shellx_prompt_end)
          else
            PROMPT_COMMAND="__shellx_prompt_start"$'\n'"${PROMPT_COMMAND-}"$'\n'"__shellx_prompt_end"
          fi ;;
      esac
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
      if [[ "$(HISTTIMEFORMAT= builtin history 1)" =~ $re ]]; then __shellx_hist=${BASH_REMATCH[1]}; fi
      __shellx_at_prompt=1
      return $ret
    }
    __shellx_debug() {
      case "${PROMPT_COMMAND[*]-}" in *__shellx_prompt_end*) ;; *) __shellx_wrap_prompt ;; esac
      if [ "$BASH_COMMAND" = __shellx_prompt_start ]; then
        __shellx_at_prompt=
        return
      fi
      [ -n "${COMP_LINE-}" ] && return
      [ -z "${__shellx_at_prompt-}" ] && return
      __shellx_at_prompt=
      local s re='^ *([0-9]+)[* ] *(.*)$' nl=$'\n' cr=$'\r' bel=$'\a' esc=$'\e'
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
    -and $env:TERM_PROGRAM -ne 'vscode' -and -not $Global:__VSCodeOriginalPrompt) {
  # Inside the wrapped shell: command notifications for the paired phone (each command line, its start
  # and its exit code as OSC 633;E, 133;C, 133;D). Not inside VS Code (its own integration reports commands).
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
}
# <<< ShellX <<<
''';
