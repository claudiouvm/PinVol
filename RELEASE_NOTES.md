# PinVol 1.13

## English

Keeps the volume of the apps you choose fixed, no matter what the system volume is.

**What's new since 1.12**

- **PinVol is now a menu-bar app.** It no longer shows a Dock icon and does not appear in ⌘Tab. Open the window from the menu bar icon or press **⌥⌘P** from any app.
- The **Show in the Dock** and **Show in the menu bar** settings are gone; the menu bar icon is always there.
- Everything else stays: pin apps with ⌘O, remove with ⌫ and undo with ⌘Z, VoiceOver announcements, the custom slider and the buttons that grow with the text.

**Requires** macOS 26 (Tahoe) or later, on a Mac with Apple silicon (M1 or later). On macOS 14.2–15 use [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2); on an Intel Mac, [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1).

**Install**: open `PinVol.dmg` and drag PinVol to Applications. The app is ad-hoc signed and not notarized; if macOS says it is "damaged", run:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```

## Español

Mantiene fijo el volumen de las apps que elijas, sin importar el volumen del sistema.

**Novedades desde la 1.12**

- **PinVol ahora es una app de barra de menús.** Ya no muestra ícono en el Dock ni aparece en ⌘Tab. Abre la ventana desde el ícono de la barra o pulsa **⌥⌘P** desde cualquier app.
- Los ajustes **Mostrar en el Dock** y **Mostrar en la barra de menús** desaparecen; el ícono de la barra siempre está.
- Lo demás sigue igual: fija apps con ⌘O, quítalas con ⌫ y deshaz con ⌘Z, anuncios de VoiceOver, el slider propio y los botones que crecen con el texto.

**Requiere** macOS 26 (Tahoe) o posterior, en un Mac con Apple silicon (M1 o posterior). En macOS 14.2–15 usa la [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2); en un Mac Intel, la [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1).

**Instalación**: abre `PinVol.dmg` y arrastra PinVol a Aplicaciones. La app está firmada ad-hoc y no notarizada; si macOS dice que está «dañada», ejecuta:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```
