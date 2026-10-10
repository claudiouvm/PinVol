# PinVol 1.6

## English

Keeps the volume of the apps you choose fixed, no matter what the system volume is.

**What's new since 1.5**

- **Download and install updates from PinVol itself.** When there is a new version, **Download** (in the menu bar icon's menu, the banner or About) now downloads it in the background, and the message then changes to **Install PinVol X and restart**. Clicking it replaces the app and reopens it quietly in the menu bar. It never installs anything by itself, and the download is checked against the checksum GitHub publishes.
- If macOS does not let PinVol replace itself (for example, it is not in Applications, or Privacy & Security → App Management blocks it), PinVol opens the disk image so you can drag the app to Applications as before.
- Because the app is ad-hoc signed, macOS may ask again for the System Audio Recording permission after an update.
- This first version has to be installed by hand; the in-app install works from the next update on.

**Requires** macOS 26 (Tahoe) or later, on a Mac with Apple silicon (M1 or later). On macOS 14.2–15 use [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2); on an Intel Mac, [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1).

**Install**: open `PinVol.dmg` and drag PinVol to Applications. The app is ad-hoc signed and not notarized; if macOS says it is "damaged", run:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```

## Español

Mantiene fijo el volumen de las apps que elijas, sin importar el volumen del sistema.

**Novedades desde la 1.5**

- **Descargar e instalar actualizaciones desde PinVol.** Cuando hay una versión nueva, **Descargar** (en el menú del ícono de la barra, en el aviso o en Acerca de) ahora la baja en segundo plano, y el mensaje pasa a **Instalar PinVol X y reiniciar**. Al pulsarlo se reemplaza la app y se reabre en silencio en la barra de menús. Nunca instala nada por su cuenta, y la descarga se comprueba con la huella que publica GitHub.
- Si macOS no deja que PinVol se reemplace (por ejemplo, no está en Aplicaciones, o Privacidad y seguridad → Gestión de apps lo bloquea), PinVol abre la imagen de disco para que arrastres la app a Aplicaciones, como siempre.
- Como la app va firmada ad-hoc, macOS puede volver a pedir el permiso de grabación de audio del sistema tras una actualización.
- Esta primera versión hay que instalarla a mano; la instalación desde la app funciona a partir de la siguiente actualización.

**Requiere** macOS 26 (Tahoe) o posterior, en un Mac con Apple silicon (M1 o posterior). En macOS 14.2–15 usa la [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2); en un Mac Intel, la [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1).

**Instalación**: abre `PinVol.dmg` y arrastra PinVol a Aplicaciones. La app está firmada ad-hoc y no notarizada; si macOS dice que está «dañada», ejecuta:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```
