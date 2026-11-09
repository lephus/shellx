//! `shellx-core-cli <method> '<json>'` prints the envelope.
//! If `SHELLX_CORE_CONFIG` is set it is sent to `config.set` first.
//!
//! `auth.google.e2e '{"purpose":"sign_in"}'` (CLI only, for the e2e harness) runs
//! `auth.google.begin`, follows the URL with its own HTTP client when it is a loopback fake Google,
//! and prints the `auth.google.finish` envelope. A real Google URL is refused.

use shellx_core::Core;

fn main() {
    let mut args = std::env::args().skip(1);
    let Some(method) = args.next() else {
        eprintln!("usage: shellx-core-cli <method> '<json>'");
        std::process::exit(2);
    };
    let json = args.next().unwrap_or_else(|| "{}".to_string());
    let core = Core::new();
    if let Ok(cfg) = std::env::var("SHELLX_CORE_CONFIG") {
        let out = core.call_json("config.set", &cfg);
        if out.contains("\"error\"") {
            println!("{out}");
            std::process::exit(1);
        }
    }
    if method == "auth.google.e2e" {
        google_e2e(&core, &json);
        return;
    }
    println!("{}", core.call_json(&method, &json));
}

fn google_e2e(core: &Core, params: &str) {
    let begun = core.call_json("auth.google.begin", params);
    let Ok(v) = serde_json::from_str::<serde_json::Value>(&begun) else {
        println!("{begun}");
        std::process::exit(1);
    };
    let (Some(ok), true) = (v.get("ok"), v.get("error").is_none()) else {
        println!("{begun}");
        std::process::exit(1);
    };
    let flow_id = ok["flow_id"].as_str().unwrap_or_default().to_string();
    let url = ok["auth_url"].as_str().unwrap_or_default().to_string();
    if !url.starts_with("http://127.0.0.1:") {
        core.call_json("auth.google.cancel", &serde_json::json!({"flow_id": flow_id}).to_string());
        println!(
            "{}",
            serde_json::json!({"error": {"code": "invalid_params", "message": "auth.google.e2e follows only a loopback fake Google"}})
        );
        std::process::exit(1);
    }
    let browser = std::thread::spawn(move || {
        let agent: ureq::Agent = ureq::Agent::config_builder()
            .max_redirects(3)
            .http_status_as_error(false)
            .proxy(None)
            .build()
            .into();
        let _ = agent.get(&url).call();
    });
    println!("{}", core.call_json("auth.google.finish", &serde_json::json!({"flow_id": flow_id}).to_string()));
    let _ = browser.join();
}
