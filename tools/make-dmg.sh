#!/bin/zsh
# Genera dist/PinVol.dmg: compila la app (solo Apple Silicon, arm64) y la empaqueta
# con un acceso directo a /Applications para instalarla arrastrando.
#   tools/make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh    # compila y firma build/PinVol.app (falla si no es un Mac con Apple Silicon)
APP=build/PinVol.app
BIN="$APP/Contents/MacOS/PinVol"
ARCHS="$(lipo -archs "$BIN")"
[[ "$ARCHS" == "arm64" ]] || { echo "El binario debe ser solo arm64 y es: $ARCHS" >&2; exit 1; }
echo "Arquitectura: $ARCHS"

VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
CHANNEL=$(/usr/libexec/PlistBuddy -c "Print :PinVolReleaseChannel" Info.plist 2>/dev/null || true)
STAGE=$(mktemp -d)
ditto "$APP" "$STAGE/PinVol.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/README.txt" <<TXT
PinVol ${CHANNEL:+$CHANNEL }$VER

ENGLISH
Requires a Mac with Apple Silicon (M1 or later) and macOS 26 (Tahoe) or later.
1. Drag PinVol to the Applications folder.
2. Open it. The first time it captures an app's audio, macOS asks for the
   "System Audio Recording" permission.
If macOS says the app is "damaged" or can't be opened (it is ad-hoc signed, not
notarized by Apple), open Terminal and run:

   xattr -dr com.apple.quarantine /Applications/PinVol.app

ESPAÑOL
Requiere un Mac con Apple Silicon (M1 o posterior) y macOS 26 (Tahoe) o posterior.
1. Arrastra PinVol a la carpeta Aplicaciones.
2. Ábrela. La primera vez que capture el audio de una app, macOS pide el permiso
   «Grabación de audio del sistema».
Si macOS dice que la app «está dañada» o que no se puede abrir (está firmada
ad-hoc, no notarizada por Apple), abre Terminal y ejecuta:

   xattr -dr com.apple.quarantine /Applications/PinVol.app
TXT

mkdir -p dist
rm -f dist/PinVol.dmg
for attempt in 1 2 3; do   # hdiutil a veces falla con «Resource busy»
  hdiutil create -volname "PinVol $VER" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov dist/PinVol.dmg && break
  [[ $attempt == 3 ]] && { echo "hdiutil falló"; exit 1; }
  sleep 3
done
rm -rf "$STAGE"
echo "OK -> $PWD/dist/PinVol.dmg ($(du -h dist/PinVol.dmg | cut -f1))"
