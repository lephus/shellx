//! What Settings › Account draws (Ruling 33), as a pure function of the account flow, so the window
//! only draws it.

use crate::account::{AccountFlow, AccountState};
use crate::strings::Str;

/// What Settings › Account draws.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AccountView {
    /// The sign-in button's label: `SignInAgain` after a server sign-out, else `SignInEllipsis`; `None`
    /// while LoggedIn.
    pub sign_in: Option<Str>,
    /// "Your session expired." above the button.
    pub session_expired: bool,
}

pub fn account_view(flow: &AccountFlow) -> AccountView {
    let signed_in = matches!(flow.state(), AccountState::LoggedIn { .. });
    let expired = flow.session_ended_by_server() && !signed_in;
    AccountView {
        sign_in: (!signed_in).then_some(if expired {
            Str::SignInAgain
        } else {
            Str::SignInEllipsis
        }),
        session_expired: expired,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::account::AccountEvent;
    use crate::core_api::{
        CoreErr, GoogleBegin, GooglePurpose, GoogleSignIn, LoginInfo, SessionInfo,
    };
    use crate::sidebar::MachineInfo;
    use crate::strings::{failure_sentence, t};

    fn me() -> MachineInfo {
        MachineInfo {
            machine_id: "me".into(),
            name: "me".into(),
            platform: "windows".into(),
            online: true,
            last_seen_unix: 0,
            fingerprint: String::new(),
            is_this_machine: true,
            can_host: false,
        }
    }

    fn logged_in() -> AccountFlow {
        let mut f = AccountFlow::new();
        f.on(AccountEvent::Started, 0);
        f.on(AccountEvent::ListResult(Ok(vec![me()])), 1);
        f
    }

    /// The Google walk-through from signed out to LoggedIn.
    fn sign_in_with_google(f: &mut AccountFlow, now: u64) {
        f.on(AccountEvent::GoogleRequested(GooglePurpose::SignIn), now);
        f.on(
            AccountEvent::GoogleBegun {
                purpose: GooglePurpose::SignIn,
                result: Ok(GoogleBegin {
                    flow_id: "g1".into(),
                    auth_url: "https://accounts.google.com/x".into(),
                }),
            },
            now,
        );
        f.on(
            AccountEvent::GoogleFinished {
                flow_id: "g1".into(),
                result: Ok(GoogleSignIn {
                    user_id: "u".into(),
                    device_id: "d".into(),
                    device_public_key_b64: "k".into(),
                    fingerprint: "f".into(),
                    email: "g@x".into(),
                    auth_method: "google".into(),
                }),
            },
            now,
        );
        f.on(AccountEvent::ListResult(Ok(vec![me()])), now);
    }

    fn view(f: &AccountFlow) -> AccountView {
        account_view(f, false, Lang::En)
    }

    #[test]
    fn account_view_offers_sign_in_again_after_a_server_sign_out() {
        let v = view(&AccountFlow::new());
        assert_eq!(
            (v.sign_in, v.session_expired),
            (Some(Str::SignInEllipsis), false)
        );
        let mut f = logged_in();
        let v = view(&f);
        assert_eq!((v.sign_in, v.session_expired), (None, false));
        f.on(AccountEvent::Tick(16_000), 16_000);
        f.on(
            AccountEvent::ListResult(Err(CoreErr::new("unauthorized", ""))),
            16_000,
        );
        let v = view(&f);
        assert_eq!(
            (v.sign_in, v.session_expired),
            (Some(Str::SignInAgain), true)
        );
        sign_in_with_google(&mut f, 17_000);
        let v = view(&f);
        assert_eq!((v.sign_in, v.session_expired), (None, false));
    }

    /// R4 Major 6: "Sign out" whenever a session is stored, the error state included.
    #[test]
    fn account_view_offers_sign_out_whenever_a_session_is_stored() {
        assert!(view(&logged_in()).sign_out);
        assert!(!view(&AccountFlow::new()).sign_out, "unknown");
        let mut out = AccountFlow::new();
        out.on(AccountEvent::Started, 0);
        out.on(
            AccountEvent::ListResult(Err(CoreErr::new("not_logged_in", ""))),
            1,
        );
        assert!(!view(&out).sign_out, "signed out");
        // R4 Blocker 1's path: the login worked, the list did not.
        let mut f = out;
        f.on(
            AccountEvent::LoginSubmitted {
                email: "a@b.c".into(),
                password: "pw".into(),
            },
            2,
        );
        f.on(
            AccountEvent::LoginResult(Ok(LoginInfo {
                user_id: "u".into(),
                device_id: "d".into(),
                device_public_key_b64: "k".into(),
                fingerprint: "f".into(),
            })),
            3,
        );
        f.on(
            AccountEvent::ListResult(Err(CoreErr::new(
                "bad_response",
                "machines.list: invalid type: null, expected a string",
            ))),
            4,
        );
        let v = view(&f);
        assert!(v.sign_out);
        assert_eq!(v.sign_in, Some(Str::SignInEllipsis));
    }

    #[test]
    fn account_view_words_errors_as_sentences() {
        for lang in [Lang::En, Lang::Vi] {
            // An error state, with the core's message.
            let mut f = AccountFlow::new();
            f.on(AccountEvent::Started, 0);
            f.on(
                AccountEvent::ListResult(Err(CoreErr::new(
                    "bad_response",
                    "machines.list: invalid type: null, expected a string",
                ))),
                1,
            );
            let error = account_view(&f, false, lang).error.expect("an error line");
            assert_eq!(error, failure_sentence(lang, "bad_response"));
            assert!(
                !error.contains("bad_response") && !error.contains("machines.list"),
                "{error}"
            );
            // A failed sign-out (the session stays).
            let mut g = logged_in();
            g.on(AccountEvent::LogoutRequested, 2);
            g.on(
                AccountEvent::LogoutResult(Err(CoreErr::new("network", "dns error: relay.x"))),
                3,
            );
            let error = account_view(&g, false, lang).error.expect("a notice");
            assert_eq!(error, t(lang, Str::RelayUnreachable));
            // A failed sign-in methods list.
            let mut h = logged_in();
            h.on(
                AccountEvent::SignInMethodsResult(Err(CoreErr::new("http_502", "Bad Gateway"))),
                2,
            );
            let error = account_view(&h, false, lang).error.expect("a notice");
            assert_eq!(error, t(lang, Str::ServerProblem));
            assert!(
                !error.contains("502") && !error.contains("Gateway"),
                "{error}"
            );
            assert_eq!(account_view(&logged_in(), false, lang).error, None);
        }
    }

    /// Ruling 28: the switch row only in a build that can sign in with Google.
    #[test]
    fn account_view_offers_the_google_switch_only_with_google() {
        let session = |method: &str| {
            let mut f = logged_in();
            f.on(
                AccountEvent::SessionResult(Ok(SessionInfo {
                    user_id: "u".into(),
                    device_id: "d".into(),
                    email: Some("a@b.c".into()),
                    auth_method: method.into(),
                })),
                2,
            );
            f
        };
        for google in [false, true] {
            let v = account_view(&session("password"), google, Lang::En);
            assert_eq!(v.google_switch, google);
            for method in ["google", "email"] {
                assert!(!account_view(&session(method), google, Lang::En).google_switch);
            }
        }
    }
}
