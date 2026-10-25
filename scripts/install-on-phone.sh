#!/bin/zsh
# Build the app and install it on the iPhone paired with this Mac.
# Usage: scripts/install-on-phone.sh   (logs to ../install.log)
cd "$(dirname "$0")/.."
exec > >(tee ../install.log) 2>&1
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
# Use the Xcode app even if xcode-select points at the Command Line Tools
if [ -z "$DEVELOPER_DIR" ]; then
  for x in /Applications/Xcode*.app; do [ -d "$x/Contents/Developer" ] && export DEVELOPER_DIR="$x/Contents/Developer"; done
fi
xcodebuild -version || exit 1
command -v xcodegen >/dev/null || brew install xcodegen
[ -f HHIL/Resources/Fonts/GeneralSans-Semibold.otf ] || scripts/fetch-fonts.sh

# Team ID from the Apple Development certificate Xcode created for your account
TEAM=$(security find-certificate -c "Apple Development" -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1)
echo "TEAM=$TEAM"
[ -n "$TEAM" ] && sed -i '' "s/^DEVELOPMENT_TEAM = .*/DEVELOPMENT_TEAM = $TEAM/" Config/Secrets.xcconfig

xcodegen generate || exit 1

# A real, paired iPhone that is reachable right now
xcrun devicectl list devices --json-output /tmp/hhil-devices.json >/dev/null
read -r DEVICE UDID NAME <<<"$(python3 -c '
import json
d=json.load(open("/tmp/hhil-devices.json"))["result"]["devices"]
ok=[x for x in d
    if x["hardwareProperties"].get("reality")=="physical"
    and x["hardwareProperties"].get("deviceType")=="iPhone"
    and x["connectionProperties"].get("pairingState")=="paired"
    and x["connectionProperties"].get("tunnelState")!="unavailable"]
x=ok[0] if ok else None
print(x["identifier"], x["hardwareProperties"]["udid"], x["deviceProperties"]["name"].replace(" ","_")) if x else print("")
')"
echo "DEVICE=$DEVICE UDID=$UDID NAME=$NAME"
[ -n "$UDID" ] || { echo "NO_DEVICE: unlock the iPhone and keep it connected"; exit 1; }

xcodebuild -project HHIL.xcodeproj -scheme HHIL -configuration Debug \
  -destination "id=$UDID" -derivedDataPath build -allowProvisioningUpdates \
  build > ../xcodebuild.log 2>&1
STATUS=$?
grep -E "error:|BUILD (SUCCEEDED|FAILED)" ../xcodebuild.log | head -30
echo "XCODEBUILD=$STATUS"
[ $STATUS -eq 0 ] || exit 1

APP=$(ls -d build/Build/Products/Debug-iphoneos/*.app | head -1)
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
xcrun devicectl device install app --device "$DEVICE" "$APP" && \
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE"
echo "DONE"
