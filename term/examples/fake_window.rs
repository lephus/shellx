//! A terminal window for tests outside this crate (the Dart suites of plan
//! P3): runs `program args…` in a fresh 80x24 PTY, copies this process's
//! stdin into the PTY and the PTY's output to stdout, and exits with the
//! program's exit code. The environment is inherited.
//!
//!     cargo build --features test-hooks --bin shellx-term --example fake_window
//!     target/debug/examples/fake_window target/debug/shellx-term wrap -- /bin/sh

#[cfg(unix)]
fn main() {
    use portable_pty::{native_pty_system, CommandBuilder, PtySize};
    use std::io::{Read, Write};

    let args: Vec<String> = std::env::args().skip(1).collect();
    let Some((program, rest)) = args.split_first() else {
        eprintln!("usage: fake_window <program> [args…]");
        std::process::exit(2);
    };
    let pair = native_pty_system()
        .openpty(PtySize {
            rows: 24,
            cols: 80,
            pixel_width: 0,
            pixel_height: 0,
        })
        .expect("openpty");
    let mut cmd = CommandBuilder::new(program);
    cmd.args(rest);
    cmd.cwd(std::env::temp_dir());
    let mut child = pair.slave.spawn_command(cmd).expect("spawn");
    drop(pair.slave);
    let mut reader = pair.master.try_clone_reader().expect("reader");
    let mut writer = pair.master.take_writer().expect("writer");
    std::thread::spawn(move || {
        let mut stdin = std::io::stdin();
        let mut buf = [0u8; 4096];
        while let Ok(n) = stdin.read(&mut buf) {
            if n == 0 || writer.write_all(&buf[..n]).is_err() {
                break;
            }
        }
    });
    let output = std::thread::spawn(move || {
        let mut stdout = std::io::stdout();
        let mut buf = [0u8; 16384];
        while let Ok(n) = reader.read(&mut buf) {
            if n == 0 {
                break;
            }
            let _ = stdout.write_all(&buf[..n]);
            let _ = stdout.flush();
        }
    });
    let status = child.wait().expect("wait");
    drop(pair.master);
    let _ = output.join();
    std::process::exit(status.exit_code() as i32);
}

#[cfg(not(unix))]
fn main() {
    eprintln!("fake_window: Unix only");
    std::process::exit(2);
}
