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
