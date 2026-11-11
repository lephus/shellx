//! The email code sign-in's pure rules (D3, D4): which address may be sent, which digits a typed or pasted
//! code holds, when six digits submit by themselves, which screen the "Sign in to ShellX" dialog draws, its Tab
//! order and what its key listener does with a key. The account flow (`account`) runs the steps; the window draws
//! them.

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
        for refused in ["phu@ẽample.com", "ẽ", "phu@\u{FF45}xample.com", long.as_str()] {
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
        assert_eq!(auto_submit(None, "123 456", true).as_deref(), Some("123456"));
        assert_eq!(auto_submit(Some("123456"), "123456", true), None);
        assert_eq!(
            auto_submit(Some("123456"), "654321", true).as_deref(),
            Some("654321")
        );
        assert_eq!(auto_submit(None, "123456", false), None);
        assert_eq!(auto_submit(None, "12345", true), None);
        assert_eq!(auto_submit(None, "１２３４５６", true).as_deref(), Some("123456"));
    }

    #[test]
    fn the_dialog_screen_follows_the_steps() {
        use EmailStep::*;
        let start = |sending, google_waiting| SignInScreen::Start {
            sending,
            google_waiting,
        };
        assert_eq!(sign_in_screen(None, false, false, false, false), start(false, false));
        assert_eq!(sign_in_screen(None, false, true, false, true), start(false, true));
        assert_eq!(sign_in_screen(None, false, false, true, true), SignInScreen::SigningIn);
        assert_eq!(sign_in_screen(None, false, false, false, true), start(false, false));
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

        assert_eq!(tab_target(tab_order(start, true), Verify, false, all), EmailField);
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
                    assert_eq!(dialog_key(h, link, k, false, false), DialogKey::Pass, "{h:?} {link} {k}");
                }
                for k in ["a", "2"] {
                    assert_eq!(dialog_key(h, link, k, true, false), DialogKey::Pass, "{h:?} {link} shift+{k}");
                }
                assert_eq!(dialog_key(h, link, "v", false, true), DialogKey::Pass);
                assert_eq!(dialog_key(h, link, "a", false, true), DialogKey::Pass);
                assert_eq!(dialog_key(h, link, "escape", false, false), DialogKey::Close);
                assert_eq!(dialog_key(h, link, "escape", false, true), DialogKey::Pass);
            }
        }
        assert_eq!(dialog_key(None, true, "enter", false, false), DialogKey::StartGoogle);
        assert_eq!(dialog_key(None, false, "enter", false, false), DialogKey::Pass);
        assert_eq!(dialog_key(Some(SendCode), false, "enter", false, false), DialogKey::Pass);
        assert_eq!(dialog_key(Some(EmailField), false, "enter", false, false), DialogKey::Pass);

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
        assert_eq!(dialog_key(Some(EmailField), false, "tab", false, false), DialogKey::Pass);
        assert_eq!(dialog_key(Some(CodeField), false, "tab", true, false), DialogKey::Pass);
        assert_eq!(dialog_key(Some(SendCode), false, "tab", false, true), DialogKey::Pass);
    }
}
