# >>> ShellX >>>
# Lets your paired phone see this terminal. Managed by ShellX: turn it off from the ShellX menu instead of editing it.
if [[ -o interactive && -z "${ZSH_EXECUTION_STRING-}" && -t 0 && -t 1 \
      && -z "${SHELLX_TERM-}${SHELLX-}${TMUX-}${STY-}" \
      && "${TERM_PROGRAM-}" != WarpTerminal \
      && -f "$HOME/Library/Application Support/ShellX/bin/shellx-term" \
      && -x "$HOME/Library/Application Support/ShellX/bin/shellx-term" ]] \
   && "$HOME/Library/Application Support/ShellX/bin/shellx-term" --version >/dev/null 2>&1; then
  __shellx_shell=${ZSH_ARGZERO#-}
  if [[ $__shellx_shell != /* ]]; then
    if [[ ${SHELL:t} == zsh ]]; then __shellx_shell=$SHELL; else __shellx_shell=${__shellx_shell:c}; fi
  fi
  # VS Code/Cursor and JetBrains start zsh with ZDOTDIR pointing at their own dir; point it back
  # there so the inner shell re-runs their integration.
  __shellx_zd=
  if [[ -n "${VSCODE_ZDOTDIR-}" ]]; then __shellx_zd=$VSCODE_ZDOTDIR
  elif [[ -n "${_INTELLIJ_ZDOTDIR-}" ]]; then __shellx_zd=$_INTELLIJ_ZDOTDIR; fi
  if [[ -n $__shellx_zd ]]; then
    export ZDOTDIR=$__shellx_zd
  fi
  exec "$HOME/Library/Application Support/ShellX/bin/shellx-term" wrap -- "$__shellx_shell"
fi
# <<< ShellX <<<
