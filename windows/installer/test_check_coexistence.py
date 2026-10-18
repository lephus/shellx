import os
import unittest

import check_coexistence as cc

HERE = os.path.dirname(os.path.abspath(__file__))
ISS = open(os.path.join(HERE, "shellx-native.iss"), encoding="utf-8").read()


class Coexistence(unittest.TestCase):
    def test_installer_coexists_with_flutter(self):
        self.assertEqual(cc.check(ISS), [])

    def test_flutter_app_id_fails(self):
        bad = ISS.replace(next(l for l in ISS.splitlines() if l.startswith("AppId=")),
                          "AppId={{6A3A45BD-0A27-407A-A1FF-3C8D1BE226EE}")
        self.assertTrue(any("AppId" in p for p in cc.check(bad)))

    def test_taskkill_flutter_exe_fails(self):
        bad = ISS + '\n[UninstallRun]\nFilename: "{sys}\\taskkill.exe"; Parameters: "/F /IM ""ShellX.exe"""\n'
        self.assertTrue(any("taskkill" in p for p in cc.check(bad)))

    def test_flutter_exe_and_delete_fail(self):
        bad = ISS.replace('#define AppExeName "shellx-desktop.exe"', '#define AppExeName "shellx.EXE"')
        self.assertTrue(cc.check(bad))
        bad = ISS + '\n[UninstallDelete]\nType: filesandordirs; Name: "{localappdata}\\ShellX\\term"\n'
        self.assertTrue(cc.check(bad))
        ok = ISS + '\n[UninstallDelete]\nType: filesandordirs; Name: "{localappdata}\\ShellX\\native"\n'
        self.assertEqual(cc.check(ok), [])


if __name__ == "__main__":
    unittest.main()
