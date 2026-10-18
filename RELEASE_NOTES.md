# PinVol 1.15

## English

Keeps the volume of the apps you choose fixed, no matter what the system volume is.

**What's new since 1.14**

- **Messages stay long enough to read.** Footer notices last 5 seconds, and engine status updates no longer replace them.
- **Reduce Transparency** is supported: the dark cards become opaque.
- **The window can be minimized** with the standard button or ⌘M, and **Zoom** is in the Window menu.
- The permission error explanation has no line limit; it grows instead of being cut off.
- Everything else stays: menu-bar-only, native buttons, pin apps with ⌘O, remove with ⌫ and undo with ⌘Z, VoiceOver announcements and the high-contrast slider.

**Requires** macOS 26 (Tahoe) or later, on a Mac with Apple silicon (M1 or later). On macOS 14.2–15 use [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2); on an Intel Mac, [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1).

**Install**: open `PinVol.dmg` and drag PinVol to Applications. The app is ad-hoc signed and not notarized; if macOS says it is "damaged", run:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```

## Español

Mantiene fijo el volumen de las apps que elijas, sin importar el volumen del sistema.

**Novedades desde la 1.14**

- **Los avisos duran lo suficiente para leerlos.** Los mensajes del pie duran 5 segundos y los cambios de estado del motor ya no los reemplazan.
- **Se admite «Reducir transparencia»:** las tarjetas oscuras pasan a ser opacas.
- **La ventana se puede minimizar** con el botón estándar o ⌘M, y **Zoom** está en el menú Ventana.
- La explicación del error de permiso no tiene límite de líneas; crece en vez de cortarse.
- Lo demás sigue igual: solo barra de menús, botones nativos, fija apps con ⌘O, quítalas con ⌫ y deshaz con ⌘Z, anuncios de VoiceOver y el slider de alto contraste.

**Requiere** macOS 26 (Tahoe) o posterior, en un Mac con Apple silicon (M1 o posterior). En macOS 14.2–15 usa la [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2); en un Mac Intel, la [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1).

**Instalación**: abre `PinVol.dmg` y arrastra PinVol a Aplicaciones. La app está firmada ad-hoc y no notarizada; si macOS dice que está «dañada», ejecuta:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```
