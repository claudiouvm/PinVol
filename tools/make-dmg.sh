#!/bin/zsh
# Genera dist/PinVol.dmg: compila la app (binario universal arm64 + x86_64) y la empaqueta
# con un acceso directo a /Applications para instalarla arrastrando.
#   tools/make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh    # compila para la arquitectura de esta máquina → build/PinVol.app
APP=build/PinVol.app
BIN="$APP/Contents/MacOS/PinVol"

# Añade la otra arquitectura para que la app corra en Mac con Apple Silicon e Intel.
for ARCH in arm64 x86_64; do
  [[ "$(lipo -archs "$BIN")" == *"$ARCH"* ]] && continue
  TRIPLE="$ARCH-apple-macosx14.2"
  swift build -c release --triple "$TRIPLE" --scratch-path ".build-$ARCH"
  OTHER="$(swift build -c release --triple "$TRIPLE" --scratch-path ".build-$ARCH" --show-bin-path)/PinVol"
  lipo -create "$BIN" "$OTHER" -output "$BIN.universal"
  mv "$BIN.universal" "$BIN"
done
strip -x "$BIN"
codesign --force --sign - "$APP"
echo "Arquitecturas: $(lipo -archs "$BIN")"

VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
STAGE=$(mktemp -d)
ditto "$APP" "$STAGE/PinVol.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/LEEME.txt" <<TXT
PinVol $VER

1. Arrastra PinVol a la carpeta Aplicaciones.
2. Ábrela. La primera vez que capture el audio de una app, macOS pide el permiso
   «Grabación de audio del sistema».

Si macOS dice que la app «está dañada» o que no se puede abrir (la app no está
notarizada por Apple, solo firmada ad-hoc), abre Terminal y ejecuta:

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
