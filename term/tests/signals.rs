mod common;

use common::{Harness, BIN};
use std::time::{Duration, Instant};

const T: Duration = Duration::from_secs(5);

/// Saves the window's modes to `before` and waits until that is done, so the
/// later type-ahead cannot leave the kernel's transient PENDIN flag in the
/// saved value.
fn record_modes_first(h: &mut Harness, dir: &std::path::Path) {
    let d = dir.display();
    h.send(&format!("stty -g > {d}/before; echo rea''dy\r"));
    h.expect("ready", T);
    h.settle(Duration::from_millis(100));
}

#[test]
fn resizing_the_window_resizes_the_shell() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("echo rea''dy\r");
    h.expect("ready", T);
    h.resize(100, 40);
    let until = Instant::now() + T;
    loop {
        h.send("stty size\r");
        h.settle(Duration::from_millis(300));
        if h.text().contains("40 100") {
            break;
        }
        assert!(
            Instant::now() < until,
            "size never reached the shell: {:?}",
            h.text()
        );
    }
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn ctrl_c_interrupts_the_foreground_command() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("sleep 30\r");
    std::thread::sleep(Duration::from_millis(300));
    h.send_bytes(b"\x03");
    h.send("echo after''int\r");
    h.expect("afterint", T);
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn ctrl_z_stops_the_foreground_command() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("sleep 30\r");
    std::thread::sleep(Duration::from_millis(300));
    h.send_bytes(b"\x1a");
    h.expect("Stopped", T);
    // SIGKILL ends a stopped job; the shell reports it before its next prompt.
    h.send("kill -KILL %1\r");
    // macOS reports the kill only once it has taken effect, at a later
    // prompt: press Enter until the shell says so.
    let until = Instant::now() + T;
    while !h.text().contains("Killed") {
        assert!(
            Instant::now() < until,
            "job never reported killed: {:?}",
            h.text()
        );
        h.settle(Duration::from_millis(300));
        h.send("\r");
    }
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn a_flood_of_output_can_be_interrupted() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("yes\r");
    std::thread::sleep(Duration::from_millis(500));
    h.send_bytes(b"\x03");
    h.send("echo after''yes\r");
    h.expect("afteryes", Duration::from_secs(10));
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn the_window_modes_are_restored_after_the_shell_exits() {
    let dir = common::temp_dir("modes-exit");
    let d = dir.display();
    let mut h = Harness::spawn("/bin/sh", &[], &[], 80, 24);
    h.send(&format!(
        "stty -g > {d}/before; {BIN} wrap -- /bin/sh; stty -g > {d}/after; echo sa''ved\r"
    ));
    h.send("echo in''side\r");
    h.expect("inside", T);
    h.send("exit 0\r");
    h.expect("saved", T);
    common::assert_same_modes(&dir);
}

#[test]
fn sigterm_restores_the_window_and_exits_143() {
    let dir = common::temp_dir("modes-term");
    let d = dir.display();
    let mut h = Harness::spawn("/bin/sh", &[], &[], 80, 24);
    record_modes_first(&mut h, &dir);
    h.send(&format!(
        "{BIN} wrap -- /bin/sh; echo code=$?; stty -g > {d}/after; echo sa''ved\r"
    ));
    h.send("echo in''side\r");
    h.expect("inside", T);
    h.send("kill -TERM $PPID\r");
    h.expect("saved", T);
    assert_eq!(h.number_after("code="), Some(143));
    common::assert_same_modes(&dir);
}

#[test]
fn closing_the_window_hangs_up_the_running_command() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("sh -c 'echo pid=$$; exec sleep 1000'\r");
    let sleeper = h.wait_number_after("pid=", T) as i32;
    std::thread::sleep(Duration::from_millis(200)); // let `exec sleep` happen
                                                    // What the kernel does to a window's process when the window closes.
    unsafe { libc::kill(h.pid(), libc::SIGHUP) };
    h.wait_exit(T);
    let until = Instant::now() + T;
    while unsafe { libc::kill(sleeper, 0) } == 0 {
        assert!(
            Instant::now() < until,
            "sleep {sleeper} survived the window closing"
        );
        std::thread::sleep(Duration::from_millis(50));
    }
}
