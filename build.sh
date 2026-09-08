#!/bin/sh
set -eu
cd "$(dirname "$0")"
if [ ! -d ui/node_modules ]; then npm --prefix ui ci; fi
npm --prefix ui run build
swift build -c release
mkdir -p build/Lully.app/Contents/MacOS
cp .build/release/Lully build/Lully.app/Contents/MacOS/Lully
cp Info.plist build/Lully.app/Contents/Info.plist
mkdir -p build/Lully.app/Contents/Resources/UI
cp ui/dist/* build/Lully.app/Contents/Resources/UI/
cat > build/Lully.app/Contents/Resources/UI/index.html <<'HTML'
<!doctype html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; font-src 'self' data:; img-src 'self' data:; connect-src 'none'; base-uri 'none'; form-action 'none'"><title>Lully</title><style>html,body{margin:0;background:#171b19;color:#e9eeeb;font:14px sans-serif}#root>p{padding:24px}</style><link rel="stylesheet" href="./lully-ui.css"></head><body><div id="root"><p>Opening Lully…</p></div><script src="./lully.js"></script></body></html>
HTML
if [ "${LULLY_BUNDLE_KEY:-1}" = "1" ] && [ -f .local-secrets/openai.key ]; then
  cp .local-secrets/openai.key build/Lully.app/Contents/Resources/openai.key
  chmod 600 build/Lully.app/Contents/Resources/openai.key
else
  rm -f build/Lully.app/Contents/Resources/openai.key
fi
python3 scripts/sign-local.py build/Lully.app
printf 'Built %s/build/Lully.app\n' "$PWD"
