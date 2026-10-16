//! The Windows console side of `shellx-term` (spec §5.3): raw VT mode,
//! window size, keystrokes and resize events, UTF-16 output, close events.
//! Windows only; the text conversions live in `wincodec` (tested everywhere).

use crate::wincodec::{KeyInput, Utf8Stream};
use std::io;
use std::sync::Mutex;
use winapi::shared::minwindef::{BOOL, DWORD, FALSE, TRUE};
use winapi::um::consoleapi::{
    GetConsoleMode, ReadConsoleInputW, SetConsoleCtrlHandler, SetConsoleMode, WriteConsoleW,
};
use winapi::um::processenv::GetStdHandle;
use winapi::um::winbase::{STD_INPUT_HANDLE, STD_OUTPUT_HANDLE};
use winapi::um::wincon::{
    GetConsoleScreenBufferInfo, CONSOLE_SCREEN_BUFFER_INFO, CTRL_BREAK_EVENT, CTRL_C_EVENT,
    DISABLE_NEWLINE_AUTO_RETURN, ENABLE_ECHO_INPUT, ENABLE_LINE_INPUT, ENABLE_MOUSE_INPUT,
    ENABLE_PROCESSED_INPUT, ENABLE_PROCESSED_OUTPUT, ENABLE_VIRTUAL_TERMINAL_INPUT,
    ENABLE_VIRTUAL_TERMINAL_PROCESSING, ENABLE_WINDOW_INPUT,
};
use winapi::um::wincontypes::{INPUT_RECORD, KEY_EVENT, WINDOW_BUFFER_SIZE_EVENT};
use winapi::um::winnt::HANDLE;

/// The Alt key's virtual-key code.
const VK_MENU: u16 = 0x12;

fn stdin() -> HANDLE {
    unsafe { GetStdHandle(STD_INPUT_HANDLE) }
}

fn stdout() -> HANDLE {
    unsafe { GetStdHandle(STD_OUTPUT_HANDLE) }
}

fn mode(h: HANDLE) -> Option<DWORD> {
    let mut m: DWORD = 0;
    (unsafe { GetConsoleMode(h, &mut m) } != 0).then_some(m)
}

/// Both stdin and stdout are a console (not a pipe or a file).
pub fn is_console() -> bool {
    mode(stdin()).is_some() && mode(stdout()).is_some()
}

/// `(cols, rows)` of the visible window.
pub fn window_size() -> Option<(u16, u16)> {
    let mut info: CONSOLE_SCREEN_BUFFER_INFO = unsafe { std::mem::zeroed() };
    if unsafe { GetConsoleScreenBufferInfo(stdout(), &mut info) } == 0 {
        return None;
    }
    let w = info.srWindow;
    let cols = i32::from(w.Right) - i32::from(w.Left) + 1;
    let rows = i32::from(w.Bottom) - i32::from(w.Top) + 1;
    let clamp = |n: i32| n.clamp(1, i32::from(u16::MAX)) as u16;
    (cols > 0 && rows > 0).then(|| (clamp(cols), clamp(rows)))
}

/// Modes to put back if we die without `Drop` (panic, close event).
static SAVED: Mutex<Option<(DWORD, DWORD)>> = Mutex::new(None);

/// Raw VT mode until dropped: every keystroke (Ctrl+C included) arrives as
/// bytes, resizes are reported, and output understands VT sequences.
pub struct RawConsole {
    input: DWORD,
    output: DWORD,
}

impl RawConsole {
    pub fn enable() -> io::Result<RawConsole> {
        let input = mode(stdin()).ok_or_else(io::Error::last_os_error)?;
        let output = mode(stdout()).ok_or_else(io::Error::last_os_error)?;
        let off =
            ENABLE_PROCESSED_INPUT | ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_MOUSE_INPUT;
        let raw_in = (input & !off) | ENABLE_VIRTUAL_TERMINAL_INPUT | ENABLE_WINDOW_INPUT;
        let raw_out = output
            | ENABLE_PROCESSED_OUTPUT
            | ENABLE_VIRTUAL_TERMINAL_PROCESSING
            | DISABLE_NEWLINE_AUTO_RETURN;
        if unsafe { SetConsoleMode(stdin(), raw_in) } == 0 {
            return Err(io::Error::last_os_error());
        }
        if unsafe { SetConsoleMode(stdout(), raw_out) } == 0 {
            let err = io::Error::last_os_error();
            unsafe { SetConsoleMode(stdin(), input) };
            return Err(err);
        }
        *SAVED.lock().unwrap_or_else(|e| e.into_inner()) = Some((input, output));
        Ok(RawConsole { input, output })
    }
}

impl Drop for RawConsole {
    fn drop(&mut self) {
        unsafe {
            SetConsoleMode(stdin(), self.input);
            SetConsoleMode(stdout(), self.output);
        }
        *SAVED.lock().unwrap_or_else(|e| e.into_inner()) = None;
    }
}

/// Puts back the modes `RawConsole::enable` saved; never blocks.
pub fn restore_saved() {
    if let Ok(mut saved) = SAVED.try_lock() {
        if let Some((input, output)) = saved.take() {
            unsafe {
                SetConsoleMode(stdin(), input);
                SetConsoleMode(stdout(), output);
            }
        }
    }
}

/// The window's output: UTF-8 from the PTY, written as UTF-16.
#[derive(Default)]
pub struct ConsoleOut {
    stream: Utf8Stream,
    units: Vec<u16>,
}

impl io::Write for ConsoleOut {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        self.units.clear();
        self.stream.push(buf, &mut self.units);
        let mut rest: &[u16] = &self.units;
        while !rest.is_empty() {
            let mut written: DWORD = 0;
            let ok = unsafe {
                WriteConsoleW(
                    stdout(),
                    rest.as_ptr().cast(),
                    rest.len() as DWORD,
                    &mut written,
                    std::ptr::null_mut(),
                )
            };
            if ok == 0 || written == 0 {
                return Err(io::Error::last_os_error());
            }
            rest = &rest[written as usize..];
        }
        Ok(buf.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

pub enum WindowEvent {
    /// Keystrokes as UTF-8 (VT sequences for special keys).
    Bytes(Vec<u8>),
    /// The window changed size; read `window_size()`.
    Resized,
    /// The console is gone.
    Gone,
}

/// Reads the window until `on_event` returns false or the console goes
/// away (then reports `Gone` once).
pub fn read_window(mut on_event: impl FnMut(WindowEvent) -> bool) {
    let mut records: [INPUT_RECORD; 64] = unsafe { std::mem::zeroed() };
    let mut keys = KeyInput::default();
    loop {
        let mut n: DWORD = 0;
        let ok = unsafe {
            ReadConsoleInputW(
                stdin(),
                records.as_mut_ptr(),
                records.len() as DWORD,
                &mut n,
            )
        };
        if ok == 0 {
            on_event(WindowEvent::Gone);
            return;
        }
        let mut bytes = Vec::new();
        let mut resized = false;
        for record in &records[..n as usize] {
            match record.EventType {
                KEY_EVENT => {
                    let key = unsafe { record.Event.KeyEvent() };
                    let unit = unsafe { *key.uChar.UnicodeChar() };
                    // Alt+numpad characters arrive on the Alt key-up, carrying the character.
                    let down = key.bKeyDown != 0 || (key.wVirtualKeyCode == VK_MENU && unit != 0);
                    keys.push(down, key.wRepeatCount, unit, &mut bytes);
                }
                WINDOW_BUFFER_SIZE_EVENT => resized = true,
                _ => {}
            }
        }
        if !bytes.is_empty() && !on_event(WindowEvent::Bytes(bytes)) {
            return;
        }
        if resized && !on_event(WindowEvent::Resized) {
            return;
        }
    }
}

unsafe extern "system" fn on_ctrl(kind: DWORD) -> BOOL {
    match kind {
        // Processed input is off, so these should not arrive; never let
        // them end us.
        CTRL_C_EVENT | CTRL_BREAK_EVENT => TRUE,
        // Close, logoff, shutdown: put the console back, then let the default
        // handler end the process; the ConPTY closes and its shell ends.
        _ => {
            restore_saved();
            FALSE
        }
    }
}

pub fn install_close_handler() {
    unsafe { SetConsoleCtrlHandler(Some(on_ctrl), TRUE) };
}
