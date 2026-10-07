//! A9 D39: `shellx config check|reload|show` (`config path` is local, in
//! [config_path]). The text is rendered by [config_path::render], which
//! tests without a session.

use super::prepare::flag;
use super::{Api, Ctx};
use crate::api::args::Parsed;
use crate::api::client::ApiError;
use crate::api::config_path;
use crate::api::output;

pub(super) fn config_remote(p: &Parsed, ctx: &mut Ctx, path: &str) -> Result<(), ApiError> {
    let mut api = Api::open(p, ctx)?;
    let (t, fields) = match path {
        "config check" => ("ui.config.check", vec![]),
        "config reload" => ("ui.config.reload", vec![]),
        _ => ("ui.config.show", vec![("defaults", flag(p, "defaults"))]),
    };
    let r = api.call(t, fields)?;
    let (out, code) = config_path::render(path, p.json, &output::result_json(&r));
    write!(ctx.out, "{out}").map_err(|e| ApiError::Io(e.to_string()))?;
    if code == 0 {
        Ok(())
    } else {
        // Already printed (also the one `--json` object): exit 1.
        Err(ApiError::Reported("config_errors".into()))
    }
}
