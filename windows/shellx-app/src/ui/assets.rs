//! GPUI `AssetSource` over the embedded icon table in `crate::icons`.

use std::borrow::Cow;

use gpui::{AssetSource, Result, SharedString};

pub use crate::icons::Icon;

pub struct Assets;

impl AssetSource for Assets {
    fn load(&self, path: &str) -> Result<Option<Cow<'static, [u8]>>> {
        Ok(crate::icons::by_path(path).map(Cow::Borrowed))
    }

    fn list(&self, path: &str) -> Result<Vec<SharedString>> {
        Ok(crate::icons::list(path)
            .into_iter()
            .map(SharedString::from)
            .collect())
    }
}
