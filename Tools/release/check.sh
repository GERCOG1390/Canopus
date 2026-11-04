#!/bin/bash
# The release gate: everything a build must pass before it goes to App Store Connect. On success it
# stamps the commit; Tools/release/upload.sh refuses to upload a commit without the stamp.
#
#   Tools/release/check.sh            # full run (about 20 minutes: two simulators, every screen)
#   SMOKE_WAIT=8 Tools/release/check.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd); cd "$ROOT"
WORK=${CANOPUS_RELEASE_WORK:-${TMPDIR:-/tmp}/canopus-release}
mkdir -p "$WORK"
HEAD=$(/usr/bin/git rev-parse --short HEAD)
step() { printf '\n=== %s ===\n' "$1"; }

step "1/6 Working tree"
if [ -n "$(/usr/bin/git status --porcelain)" ]; then
  echo "Uncommitted changes: commit first, the stamp is for a commit."; /usr/bin/git status --short; exit 1
fi

step "2/6 Package tests (engine vs Pyfa, item lists → fits, SDE queries, ESI decoding)"
for pkg in EVEStaticData EVEAuth; do
  swift test --package-path "Packages/$pkg" --scratch-path "$WORK/spm-$pkg" > "$WORK/test-$pkg.log" 2>&1 || true
  grep -E "Test run with" "$WORK/test-$pkg.log" | tail -1
  grep -qE "Test run with .* passed" "$WORK/test-$pkg.log" || { grep -E "✘" "$WORK/test-$pkg.log" | head -20; echo "$pkg tests failed"; exit 1; }
done

step "3/6 Release build for a device (what the archive compiles)"
xcodebuild -project Canopus.xcodeproj -scheme Canopus -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$WORK/device" CODE_SIGNING_ALLOWED=NO build > "$WORK/device.log" 2>&1 || { grep -E "error:" "$WORK/device.log" | head; exit 1; }
grep -E "warning: .*(deprecated|will never be executed|unused)" "$WORK/device.log" | sort -u | head -5 || true
echo "Release build OK"

step "4/6 Simulator build"
xcodebuild -project Canopus.xcodeproj -scheme Canopus -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$WORK/sim" build > "$WORK/sim.log" 2>&1 || { grep -E "error:" "$WORK/sim.log" | head; exit 1; }
APP="$WORK/sim/Build/Products/Debug-iphonesimulator/Canopus.app"
echo "Simulator build OK"

step "5/6 Translations (every visible string has Russian)"
MISSING=$(python3 Tools/l10n/sync_strings.py "$WORK/sim" | awk '/^app:/{f=1;next}/^widget:/{f=0}f' \
  | python3 -c "import sys,ast; same={l.rstrip('\n') for l in open('Tools/release/l10n-same.txt') if l.strip() and not l.startswith('#')}
for l in sys.stdin:
    k=ast.literal_eval(l.strip())
    if k not in same: print('   ', repr(k))")
/usr/bin/git checkout -- Canopus/Resources/Localizable.xcstrings CanopusWidget/Localizable.xcstrings 2>/dev/null || true
if [ -n "$MISSING" ]; then echo "No Russian for:"; echo "$MISSING"; exit 1; fi
echo "Translations OK"

step "6/6 Every screen on iPhone and iPad"
Tools/release/smoke.sh "$APP" "$WORK/smoke"
echo "Look over the sheets before uploading: $WORK/smoke/sheet-iphone.jpg, $WORK/smoke/sheet-ipad.jpg"

mkdir -p "$ROOT/.release"; date -u +%FT%TZ > "$ROOT/.release/checked-$HEAD"
printf '\nRELEASE CHECK PASSED for %s\n' "$HEAD"
