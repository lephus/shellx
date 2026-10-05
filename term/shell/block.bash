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
elif [[ $- == *i* && -n "${SHELLX_TERM-}" ]] && [[ "$SHELLX_TERM" == "$(tty 2>/dev/null)" ]]; then
  # Inside the wrapped shell: command notifications for the paired phone (each command line, its start
  # and its exit code as OSC 633;E, 133;C, 133;D).
  if [[ $- == *i* && -z "${__shellx_hooked-}" && -z "$(builtin trap -p DEBUG)" ]]; then
    __shellx_hooked=1
    __shellx_wrap_prompt() {
      case "${PROMPT_COMMAND-}" in
        *__shellx_prompt_end*) ;;
        *) PROMPT_COMMAND="__shellx_prompt_start"$'\n'"${PROMPT_COMMAND-}"$'\n'"__shellx_prompt_end" ;;
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
      if [ "$BASH_COMMAND" = __shellx_prompt_start ]; then
        __shellx_at_prompt=
        __shellx_wrap_prompt
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
