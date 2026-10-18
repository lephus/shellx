#!/usr/bin/env python3
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_deps as cd  # noqa: E402


class OkExpr(unittest.TestCase):
    def test_pass(self):
        for e in ["MIT", "MIT OR Apache-2.0", "MIT/Apache-2.0", "(MIT OR GPL-3.0) AND ISC",
                  "Apache-2.0 WITH LLVM-exception", "MIT or GPL-3.0", "ISC AND MIT"]:
            self.assertTrue(cd.ok_expr(e), e)

    def test_fail_closed(self):
        for e in ["", "GPL-3.0", "MIT and GPL-3.0", "MIT AND GPL-3.0", "(MIT", "MIT)", "MIT MIT",
                  "MIT OR", "AND MIT", "MIT WITH Bogus-exception", "MIT WITH", "()", "GPL-3.0 OR (MIT"]:
            self.assertFalse(cd.ok_expr(e), e)


class Forbidden(unittest.TestCase):
    def test_names(self):
        for n in ["iroh", "iroh-relay", "iroh-base", "aws-lc-rs", "aws-lc-sys", "aws-lc-fips-sys",
                  "openssl", "openssl-sys", "native-tls"]:
            self.assertTrue(cd.is_forbidden(n), n)
        for n in ["irohx", "ring", "openssl-probe-not", "rustls", "awslc"]:
            self.assertFalse(cd.is_forbidden(n), n)


if __name__ == "__main__":
    unittest.main()
