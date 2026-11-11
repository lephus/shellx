//! The email code sign-in's pure rules (D3, D4): which address may be sent, which digits a typed or pasted
//! code holds, when six digits submit by themselves, which screen the "Sign in to ShellX" dialog draws, its Tab
//! order and what its key listener does with a key. The account flow (`account`) runs the steps; the window draws
//! them.

/// Digits in a sign-in code.
pub const CODE_LEN: usize = 6;

/// The relay's longest address, in bytes (ASCII only); equal to `shellx_core::auth_email::MAX_EMAIL_BYTES`
/// (`shellx-app`'s `the_model_maps_digits_and_lengths_like_the_core` pins it).
pub const EMAIL_MAX_LEN: usize = 254;

/// Copied from `shellx_core::auth_email::DECIMAL_ZEROS` (this crate does not link the core; `shellx-app`'s
/// `the_model_maps_digits_and_lengths_like_the_core` pins the copy):
///
/// The first code point of every run of ten Unicode decimal digits (General_Category Nd, Unicode 13), from
/// `python3 -I -c "import unicodedata as u; print([hex(c) for c in range(0x110000) if u.category(chr(c)) == 'Nd' and u.decimal(chr(c)) == 0])"`.
/// Digits of scripts added after Unicode 13 are not mapped, and are refused like letters.
pub const DECIMAL_ZEROS: &[u32] = &[
    0x0030, 0x0660, 0x06F0, 0x07C0, 0x0966, 0x09E6, 0x0A66, 0x0AE6, 0x0B66, 0x0BE6, 0x0C66, 0x0CE6,
    0x0D66, 0x0DE6, 0x0E50, 0x0ED0, 0x0F20, 0x1040, 0x1090, 0x17E0, 0x1810, 0x1946, 0x19D0, 0x1A80,
    0x1A90, 0x1B50, 0x1BB0, 0x1C40, 0x1C50, 0xA620, 0xA8D0, 0xA900, 0xA9D0, 0xA9F0, 0xAA50, 0xABF0,
    0xFF10, 0x104A0, 0x10D30, 0x11066, 0x110F0, 0x11136, 0x111D0, 0x112F0, 0x11450, 0x114D0,
    0x11650, 0x116C0, 0x11730, 0x118E0, 0x11950, 0x11C50, 0x11D50, 0x11DA0, 0x16A60, 0x16B50,
    0x1D7CE, 0x1D7D8, 0x1D7E2, 0x1D7EC, 0x1D7F6, 0x1E140, 0x1E2F0, 0x1E950, 0x1FBF0,
];

/// Where an email sign-in run stands: the first screen, the code on its way, the code step, the code being
/// checked.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EmailStep {
    Email,
    Sending,
    Code,
    Verifying,
}

/// Whether "Send code" may send `text`. After trimming: ASCII only (D4), at most `EMAIL_MAX_LEN` bytes, no
/// whitespace inside, text before and after one '@', and after it a '.' with text on both sides. The relay
/// checks the rest (and words its answer).
pub fn email_looks_valid(text: &str) -> bool {
    let t = text.trim();
    if t.is_empty() || !t.is_ascii() || t.len() > EMAIL_MAX_LEN || t.contains(char::is_whitespace) {
        return false;
    }
    let Some((local, domain)) = t.split_once('@') else {
        return false;
    };
    !local.is_empty()
        && !domain.contains('@')
        && domain
            .char_indices()
            .any(|(i, c)| c == '.' && i > 0 && i + 1 < domain.len())
}

/// After trimming, `text` has a character outside ASCII (a Vietnamese letter a Telex, VNI or Unikey input
/// method put in: "ẽ") or is longer than `EMAIL_MAX_LEN`: the dialog shows `InvalidEmail` under the field
/// before any request.
pub fn email_text_refused(text: &str) -> bool {
    let t = text.trim();
    !t.is_ascii() || t.len() > EMAIL_MAX_LEN
}

/// The value of a Unicode decimal digit (ASCII, full-width, Arabic-Indic, Devanagari, …).
fn decimal_digit(c: char) -> Option<u32> {
    let n = c as u32;
    DECIMAL_ZEROS
        .iter()
        .find(|&&z| (z..z + 10).contains(&n))
        .map(|&z| n - z)
}

/// Every Unicode decimal digit (category Nd) of `raw` as an ASCII digit, when there are exactly six; every
/// other character is skipped, so a code pasted with spaces, a line break or the mail's sentence around it
/// still gives its six digits, and the mail's whole body (which also says "10 minutes") gives none.
pub fn code_digits(raw: &str) -> Option<String> {
    let mut out = String::with_capacity(CODE_LEN);
    for d in raw.chars().filter_map(decimal_digit) {
        if out.len() == CODE_LEN {
            return None;
        }
        out.push(char::from_digit(d, 10)?);
    }
    (out.len() == CODE_LEN).then_some(out)
}

/// The digits to submit without a click: `code_digits(text)` when a challenge can be verified now and they
/// differ from `last` (the digits this dialog last submitted that way), so one paste submits once.
pub fn auto_submit(last: Option<&str>, text: &str, can_verify: bool) -> Option<String> {
    if !can_verify {
        return None;
    }
    code_digits(text).filter(|d| last != Some(d.as_str()))
}

/// What the "Sign in to ShellX" dialog draws.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SignInScreen {
    /// The email field with "Send code", then Google. `sending`: the first code is on its way.
    /// `google_waiting`: a Google flow waits for the browser ("Waiting for Google…" instead of its button).
    Start { sending: bool, google_waiting: bool },
    /// The code step. `busy`: a code is being checked or another one is on its way.
    Code { busy: bool },
    /// A right code (or Google) signed in and the window registers this PC.
    SigningIn,
}

/// The dialog's screen. `step`: the shown email run's step. `has_sent_to`: a code was already sent in this
/// run. `google_waiting`: a Google flow runs. `code_submitted`: this dialog submitted a code since it
/// opened. `logging_in`: `AccountState::LoggingIn`.
pub fn sign_in_screen(
    step: Option<EmailStep>,
    has_sent_to: bool,
    google_waiting: bool,
    code_submitted: bool,
    logging_in: bool,
) -> SignInScreen {
    match step {
        Some(EmailStep::Email) => SignInScreen::Start {
            sending: false,
            google_waiting,
        },
        Some(EmailStep::Sending) if has_sent_to => SignInScreen::Code { busy: true },
        Some(EmailStep::Sending) => SignInScreen::Start {
            sending: true,
            google_waiting: false,
        },
        Some(EmailStep::Code) => SignInScreen::Code { busy: false },
        Some(EmailStep::Verifying) => SignInScreen::Code { busy: true },
        None if google_waiting => SignInScreen::Start {
            sending: false,
            google_waiting: true,
        },
        None if code_submitted && logging_in => SignInScreen::SigningIn,
        None => SignInScreen::Start {
            sending: false,
            google_waiting: false,
        },
    }
}

/// A control of the dialog that can hold the keyboard.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DialogFocus {
    EmailField,
    SendCode,
    Google,
    CodeField,
    Verify,
    Resend,
    ChangeEmail,
    Cancel,
}

/// D3's Tab order. `Start`: email field, Send code, Continue with Google, Cancel; without Google when `google`
/// is false (the build has no Google client: Ruling 28). `Code`: code field, Verify, Resend, Use a different
/// email, Cancel. `SigningIn`: Cancel.
pub fn tab_order(screen: SignInScreen, google: bool) -> &'static [DialogFocus] {
    use DialogFocus::*;
    match screen {
        SignInScreen::Start { .. } if google => &[EmailField, SendCode, Google, Cancel],
        SignInScreen::Start { .. } => &[EmailField, SendCode, Cancel],
        SignInScreen::Code { .. } => &[CodeField, Verify, Resend, ChangeEmail, Cancel],
        SignInScreen::SigningIn => &[Cancel],
    }
}

/// Where Tab (Shift+Tab with `back`) moves from `from`: the next (previous) entry of `order` that `enabled`
/// accepts, wrapping around; `from` when no other entry is accepted; the first accepted entry when `from` is
/// not in `order` (`from` when none is).
pub fn tab_target(
    order: &[DialogFocus],
    from: DialogFocus,
    back: bool,
    enabled: impl Fn(DialogFocus) -> bool,
) -> DialogFocus {
    let Some(i) = order.iter().position(|&f| f == from) else {
        return order.iter().copied().find(|&f| enabled(f)).unwrap_or(from);
    };
    let n = order.len();
    (1..n)
        .map(|step| {
            if back {
                (i + n - step) % n
            } else {
                (i + step) % n
            }
        })
        .map(|j| order[j])
        .find(|&f| enabled(f))
        .unwrap_or(from)
}

/// What the dialog card's own key-down listener does with a key that reached it (Ruling 30).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DialogKey {
    /// Not the dialog's: the listener leaves it unstopped, so the platform turns it into typed text.
    Pass,
    Close,
    /// Tab / Shift+Tab from a button or the dialog's own handle.
    Move {
        back: bool,
    },
    /// Enter on the Link dialog ("Switch to Google sign-in").
    StartGoogle,
}

/// `holder`: the field or button that holds the keyboard, `None` for the dialog's own handle. `link`: the
/// dialog switches a password session to Google. `key`: GPUI's key name. `shift`: Shift held. `other`: Ctrl,
/// Alt or Win held. The listener stops propagation only for a result other than `Pass`: on GPUI-Windows a
/// key-down that a handler stops is never translated, so no character follows (R2 §1).
pub fn dialog_key(
    holder: Option<DialogFocus>,
    link: bool,
    key: &str,
    shift: bool,
    other: bool,
) -> DialogKey {
    if other {
        // A field handles Ctrl+A/C/V/X itself; the window root swallows the other chords.
        return DialogKey::Pass;
    }
    let field = matches!(
        holder,
        Some(DialogFocus::EmailField | DialogFocus::CodeField)
    );
    match key {
        "escape" => DialogKey::Close,
        // A field already turned Tab into its own Next / Prev and stopped it.
        "tab" if field => DialogKey::Pass,
        "tab" => DialogKey::Move { back: shift },
        // A field turned Enter into Submit first; GPUI clicks a focused button on key-up.
        "enter" if holder.is_none() && link => DialogKey::StartGoogle,
        _ => DialogKey::Pass,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use DialogFocus::*;

    fn long_address() -> String {
        let s = format!("{}@b.co", "a".repeat(250));
        assert_eq!(s.len(), 255);
        s
    }

    #[test]
    fn plausible_addresses() {
        for ok in ["a@b.c", " a@b.co ", "phu@example.com\u{00A0}"] {
            assert!(email_looks_valid(ok), "{ok:?}");
        }
        let long = long_address();
        for bad in [
            "",
            "a@b",
            "a@.c",
            "a@b.",
            "@b.c",
            "a b@c.d",
            "phu@ẽample.com",
            "phú@example.com",
            "phu@example.cóm",
            "phu@\u{FF45}xample.com",
            long.as_str(),
        ] {
            assert!(!email_looks_valid(bad), "{bad:?}");
        }
    }

    #[test]
    fn refused_text_shows_the_invalid_email_sentence() {
        let long = long_address();
        for refused in [
            "phu@ẽample.com",
            "ẽ",
            "phu@\u{FF45}xample.com",
            long.as_str(),
        ] {
            assert!(email_text_refused(refused), "{refused:?}");
        }
        for fine in ["", "phu@exam", "a@b.co", "phu@example.com\u{00A0}"] {
            assert!(!email_text_refused(fine), "{fine:?}");
        }
    }

    #[test]
    fn code_digits_takes_the_six_digits_of_what_was_typed() {
        for s in [
            " 123 456\n",
            "１２３４５６",
            "١٢٣٤٥٦",
            "Your ShellX sign-in code is 123456",
        ] {
            assert_eq!(code_digits(s).as_deref(), Some("123456"), "{s:?}");
        }
        for s in ["004217", "Mã đăng nhập ShellX của bạn là 004217"] {
            assert_eq!(code_digits(s).as_deref(), Some("004217"), "{s:?}");
        }
        for s in [
            "12345",
            "1234567",
            "12a45",
            "",
            "12345²",
            "Your code is 004217. It works for 10 minutes.",
        ] {
            assert_eq!(code_digits(s), None, "{s:?}");
        }
    }

    #[test]
    fn auto_submit_fires_once_per_new_six_digits() {
        assert_eq!(
            auto_submit(None, "123 456", true).as_deref(),
            Some("123456")
        );
        assert_eq!(auto_submit(Some("123456"), "123456", true), None);
        assert_eq!(
            auto_submit(Some("123456"), "654321", true).as_deref(),
            Some("654321")
        );
        assert_eq!(auto_submit(None, "123456", false), None);
        assert_eq!(auto_submit(None, "12345", true), None);
        assert_eq!(
            auto_submit(None, "１２３４５６", true).as_deref(),
            Some("123456")
        );
    }

    #[test]
    fn the_dialog_screen_follows_the_steps() {
        use EmailStep::*;
        let start = |sending, google_waiting| SignInScreen::Start {
            sending,
            google_waiting,
        };
        assert_eq!(
            sign_in_screen(None, false, false, false, false),
            start(false, false)
        );
        assert_eq!(
            sign_in_screen(None, false, true, false, true),
            start(false, true)
        );
        assert_eq!(
            sign_in_screen(None, false, false, true, true),
            SignInScreen::SigningIn
        );
        assert_eq!(
            sign_in_screen(None, false, false, false, true),
            start(false, false)
        );
        assert_eq!(
            sign_in_screen(Some(Email), false, false, false, false),
            start(false, false)
        );
        assert_eq!(
            sign_in_screen(Some(Sending), false, false, false, false),
            start(true, false)
        );
        assert_eq!(
            sign_in_screen(Some(Sending), true, false, false, false),
            SignInScreen::Code { busy: true }
        );
        assert_eq!(
            sign_in_screen(Some(Code), true, false, false, false),
            SignInScreen::Code { busy: false }
        );
        assert_eq!(
            sign_in_screen(Some(Verifying), true, false, false, false),
            SignInScreen::Code { busy: true }
        );
    }

    #[test]
    fn tab_follows_the_dialog_order() {
        let start = SignInScreen::Start {
            sending: false,
            google_waiting: false,
        };
        let all = |_: DialogFocus| true;
        let order = tab_order(start, true);
        assert_eq!(order, [EmailField, SendCode, Google, Cancel]);
        assert_eq!(tab_target(order, EmailField, false, all), SendCode);
        assert_eq!(tab_target(order, SendCode, false, all), Google);
        assert_eq!(tab_target(order, Google, false, all), Cancel);
        assert_eq!(tab_target(order, Cancel, false, all), EmailField);
        assert_eq!(tab_target(order, EmailField, true, all), Cancel);
        let no_send = |f: DialogFocus| f != SendCode;
        assert_eq!(tab_target(order, EmailField, false, no_send), Google);
        assert_eq!(tab_target(order, Google, true, no_send), EmailField);
        // Without a Google client (Ruling 28) Tab skips Google.
        let order = tab_order(start, false);
        assert_eq!(order, [EmailField, SendCode, Cancel]);
        assert_eq!(tab_target(order, SendCode, false, all), Cancel);

        let code = SignInScreen::Code { busy: false };
        assert_eq!(tab_order(code, false), tab_order(code, true));
        let order = tab_order(code, true);
        assert_eq!(order, [CodeField, Verify, Resend, ChangeEmail, Cancel]);
        let locked = |f: DialogFocus| f != Verify && f != Resend;
        assert_eq!(tab_target(order, CodeField, false, locked), ChangeEmail);

        let order = tab_order(SignInScreen::SigningIn, true);
        assert_eq!(order, [Cancel]);
        assert_eq!(tab_target(order, Cancel, false, all), Cancel);

        assert_eq!(
            tab_target(tab_order(start, true), Verify, false, all),
            EmailField
        );
    }

    /// The 2026-10-31 "cannot type" defect: a key-down that the dialog stops never becomes WM_CHAR on Windows (R2 §1).
    #[test]
    fn keys_the_dialog_does_not_act_on_pass_through() {
        let holders = [
            None,
            Some(EmailField),
            Some(SendCode),
            Some(Google),
            Some(CodeField),
            Some(Verify),
            Some(Resend),
            Some(ChangeEmail),
            Some(Cancel),
        ];
        for link in [false, true] {
            for h in holders {
                for k in [
                    "a",
                    "z",
                    "0",
                    "9",
                    "space",
                    "backspace",
                    "delete",
                    "left",
                    "home",
                    "end",
                ] {
                    assert_eq!(
                        dialog_key(h, link, k, false, false),
                        DialogKey::Pass,
                        "{h:?} {link} {k}"
                    );
                }
                for k in ["a", "2"] {
                    assert_eq!(
                        dialog_key(h, link, k, true, false),
                        DialogKey::Pass,
                        "{h:?} {link} shift+{k}"
                    );
                }
                assert_eq!(dialog_key(h, link, "v", false, true), DialogKey::Pass);
                assert_eq!(dialog_key(h, link, "a", false, true), DialogKey::Pass);
                assert_eq!(
                    dialog_key(h, link, "escape", false, false),
                    DialogKey::Close
                );
                assert_eq!(dialog_key(h, link, "escape", false, true), DialogKey::Pass);
            }
        }
        assert_eq!(
            dialog_key(None, true, "enter", false, false),
            DialogKey::StartGoogle
        );
        assert_eq!(
            dialog_key(None, false, "enter", false, false),
            DialogKey::Pass
        );
        assert_eq!(
            dialog_key(Some(SendCode), false, "enter", false, false),
            DialogKey::Pass
        );
        assert_eq!(
            dialog_key(Some(EmailField), false, "enter", false, false),
            DialogKey::Pass
        );

        assert_eq!(
            dialog_key(Some(SendCode), false, "tab", false, false),
            DialogKey::Move { back: false }
        );
        assert_eq!(
            dialog_key(Some(Cancel), false, "tab", true, false),
            DialogKey::Move { back: true }
        );
        assert_eq!(
            dialog_key(None, false, "tab", false, false),
            DialogKey::Move { back: false }
        );
        assert_eq!(
            dialog_key(Some(EmailField), false, "tab", false, false),
            DialogKey::Pass
        );
        assert_eq!(
            dialog_key(Some(CodeField), false, "tab", true, false),
            DialogKey::Pass
        );
        assert_eq!(
            dialog_key(Some(SendCode), false, "tab", false, true),
            DialogKey::Pass
        );
    }
}
