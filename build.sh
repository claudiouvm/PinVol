#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/PinVol.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/PinVol "$APP/Contents/MacOS/PinVol"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
strip -x "$APP/Contents/MacOS/PinVol"
codesign --force --sign - "$APP"
echo "OK -> $PWD/$APP ($(du -sh "$APP" | cut -f1))"

# ./build.sh install → instala en /Applications (macOS solo muestra el ícono de la barra de menús si la app está ahí)
if [[ "${1:-}" == "install" ]]; then
  pkill -f "/Applications/PinVol.app/Contents/MacOS/PinVol" || true
  sleep 1
  rm -rf /Applications/PinVol.app
  ditto "$APP" /Applications/PinVol.app
  echo "Instalada en /Applications/PinVol.app"
  open /Applications/PinVol.app
fi
