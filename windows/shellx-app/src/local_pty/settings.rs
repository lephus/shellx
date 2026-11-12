//! Which shell a new local pane starts: the stored choice, the shell catalogue and the plan.

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;
    use std::path::PathBuf;
    use std::sync::Arc;
    use std::time::{Duration, Instant};

    use shellx_model::shell::{
        CustomShellError, POWERSHELL_PROMPT_HOOK, ShellChoice, ShellError, ShellKind, ShellLaunch,
        ShellProbe,
    };

    use crate::local_pty::{ShellCmd, command_prompt_for};

    const PWSH: &str = r"C:\Program Files\PowerShell\7\pwsh.exe";
    const WINPS: &str = r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe";
    const CMD: &str = r"C:\Windows\system32\cmd.exe";
    const SYSTEM32_CMD: &str = r"C:\Windows\System32\cmd.exe";

    /// A Windows machine as the probe sees it (the tests run on a Mac).
    fn probe() -> ShellProbe {
        ShellProbe {
            system_root: Some(r"C:\Windows".into()),
            program_files: Some(r"C:\Program Files".into()),
            comspec: Some(CMD.into()),
            path: r"C:\Windows\System32".into(),
            git_install_path: None,
        }
    }

    type Exists = Arc<dyn Fn(&str) -> bool + Send + Sync>;

    fn exists_in(files: &[&str]) -> Exists {
        let set: HashSet<String> = files.iter().map(|f| f.to_string()).collect();
        Arc::new(move |p: &str| set.contains(p))
    }

    /// Every answer takes `delay`: an offline network folder on PATH.
    fn slow(delay: Duration, files: &[&str]) -> Exists {
        let fast = exists_in(files);
        Arc::new(move |p: &str| {
            std::thread::sleep(delay);
            fast(p)
        })
    }

    /// `settings.json` in a folder whose name has Vietnamese letters and a space.
    fn settings_path() -> (tempfile::TempDir, PathBuf) {
        let dir = tempfile::tempdir().unwrap();
        let folder = dir.path().join("Phú Lê");
        std::fs::create_dir_all(&folder).unwrap();
        let path = folder.join("settings.json");
        (dir, path)
    }

    fn windows(path: &PathBuf, exists: Exists, env: Option<&str>, wait: Duration) -> Shells {
        Shells::new(
            SettingsFile::new(path.clone()),
            probe(),
            env.map(String::from),
            exists,
            ShellHost::Windows,
            wait,
        )
    }

    fn hook_args() -> Vec<String> {
        ["-NoLogo", "-NoExit", "-Command", POWERSHELL_PROMPT_HOOK]
            .map(String::from)
            .to_vec()
    }

    fn kinds(found: &[ShellLaunch]) -> Vec<Option<ShellKind>> {
        found.iter().map(|l| l.kind).collect()
    }

    fn json(path: &PathBuf) -> serde_json::Value {
        serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
    }

    #[test]
    fn the_stored_choice_round_trips_and_keeps_other_keys() {
        let (_dir, path) = settings_path();
        std::fs::write(
            &path,
            r#"{"shell":{"kind":"known","shell":"git_bash"},"future":1}"#,
        )
        .unwrap();
        let file = SettingsFile::new(path.clone());
        assert_eq!(
            file.load(),
            ShellChoice::Known {
                shell: ShellKind::GitBash
            }
        );
        file.save(&ShellChoice::Auto).unwrap();
        assert_eq!(
            json(&path),
            serde_json::json!({"shell": {"kind": "auto"}, "future": 1})
        );
        let custom = ShellChoice::Custom {
            command_line: r#""C:\Program Files\Git\bin\bash.exe" -l"#.into(),
        };
        file.save(&custom).unwrap();
        assert_eq!(file.load(), custom);
        assert_eq!(json(&path)["future"], 1);
        // the temporary file was renamed over settings.json: nothing else is left
        let names: Vec<_> = std::fs::read_dir(path.parent().unwrap())
            .unwrap()
            .map(|e| e.unwrap().file_name())
            .collect();
        assert_eq!(names, ["settings.json"]);
        // a folder that does not exist yet is created
        let nested = path.parent().unwrap().join("native").join("settings.json");
        SettingsFile::new(nested.clone())
            .save(&ShellChoice::Auto)
            .unwrap();
        assert_eq!(SettingsFile::new(nested).load(), ShellChoice::Auto);
    }

    #[test]
    fn a_missing_or_unreadable_file_means_auto() {
        let (_dir, path) = settings_path();
        let file = SettingsFile::new(path.clone());
        assert_eq!(file.load(), ShellChoice::Auto);
        for text in ["{", "[]", r#"{"shell":{"kind":"bash"}}"#, r#"{"shell":3}"#, ""] {
            std::fs::write(&path, text).unwrap();
            assert_eq!(file.load(), ShellChoice::Auto, "{text}");
        }
        // saving over an unreadable file leaves a readable one
        std::fs::write(&path, "[]").unwrap();
        let cmd = ShellChoice::Known {
            shell: ShellKind::Cmd,
        };
        file.save(&cmd).unwrap();
        assert_eq!(file.load(), cmd);
    }

    #[test]
    fn the_catalogue_follows_the_choice_and_shellx_shell() {
        let (_dir, path) = settings_path();
        let files = [PWSH, WINPS, CMD];
        let shells = windows(&path, exists_in(&files), None, Duration::from_millis(100));
        assert_eq!(shells.choice(), ShellChoice::Auto);
        let snap = shells.refresh_now();
        assert_eq!(snap.choice, ShellChoice::Auto);
        assert_eq!(snap.env_override, None);
        assert_eq!(
            kinds(&snap.found),
            [
                Some(ShellKind::Pwsh),
                Some(ShellKind::WindowsPowerShell),
                Some(ShellKind::Cmd)
            ]
        );
        let plan = snap.plan.unwrap().unwrap();
        assert_eq!(plan.first.kind, Some(ShellKind::Pwsh));
        assert_eq!(
            plan.fallback.as_ref().unwrap().kind,
            Some(ShellKind::WindowsPowerShell)
        );
        // the OSC 7 prompt hook travels in PowerShell's arguments
        let first = ShellCmd::from_launch(&plan.first);
        assert_eq!(first.program, PWSH);
        assert_eq!(first.args, hook_args());
        assert!(first.env.is_empty());
        assert_eq!(first.label, "PowerShell 7");
        assert_eq!(first.kind, Some(ShellKind::Pwsh));

        // a stored choice: saved, then the next plan starts it
        let cmd = ShellChoice::Known {
            shell: ShellKind::Cmd,
        };
        shells.set_choice(cmd.clone()).unwrap();
        assert_eq!(shells.choice(), cmd);
        assert_eq!(SettingsFile::new(path.clone()).load(), cmd);
        let plan = shells.refresh_now().plan.unwrap().unwrap();
        assert_eq!(plan.first.kind, Some(ShellKind::Cmd));
        assert!(plan.first.args.is_empty());
        assert_eq!(plan.fallback.unwrap().kind, Some(ShellKind::Pwsh));
        let pane = shells.plan_for_new_pane().unwrap();
        assert_eq!(pane.first.label, "Command Prompt");
        assert_eq!(pane.first.program, CMD);
        assert_eq!(pane.fallback.unwrap().label, "PowerShell 7");

        // SHELLX_SHELL wins over the stored choice and takes arguments
        let over = windows(
            &path,
            exists_in(&files),
            Some(r"C:\Windows\system32\cmd.exe /k"),
            Duration::from_millis(100),
        );
        let snap = over.refresh_now();
        assert_eq!(
            snap.env_override.as_deref(),
            Some(r"C:\Windows\system32\cmd.exe /k")
        );
        let plan = snap.plan.unwrap().unwrap();
        assert_eq!(plan.first.program, CMD);
        assert_eq!(plan.first.args, ["/k"]);
        // a blank SHELLX_SHELL is no override
        let blank = windows(&path, exists_in(&files), Some("  "), Duration::ZERO);
        assert_eq!(blank.refresh_now().env_override, None);

        // a custom line that names no program is an error, not another shell
        shells
            .set_choice(ShellChoice::Custom {
                command_line: "nope.exe".into(),
            })
            .unwrap();
        let missing = ShellError::Custom(CustomShellError::NotFound("nope.exe".into()));
        assert_eq!(shells.refresh_now().plan, Some(Err(missing.clone())));
        assert_eq!(shells.plan_for_new_pane(), Err(missing));
    }

    #[test]
    fn the_first_pane_waits_at_most_the_bound_then_starts_windows_powershell() {
        let (_dir, path) = settings_path();
        let shells = windows(
            &path,
            slow(Duration::from_secs(1), &[PWSH, WINPS, CMD]),
            None,
            Duration::from_millis(100),
        );
        let started = Instant::now();
        let plan = shells.plan_for_new_pane().unwrap();
        let took = started.elapsed();
        assert!(took >= Duration::from_millis(90), "{took:?}");
        assert!(took < Duration::from_secs(1), "{took:?}");
        assert_eq!(plan.first.program, WINPS);
        assert_eq!(plan.first.args, hook_args());
        assert_eq!(plan.first.label, "Windows PowerShell");
        assert_eq!(plan.first.kind, Some(ShellKind::WindowsPowerShell));
        let fallback = plan.fallback.unwrap();
        assert_eq!(fallback.program, SYSTEM32_CMD);
        assert!(fallback.args.is_empty());
        assert_eq!(fallback.label, "Command Prompt");
        // the probe is still running: nothing is known yet
        assert_eq!(shells.snapshot().plan, None);
        assert!(shells.snapshot().found.is_empty());
    }

    #[test]
    fn a_new_pane_uses_the_catalogue_once_it_is_ready() {
        let (_dir, path) = settings_path();
        let shells = windows(
            &path,
            exists_in(&[PWSH, WINPS, CMD]),
            None,
            Duration::from_millis(100),
        );
        shells.refresh_now();
        assert_eq!(shells.plan_for_new_pane().unwrap().first.label, "PowerShell 7");

        // the probe the first pane started feeds the panes after it
        let shells = windows(
            &path,
            slow(Duration::from_millis(20), &[PWSH, WINPS, CMD]),
            None,
            Duration::ZERO,
        );
        assert_eq!(
            shells.plan_for_new_pane().unwrap().first.label,
            "Windows PowerShell"
        );
        let deadline = Instant::now() + Duration::from_secs(10);
        while shells.snapshot().plan.is_none() {
            assert!(Instant::now() < deadline, "the background probe never ended");
            std::thread::sleep(Duration::from_millis(10));
        }
        assert_eq!(shells.plan_for_new_pane().unwrap().first.label, "PowerShell 7");
    }

    #[test]
    fn only_the_first_pane_ever_waits() {
        let (_dir, path) = settings_path();
        let shells = windows(
            &path,
            slow(Duration::from_secs(1), &[PWSH, WINPS, CMD]),
            None,
            Duration::from_millis(100),
        );
        let started = Instant::now();
        let first = shells.plan_for_new_pane().unwrap();
        assert!(started.elapsed() >= Duration::from_millis(90));
        let started = Instant::now();
        let second = shells.plan_for_new_pane().unwrap();
        assert!(
            started.elapsed() < Duration::from_millis(20),
            "{:?}",
            started.elapsed()
        );
        assert_eq!(first.first.program, WINPS);
        assert_eq!(second.first.program, WINPS);
    }

    #[test]
    fn the_mac_harness_keeps_bash() {
        let (_dir, path) = settings_path();
        SettingsFile::new(path.clone())
            .save(&ShellChoice::Known {
                shell: ShellKind::Cmd,
            })
            .unwrap();
        let mac = |env: Option<&str>| {
            Shells::new(
                SettingsFile::new(path.clone()),
                ShellProbe::default(),
                env.map(String::from),
                exists_in(&[]),
                ShellHost::MacDev,
                Duration::from_secs(2),
            )
        };
        let plan = mac(None).plan_for_new_pane().unwrap();
        assert_eq!(plan.first.program, "/bin/bash");
        assert_eq!(plan.first.args, ["--noprofile", "--norc", "-i"]);
        assert!(
            plan.first
                .env
                .iter()
                .any(|(k, v)| k == "PROMPT_COMMAND" && v.contains("]7;file://"))
        );
        assert_eq!(plan.first.label, "bash");
        // SHELLX_SHELL: that program, without arguments
        let plan = mac(Some("/bin/zsh")).plan_for_new_pane().unwrap();
        assert_eq!(plan.first.program, "/bin/zsh");
        assert!(plan.first.args.is_empty());
        assert_eq!(plan.fallback, None);
    }

    #[cfg(unix)]
    #[test]
    fn program_files_are_files_folders_are_not_links_are_followed() {
        let dir = tempfile::tempdir().unwrap();
        let at = |name: &str| dir.path().join(name).to_str().unwrap().to_string();
        std::fs::write(at("a.exe"), b"MZ").unwrap();
        std::fs::create_dir(at("d")).unwrap();
        std::os::unix::fs::symlink(at("a.exe"), at("l.exe")).unwrap();
        std::os::unix::fs::symlink(at("gone.exe"), at("dangling.exe")).unwrap();
        std::os::unix::fs::symlink(at("d"), at("dir-link")).unwrap();
        assert!(is_program_file(&at("a.exe")));
        assert!(!is_program_file(&at("d")));
        assert!(is_program_file(&at("l.exe")));
        assert!(!is_program_file(&at("dangling.exe")));
        assert!(!is_program_file(&at("dir-link")));
        assert!(!is_program_file(&at("missing.exe")));
        assert!(!is_program_file(""));
    }

    #[test]
    fn command_prompt_prefers_the_catalogue_then_comspec_then_system32() {
        let found = vec![ShellLaunch {
            kind: Some(ShellKind::Cmd),
            program: CMD.into(),
            args: vec![],
            osc7_hook: false,
        }];
        let cmd = command_prompt_for(&found, &probe());
        assert_eq!(cmd.program, CMD);
        assert_eq!(cmd.label, "Command Prompt");
        assert_eq!(cmd.kind, Some(ShellKind::Cmd));
        assert!(cmd.args.is_empty() && cmd.env.is_empty());

        let comspec = ShellProbe {
            comspec: Some(r"D:\cmd\cmd.exe".into()),
            ..probe()
        };
        assert_eq!(command_prompt_for(&[], &comspec).program, r"D:\cmd\cmd.exe");

        let relative = ShellProbe {
            comspec: Some("cmd.exe".into()),
            ..probe()
        };
        let cmd = command_prompt_for(&[], &relative);
        assert_eq!(cmd.program, SYSTEM32_CMD);
        assert_eq!(cmd.label, "Command Prompt");
        // nothing usable at all: C:\Windows
        let bare = ShellProbe {
            system_root: Some("Windows".into()),
            comspec: None,
            ..ShellProbe::default()
        };
        assert_eq!(command_prompt_for(&[], &bare).program, SYSTEM32_CMD);
    }

    #[test]
    fn the_startup_plan_reads_system_root_without_probing() {
        let plan = startup_plan(&ShellProbe {
            system_root: Some(r"D:\Win\".into()),
            ..ShellProbe::default()
        });
        assert_eq!(
            plan.first.program,
            r"D:\Win\System32\WindowsPowerShell\v1.0\powershell.exe"
        );
        assert_eq!(plan.fallback.unwrap().program, r"D:\Win\System32\cmd.exe");
        let plan = startup_plan(&ShellProbe::default());
        assert_eq!(plan.first.program, WINPS);
    }
}
