// The exe's version information (spec §4.6, Ruling 26): the VERSIONINFO block that build.rs
// writes to $OUT_DIR/shellx-version.rc, which resources/shellx.rc includes. Only `//` and
// `///` comments here: build.rs `include!`s this file, where an inner doc comment is not
// allowed. main.rs compiles it for its tests only.

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
        for bad in ["1.7", "1.7.0-test", "", "1.7.0.0", "a.b.c", "1..0", "1.7.65536", " 1.7.0"] {
            assert_eq!(version_resource(bad), None, "{bad:?}");
        }
    }
}
