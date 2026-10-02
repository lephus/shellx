#![cfg(feature = "test-hooks")]
//! Its own test binary: it sets SHELLX_TERM_FAULT for the whole process.

mod common;

use common::fake_agent::{Behavior, FakeAgent};
use shellx_term::link::{Link, LinkEvents, Timing};
use shellx_term::proto::endpoint::endpoint_path_in;
use shellx_term::proto::messages::{AgentMsg, TermInfo};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

const T: Duration = Duration::from_secs(5);

struct Events;

impl LinkEvents for Events {
    fn info(&self) -> TermInfo {
        TermInfo {
            term_id: [3; 16],
            app: String::new(),
            shell: "zsh".into(),
            pid: 1,
            cols: 80,
            rows: 24,
            started_at: 1,
        }
    }
    fn input(&self, _data: &[u8]) {}
    fn phone_resize(&self, _cols: u16, _rows: u16) {}
    fn phone_left(&self) {}
}

#[test]
fn a_reader_panic_ends_the_session_even_while_output_flows() {
    std::env::set_var("SHELLX_TERM_FAULT", "reader-panic");
    let home = common::temp_dir("link-reader-panic");
    let link = Arc::new(Link::start(
        Some(endpoint_path_in(&home)),
        Timing::fast(),
        Arc::new(Events),
    ));
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut first = agent.next_session(T);
    first.snapshot(T);
    let stop = Arc::new(AtomicBool::new(false));
    let pump = {
        let (link, stop) = (link.clone(), stop.clone());
        std::thread::spawn(move || {
            while !stop.load(Ordering::SeqCst) {
                link.output(b"tick\r\n");
                std::thread::sleep(Duration::from_millis(5));
            }
        })
    };
    first.send(&AgentMsg::In {
        data: b"x".to_vec(),
    }); // the reader panics here
        // Without the guard the session lives on (output keeps its writer busy)
        // and phone input is lost; with it the session ends and the link
        // reconnects.
    let _second = agent.next_session(T);
    stop.store(true, Ordering::SeqCst);
    pump.join().unwrap();
}
