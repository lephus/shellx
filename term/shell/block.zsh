# >>> ShellX >>>
# Lets your paired phone see this terminal. Managed by ShellX: turn it off from the ShellX menu instead of editing it.
if [[ -o interactive && -z "${ZSH_EXECUTION_STRING-}" && -t 0 && -t 1 \
      && -z "${SHELLX_TERM-}${SHELLX-}${TMUX-}${STY-}" \
      && "${TERM_PROGRAM-}" != WarpTerminal \
      && -x "$HOME/Library/Application Support/ShellX/bin/shellx-term" ]]; then
  __shellx_shell=${ZSH_ARGZERO#-}
  if [[ $__shellx_shell != /* ]]; then
    if [[ ${SHELL:t} == zsh ]]; then __shellx_shell=$SHELL; else __shellx_shell=${__shellx_shell:c}; fi
  fi
  if [[ -o login ]]; then
    exec "$HOME/Library/Application Support/ShellX/bin/shellx-term" wrap --login -- "$__shellx_shell"
  else
    exec "$HOME/Library/Application Support/ShellX/bin/shellx-term" wrap -- "$__shellx_shell"
  fi
  unset __shellx_shell
fi
# <<< ShellX <<<
