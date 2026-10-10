#!/bin/zsh
# Solo desarrollo: compila con -DSNAPSHOT y genera PNGs de la ventana, en claro y oscuro y en cada idioma.
# Salida: <carpeta>/<idioma>/<nombre>.png (por defecto build/snapshots/en y build/snapshots/es; LANGS="en" para uno solo).
set -euo pipefail
cd "$(dirname "$0")"
OUT=${1:-build/snapshots}
LANGS=${LANGS:-"en es"}
mkdir -p "$OUT"
swift build -c release -Xswiftc -DSNAPSHOT --scratch-path .build-snap 2>&1 | grep -E "error|warning: unre|Compiling|Build" | grep -v "^\[" | tail -5
APP=build/PinVol-snap.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build-snap/release/PinVol "$APP/Contents/MacOS/PinVol"
cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.claudiouvm.pinvol.dev" "$APP/Contents/Info.plist"   # ajustes y permisos aparte de la app real
cp -R Resources/* "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null 2>&1
BIN="$APP/Contents/MacOS/PinVol"

# Una captura en el idioma de la variable `lang` (como si el Mac estuviera en ese idioma).
# En macOS 26 el servicio de íconos genera bajo demanda (y por separado para claro y oscuro) los de las apps recién
# instaladas, y hasta entonces dibuja cuadros punteados. El binario comprueba que los íconos de la ventana estén de verdad
# y, si no, sale con código 3 sin capturar: aquí se repite en un proceso nuevo (hasta 30 veces, cada 2 s). Si aun así no se
# generan, se captura igual con --force y se avisa.
run() {
  local name=$1 code=0 msg=""; shift
  for attempt in {1..30}; do
    msg=$("$BIN" -AppleLanguages "($lang)" --snapshot "$OUT/$lang/$name.png" "$@" 2>&1) && code=0 || code=$?
    if [[ $code -ne 3 ]]; then break; fi
    echo "  $lang/$name, intento $attempt: ${msg##*$'\n'}"
    sleep 2
  done
  if [[ $code -eq 3 ]]; then
    echo "aviso: $lang/$name con íconos sin generar tras 30 intentos"
    "$BIN" -AppleLanguages "($lang)" --snapshot "$OUT/$lang/$name.png" --force "$@" >/dev/null 2>&1 && code=0 || code=$?
  fi
  if [[ $code -ne 0 ]]; then echo "falló $lang/$name"; fi
}

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

for lang in ${=LANGS}; do
  mkdir -p "$OUT/$lang"
  run light-empty
  run light-assigned   --assigned com.apple.Music --level 0.45 --gains $ONE --on --status active
  run light-five       --assigned $APPS --level $LEVELS --gains $FIVE --on --status active
  run light-settings   --tab settings
  run light-about      --tab about
  run light-update     --assigned com.apple.Music --level 0.45 --gains $ONE --on --update available --status active
  run light-update-downloading --assigned com.apple.Music --level 0.45 --gains $ONE --on --update downloading --status active
  run light-update-ready       --assigned com.apple.Music --level 0.45 --gains $ONE --on --update ready --status active
  run light-about-update       --tab about --update ready
  run dark-empty       --dark
  run dark-assigned    --dark --assigned com.apple.Music --level 0.45 --gains $ONE --on --status active
  run dark-five        --dark --assigned $APPS --level $LEVELS --gains $FIVE --on --status active
  run dark-about       --dark --tab about
  run light-waiting    --assigned com.apple.Music --level 0.8 --on --status waiting
  run light-error      --assigned com.apple.Music --level 0.8 --on --status error
done
ls -R "$OUT"
