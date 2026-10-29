#!/bin/zsh
# Archive the app and upload it to App Store Connect (TestFlight).
# Needs: the app record for com.ethanpany.hhil in App Store Connect, and your
# Apple account signed in to Xcode. Logs to ../testflight.log
# The Apple Watch app ships in the same archive; automatic signing registers
# its bundle ids (com.ethanpany.hhil.watchkitapp, .watchkitapp.widgets) and the
# app group group.com.ethanpany.hhil.watch on the first run.
cd "$(dirname "$0")/.."
exec > >(tee ../testflight.log) 2>&1
# System tools first: Xcode's IPA packaging breaks with Homebrew's rsync
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH:/opt/homebrew/bin:/usr/local/bin"
if [ -z "$DEVELOPER_DIR" ]; then
  # TestFlight needs a release Xcode; prefer a non beta one when installed
  for x in /Applications/Xcode-beta.app /Applications/Xcode.app; do [ -d "$x/Contents/Developer" ] && export DEVELOPER_DIR="$x/Contents/Developer"; done
fi
xcodebuild -version || exit 1
# The archive embeds the Apple Watch app (HHILWatch, with its widgets), so
# Xcode needs the watchOS platform. Settings > Components, or download it here.
if ! xcodebuild -showsdks 2>/dev/null | grep -q watchos; then
  echo "watchOS platform missing: downloading it (or add it in Xcode > Settings > Components)"
  xcodebuild -downloadPlatform watchOS || exit 1
fi
TEAM=$(security find-certificate -c "Apple Development" -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1)
[ -n "$TEAM" ] && sed -i '' "s/^DEVELOPMENT_TEAM = .*/DEVELOPMENT_TEAM = $TEAM/" Config/Secrets.xcconfig
xcodegen generate || exit 1
BUILD=$(date +%Y%m%d%H%M)
rm -rf build/HHIL.xcarchive build/export
xcodebuild -project HHIL.xcodeproj -scheme HHIL -configuration Release \
  -destination "generic/platform=iOS" -archivePath build/HHIL.xcarchive \
  -allowProvisioningUpdates CURRENT_PROJECT_VERSION=$BUILD archive > ../archive.log 2>&1
STATUS=$?; grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)" ../archive.log | head -20; echo "ARCHIVE=$STATUS BUILD=$BUILD"
[ $STATUS -eq 0 ] || exit 1
# One upload carries both apps: the watch app sits inside the iOS app
WATCH=build/HHIL.xcarchive/Products/Applications/HHIL.app/Watch/HHILWatch.app
[ -d "$WATCH" ] && echo "WATCH_APP=embedded" || { echo "WATCH_APP=missing"; exit 1; }
cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>testFlightInternalTestingOnly</key><false/>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath build/HHIL.xcarchive -exportOptionsPlist build/ExportOptions.plist \
  -exportPath build/export -allowProvisioningUpdates
echo "UPLOAD=$?"
