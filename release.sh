#!/bin/sh
set -eu
cd "$(dirname "$0")"
./check.sh
LULLY_BUNDLE_KEY=0 ./build.sh
if [ -f build/Lully.app/Contents/Resources/openai.key ]; then
  printf 'Refusing to package a release with a bundled API key.\n' >&2
  exit 1
fi
codesign --verify --deep --strict build/Lully.app
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
architecture=$(uname -m)
mkdir -p releases
archive="Lully-$version-macos-$architecture.zip"
ditto -c -k --sequesterRsrc --keepParent build/Lully.app "releases/$archive"
(cd releases && shasum -a 256 "$archive" > "$archive.sha256")
printf 'Release archive: releases/%s\n' "$archive"
