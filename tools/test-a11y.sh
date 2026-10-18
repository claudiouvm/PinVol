#!/bin/zsh
# Solo desarrollo y CI: comprueba el contraste de los colores propios y la accesibilidad de la ventana.
# Lo ejecuta el workflow Release en macOS. No necesita permisos de grabación ni pantalla.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release -Xswiftc -DSNAPSHOT --scratch-path .build-a11y 2>&1 | tail -1

APP=build/PinVol-a11y.app
BIN="$APP/Contents/MacOS/PinVol"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build-a11y/release/PinVol "$BIN"
cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.claudiouvm.pinvol.a11y" "$APP/Contents/Info.plist" >/dev/null
cp -R Resources/* "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null 2>&1

echo "— contraste —"
"$BIN" --selftest-contrast

echo "— accesibilidad (escala normal) —"
"$BIN" --selftest-a11y

echo "— accesibilidad (texto al 150 %) —"
PV_TEXT_SCALE=1.5 "$BIN" --selftest-a11y

echo "OK: pruebas de accesibilidad y contraste"
