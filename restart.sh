#!/bin/sh
set -eu
cd "$(dirname "$0")"
./build.sh
pkill -x Lully || true
attempt=0
while pgrep -x Lully >/dev/null; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 50 ]; then
    printf 'Lully is still closing. Please quit it before relaunching.\n' >&2
    exit 1
  fi
  sleep 0.1
done
ditto "$PWD/build/Lully.app" /Applications/Lully.app
codesign --verify --deep --strict /Applications/Lully.app
open -n /Applications/Lully.app
