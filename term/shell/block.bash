# >>> ShellX >>>
# Lets your paired phone see this terminal. Managed by ShellX: turn it off from the ShellX menu instead of editing it.
if [[ $- == *i* && -z "${BASH_EXECUTION_STRING-}" && -t 0 && -t 1 \
      && -z "${SHELLX_TERM-}${SHELLX-}${TMUX-}${STY-}" \
      && "${TERM_PROGRAM-}" != WarpTerminal \
      && "${TERM_PROGRAM-}" != vscode \
      && "${TERMINAL_EMULATOR-}" != JetBrains-JediTerm \
      && -f "$HOME/Library/Application Support/ShellX/bin/shellx-term" \
      && -x "$HOME/Library/Application Support/ShellX/bin/shellx-term" ]] \
   && "$HOME/Library/Application Support/ShellX/bin/shellx-term" --version >/dev/null 2>&1; then
  if shopt -q login_shell; then
    exec "$HOME/Library/Application Support/ShellX/bin/shellx-term" wrap --login -- "$BASH"
  else
    exec "$HOME/Library/Application Support/ShellX/bin/shellx-term" wrap -- "$BASH"
  fi
fi
# <<< ShellX <<<
