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
    -and -not $env:VSCODE_SHELL_INTEGRATION -and -not $Global:__VSCodeOriginalPrompt) {
  # Inside the wrapped shell: command notifications for the paired phone (each command line, its start
  # and its exit code as OSC 633;E, 133;C, 133;D). Not where VS Code's own shell integration runs.
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
        $loc = $executionContext.SessionState.Path.CurrentLocation
        if ($loc.Provider.Name -eq 'FileSystem') {
          try { $mark += "$([char]27)]7;$(([System.Uri]$loc.ProviderPath).AbsoluteUri)$([char]7)" } catch { }
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
