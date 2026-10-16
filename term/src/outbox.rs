//! Frames waiting for the agent (spec §5.4 item 1). Pushing never blocks:
//! past the limit the outbox drops everything and reports overflow, and the
//! link ends the session and resyncs later from the ring buffer.

use std::collections::VecDeque;
use std::sync::{Condvar, Mutex, MutexGuard};
use std::time::{Duration, Instant};

pub const LIMIT: usize = 1024 * 1024;

#[derive(Debug, PartialEq, Eq)]
pub enum Pop {
    Frame(Vec<u8>),
    Timeout,
    Overflowed,
    Closed,
}

#[derive(Default)]
struct State {
    frames: VecDeque<Vec<u8>>,
    bytes: usize,
    overflowed: bool,
    closed: bool,
    /// A popped frame is being written.
    in_flight: bool,
}

pub struct Outbox {
    state: Mutex<State>,
    changed: Condvar,
    limit: usize,
}

impl Outbox {
    pub fn new(limit: usize) -> Outbox {
        Outbox {
            state: Mutex::new(State::default()),
            changed: Condvar::new(),
            limit,
        }
    }

    fn lock(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// Queues a frame. False (and nothing queued) when closed, overflowed,
    /// or when this frame would pass the limit — which marks overflow.
    pub fn push(&self, frame: Vec<u8>) -> bool {
        let mut s = self.lock();
        if s.closed || s.overflowed {
            return false;
        }
        if s.bytes + frame.len() > self.limit {
            s.overflowed = true;
            s.frames.clear();
            s.bytes = 0;
            self.changed.notify_all();
            return false;
        }
        s.bytes += frame.len();
        s.frames.push_back(frame);
        self.changed.notify_all();
        true
    }

    /// Next frame, or why there is none. `Closed` only once drained.
    pub fn pop(&self, timeout: Duration) -> Pop {
        let until = Instant::now() + timeout;
        let mut s = self.lock();
        loop {
            if s.overflowed {
                return Pop::Overflowed;
            }
            if let Some(frame) = s.frames.pop_front() {
                s.bytes -= frame.len();
                s.in_flight = true;
                return Pop::Frame(frame);
            }
            if s.closed {
                return Pop::Closed;
            }
            let left = until.saturating_duration_since(Instant::now());
            if left.is_zero() {
                return Pop::Timeout;
            }
            s = self
                .changed
                .wait_timeout(s, left)
                .unwrap_or_else(|e| e.into_inner())
                .0;
        }
    }

    /// The frame from the last `pop` has been written (or failed).
    pub fn written(&self) {
        self.lock().in_flight = false;
        self.changed.notify_all();
    }

    /// Empties the queue and clears overflow for a new session.
    pub fn reset(&self) {
        let mut s = self.lock();
        s.frames.clear();
        s.bytes = 0;
        s.overflowed = false;
        s.in_flight = false;
        self.changed.notify_all();
    }

    pub fn close(&self) {
        self.lock().closed = true;
        self.changed.notify_all();
    }

    /// Waits until every queued frame was written; false on timeout.
    pub fn wait_drained(&self, timeout: Duration) -> bool {
        let until = Instant::now() + timeout;
        let mut s = self.lock();
        loop {
            if (s.frames.is_empty() && !s.in_flight) || s.overflowed {
                return true;
            }
            let left = until.saturating_duration_since(Instant::now());
            if left.is_zero() {
                return false;
            }
            s = self
                .changed
                .wait_timeout(s, left)
                .unwrap_or_else(|e| e.into_inner())
                .0;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    const SHORT: Duration = Duration::from_millis(50);

    #[test]
    fn frames_come_out_in_order() {
        let o = Outbox::new(100);
        assert!(o.push(vec![1]));
        assert!(o.push(vec![2, 2]));
        assert_eq!(o.pop(SHORT), Pop::Frame(vec![1]));
        assert_eq!(o.pop(SHORT), Pop::Frame(vec![2, 2]));
        assert_eq!(o.pop(SHORT), Pop::Timeout);
    }

    #[test]
    fn passing_the_limit_drops_everything_and_reports_overflow() {
        let o = Outbox::new(10);
        assert!(o.push(vec![0; 6]));
        assert!(!o.push(vec![0; 6]));
        assert_eq!(o.pop(SHORT), Pop::Overflowed);
        assert!(!o.push(vec![1]), "stays overflowed until reset");
        o.reset();
        assert!(o.push(vec![1]));
        assert_eq!(o.pop(SHORT), Pop::Frame(vec![1]));
    }

    #[test]
    fn push_never_blocks_even_when_nobody_pops() {
        let o = Outbox::new(LIMIT);
        let start = Instant::now();
        for _ in 0..10_000 {
            o.push(vec![0; 1024]);
        }
        assert!(start.elapsed() < Duration::from_millis(500));
    }

    #[test]
    fn close_lets_queued_frames_out_first() {
        let o = Outbox::new(100);
        o.push(vec![9]);
        o.close();
        assert!(!o.push(vec![1]));
        assert_eq!(o.pop(SHORT), Pop::Frame(vec![9]));
        assert_eq!(o.pop(SHORT), Pop::Closed);
    }

    #[test]
    fn a_waiting_pop_wakes_on_push() {
        let o = Arc::new(Outbox::new(100));
        let o2 = o.clone();
        let t = std::thread::spawn(move || o2.pop(Duration::from_secs(5)));
        std::thread::sleep(Duration::from_millis(50));
        o.push(vec![5]);
        assert_eq!(t.join().unwrap(), Pop::Frame(vec![5]));
    }

    #[test]
    fn wait_drained_counts_the_frame_being_written() {
        let o = Outbox::new(100);
        o.push(vec![1]);
        assert!(!o.wait_drained(SHORT));
        assert_eq!(o.pop(SHORT), Pop::Frame(vec![1]));
        assert!(!o.wait_drained(SHORT), "still being written");
        o.written();
        assert!(o.wait_drained(SHORT));
    }
}
