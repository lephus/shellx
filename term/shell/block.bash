# >>> ShellX >>>
# Lets your paired phone see this terminal. Managed by ShellX: turn it off from the ShellX menu instead of editing it.
if [[ $- == *i* && -z "${BASH_EXECUTION_STRING-}" && -t 0 && -t 1 \
      && -z "${SHELLX_TERM-}${SHELLX-}${TMUX-}${STY-}" \
      && "${TERM_PROGRAM-}" != WarpTerminal \
      && -x "$HOME/Library/Application Support/ShellX/bin/shellx-term" ]]; then
  if shopt -q login_shell; then
    exec "$HOME/Library/Application Support/ShellX/bin/shellx-term" wrap --login -- "$BASH"
  else
    exec "$HOME/Library/Application Support/ShellX/bin/shellx-term" wrap -- "$BASH"
  fi
fi
# <<< ShellX <<<
