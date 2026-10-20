#!/bin/bash
# Builds CMusic, signs it with Developer ID, notarizes it and publishes it as a GitHub release.
#
# Usage: scripts/release.sh 1.1
#
# Needs a "Developer ID Application" certificate in the keychain and an App Store Connect API key
# at ~/.config/asc/key.json ({"key_id", "issuer_id", "key"}) for notarization.
set -euo pipefail

VERSION=${1:?usage: scripts/release.sh <version>}
cd "$(dirname "$0")/.."

[[ -z $(git status --porcelain) ]] || { echo "Commit or stash changes first." >&2; exit 1; }
git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && { echo "v$VERSION already exists." >&2; exit 1; }

OUT=build/release
BUILD=$(git rev-list --count HEAD)
rm -rf "$OUT"
mkdir -p "$OUT"

echo "==> Archiving $VERSION ($BUILD)"
xcodebuild archive -quiet \
    -project CMusic.xcodeproj -scheme CMusic -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$OUT/CMusic.xcarchive" \
    -allowProvisioningUpdates \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD"

echo "==> Exporting with Developer ID"
xcodebuild -exportArchive -quiet \
    -archivePath "$OUT/CMusic.xcarchive" \
    -exportOptionsPlist scripts/ExportOptions.plist \
    -exportPath "$OUT" \
    -allowProvisioningUpdates

echo "==> Notarizing"
KEY_DIR=$(mktemp -d)
trap 'rm -rf "$KEY_DIR"' EXIT
read -r KEY_ID ISSUER < <(python3 - "$KEY_DIR/AuthKey.p8" <<'EOF'
import json, os, sys
key = json.load(open(os.path.expanduser("~/.config/asc/key.json")))
with open(sys.argv[1], "w") as f:
    f.write(key["key"])
print(key["key_id"], key["issuer_id"])
EOF
)
ditto -c -k --keepParent "$OUT/CMusic.app" "$OUT/notarize.zip"
xcrun notarytool submit "$OUT/notarize.zip" --key "$KEY_DIR/AuthKey.p8" --key-id "$KEY_ID" --issuer "$ISSUER" --wait
xcrun stapler staple "$OUT/CMusic.app"
spctl --assess --type execute --verbose "$OUT/CMusic.app"

ZIP="$OUT/CMusic-$VERSION.zip"
ditto -c -k --keepParent "$OUT/CMusic.app" "$ZIP"

echo "==> Publishing v$VERSION"
git tag "v$VERSION"
git push origin "v$VERSION"
gh release create "v$VERSION" "$ZIP" --title "CMusic $VERSION" --generate-notes \
    --notes-file <(printf 'Download **CMusic-%s.zip**, unzip it and drag CMusic to Applications. Requires macOS 27 or later and an Apple Music subscription.\n\n' "$VERSION")
