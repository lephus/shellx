//! `shellx_model::core_api::CoreCall` over the real `shellx_core::Core` (K3).
//! `Core` serializes its own state files; calls block, so run them off the UI
//! thread. The account token never leaves shellx-core.

use serde_json::Value;
use shellx_model::core_api::{CoreCall, CoreErr};

pub struct CoreBridge(shellx_core::Core);

impl CoreBridge {
    pub fn new() -> CoreBridge {
        CoreBridge(shellx_core::Core::new())
    }
}

impl Default for CoreBridge {
    fn default() -> Self {
        CoreBridge::new()
    }
}

impl CoreCall for CoreBridge {
    fn call(&self, method: &str, params: Value) -> Result<Value, CoreErr> {
        self.0.call(method, params).map_err(|e| CoreErr {
            code: e.code,
            message: e.message,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use shellx_fake_api::{FakeApi, FakeOptions};
    use shellx_model::core_api::{
        CoreConfig, config_set, heartbeat, list_machines, login, logout, register_machine,
    };

    fn configured(api_base: &str, dir: &std::path::Path) -> CoreBridge {
        let bridge = CoreBridge::new();
        config_set(
            &bridge,
            &CoreConfig {
                api_base: api_base.into(),
                state_dir: dir.to_str().unwrap().into(),
                app_version: "2.0.0".into(),
                os_version: "10.0.26100".into(),
                device_name: "TEST-PC".into(),
            },
        )
        .unwrap();
        bridge
    }

    #[test]
    fn errors_map_code_and_message() {
        let bridge = CoreBridge::new();
        let e = bridge.call("nope.nope", json!({})).unwrap_err();
        assert_eq!(e.code, "unknown_method");
        let e = bridge.call("machines.list", json!({})).unwrap_err();
        assert_eq!(e.code, "not_configured");
    }

    #[test]
    fn logged_out_list_is_not_logged_in() {
        let api = FakeApi::start(FakeOptions::default());
        let tmp = tempfile::tempdir().unwrap();
        let bridge = configured(&api.base_url, &tmp.path().join("core"));
        assert_eq!(list_machines(&bridge).unwrap_err().code, "not_logged_in");
        api.stop();
    }

    #[test]
    fn login_register_list_heartbeat_logout_against_fake_api() {
        let api = FakeApi::start(FakeOptions::default());
        let tmp = tempfile::tempdir().unwrap();
        let bridge = configured(&api.base_url, &tmp.path().join("core"));

        let li = login(&bridge, "a@b.c", "pw").unwrap();
        assert!(!li.fingerprint.is_empty());
        // nothing registered yet: this machine is absent from the list
        let before = list_machines(&bridge).unwrap();
        assert!(before.iter().all(|m| !m.is_this_machine));

        let reg = register_machine(&bridge, "TEST-PC", "10.0.26100", "2.0.0").unwrap();
        assert!(!reg.machine_id.is_empty() && !reg.slot.is_empty());
        let after = list_machines(&bridge).unwrap();
        let me: Vec<_> = after.iter().filter(|m| m.is_this_machine).collect();
        assert_eq!(me.len(), 1);
        assert_eq!(me[0].machine_id, reg.machine_id);
        assert_eq!(me[0].platform, "windows");

        heartbeat(&bridge).unwrap();

        logout(&bridge).unwrap();
        assert_eq!(list_machines(&bridge).unwrap_err().code, "not_logged_in");
        api.stop();
    }

    #[test]
    fn unreachable_api_is_an_error_not_a_panic() {
        let tmp = tempfile::tempdir().unwrap();
        // port 9 (discard) on loopback: connection refused
        let bridge = configured("http://127.0.0.1:9", &tmp.path().join("core"));
        let e = login(&bridge, "a@b.c", "pw").unwrap_err();
        assert!(!e.code.is_empty() && e.code != "not_logged_in", "{e}");
    }
}
