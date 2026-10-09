#!/bin/zsh
# Solo desarrollo: compila con -DSNAPSHOT y genera PNGs de la ventana en claro/oscuro.
set -euo pipefail
cd "$(dirname "$0")"
OUT=${1:-build/snapshots}
mkdir -p "$OUT"
swift build -c release -Xswiftc -DSNAPSHOT --scratch-path .build-snap 2>&1 | grep -E "error|warning: unre|Compiling|Build" | grep -v "^\[" | tail -5
APP=build/PinVol-snap.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build-snap/release/PinVol "$APP/Contents/MacOS/PinVol"
cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.claudiouvm.pinvol.dev" "$APP/Contents/Info.plist"   # ajustes y permisos aparte de la app real
cp Resources/* "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null 2>&1
BIN="$APP/Contents/MacOS/PinVol"
run() { name=$1; shift; "$BIN" --snapshot "$OUT/$name.png" "$@" >/dev/null 2>&1 || echo "falló $name"; }
run light-empty
run light-assigned   --assigned com.apple.Music --level 0.45 --on --status active --text "Activo · +6.2 dB"
run dark-empty       --dark
run dark-assigned    --dark --assigned com.apple.Music --level 0.45 --on --status active --text "Activo · +6.2 dB"
run light-waiting    --assigned com.apple.Music --level 0.8 --on --status waiting --text "Esperando audio de la app…"
run light-error      --assigned com.apple.Music --level 0.8 --on --status error --text "Error de audio (-1). ¿Concediste el permiso de audio?"
ls "$OUT"
