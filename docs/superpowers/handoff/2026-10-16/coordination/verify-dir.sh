#!/bin/zsh
# Full verification of one checkout: every package and both apps. Usage: verify-dir.sh <repo dir>
export PATH=~/fvm/versions/3.41.4/bin:$PATH
cd "$1" || exit 2
echo "== $(git rev-parse --short HEAD) $(date +%H:%M)"
echo "== pub get"; flutter pub get >/dev/null 2>&1 && echo ok || echo "FAIL pub get"
for d in packages/shellx_core packages/shellx_agent packages/shellx_client packages/shellx_e2e packages/shellx_acp packages/shellx_ai; do
  [ -d "$d/test" ] || continue
  echo "== $d"
  (cd $d && dart analyze 2>&1 | tail -1 && dart test 2>&1 | tail -1) || echo "FAIL $d"
done
for d in apps/desktop apps/mobile; do
  echo "== $d"
  (cd $d && flutter analyze 2>&1 | tail -1 && flutter test 2>&1 | tail -1) || echo "FAIL $d"
done
git status --short | grep -v '^??' | head -5
echo "== done $(date +%H:%M)"
