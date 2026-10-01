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
elif [[ -n "${SHELLX_TERM_LOGIN-}" && "${SHELLX_TERM-}" == "$TTY" ]]; then
  # Inside the wrapped shell: act as the login shell this window started (zsh then reads ~/.zlogin).
  unset SHELLX_TERM_LOGIN
  setopt login
fi
# <<< ShellX <<<
