// Embeds the ShellX icon (resource id 1, which GPUI loads as the window
// icon) and the application manifest (per-monitor v2 DPI awareness) into
// the Windows executable. Nothing to do on other targets.
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
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        embed_resource::compile("resources/shellx.rc", embed_resource::NONE)
            .manifest_required()
            .expect("failed to embed the Windows icon/manifest resource");
    }
}
