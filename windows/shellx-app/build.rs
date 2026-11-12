// Embeds the ShellX icon (resource id 1, which GPUI loads as the window
// icon) and the application manifest (per-monitor v2 DPI awareness) into
// the Windows executable, with the version information (src/exe_resource.rs). Nothing to do
// on other targets.

include!("src/exe_resource.rs");

fn main() {
    // Google's official "G" and Google Sans Medium are added by scripts/shellx/fetch-google-branding.sh
    // (downloaded by the user). Without them the button is text-only in the UI font. A font without its
    // licence text is never embedded.
    println!("cargo::rustc-check-cfg=cfg(shellx_google_mark)");
    println!("cargo::rustc-check-cfg=cfg(shellx_google_sans)");
    println!("cargo:rerun-if-changed=assets/google");
    println!("cargo:rerun-if-changed=assets/fonts");
    let file = |p: &str| std::path::Path::new(p).is_file();
    if file("assets/google/google-g.png") {
        println!("cargo:rustc-cfg=shellx_google_mark");
    }
    if file("assets/fonts/GoogleSans-Medium.ttf") && file("assets/fonts/GoogleSans-OFL.txt") {
        println!("cargo:rustc-cfg=shellx_google_sans");
    }
    println!("cargo:rerun-if-changed=resources/shellx.rc");
    println!("cargo:rerun-if-changed=resources/shellx.manifest");
    println!("cargo:rerun-if-changed=resources/app_icon.ico");
    println!("cargo:rerun-if-changed=src/exe_resource.rs");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        // The exe's version information (Ruling 26): resources/shellx.rc includes
        // shellx-version.rc, found on the include path both resource pipelines give OUT_DIR.
        let version = std::env::var("CARGO_PKG_VERSION").unwrap_or_default();
        let resource = version_resource(&version).expect("the workspace version must be x.y.z");
        let out_dir = std::path::PathBuf::from(std::env::var_os("OUT_DIR").expect("OUT_DIR"));
        std::fs::write(out_dir.join("shellx-version.rc"), resource)
            .expect("failed to write shellx-version.rc");
        embed_resource::compile("resources/shellx.rc", embed_resource::NONE)
            .manifest_required()
            .expect("failed to embed the Windows icon/manifest resource");
    }
}
