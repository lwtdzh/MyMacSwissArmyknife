#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: package-release.sh <version>" >&2
  exit 64
fi

version="$1"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
staging_root="$(mktemp -d "${TMPDIR:-/tmp}/MyMacSwissArmyknife-source.XXXXXX")"
staging_source="${staging_root}/MyMacSwissArmyknife"
release_dir="${root}/Build/Release"
archive="${release_dir}/MyMacSwissArmyknife-${version}.zip"

cleanup() {
  rm -rf "${staging_root}"
}
trap cleanup EXIT

mkdir -p "${release_dir}"
cp -cR "${root}" "${staging_source}"
rm -rf \
  "${staging_source}/.git" \
  "${staging_source}/.idea" \
  "${staging_source}/.trae" \
  "${staging_source}/Build" \
  "${staging_source}/DerivedData" \
  "${staging_source}/Upstream/ClipyEnhanced/build"

VERIFY_RELEASE_PRIVACY=1 "${staging_source}/Scripts/test-all.sh"

source_app="${staging_source}/Build/Release/MyMacSwissArmyknife.app"
release_app="${release_dir}/MyMacSwissArmyknife.app"
rm -rf "${release_app}" "${archive}"
ditto "${source_app}" "${release_app}"
ditto -c -k --norsrc --noextattr --keepParent "${release_app}" "${archive}"

codesign --verify --deep --strict "${release_app}"
shasum -a 256 "${archive}"
echo "Release archive: ${archive}"
