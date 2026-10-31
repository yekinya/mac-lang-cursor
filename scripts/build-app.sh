#!/bin/zsh
# Builds dist/LangCursor.app and ad-hoc signs it.
set -euo pipefail

cd "${0:a:h}/.."

swift build -c release
bin_path="$(swift build -c release --show-bin-path)"

app="dist/LangCursor.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_path/LangCursor" "$app/Contents/MacOS/LangCursor"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - --identifier com.yekinya.langcursor "$app"

echo "Built $app"
