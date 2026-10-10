# PinVol 1.5

## English

Keeps the volume of the apps you choose fixed, no matter what the system volume is.

**What's new since 1.4**

- **Check for updates from the menu bar.** The menu of the PinVol icon has a new "Check for updates…" item, so you don't have to open the app to look for a new version. The result shows next to the icon for a few seconds; if there is a new version, the menu then offers to download it.

**Requires** macOS 26 (Tahoe) or later, on a Mac with Apple silicon (M1 or later). On macOS 14.2–15 use [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2); on an Intel Mac, [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1).

**Install**: open `PinVol.dmg` and drag PinVol to Applications. The app is ad-hoc signed and not notarized; if macOS says it is "damaged", run:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```

## Español

Mantiene fijo el volumen de las apps que elijas, sin importar el volumen del sistema.

**Novedades desde la 1.4**

- **Buscar actualizaciones desde la barra de menús.** El menú del ícono de PinVol tiene una opción nueva, «Buscar actualizaciones…», para no tener que abrir la app a buscar una versión nueva. El resultado aparece junto al ícono unos segundos; si hay una versión nueva, el menú ofrece descargarla.

**Requiere** macOS 26 (Tahoe) o posterior, en un Mac con Apple silicon (M1 o posterior). En macOS 14.2–15 usa la [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2); en un Mac Intel, la [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1).

**Instalación**: abre `PinVol.dmg` y arrastra PinVol a Aplicaciones. La app está firmada ad-hoc y no notarizada; si macOS dice que está «dañada», ejecuta:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```
