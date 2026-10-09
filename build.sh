#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
# PinVol es solo para Apple Silicon: no se genera binario x86_64.
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "PinVol solo se compila para Apple Silicon (arm64). Usa un Mac con Apple Silicon y una terminal nativa, sin Rosetta." >&2
  exit 1
fi
swift build -c release
APP=build/PinVol.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/PinVol "$APP/Contents/MacOS/PinVol"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/* "$APP/Contents/Resources/"   # ícono de la app y glifos de la barra de menús
strip -x "$APP/Contents/MacOS/PinVol"
codesign --force --sign - "$APP"
echo "OK -> $PWD/$APP ($(du -sh "$APP" | cut -f1))"

# ./build.sh install → instala en /Applications (macOS solo muestra el ícono de la barra de menús si la app está ahí)
if [[ "${1:-}" == "install" ]]; then
  pkill -f "/Applications/PinVol.app/Contents/MacOS/PinVol" || true
  sleep 1
  rm -rf /Applications/PinVol.app
  ditto "$APP" /Applications/PinVol.app
  # Launch Services guarda el ícono de cada app registrada. Sin esto, Ajustes del Sistema (ítems de inicio,
  # barra de menús, grabación de audio) y el Dock pueden seguir mostrando un ícono anterior o el de build/.
  LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -u "$PWD/$APP" || true
    "$LSREGISTER" -f /Applications/PinVol.app || true
  fi
  touch /Applications/PinVol.app
  echo "Instalada en /Applications/PinVol.app"
  open /Applications/PinVol.app
fi
