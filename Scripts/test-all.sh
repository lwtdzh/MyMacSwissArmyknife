#!/bin/bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if grep -nF "NSMenuItem.separator()" \
  "${root}/Sources/RightClickMenuExtension/FinderSync.swift"; then
  echo "FinderSync menus must not contain separators; Finder drops the entire contribution." >&2
  exit 1
fi

xcodegen generate \
  --spec "${root}/Upstream/ResourceMonitor/project.yml" \
  --project "${root}/Upstream/ResourceMonitor"
xcodegen generate --spec "${root}/project.yml" --project "${root}"

xcodebuild \
  -workspace "${root}/Upstream/ClipyEnhanced/Clipy.xcworkspace" \
  -scheme Clipy \
  -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "${root}/DerivedData/Validation/ClipyEnhancedTests" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="-" \
  test

for configuration in Debug Release; do
  xcodebuild \
    -project "${root}/Upstream/ResourceMonitor/NetSpeedMonitor.xcodeproj" \
    -scheme NetSpeedMonitor \
    -configuration "${configuration}" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "${root}/DerivedData/Validation/ResourceMonitor-${configuration}" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="-" \
    build
done

xcodebuild \
  -project "${root}/Upstream/ResourceMonitor/NetSpeedMonitor.xcodeproj" \
  -scheme NetSpeedMonitor \
  -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "${root}/DerivedData/Validation/ResourceMonitorTests" \
  test

xcodebuild \
  -project "${root}/MyMacSwissArmyknife.xcodeproj" \
  -scheme MyMacSwissArmyknife \
  -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "${root}/DerivedData/Validation/HostTests" \
  test

xcodebuild \
  -project "${root}/MyMacSwissArmyknife.xcodeproj" \
  -scheme MyMacSwissArmyknife \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "${root}/DerivedData/Validation/HostRelease" \
  clean build

app="${root}/DerivedData/Validation/HostRelease/Build/Products/Release/MyMacSwissArmyknife.app"
test -x "${app}/Contents/MacOS/MyMacSwissArmyknife"
test -x "${app}/Contents/Helpers/ResourceMonitor.app/Contents/MacOS/ResourceMonitor"
clipy="${app}/Contents/Helpers/ClipyEnhanced.app"
test -x "${clipy}/Contents/MacOS/ClipyEnhanced"
test "$(
  plutil -extract CFBundleIdentifier raw "${clipy}/Contents/Info.plist"
)" = "com.clipy-app.ClipyEnhanced"
test "$(
  lipo -archs "${clipy}/Contents/MacOS/ClipyEnhanced"
)" = "x86_64 arm64"
test ! -e "${app}/Contents/Helpers/ScrollReverser.app"
helper="${app}/Contents/Helpers/RightClickNewFilesHost.app"
extension="${helper}/Contents/PlugIns/RightClickNewFilesExtension.appex"
test -x "${helper}/Contents/MacOS/RightClickNewFilesHost"
test -x "${extension}/Contents/MacOS/RightClickNewFilesExtension"
test "$(
  plutil -extract NSExtension.NSExtensionPointIdentifier raw \
    "${extension}/Contents/Info.plist"
)" = "com.apple.FinderSync"
test "$(
  plutil -extract CFBundleVersion raw "${app}/Contents/Info.plist"
)" = "$(
  plutil -extract CFBundleVersion raw "${extension}/Contents/Info.plist"
)"
codesign --verify --strict "${extension}"
codesign --verify --deep --strict "${helper}"
codesign --verify --deep --strict "${clipy}"
if plutil -extract NSExtension raw "${app}/Contents/Info.plist" >/dev/null 2>&1; then
  echo "Host Info.plist must not contain NSExtension" >&2
  exit 1
fi
codesign --verify --deep --strict "${app}"

release_dir="${root}/Build/Release"
release_app="${release_dir}/MyMacSwissArmyknife.app"
mkdir -p "${release_dir}"
rm -rf "${release_app}"
ditto "${app}" "${release_app}"
codesign \
  --force \
  --sign - \
  --requirements '=designated => identifier "com.mymacswissarmyknife.host"' \
  "${release_app}"
codesign --verify --deep --strict "${release_app}"
codesign -d -r- "${release_app}" 2>&1 |
  grep -Fx 'designated => identifier "com.mymacswissarmyknife.host"'

echo "All module builds, module tests, host tests, and bundle checks passed."
echo "Release app: ${release_app}"
