//! ShellX palette (spec §7.4). Soft colors only: no gradients, glows or colored shadows.

use crate::strings::Str;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Rgba {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: f32,
}

impl Rgba {
    pub const fn rgb(hex: u32) -> Rgba {
        Rgba {
            r: (hex >> 16) as u8,
            g: (hex >> 8) as u8,
            b: hex as u8,
            a: 1.0,
        }
    }

    pub const fn with_alpha(self, a: f32) -> Rgba {
        Rgba { a, ..self }
    }

    /// "#rrggbb" (alpha not included).
    pub fn hex(&self) -> String {
        format!("#{:02x}{:02x}{:02x}", self.r, self.g, self.b)
    }
}

pub const BG: Rgba = Rgba::rgb(0x0b0716);
pub const PANEL: Rgba = Rgba::rgb(0x100b1d);
pub const RAISE: Rgba = Rgba::rgb(0x171128);
pub const LINE: Rgba = Rgba::rgb(0x211a37);
pub const BORDER: Rgba = Rgba::rgb(0x2a2145);
pub const TEXT: Rgba = Rgba::rgb(0xcdc7e0);
pub const TEXT_HI: Rgba = Rgba::rgb(0xe6e2f2);
pub const MUTED: Rgba = Rgba::rgb(0x8a83a6);
pub const PRIMARY: Rgba = Rgba::rgb(0x60a5fa);
pub const PRIMARY_SOFT: Rgba = PRIMARY.with_alpha(0.12);
pub const PRIMARY_LINE: Rgba = PRIMARY.with_alpha(0.45);
pub const PRIMARY_TEXT: Rgba = Rgba::rgb(0x93c5fd);
pub const RUNNING: Rgba = Rgba::rgb(0xe8c468);
pub const DONE: Rgba = Rgba::rgb(0x6fd49a);
pub const ERROR: Rgba = Rgba::rgb(0xe88a8a);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Status {
    Waiting,
    Running,
    Done,
    Error,
    Idle,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Pill {
    pub fg: Rgba,
    /// `fg` at alpha 0.12.
    pub bg: Rgba,
    pub label: Str,
}

impl Status {
    pub fn pill(self) -> Option<Pill> {
        let (fg, label) = match self {
            Status::Waiting => (PRIMARY, Str::StatusWaiting),
            Status::Running => (RUNNING, Str::StatusRunning),
            Status::Done => (DONE, Str::StatusDone),
            Status::Error => (ERROR, Str::StatusError),
            Status::Idle => return None,
        };
        Some(Pill {
            fg,
            bg: fg.with_alpha(0.12),
            label,
        })
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ButtonStyle {
    pub bg: Rgba,
    pub border: Rgba,
    pub text: Rgba,
}

pub const PRIMARY_BUTTON: ButtonStyle = ButtonStyle {
    bg: PRIMARY_SOFT,
    border: PRIMARY_LINE,
    text: PRIMARY_TEXT,
};
pub const SECONDARY_BUTTON: ButtonStyle = ButtonStyle {
    bg: RAISE,
    border: BORDER,
    text: TEXT,
};

pub const TERM_BG: Rgba = BG;
pub const TERM_FG: Rgba = TEXT;
pub const TERM_CURSOR: Rgba = PRIMARY;
pub const TERM_SELECTION: Rgba = PRIMARY.with_alpha(0.30);

/// Terminal ANSI 16, soft and tuned to the background.
pub const ANSI: [Rgba; 16] = [
    Rgba::rgb(0x1b1530),
    Rgba::rgb(0xe88a8a),
    Rgba::rgb(0x6fd49a),
    Rgba::rgb(0xe8c468),
    Rgba::rgb(0x60a5fa),
    Rgba::rgb(0xc4a1f5),
    Rgba::rgb(0x7fd3e6),
    Rgba::rgb(0xcdc7e0),
    Rgba::rgb(0x4a4166),
    Rgba::rgb(0xf2a7a7),
    Rgba::rgb(0x93e3b5),
    Rgba::rgb(0xf2d78f),
    Rgba::rgb(0x93c5fd),
    Rgba::rgb(0xd8c0fa),
    Rgba::rgb(0xa6e4f0),
    Rgba::rgb(0xe6e2f2),
];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn token_hex_exact() {
        let cases = [
            (BG, "#0b0716"),
            (PANEL, "#100b1d"),
            (RAISE, "#171128"),
            (LINE, "#211a37"),
            (BORDER, "#2a2145"),
            (TEXT, "#cdc7e0"),
            (TEXT_HI, "#e6e2f2"),
            (MUTED, "#8a83a6"),
            (PRIMARY, "#60a5fa"),
            (PRIMARY_TEXT, "#93c5fd"),
            (RUNNING, "#e8c468"),
            (DONE, "#6fd49a"),
            (ERROR, "#e88a8a"),
        ];
        for (c, h) in cases {
            assert_eq!(c.hex(), h);
            assert_eq!(c.a, 1.0);
        }
    }

    #[test]
    fn soft_and_line_alphas() {
        assert_eq!(PRIMARY_SOFT.hex(), "#60a5fa");
        assert_eq!(PRIMARY_SOFT.a, 0.12);
        assert_eq!(PRIMARY_LINE.hex(), "#60a5fa");
        assert_eq!(PRIMARY_LINE.a, 0.45);
        assert_eq!(PRIMARY.with_alpha(0.5).a, 0.5);
    }

    #[test]
    fn pill_colors_and_labels() {
        let w = Status::Waiting.pill().unwrap();
        assert_eq!((w.fg, w.label), (PRIMARY, Str::StatusWaiting));
        assert_eq!(w.bg, PRIMARY.with_alpha(0.12));
        let r = Status::Running.pill().unwrap();
        assert_eq!((r.fg, r.label), (RUNNING, Str::StatusRunning));
        assert_eq!(r.bg, RUNNING.with_alpha(0.12));
        let d = Status::Done.pill().unwrap();
        assert_eq!((d.fg, d.label), (DONE, Str::StatusDone));
        assert_eq!(d.bg, DONE.with_alpha(0.12));
        let e = Status::Error.pill().unwrap();
        assert_eq!((e.fg, e.label), (ERROR, Str::StatusError));
        assert_eq!(e.bg, ERROR.with_alpha(0.12));
    }

    #[test]
    fn idle_has_no_pill() {
        assert!(Status::Idle.pill().is_none());
    }

    #[test]
    fn buttons_and_terminal_defaults() {
        assert_eq!(PRIMARY_BUTTON.bg, PRIMARY_SOFT);
        assert_eq!(PRIMARY_BUTTON.border, PRIMARY_LINE);
        assert_eq!(PRIMARY_BUTTON.text, PRIMARY_TEXT);
        assert_eq!(SECONDARY_BUTTON.bg, RAISE);
        assert_eq!(SECONDARY_BUTTON.border, BORDER);
        assert_eq!(SECONDARY_BUTTON.text, TEXT);
        assert_eq!((TERM_BG, TERM_FG, TERM_CURSOR), (BG, TEXT, PRIMARY));
        assert_eq!(TERM_SELECTION, PRIMARY.with_alpha(0.30));
    }

    #[test]
    fn ansi_palette() {
        assert_eq!(ANSI.len(), 16);
        assert_eq!(ANSI[4], PRIMARY);
        let hexes: Vec<String> = ANSI.iter().map(Rgba::hex).collect();
        assert_eq!(
            hexes,
            [
                "#1b1530", "#e88a8a", "#6fd49a", "#e8c468", "#60a5fa", "#c4a1f5", "#7fd3e6",
                "#cdc7e0", "#4a4166", "#f2a7a7", "#93e3b5", "#f2d78f", "#93c5fd", "#d8c0fa",
                "#a6e4f0", "#e6e2f2"
            ]
        );
    }
}
