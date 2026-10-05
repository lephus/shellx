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
elif [[ -n "${SHELLX_TERM_LOGIN-}" && "${SHELLX_TERM-}" == "$TTY" ]]; then
  # Inside the wrapped shell: act as the login shell this window started (zsh then reads ~/.zlogin).
  unset SHELLX_TERM_LOGIN
  setopt login
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
}
# <<< ShellX <<<
''';
