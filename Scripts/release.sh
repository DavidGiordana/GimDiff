#!/bin/bash
#
#  Created by David Giordana.
#  Copyright © 2026 David Giordana. All rights reserved.
#
#  Builds GimDiff, signs it with Developer ID, notarizes it, and staples the ticket, leaving
#  build/release/GimDiff-<name>.zip ready to attach to a GitHub release.
#
#  Usage: Scripts/release.sh <name>          e.g. Scripts/release.sh 1.0.0-beta.7
#
#  Needs, once per Mac:
#    - a Developer ID Application certificate for your team (Xcode ▸ Settings ▸ Accounts);
#    - your team in Config/Local.xcconfig (see Config/Local.xcconfig.template);
#    - notary credentials saved under the profile below:
#        xcrun notarytool store-credentials gimdiff-notary --apple-id <you> --team-id <team>
#
set -euo pipefail

name="${1:?Usage: Scripts/release.sh <name>, e.g. 1.0.0-beta.7}"
profile="${NOTARY_PROFILE:-gimdiff-notary}"

cd "$(dirname "$0")/.."
out=build/release
archive="$out/GimDiff.xcarchive"
app="$out/export/GimDiff.app"
zip="$out/GimDiff-$name.zip"

# Fail before a ten-minute build rather than after it.
if [ ! -f Config/Local.xcconfig ]; then
    echo "error: Config/Local.xcconfig is missing; a Developer ID export needs your team." >&2
    exit 1
fi
if ! xcrun notarytool history --keychain-profile "$profile" > /dev/null 2>&1; then
    echo "error: no notary credentials saved as '$profile'. Run:" >&2
    echo "  xcrun notarytool store-credentials $profile --apple-id <you> --team-id <team>" >&2
    exit 1
fi

rm -rf "$out"
mkdir -p "$out"

echo "Archiving…"
xcodebuild archive -quiet \
    -scheme GimDiff -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$archive"

echo "Signing with Developer ID…"
xcodebuild -exportArchive -quiet \
    -archivePath "$archive" \
    -exportOptionsPlist Scripts/ExportOptions.plist \
    -exportPath "$out/export" \
    -allowProvisioningUpdates

echo "Notarizing (this usually takes a few minutes)…"
ditto -c -k --keepParent "$app" "$out/notarize.zip"
xcrun notarytool submit "$out/notarize.zip" \
    --keychain-profile "$profile" --wait --output-format plist > "$out/notary.plist"
status=$(/usr/libexec/PlistBuddy -c 'Print status' "$out/notary.plist")
if [ "$status" != "Accepted" ]; then
    id=$(/usr/libexec/PlistBuddy -c 'Print id' "$out/notary.plist")
    echo "error: notarization finished as '$status'. Apple's log says why:" >&2
    xcrun notarytool log "$id" --keychain-profile "$profile" >&2
    exit 1
fi

# The ticket lets Gatekeeper accept the app offline; zip again so the upload carries it.
xcrun stapler staple -q "$app"
spctl --assess --type execute "$app"
ditto -c -k --norsrc --noextattr --keepParent "$app" "$zip"
rm "$out/notarize.zip" "$out/notary.plist"

echo "Ready: $zip"
