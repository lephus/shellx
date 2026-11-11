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
    use crate::core_api::{CoreErr, GoogleBegin, GooglePurpose, GoogleSignIn};
    use crate::sidebar::MachineInfo;

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

    #[test]
    fn account_view_offers_sign_in_again_after_a_server_sign_out() {
        assert_eq!(
            account_view(&AccountFlow::new()),
            AccountView {
                sign_in: Some(Str::SignInEllipsis),
                session_expired: false,
            }
        );
        let mut f = logged_in();
        assert_eq!(
            account_view(&f),
            AccountView {
                sign_in: None,
                session_expired: false,
            }
        );
        f.on(AccountEvent::Tick(16_000), 16_000);
        f.on(
            AccountEvent::ListResult(Err(CoreErr::new("unauthorized", ""))),
            16_000,
        );
        assert_eq!(
            account_view(&f),
            AccountView {
                sign_in: Some(Str::SignInAgain),
                session_expired: true,
            }
        );
        sign_in_with_google(&mut f, 17_000);
        assert_eq!(
            account_view(&f),
            AccountView {
                sign_in: None,
                session_expired: false,
            }
        );
    }
}
