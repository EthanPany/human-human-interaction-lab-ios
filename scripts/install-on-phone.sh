#!/bin/zsh
# Build the app and install it on the iPhone paired with this Mac.
# Usage: scripts/install-on-phone.sh   (logs to ../install.log)
cd "$(dirname "$0")/.."
exec > >(tee ../install.log) 2>&1
# System tools first: Xcode's IPA packaging breaks with Homebrew's rsync
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH:/opt/homebrew/bin:/usr/local/bin"
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

# Every real, paired iPhone that is reachable right now (install on all of them)
xcrun devicectl list devices --json-output /tmp/hhil-devices.json >/dev/null
DEVICES=("${(@f)$(python3 -c '
import json
d=json.load(open("/tmp/hhil-devices.json"))["result"]["devices"]
for x in d:
    h,c=x["hardwareProperties"],x["connectionProperties"]
    if h.get("reality")=="physical" and h.get("deviceType")=="iPhone" and c.get("pairingState")=="paired" and c.get("tunnelState")!="unavailable":
        print(x["identifier"], h["udid"], x["deviceProperties"]["name"].replace(" ","_"))
')}")
if [ -z "${DEVICES[1]}" ]; then
  echo "NO_DEVICE: unlock the iPhone and keep it connected. Phones seen:"
  python3 -c '
import json
for x in json.load(open("/tmp/hhil-devices.json"))["result"]["devices"]:
    h,c=x["hardwareProperties"],x["connectionProperties"]
    print(" ", x["deviceProperties"]["name"], h.get("reality"), c.get("pairingState"), c.get("tunnelState"), c.get("transportType"))
'
  exit 1
fi
for line in "${DEVICES[@]}"; do echo "DEVICE $line"; done
FIRST_UDID=$(echo "${DEVICES[1]}" | cut -d' ' -f2)

xcodebuild -project HHIL.xcodeproj -scheme HHIL -configuration Debug \
  -destination "id=$FIRST_UDID" -derivedDataPath build -allowProvisioningUpdates \
  build > ../xcodebuild.log 2>&1
STATUS=$?
grep -E "error:|BUILD (SUCCEEDED|FAILED)" ../xcodebuild.log | head -30
echo "XCODEBUILD=$STATUS"
[ $STATUS -eq 0 ] || exit 1

APP=$(ls -d build/Build/Products/Debug-iphoneos/*.app | head -1)
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
for line in "${DEVICES[@]}"; do
  DEVICE=$(echo "$line" | cut -d' ' -f1)
  xcrun devicectl device install app --device "$DEVICE" "$APP" && \
  xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE" && echo "INSTALLED $line"
done
echo "DONE"
