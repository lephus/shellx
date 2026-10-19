# Task 1+2 review 1 findings (at b840038771), sent to fix round 1
1. Important: StateStore::open / config.set accept a state root with a trailing slash (or `/.`), and the root is then opened via AT_FDCWD + full path, so a symlinked root slips past the O_NOFOLLOW check (symlinked root bypass via trailing slash).
2. Minor (fixed in round 1 anyway): scripts/check_deps.py license-expression check must fail closed (unparsed/garbage expressions, dangling operators, unbalanced parens must not pass).
3. Minor (fixed in round 1): forbidden-crate check must cover prefixes (iroh-*, aws-lc-*), exact openssl/openssl-sys/native-tls.
4. Minor (fixed in round 1): scripts/c-smoke.sh masks a failing `cargo rustc` inside a pipe (needs pipefail / capture first).
5. Minor (fixed in round 1): leftover `*.tmp.<hex>` temp files from a crashed write are never swept.
