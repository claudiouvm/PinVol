# Desarrollo

*English: [DEVELOPMENT.md](DEVELOPMENT.md)*

## Requisitos

Para compilar PinVol necesitas:

- Un Mac con **Apple Silicon** (M1 o posterior), con **macOS 26 (Tahoe)** o posterior. `build.sh` se niega a correr en Intel o bajo Rosetta, porque la app es solo arm64.
- **Xcode 26** o sus herramientas de línea de comandos (Swift 6.2): la app apunta a macOS 26 (`Package.swift`) y se compila con ese SDK, tanto en el CI como en las releases. El paquete en sí declara `swift-tools-version:5.9` y se compila en modo de lenguaje Swift 5.
- Ninguna dependencia externa. Solo `tools/make-icon.py` necesita más: Python 3 y Pillow (`pip3 install pillow`).

## Cómo funciona

macOS no tiene volumen por app. PinVol usa las **Core Audio process taps** (`AudioHardwareCreateProcessTap`, una API que existe desde macOS 14.2; PinVol en sí requiere macOS 26):

1. Crea un tap sobre los procesos de la app (incluidos sus procesos auxiliares: coincide por prefijo del bundle id, algo necesario en navegadores y apps Electron). El audio original queda silenciado. Cada app fijada tiene su propio tap y su propio nivel; si dos apps comparten prefijo (`com.google.Chrome` y `com.google.Chrome.canary`), los procesos van a la más específica.
2. Reproduce ese audio por un dispositivo agregado privado, aplicando una ganancia.
3. La ganancia es `nivel fijo ÷ volumen del sistema`, recalculada cada vez que cambia el volumen o el mute, con un limitador suave y un máximo de +24 dB.

El detalle importante está en cómo se miden los decibeles. La conversión estándar escalar→dB que expone Core Audio **no coincide con la curva real** que aplica el sistema (en los Mac con altavoces integrados es cuadrática: `dB = −63.5 × (1 − √volumen)`). Usarla hace que la app suba o baje al mover el volumen. PinVol lee los dB reales del dispositivo (`kAudioDevicePropertyVolumeDecibels`) e invierte la conversión dB→escalar del propio dispositivo para traducir el nivel del slider.

## Arquitectura

PinVol corre como **dos instancias de la misma app**:

- **Residente**: Dock y barra de menús, motores de audio y ajustes guardados. Siempre viva.
- **Interfaz** (`--ui`): muestra la ventana y termina al cerrarla.

Se comunican con `DistributedNotificationCenter`. La razón es la memoria: abrir una ventana hace que AppKit reserve unos 8 MB para dibujarla, más 5–7 MB por los interruptores y el slider nativos, y el sistema no los devuelve aunque cierres la ventana. Con la ventana en otro proceso, esa memoria se libera al cerrarla. Con la ventana cerrada, el proceso residente ocupa unos 15–20 MB; mientras está abierta, la instancia de interfaz suma unos 22–25 MB más. Estas cifras se midieron con la versión original, de una sola app, y no se han vuelto a medir con cinco apps ni en macOS 26.

La instancia residente abre la ventana lanzando la de interfaz con `--ui` (o, si ya está abierta, mandándole un aviso `show`). Para abrirla en una pestaña concreta —**Acerca de PinVol** en el menú del ícono de la barra abre la pestaña Acerca de— el arranque añade `--tab about` y el aviso lleva un campo `tab` (`openWindow` en `main.swift`, `UIDelegate`).

Todos los controles son nativos de AppKit (`NSSwitch`, `NSSlider`, símbolos SF). Respetan el modo claro y oscuro y, como la app se compila con el SDK de macOS 26, el aspecto actual del sistema.

El código está en `Sources/PinVol/`, repartido por responsabilidad:

| Archivo | Contenido |
|---|---|
| `main.swift` | Instancia residente (Dock, barra de menús) y arranque |
| `UIDelegate.swift` | Instancia de interfaz (`--ui`) y menú principal |
| `Controller.swift` | Estado guardado, un `Engine` por app, mensajes de la interfaz y comprobación de versión |
| `Audio.swift` | Core Audio: tap, dispositivo agregado, ganancia, volumen del sistema |
| `Model.swift` | `AppState`, `PinnedApp`, mensajería entre procesos |
| `SettingsWindow.swift` | Ventana con pestañas (Apps, Ajustes, Acerca de) y su animación de tamaño. El botón **¡Invítame un café!** de Acerca de abre la página de Ko-fi (`donateURL`) |
| `AppsPanel.swift` | Zona de arrastre y filas de apps |
| `Style.swift` | Etiquetas, tarjetas y filas de ajustes compartidas |
| `Strings.swift` | Textos de la interfaz (`L("…")`) y formatos de números según el idioma |
| `Updates.swift` | Consulta de la última release en GitHub (versión, `.dmg` y su huella) |
| `Installer.swift` | Descarga e instalación de una versión nueva (solo la instancia residente) |
| `Snapshot.swift` | Solo desarrollo: capturas de la ventana |
| `SelfTest.swift` | Solo desarrollo: `--selftest-install`, la prueba del instalador de actualizaciones que ejecuta el CI |

## Inicio al encender el Mac

Cuando «Abrir al iniciar sesión» abre PinVol (por ejemplo al encender el Mac) y ya hay al menos una app fijada (`Controller.isConfigured`), la instancia residente pasa directo a la barra de menús, o al Dock si el ícono de la barra está desactivado, y no abre la ventana. Si el usuario abre la app, o mientras no haya nada fijado, la ventana se abre como siempre.

macOS marca en el evento de apertura que la app se abrió como elemento de inicio de sesión, pero no siempre, así que hay un respaldo: un arranque pocos segundos después de que empezara la sesión del usuario (la hora de arranque de su proceso `loginwindow`) también cuenta como arranque de inicio: dentro del primer minuto con «Abrir al iniciar sesión» activado, y de 25 segundos si no, para no confundirlo con una apertura manual justo después de iniciar sesión. Si no se encuentra la sesión, solo cuenta un Mac encendido hace menos de dos minutos, y solo con «Abrir al iniciar sesión» activado. Por lo mismo, se ignora un aviso de reapertura en los primeros 10 segundos. La decisión queda en el registro: `log show --last 10m --predicate 'subsystem == "com.claudiouvm.pinvol"'`.

## Idiomas

La interfaz está en inglés y en español y sigue el idioma del Mac: en español si es el idioma preferido, y en inglés en cualquier otro caso (el inglés es también el idioma de reserva).

- Todo texto visible pasa por `L("English text")` (`Strings.swift`): el texto en inglés es la clave. `Resources/es.lproj/Localizable.strings` tiene la traducción al español, e `InfoPlist.strings` (en `en.lproj` y `es.lproj`) los textos localizados de `Info.plist`, como el aviso del permiso de audio. Los formatos usan `%@` y `%ld`.
- Los números siguen el idioma de la interfaz, no el de la región del Mac: `45%` y `+11.9 dB` en inglés, `45 %` y `+11,9 dB` en español.
- Para añadir un texto, usa `L("…")` en el código y añade su línea a `es.lproj/Localizable.strings`. `tools/check-strings.py` (que también ejecuta el CI) falla si un texto no tiene traducción, si una traducción ya no se usa o si los especificadores de formato no coinciden.
- Para añadir un idioma, crea `Resources/<código>.lproj/` con los mismos dos archivos y añade el código a `CFBundleLocalizations` en `Info.plist`; el script lo comprueba todo.
- Para probar un idioma sin cambiar el del Mac, ejecuta el binario con `-AppleLanguages "(es)"`, o ponlo solo para PinVol en Ajustes del Sistema → General → Idioma y región → Aplicaciones.
- La instancia residente escribe los textos de estado, así que conserva el idioma con el que arrancó: tras cambiar el idioma del Mac, cierra PinVol y ábrela de nuevo.

## Comandos

| Comando | Qué hace |
|---|---|
| `./build.sh` | Compila y genera `build/PinVol.app` (solo Apple Silicon: se niega a correr en Intel o bajo Rosetta) |
| `./build.sh install` | Además la instala en `/Applications` y la abre |
| `tools/make-dmg.sh` | Compila la app arm64 y genera `dist/PinVol.dmg` (falla si el binario no es solo arm64) |
| `./snapshot.sh` | Compila una variante de desarrollo y genera capturas PNG de la ventana (claro/oscuro, 1 y 5 apps, cada pestaña) en inglés y en español, en `build/snapshots/en` y `build/snapshots/es`, sin necesitar permiso de grabación de pantalla |
| `python3 tools/check-strings.py` | Comprueba que cada texto de la interfaz tenga su traducción (el CI también lo ejecuta; no necesita un Mac) |
| `tools/test-install.sh` | Prueba el instalador de actualizaciones en un macOS de verdad: monta el `.dmg` recién generado y cambia por él una app «instalada» más vieja (con la marca de cuarentena, como la deja un navegador), y comprueba que la nueva no conserva la marca (hay que ejecutar antes `tools/make-dmg.sh` y la compilación `-DSNAPSHOT`; el CI lo ejecuta) |
| `python3 tools/make-icon.py` | Regenera `Resources/AppIcon.icns` y los glifos de la barra de menús (`MenuBar*Template*.png`). Todo está dibujado en código |

`snapshot.sh` compila con `-DSNAPSHOT` y usa otro identificador (`com.claudiouvm.pinvol.dev`), así que no toca los ajustes ni los permisos de la app real. Las opciones del binario de desarrollo están listadas al principio de `Snapshot.swift`. El script se ajusta con variables de entorno:

- `APPS=com.apple.Music,com.apple.Safari,… ./snapshot.sh` elige las cinco apps de los mockups. Por defecto son Music, Safari, Spotify, IINA y TIDAL, todas con audio; si alguna no está instalada, sale con su bundle id.
- `SYSTEM=0.4 ./snapshot.sh` fija el volumen del sistema que suponen los mockups (50 % por defecto). Las ganancias que se muestran (por ejemplo −2,3 dB o +11,9 dB) son las reales: el script las calcula con la fórmula del motor, `dB(nivel fijo) − dB(volumen del sistema)`, sobre la curva cuadrática de los altavoces.
- `LANGS=es ./snapshot.sh` genera un solo idioma (por defecto `en es`). El binario de desarrollo toma el idioma de `-AppleLanguages "(es)"`, como cualquier app.
- En macOS 26 el sistema genera bajo demanda los íconos de las apps recién instaladas (por separado para claro y oscuro) y dibuja un cuadro punteado hasta que están listos. Por eso, antes de capturar, el binario de desarrollo dibuja cada ícono de la ventana y comprueba que no sea ese cuadro; si lo es, sale con código 3 y el script repite la captura en un proceso nuevo (hasta 30 veces, cada 2 s), y como último recurso captura igual con `--force` y avisa.

## CI

Todos los workflows corren en el runner `macos-26` (Apple Silicon, Xcode 26) salvo el último.

| Workflow | Cuándo | Qué hace |
|---|---|---|
| `Release` (`release.yml`) | Pull requests y pushes a `main` (se omite si solo cambian `dist/`, `docs/`, archivos `.md` o `.github/FUNDING.yml`) | Comprueba las traducciones (`tools/check-strings.py`). Compila también la variante de capturas, para comprobar el código de `-DSNAPSHOT`. Genera el `.dmg` arm64 y comprueba `Info.plist`, el ícono, los recursos del paquete, que el binario sea solo arm64 y que `RELEASE_NOTES.md` nombre la versión. Prueba el instalador de actualizaciones (`tools/test-install.sh`). Sube los artefactos `PinVol-dmg` y `capturas`. En `main` además commitea `dist/PinVol.dmg` (un commit del bot marcado `[skip ci]`) y crea la release `v<versión>` si todavía no existe. |
| `Screenshots` (`screenshots.yml`) | A mano, o en un pull request que cambie `snapshot.sh` o el propio workflow | Instala Spotify, IINA y TIDAL, toma las capturas (en inglés y en español) y las sube como `capturas-portada`. Las imágenes de la portada son `en/light-five.png` y `en/dark-five.png` de ese artefacto (`docs/apps-claro.png` y `docs/apps-oscuro.png`, para `README.md`) y `es/light-five.png` y `es/dark-five.png` (`docs/apps-claro.es.png` y `docs/apps-oscuro.es.png`, para `README.es.md`). |
| `Release notes` (`release-notes.yml`, `ubuntu-latest`) | A mano | Copia `RELEASE_NOTES.md` a la release de la versión de `Info.plist`. Con las entradas `tag` y `notes` (siempre juntas) reemplaza en cambio las notas de otra release con el texto que le pases. |

Swift no se puede compilar en Linux, así que el CI es la compilación real. Los artefactos son la forma de revisar el diseño de la ventana.

## Actualizaciones y releases

PinVol consulta una vez al día (y cuando lo pides en **Acerca de**, o con **Buscar actualizaciones…** en el menú del ícono de la barra) la última release de GitHub y la compara con su versión. Si hay una nueva, muestra un aviso en la ventana y una entrada en el menú; no se descarga ni instala nada hasta que el usuario lo pide (ver más abajo). Se puede apagar en **Ajustes**. Desde la barra de menús la instancia residente no tiene ventana donde mostrar el resultado, así que aparece junto al ícono unos segundos (`noteInMenuBar` en `main.swift`). La consulta usa la API pública de GitHub, así que el repositorio debe ser público.

**Instalación desde la app.** **Descargar** (aviso, Acerca de o el menú del ícono de la barra) baja el `PinVol.dmg` de la release a `~/Library/Caches/com.claudiouvm.pinvol/Updates` y lo comprueba con el SHA-256 que la API de GitHub publica para el adjunto (`digest`); la entrada pasa entonces a **Instalar PinVol X y reiniciar**. Instalar (`UpdateInstaller.install`) monta la imagen en solo lectura y sin mostrarla, comprueba que la app de dentro tiene el mismo identificador de bundle, la versión esperada (más nueva que la instalada) y una firma íntegra, la copia junto a la instalada, las intercambia con `FileManager.replaceItemAt`, quita la marca de cuarentena de la app instalada (el intercambio puede dejar en la nueva los atributos de la vieja) y borra la imagen. Después la instancia residente detiene sus motores, abre una instancia nueva con `--updated` (arranca sin ventana y avisa «Actualizada a X» junto al ícono) y termina. Si la instancia nueva no se puede abrir, esta sigue en marcha con sus motores y avisa «Instalada · vuelve a abrir PinVol» en vez de dejar el Mac sin PinVol (`relaunch` en `main.swift`). La confianza es la misma que al bajar el `.dmg` a mano: la app va firmada ad-hoc, así que no hay identidad que verificar y la huella solo protege de descargas dañadas.

Si la carpeta de la app no admite escritura (no está en Aplicaciones, o corre desde una imagen de disco) o macOS se niega (Privacidad y seguridad → Gestión de apps), el instalador falla con `.notWritable` o `.permission` y se abre la imagen de disco para que el usuario arrastre la app, como siempre. Otros fallos muestran su motivo en Acerca de y el estado vuelve a «disponible». Actualizar cambia la firma ad-hoc, así que macOS puede volver a pedir el permiso de audio. Los pasos quedan en el registro, subsistema `com.claudiouvm.pinvol`, categoría `update`. El CI prueba el instalador de verdad (`tools/test-install.sh` ejecuta `--selftest-install` del binario `-DSNAPSHOT` contra el `.dmg` que acaba de generar), así que mantén `SelfTest.swift` al día con `Installer.swift`.

Para publicar una versión: sube `CFBundleShortVersionString` (y `CFBundleVersion`) en `Info.plist`, actualiza `RELEASE_NOTES.md` (inglés y después español; el CI exige que su primera línea nombre la versión) y haz merge a `main`. El workflow `Release` compila el `.dmg` arm64, lo guarda en `dist/PinVol.dmg` y crea la release `v<versión>` con esas notas si todavía no existe. Si solo cambias las notas, ejecuta el workflow manual `Release notes` para copiarlas a la release existente.

Sube la versión siempre que cambien el binario o sus requisitos (chip, macOS, comportamiento): si no, `dist/PinVol.dmg` y el `.dmg` adjunto de la release existente dejan de coincidir.

Para etiquetar una versión como beta, añade `PinVolReleaseChannel` = `Beta` en `Info.plist` (se muestra en Acerca de y en el título de la release). No marques la release como «pre-release» en GitHub: la API `releases/latest`, que usa la app, ignora las pre-release.

## Convenciones

- Las descripciones en GitHub (pull requests, releases, issues) van primero en inglés y después en español. El código, los comentarios y los mensajes de commit van en español.
- `README.md` y `README.es.md`, y este archivo y `DEVELOPMENT.md`, son espejos: si cambias uno, cambia el otro.
- Los textos de la interfaz pasan por `L("English text")`, con su traducción al español en `Resources/es.lproj/Localizable.strings` (ver [Idiomas](#idiomas)).
- Se hace merge a `main` cuando el CI está en verde.
- El enlace de Ko-fi (`https://ko-fi.com/claudiouvm`) está en varios sitios que deben coincidir: el botón **¡Invítame un café!** de Acerca de (`SettingsWindow.donateURL`), el botón **Sponsor** de GitHub (`.github/FUNDING.yml`, clave `ko_fi`) y el enlace **¡Invítame un café!** junto al de descarga de los dos README (un enlace de texto, no una insignia de imagen: el texto dentro de una imagen puede no ser clicable en todos los navegadores).

## Límites conocidos

- Solo Apple Silicon (arm64) y macOS 26 (Tahoe) o posterior. La API de process taps existe desde macOS 14.2, pero esa no es la versión en que PinVol se compila y prueba. Los Mac Intel y las versiones anteriores de macOS no están soportados (usa la [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2) en macOS 14.2–15, o la [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1) en Intel).
- El máximo es de 5 apps a la vez (`maxPinnedApps` en `Model.swift`): cada una abre su propio tap y su propio dispositivo agregado.
- Con el volumen del sistema muy bajo y un nivel fijo alto, la ganancia llega al máximo (+24 dB) y ya no se puede compensar más; la línea de estado lo indica.
- En salidas sin control de volumen por software (algunas HDMI o USB) no hay nada que compensar y la app lo avisa.
- Las apps con DRM o procesos protegidos pueden no ser capturables.
- El `.dmg` no está notarizado (haría falta una cuenta de desarrollador de Apple).
- Al estar firmada ad-hoc, cada recompilación o actualización cambia la firma y macOS puede volver a pedir el permiso de audio.
- La instalación desde la app necesita una carpeta con permiso de escritura y, en algunos Mac, el permiso de Gestión de apps; la primera versión que la trae (1.6) hay que instalarla a mano.
