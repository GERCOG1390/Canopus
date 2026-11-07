#!/bin/bash
# Archives and uploads the current commit to App Store Connect — only after Tools/release/check.sh passed
# for this very commit. The build number must be higher than any uploaded before (CURRENT_PROJECT_VERSION).
set -euo pipefail
export PATH="/usr/bin:$PATH"
ROOT=$(cd "$(dirname "$0")/../.." && pwd); cd "$ROOT"
WORK=${CANOPUS_RELEASE_WORK:-${TMPDIR:-/tmp}/canopus-release}
HEAD=$(/usr/bin/git rev-parse --short HEAD)
[ -z "$(/usr/bin/git status --porcelain)" ] || { echo "Uncommitted changes."; exit 1; }
[ -f ".release/checked-$HEAD" ] || { echo "Tools/release/check.sh has not passed for $HEAD — run it first."; exit 1; }
BUILD=$(xcodebuild -project Canopus.xcodeproj -scheme Canopus -showBuildSettings -configuration Release 2>/dev/null | awk '/ CURRENT_PROJECT_VERSION =/{print $3; exit}')
VERSION=$(xcodebuild -project Canopus.xcodeproj -scheme Canopus -showBuildSettings -configuration Release 2>/dev/null | awk '/ MARKETING_VERSION =/{print $3; exit}')
echo "Uploading $VERSION ($BUILD) from $HEAD"
rm -rf "$WORK/Canopus.xcarchive" "$WORK/export"
xcodebuild -project Canopus.xcodeproj -scheme Canopus -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$WORK/Canopus.xcarchive" -allowProvisioningUpdates archive > "$WORK/archive.log" 2>&1 || { grep -E "error:" "$WORK/archive.log"; exit 1; }
xcodebuild -exportArchive -archivePath "$WORK/Canopus.xcarchive" -exportOptionsPlist Tools/release/ExportOptions.plist \
  -exportPath "$WORK/export" -allowProvisioningUpdates > "$WORK/export.log" 2>&1 || { grep -iE "error" "$WORK/export.log"; exit 1; }
grep -q "Upload succeeded" "$WORK/export.log" && /usr/bin/git tag -a "ios-$VERSION-$BUILD" -m "App Store Connect build $VERSION ($BUILD)" && /usr/bin/git push -q origin "ios-$VERSION-$BUILD"
echo "Uploaded $VERSION ($BUILD); tagged ios-$VERSION-$BUILD"
