//! Who decides the PTY's size when desktop and phone share it (spec §5.5):
//! the side that acted last. The desktop takes over without waiting for
//! the agent.

use crate::proto::messages::TermMsg;

pub trait Resizer {
    fn resize(&self, cols: u16, rows: u16);
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Driver {
    Desktop,
    Phone,
}

/// What to tell the agent after a desktop-side change.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Notice {
    Size { cols: u16, rows: u16 },
    Local,
}

impl Notice {
    pub fn to_msg(self) -> TermMsg {
        match self {
            Notice::Size { cols, rows } => TermMsg::Size { cols, rows },
            Notice::Local => TermMsg::Local,
        }
    }
}

pub struct SizeControl<R: Resizer> {
    resizer: R,
    driver: Driver,
    window: (u16, u16),
    applied: (u16, u16),
}

impl<R: Resizer> SizeControl<R> {
    /// The PTY starts at the window's size, driven by the desktop.
    pub fn new(resizer: R, window: (u16, u16)) -> SizeControl<R> {
        SizeControl {
            resizer,
            driver: Driver::Desktop,
            window,
            applied: window,
        }
    }

    pub fn driver(&self) -> Driver {
        self.driver
    }

    pub fn applied(&self) -> (u16, u16) {
        self.applied
    }

    /// The window was resized (SIGWINCH): the desktop drives.
    pub fn window_resized(&mut self, size: (u16, u16)) -> Vec<Notice> {
        self.window = size;
        let was_phone = self.driver == Driver::Phone;
        self.driver = Driver::Desktop;
        self.apply(size, was_phone);
        let mut notices = vec![Notice::Size {
            cols: size.0,
            rows: size.1,
        }];
        if was_phone {
            notices.push(Notice::Local);
        }
        notices
    }

    /// The user typed in the window. Cheap when the desktop already drives.
    pub fn local_input(&mut self) -> Vec<Notice> {
        if self.driver == Driver::Desktop {
            return vec![];
        }
        self.driver = Driver::Desktop;
        self.apply(self.window, true);
        vec![Notice::Local]
    }

    /// The phone attached, typed or resized (agent `resize`).
    pub fn phone_resize(&mut self, size: (u16, u16)) {
        let was_desktop = self.driver == Driver::Desktop;
        self.driver = Driver::Phone;
        self.apply(size, was_desktop);
    }

    /// The phone left (agent `local_size`, or the link dropped).
    pub fn phone_left(&mut self) {
        if self.driver == Driver::Phone {
            self.driver = Driver::Desktop;
            self.apply(self.window, true);
        }
    }

    /// Resizes to `size`. When the size does not change but the driver did,
    /// shrink by one row and back so full-screen programs redraw.
    fn apply(&mut self, size: (u16, u16), driver_changed: bool) {
        let (cols, rows) = size;
        if size != self.applied {
            self.resizer.resize(cols, rows);
            self.applied = size;
        } else if driver_changed {
            let bounce = if rows > 1 { rows - 1 } else { rows + 1 };
            self.resizer.resize(cols, bounce);
            self.resizer.resize(cols, rows);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    #[derive(Default)]
    struct Log(RefCell<Vec<(u16, u16)>>);
    impl Resizer for &Log {
        fn resize(&self, cols: u16, rows: u16) {
            self.0.borrow_mut().push((cols, rows));
        }
    }

    #[test]
    fn starts_with_the_desktop_at_window_size() {
        let log = Log::default();
        let s = SizeControl::new(&log, (80, 24));
        assert_eq!((s.driver(), s.applied()), (Driver::Desktop, (80, 24)));
        assert!(log.0.borrow().is_empty());
    }

    #[test]
    fn the_phone_takes_over_with_its_size() {
        let log = Log::default();
        let mut s = SizeControl::new(&log, (80, 24));
        s.phone_resize((50, 20));
        assert_eq!((s.driver(), s.applied()), (Driver::Phone, (50, 20)));
        assert_eq!(*log.0.borrow(), vec![(50, 20)]);
    }

    #[test]
    fn a_desktop_keystroke_takes_the_size_back_and_tells_the_agent() {
        let log = Log::default();
        let mut s = SizeControl::new(&log, (80, 24));
        s.phone_resize((50, 20));
        assert_eq!(s.local_input(), vec![Notice::Local]);
        assert_eq!((s.driver(), s.applied()), (Driver::Desktop, (80, 24)));
        assert_eq!(s.local_input(), vec![], "already the desktop's");
    }

    #[test]
    fn a_window_resize_while_the_phone_drives_restores_the_desktop() {
        let log = Log::default();
        let mut s = SizeControl::new(&log, (80, 24));
        s.phone_resize((50, 20));
        assert_eq!(
            s.window_resized((100, 30)),
            vec![
                Notice::Size {
                    cols: 100,
                    rows: 30
                },
                Notice::Local
            ]
        );
        assert_eq!((s.driver(), s.applied()), (Driver::Desktop, (100, 30)));
        assert_eq!(
            s.window_resized((90, 30)),
            vec![Notice::Size { cols: 90, rows: 30 }]
        );
    }

    #[test]
    fn the_phone_leaving_restores_the_window_size() {
        let log = Log::default();
        let mut s = SizeControl::new(&log, (80, 24));
        s.phone_resize((50, 20));
        s.phone_left();
        assert_eq!((s.driver(), s.applied()), (Driver::Desktop, (80, 24)));
    }

    #[test]
    fn changing_driver_at_the_same_size_bounces_to_force_a_redraw() {
        let log = Log::default();
        let mut s = SizeControl::new(&log, (80, 24));
        s.phone_resize((80, 24));
        assert_eq!(*log.0.borrow(), vec![(80, 23), (80, 24)]);
        log.0.borrow_mut().clear();
        s.phone_resize((80, 24)); // same driver, same size: nothing
        assert!(log.0.borrow().is_empty());
        s.local_input();
        assert_eq!(*log.0.borrow(), vec![(80, 23), (80, 24)]);
    }

    #[test]
    fn a_one_row_terminal_bounces_upwards() {
        let log = Log::default();
        let mut s = SizeControl::new(&log, (80, 1));
        s.phone_resize((80, 1));
        assert_eq!(*log.0.borrow(), vec![(80, 2), (80, 1)]);
    }

    #[test]
    fn notices_become_link_messages() {
        assert_eq!(
            Notice::Size { cols: 3, rows: 4 }.to_msg(),
            TermMsg::Size { cols: 3, rows: 4 }
        );
        assert_eq!(Notice::Local.to_msg(), TermMsg::Local);
    }
}
