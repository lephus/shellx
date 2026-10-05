//! The block files as text: what every installer relies on.

const BLOCKS: [(&str, &str); 3] = [
    ("block.zsh", include_str!("../shell/block.zsh")),
    ("block.bash", include_str!("../shell/block.bash")),
    ("block.ps1", include_str!("../shell/block.ps1")),
];

#[test]
fn every_block_is_ascii_with_exact_markers() {
    for (name, block) in BLOCKS {
        assert!(block.is_ascii(), "{name}");
        let lines: Vec<&str> = block.lines().collect();
        assert_eq!(lines.first(), Some(&"# >>> ShellX >>>"), "{name}");
        assert_eq!(lines.last(), Some(&"# <<< ShellX <<<"), "{name}");
        assert!(block.ends_with('\n'), "{name}");
    }
}

#[test]
fn the_powershell_block_uses_the_installed_path_and_222() {
    let ps1 = BLOCKS[2].1;
    assert!(ps1.contains(r"Join-Path $env:LOCALAPPDATA 'ShellX\bin\shellx-term.exe'"));
    assert!(ps1.contains("$global:LASTEXITCODE = 222"));
    assert!(ps1.contains("if ($LASTEXITCODE -ne 222 -and $LASTEXITCODE -ge 0) { [Environment]::Exit($LASTEXITCODE) }"));
    assert!(ps1.contains("$null -eq (Get-History -Count 1)"));
}

#[test]
fn every_block_installs_command_hooks_only_in_its_inner_shell_branch() {
    for (name, block) in BLOCKS {
        for needle in ["]133;D;", "]633;E;", "]133;C", "]777;notify;;"] {
            assert!(block.contains(needle), "{name}: {needle}");
        }
    }
    // The hooks follow the last `elif`/`elseif`: the inner-shell branch.
    let zsh = BLOCKS[0].1;
    assert!(
        zsh.find("__shellx_preexec").unwrap()
            > zsh
                .rfind("elif [[ -n \"${SHELLX_TERM-}\" && \"$SHELLX_TERM\" == \"$TTY\" ]]")
                .unwrap()
    );
    let bash = BLOCKS[1].1;
    assert!(
        bash.find("__shellx_debug").unwrap()
            > bash
                .find("elif [[ $- == *i* && -n \"${SHELLX_TERM-}\" ]]")
                .unwrap()
    );
    let ps1 = BLOCKS[2].1;
    assert!(
        ps1.find("__ShellxPrompt").unwrap()
            > ps1
                .find("} elseif ($env:SHELLX_TERM -and -not $env:SHELLX")
                .unwrap()
    );
}
