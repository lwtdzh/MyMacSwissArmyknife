#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: build-modules.sh <destination>" >&2
  exit 64
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
destination="$1"
configuration="${CONFIGURATION:-Debug}"
module_build_root="${root}/Build/Modules/${configuration}"
clean_path="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"

resource_root="${root}/Upstream/ResourceMonitor"
clipy_root="${root}/Upstream/ClipyEnhanced"

/usr/bin/env -i \
  HOME="${HOME}" \
  USER="${USER}" \
  LOGNAME="${LOGNAME}" \
  TMPDIR="${TMPDIR}" \
  PATH="${clean_path}" \
  DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
  xcodebuild \
  -project "${resource_root}/NetSpeedMonitor.xcodeproj" \
  -scheme NetSpeedMonitor \
  -configuration "${configuration}" \
  -destination "generic/platform=macOS" \
  -derivedDataPath "${module_build_root}/ResourceMonitor" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="-" \
  build

rm -rf "${destination}"
mkdir -p "${destination}"

ditto \
  "${module_build_root}/ResourceMonitor/Build/Products/${configuration}/ResourceMonitor.app" \
  "${destination}/ResourceMonitor.app"

/usr/bin/env -i \
  HOME="${HOME}" \
  USER="${USER}" \
  LOGNAME="${LOGNAME}" \
  TMPDIR="${TMPDIR}" \
  PATH="${clean_path}" \
  DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
  xcodebuild \
  -workspace "${clipy_root}/Clipy.xcworkspace" \
  -scheme Clipy \
  -configuration "${configuration}" \
  -destination "generic/platform=macOS" \
  -derivedDataPath "${module_build_root}/ClipyEnhanced" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="-" \
  build

ditto \
  "${module_build_root}/ClipyEnhanced/Build/Products/${configuration}/ClipyEnhanced.app" \
  "${destination}/ClipyEnhanced.app"

/usr/bin/codesign \
  --force \
  --deep \
  --sign - \
  "${destination}/ClipyEnhanced.app"
