# Desarrollo

*English: [DEVELOPMENT.md](DEVELOPMENT.md)*

## Cómo funciona

macOS no tiene volumen por app. PinVol usa las **Core Audio process taps** (`AudioHardwareCreateProcessTap`, macOS 14.2+):

1. Crea un tap sobre los procesos de la app (incluidos sus procesos auxiliares: coincide por prefijo del bundle id, algo necesario en navegadores y apps Electron). El audio original queda silenciado. Cada app fijada tiene su propio tap y su propio nivel; si dos apps comparten prefijo (`com.google.Chrome` y `com.google.Chrome.canary`), los procesos van a la más específica.
2. Reproduce ese audio por un dispositivo agregado privado, aplicando una ganancia.
3. La ganancia es `nivel fijo ÷ volumen del sistema`, recalculada cada vez que cambia el volumen o el mute, con un limitador suave y un máximo de +24 dB.

El detalle importante está en cómo se miden los decibeles. La conversión estándar escalar→dB que expone Core Audio **no coincide con la curva real** que aplica el sistema (en los Mac con altavoces integrados es cuadrática: `dB = −63.5 × (1 − √volumen)`). Usarla hace que la app suba o baje al mover el volumen. PinVol lee los dB reales del dispositivo (`kAudioDevicePropertyVolumeDecibels`) e invierte la conversión dB→escalar del propio dispositivo para traducir el nivel del slider.

## Arquitectura

PinVol corre como **dos instancias de la misma app**:

- **Residente**: Dock y barra de menús, motores de audio y ajustes guardados. Siempre viva.
- **Interfaz** (`--ui`): muestra la ventana y termina al cerrarla.

Se comunican con `DistributedNotificationCenter`. La razón es la memoria: abrir una ventana hace que AppKit reserve unos 8 MB para dibujarla, más 5–7 MB por los interruptores y el slider nativos, y el sistema no los devuelve aunque cierres la ventana. Con la ventana en otro proceso, esa memoria se libera al cerrarla. Con la ventana cerrada, el proceso residente ocupa unos 15–20 MB; mientras está abierta, la instancia de interfaz suma unos 22–25 MB más.

Todos los controles son nativos de AppKit (`NSSwitch`, `NSSlider`, símbolos SF) y respetan el modo claro y oscuro.

El código está en `Sources/PinVol/`, repartido por responsabilidad:

| Archivo | Contenido |
|---|---|
| `main.swift` | Instancia residente (Dock, barra de menús) y arranque |
| `UIDelegate.swift` | Instancia de interfaz (`--ui`) y menú principal |
| `Controller.swift` | Estado guardado, un `Engine` por app, mensajes de la interfaz y comprobación de versión |
| `Audio.swift` | Core Audio: tap, dispositivo agregado, ganancia, volumen del sistema |
| `Model.swift` | `AppState`, `PinnedApp`, mensajería entre procesos |
| `SettingsWindow.swift` | Ventana con pestañas (Apps, Ajustes, Acerca de) y su animación de tamaño |
| `AppsPanel.swift` | Zona de arrastre y filas de apps |
| `Style.swift` | Etiquetas, tarjetas y filas de ajustes compartidas |
| `Updates.swift` | Consulta de la última release en GitHub |
| `Snapshot.swift` | Solo desarrollo: capturas de la ventana |

## Comandos

| Comando | Qué hace |
|---|---|
| `./build.sh` | Compila y genera `build/PinVol.app` (solo Apple Silicon: se niega a correr en Intel o bajo Rosetta) |
| `./build.sh install` | Además la instala en `/Applications` y la abre |
| `tools/make-dmg.sh` | Compila la app arm64 y genera `dist/PinVol.dmg` (falla si el binario no es solo arm64) |
| `./snapshot.sh` | Compila una variante de desarrollo y genera capturas PNG de la ventana (claro/oscuro, 1 y 5 apps, cada pestaña) en `build/snapshots/`, sin necesitar permiso de grabación de pantalla |
| `python3 tools/make-icon.py` | Regenera `Resources/AppIcon.icns` y los glifos de la barra de menús (`MenuBar*Template*.png`). Todo está dibujado en código; requiere `pip3 install pillow` |

Las capturas de la portada (`docs/apps-claro.png`, `docs/apps-oscuro.png`) salen del workflow manual `Screenshots`, que instala Spotify, IINA y TIDAL en el runner para que aparezcan sus íconos y nombres reales; copia `light-five.png` y `dark-five.png` de su artefacto `capturas-portada`. Las ganancias de los mockups (por ejemplo −2,3 dB o +11,9 dB) son las reales: `snapshot.sh` las calcula con la fórmula del motor, `dB(nivel fijo) − dB(volumen del sistema)`, sobre la curva cuadrática de los altavoces y con el volumen del sistema al 50 % (`SYSTEM=0.4 ./snapshot.sh` para cambiarlo).

`snapshot.sh` compila con `-DSNAPSHOT` y usa otro identificador (`com.claudiouvm.pinvol.dev`), así que no toca los ajustes ni los permisos de la app real.

## Actualizaciones y releases

PinVol consulta una vez al día (y cuando lo pides en **Acerca de**) la última release de GitHub y la compara con su versión. Si hay una nueva, muestra un aviso en la ventana y una entrada en el menú que abre la página de la release; no descarga ni instala nada. Se puede apagar en **Ajustes**. La consulta usa la API pública de GitHub, así que el repositorio debe ser público.

Para publicar una versión: sube `CFBundleShortVersionString` (y `CFBundleVersion`) en `Info.plist`, actualiza `RELEASE_NOTES.md` (inglés y después español; el CI exige que su primera línea nombre la versión) y haz merge a `main`. El workflow `Release` compila el `.dmg` arm64, lo guarda en `dist/PinVol.dmg` y crea la release `v<versión>` con esas notas si todavía no existe. Si solo cambias las notas, ejecuta el workflow manual `Release notes` para copiarlas a la release existente.

Para etiquetar una versión como beta, añade `PinVolReleaseChannel` = `Beta` en `Info.plist` (se muestra en Acerca de y en el título de la release). No marques la release como «pre-release» en GitHub: la API `releases/latest`, que usa la app, ignora las pre-release.

## Límites conocidos

- Solo Apple Silicon (arm64) y macOS 26 (Tahoe) o posterior. La API de process taps existe desde macOS 14.2, pero esa no es la versión en que PinVol se compila y prueba. Los Mac Intel y las versiones anteriores de macOS no están soportados (usa la [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2) en macOS 14.2–15, o la [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1) en Intel).
- El máximo es de 5 apps a la vez (`maxPinnedApps` en `Model.swift`): cada una abre su propio tap y su propio dispositivo agregado.
- Con el volumen del sistema muy bajo y un nivel fijo alto, la ganancia llega al máximo (+24 dB) y ya no se puede compensar más; la línea de estado lo indica.
- En salidas sin control de volumen por software (algunas HDMI o USB) no hay nada que compensar y la app lo avisa.
- Las apps con DRM o procesos protegidos pueden no ser capturables.
- El `.dmg` no está notarizado (haría falta una cuenta de desarrollador de Apple).
- Al estar firmada ad-hoc, cada recompilación cambia la firma y macOS puede volver a pedir el permiso de audio.
