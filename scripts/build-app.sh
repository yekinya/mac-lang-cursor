#!/bin/zsh
# Build the universal app and its drag-to-Applications installer.
set -euo pipefail

cd "${0:a:h}/.."

release_args=(-c release --arch arm64 --arch x86_64)
swift build "${release_args[@]}"
bin_path="$(swift build "${release_args[@]}" --show-bin-path)"

mkdir -p dist build
stage=$(mktemp -d dist/.package.XXXXXX)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/image"
app="$stage/image/LangCursor.app"
mkdir -p "$app/Contents/"{MacOS,Resources}
cp "$bin_path/LangCursor" "$app/Contents/MacOS/LangCursor"
ditto "$bin_path/LangCursor_LangCursor.bundle" "$app/Contents/Resources/LangCursor_LangCursor.bundle"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - --identifier com.yekinya.langcursor "$app"
codesign --verify --deep --strict "$app"
for arch in arm64 x86_64; do
    lipo "$app/Contents/MacOS/LangCursor" -verify_arch "$arch"
done

ln -s /Applications "$stage/image/Applications"
hdiutil create -quiet -format UDZO -fs HFS+ -volname LangCursor \
    -srcfolder "$stage/image" "$stage/LangCursor.dmg"
hdiutil verify -quiet "$stage/LangCursor.dmg"
rm -rf dist/LangCursor.app
mv "$app" dist/LangCursor.app
mv -f "$stage/LangCursor.dmg" build/LangCursor-macOS.dmg
./scripts/macos-checksums.sh > "$stage/macos.sha256"
mv "$stage/macos.sha256" build/macos.sha256
echo "Built dist/LangCursor.app and build/LangCursor-macOS.dmg"
