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
# Apps de ejemplo para las capturas de 5 apps (todas con audio). Si no están instaladas salen con el nombre del bundle id.
# Se pueden cambiar: APPS=com.apple.Music,com.apple.Safari,... ./snapshot.sh
APPS=${APPS:-com.apple.Music,com.apple.Safari,com.spotify.client,com.colliderli.iina,com.tidal.desktop}
LEVELS=0.45,0.8,0.3,0.6,0.15

# Ganancia real que mostraría cada app con el volumen del sistema al SYSTEM (50 % por defecto).
# Misma cuenta que el motor: dB(nivel fijo) − dB(volumen del sistema), con la curva de los altavoces del Mac,
# que es cuadrática: dB = −63.5 × (1 − √volumen). Con 50 %: 0.45 → −2.3 dB, 0.8 → +11.9 dB, 0.3 → −10.1 dB…
SYSTEM=${SYSTEM:-0.5}
gains() { awk -v sys="$SYSTEM" -v levels="$1" 'function db(v) { return -63.5 * (1 - sqrt(v)) } BEGIN { n = split(levels, a, ","); for (i = 1; i <= n; i++) printf "%s%.1f", (i > 1 ? "," : ""), db(a[i]) - db(sys) }'; }
FIVE=$(gains $LEVELS)
ONE=$(gains 0.45)

# En macOS 26 el servicio de íconos tarda unos segundos en generar los de apps recién instaladas: sin esto, las primeras
# capturas salen con cuadros punteados. Se repite una captura de calentamiento (se descarta) hasta que dos seguidas
# son idénticas, con un máximo de 10 intentos.
prev=""
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  "$BIN" --snapshot "$OUT/warmup.png" --assigned $APPS --level $LEVELS >/dev/null 2>&1 || true
  if [[ -n "$prev" ]] && cmp -s "$OUT/warmup.png" "$prev"; then break; fi
  cp "$OUT/warmup.png" "$OUT/warmup-prev.png"; prev="$OUT/warmup-prev.png"
  sleep 2
done
rm -f "$OUT/warmup.png" "$OUT/warmup-prev.png"

run light-empty
run light-assigned   --assigned com.apple.Music --level 0.45 --gains $ONE --on --status active
run light-five       --assigned $APPS --level $LEVELS --gains $FIVE --on --status active
run light-settings   --tab settings
run light-about      --tab about
run light-update     --assigned com.apple.Music --level 0.45 --gains $ONE --on --update available --status active
run dark-empty       --dark
run dark-assigned    --dark --assigned com.apple.Music --level 0.45 --gains $ONE --on --status active
run dark-five        --dark --assigned $APPS --level $LEVELS --gains $FIVE --on --status active
run dark-about       --dark --tab about
run light-waiting    --assigned com.apple.Music --level 0.8 --on --status waiting --text "Esperando audio de la app…"
run light-error      --assigned com.apple.Music --level 0.8 --on --status error --text "Error de audio (-1). ¿Concediste el permiso de audio?"
ls "$OUT"
