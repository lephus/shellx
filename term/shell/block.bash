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
fi
# <<< ShellX <<<
