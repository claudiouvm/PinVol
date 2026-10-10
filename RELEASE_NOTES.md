# PinVol 1.6.1

## English

Keeps the volume of the apps you choose fixed, no matter what the system volume is.

**What's new since 1.6**

- **Safer in-app updates.** After installing an update, PinVol removes macOS's quarantine mark from the new app, so macOS does not check it again or block it when it reopens. If the new version can't be opened, PinVol keeps running with your levels and tells you to reopen it, instead of quitting.
- If you have 1.6, you can update to this version from PinVol itself: **Check for updates…** in the menu bar icon's menu, then **Download** and **Install**.

**Requires** macOS 26 (Tahoe) or later, on a Mac with Apple silicon (M1 or later). On macOS 14.2–15 use [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2); on an Intel Mac, [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1).

**Install**: open `PinVol.dmg` and drag PinVol to Applications. The app is ad-hoc signed and not notarized; if macOS says it is "damaged", run:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```

## Español

Mantiene fijo el volumen de las apps que elijas, sin importar el volumen del sistema.

**Novedades desde la 1.6**

- **Actualizaciones desde la app, más seguras.** Tras instalar una actualización, PinVol quita de la app nueva la marca de cuarentena de macOS, para que no la vuelva a revisar ni la bloquee al reabrirla. Si la versión nueva no se puede abrir, PinVol sigue en marcha con tus niveles y te avisa que la vuelvas a abrir, en vez de cerrarse.
- Si tienes la 1.6, puedes actualizar a esta versión desde PinVol: **Buscar actualizaciones…** en el menú del ícono de la barra, luego **Descargar** e **Instalar**.

**Requiere** macOS 26 (Tahoe) o posterior, en un Mac con Apple silicon (M1 o posterior). En macOS 14.2–15 usa la [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2); en un Mac Intel, la [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1).

**Instalación**: abre `PinVol.dmg` y arrastra PinVol a Aplicaciones. La app está firmada ad-hoc y no notarizada; si macOS dice que está «dañada», ejecuta:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```
