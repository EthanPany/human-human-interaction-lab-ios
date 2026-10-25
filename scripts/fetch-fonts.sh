#!/usr/bin/env bash
# Downloads General Sans (Fontshare, ITF Free Font License) into the app.
# The license allows embedding in apps but not redistributing the files, so
# they are not committed. Run once after cloning, then run xcodegen.
set -euo pipefail
cd "$(dirname "$0")/.."
dest="HHIL/Resources/Fonts"
tmp="$(mktemp -d)"
curl -fsSL -o "$tmp/gs.zip" "https://api.fontshare.com/v2/fonts/download/general-sans"
unzip -q "$tmp/gs.zip" -d "$tmp"
for w in Regular Medium Semibold Bold; do
  cp "$tmp"/GeneralSans_Complete/Fonts/OTF/GeneralSans-$w.otf "$dest/"
done
rm -rf "$tmp"
echo "General Sans installed in $dest"
