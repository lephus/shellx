// The exe's version information (spec §4.6, Ruling 26): the VERSIONINFO block that build.rs
// writes to $OUT_DIR/shellx-version.rc, which resources/shellx.rc includes. Only `//` and
// `///` comments here: build.rs `include!`s this file, where an inner doc comment is not
// allowed. main.rs compiles it for its tests only.

/// The `x.y.z` version's three parts, each a whole number a VERSIONINFO word can hold.
fn version_parts(version: &str) -> Option<[u16; 3]> {
    let mut parts = version.split('.');
    let mut out = [0u16; 3];
    for slot in &mut out {
        let part = parts.next()?;
        if part.is_empty() || !part.bytes().all(|b| b.is_ascii_digit()) {
            return None;
        }
        *slot = part.parse().ok()?;
    }
    parts.next().is_none().then_some(out)
}

/// The VERSIONINFO resource for `version` (`x.y.z` digits, else `None`): file and product
/// version `x,y,z,0`, company, description and product "ShellX", the exe's names, US English
/// in Unicode. Numbers instead of winver.h names (`0x40004` = VOS_NT_WINDOWS32, `0x1` =
/// VFT_APP), so no SDK header is needed. The version inside the app stays `x.y.z`; a test
/// label never appears here (spec §4.6).
pub fn version_resource(version: &str) -> Option<String> {
    let [major, minor, patch] = version_parts(version)?;
    Some(format!(
        "1 VERSIONINFO
FILEVERSION {major},{minor},{patch},0
PRODUCTVERSION {major},{minor},{patch},0
FILEFLAGSMASK 0x3F
FILEFLAGS 0x0
FILEOS 0x40004
FILETYPE 0x1
FILESUBTYPE 0x0
BEGIN
  BLOCK \"StringFileInfo\"
  BEGIN
    BLOCK \"040904B0\"
    BEGIN
      VALUE \"CompanyName\", \"ShellX\"
      VALUE \"FileDescription\", \"ShellX\"
      VALUE \"FileVersion\", \"{version}\"
      VALUE \"InternalName\", \"shellx-desktop\"
      VALUE \"OriginalFilename\", \"shellx-desktop.exe\"
      VALUE \"ProductName\", \"ShellX\"
      VALUE \"ProductVersion\", \"{version}\"
    END
  END
  BLOCK \"VarFileInfo\"
  BEGIN
    VALUE \"Translation\", 0x409, 1200
  END
END
"
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 3b §7, exactly.
    const EXPECTED: &str = "1 VERSIONINFO
FILEVERSION 1,7,0,0
PRODUCTVERSION 1,7,0,0
FILEFLAGSMASK 0x3F
FILEFLAGS 0x0
FILEOS 0x40004
FILETYPE 0x1
FILESUBTYPE 0x0
BEGIN
  BLOCK \"StringFileInfo\"
  BEGIN
    BLOCK \"040904B0\"
    BEGIN
      VALUE \"CompanyName\", \"ShellX\"
      VALUE \"FileDescription\", \"ShellX\"
      VALUE \"FileVersion\", \"1.7.0\"
      VALUE \"InternalName\", \"shellx-desktop\"
      VALUE \"OriginalFilename\", \"shellx-desktop.exe\"
      VALUE \"ProductName\", \"ShellX\"
      VALUE \"ProductVersion\", \"1.7.0\"
    END
  END
  BLOCK \"VarFileInfo\"
  BEGIN
    VALUE \"Translation\", 0x409, 1200
  END
END
";

    #[test]
    fn the_version_resource_names_shellx_and_the_version() {
        let rc = version_resource("1.7.0").unwrap();
        for line in [
            "FILEVERSION 1,7,0,0",
            "PRODUCTVERSION 1,7,0,0",
            "VALUE \"CompanyName\", \"ShellX\"",
            "VALUE \"FileDescription\", \"ShellX\"",
            "VALUE \"ProductName\", \"ShellX\"",
            "VALUE \"OriginalFilename\", \"shellx-desktop.exe\"",
            "VALUE \"FileVersion\", \"1.7.0\"",
            "VALUE \"ProductVersion\", \"1.7.0\"",
            "VALUE \"Translation\", 0x409, 1200",
        ] {
            assert!(rc.contains(line), "{line:?} missing:\n{rc}");
        }
        assert_eq!(rc, EXPECTED);
        assert!(
            version_resource("2.12.300")
                .unwrap()
                .contains("FILEVERSION 2,12,300,0")
        );
        // Not x.y.z digits, or a part a VERSIONINFO word cannot hold: no resource.
        for bad in [
            "1.7",
            "1.7.0-test",
            "",
            "1.7.0.0",
            "a.b.c",
            "1..0",
            "1.7.65536",
            " 1.7.0",
        ] {
            assert_eq!(version_resource(bad), None, "{bad:?}");
        }
    }
}
