#!/bin/zsh
# Prueba, en un macOS de verdad, que se puede instalar una actualización: monta el .dmg recién generado, comprueba la app de
# dentro, la intercambia por una «instalada» más vieja y no deja restos ni imágenes montadas. Usa la variante de capturas del
# binario (-DSNAPSHOT), que trae `--selftest-install` (ver Sources/PinVol/SelfTest.swift).
# Hay que haber compilado antes: tools/make-dmg.sh y `swift build -c release -Xswiftc -DSNAPSHOT --scratch-path .build-snap`.
#   tools/test-install.sh
set -euo pipefail
cd "$(dirname "$0")/.."
BIN=.build-snap/release/PinVol
APP=build/PinVol.app
DMG=dist/PinVol.dmg
[[ -x "$BIN" && -d "$APP" && -f "$DMG" ]] || { echo "Faltan $BIN, $APP o $DMG: compila antes" >&2; exit 1; }

PB=/usr/libexec/PlistBuddy
VER=$($PB -c "Print :CFBundleShortVersionString" Info.plist)
ID=$($PB -c "Print :CFBundleIdentifier" Info.plist)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# Una app «instalada» más vieja: la misma, con la versión 0.0.1 (se vuelve a firmar, como en un build de verdad).
mkdir -p "$T/Applications"
ditto "$APP" "$T/Applications/PinVol.app"
$PB -c "Set :CFBundleShortVersionString 0.0.1" "$T/Applications/PinVol.app/Contents/Info.plist"
codesign --force --sign - "$T/Applications/PinVol.app" >/dev/null 2>&1
# Con la marca de cuarentena que dejaría un navegador: la app nueva no debe quedarse con ella.
xattr -w com.apple.quarantine "0083;5f3e0000;Safari;" "$T/Applications/PinVol.app"
[[ -n "$(xattr -p com.apple.quarantine "$T/Applications/PinVol.app" 2>/dev/null)" ]] || { echo "No se pudo marcar con la cuarentena la app «instalada»" >&2; exit 1; }

if ! "$BIN" --selftest-install "$DMG" "$T/Applications/PinVol.app" "$ID" "$VER" "0.0.1"; then
  echo "--- estado tras la prueba ---" >&2
  ls -la "$T/Applications" >&2 || true
  $PB -c "Print :CFBundleShortVersionString" "$T/Applications/PinVol.app/Contents/Info.plist" >&2 || true
  hdiutil info >&2 || true
  exit 1
fi

NEW=$($PB -c "Print :CFBundleShortVersionString" "$T/Applications/PinVol.app/Contents/Info.plist")
[[ "$NEW" == "$VER" ]] || { echo "La app instalada es la $NEW y debería ser la $VER" >&2; exit 1; }
codesign --verify --deep --strict "$T/Applications/PinVol.app"
if [[ -n "$(xattr -p com.apple.quarantine "$T/Applications/PinVol.app" 2>/dev/null)" ]]; then
  echo "La app instalada conserva la marca de cuarentena" >&2
  exit 1
fi
INFO=$(hdiutil info)
[[ "$INFO" != *"/Updates/mount-"* ]] || { echo "Quedó una imagen montada" >&2; echo "$INFO" >&2; exit 1; }
echo "OK: la instalación de la $VER funciona (app firmada, sin cuarentena, sin restos ni imágenes montadas)"
