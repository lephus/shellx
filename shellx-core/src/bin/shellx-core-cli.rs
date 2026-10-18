//! `shellx-core-cli <method> '<json>'` prints the envelope.
//! If `SHELLX_CORE_CONFIG` is set it is sent to `config.set` first.

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
    println!("{}", core.call_json(&method, &json));
}
