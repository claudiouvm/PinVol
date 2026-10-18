# PinVol 1.14

## English

Keeps the volume of the apps you choose fixed, no matter what the system volume is.

**What's new since 1.13**

- **Native buttons are back.** The custom pill style is gone; buttons look and behave like macOS controls again, and the cup in **Buy me a coffee!** now fits inside its button.
- The permission error can show its full explanation (up to four lines) instead of being cut off.
- Everything else stays: menu-bar-only, pin apps with ⌘O, remove with ⌫ and undo with ⌘Z, VoiceOver announcements and the high-contrast slider.

**Requires** macOS 26 (Tahoe) or later, on a Mac with Apple silicon (M1 or later). On macOS 14.2–15 use [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2); on an Intel Mac, [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1).

**Install**: open `PinVol.dmg` and drag PinVol to Applications. The app is ad-hoc signed and not notarized; if macOS says it is "damaged", run:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```

## Español

Mantiene fijo el volumen de las apps que elijas, sin importar el volumen del sistema.

**Novedades desde la 1.13**

- **Vuelven los botones nativos.** El estilo de píldora propio desaparece; los botones se ven y se comportan como controles de macOS, y la taza de **¡Invítame un café!** ya cabe dentro de su botón.
- El error de permiso puede mostrar su explicación completa (hasta cuatro líneas) en vez de quedar cortado.
- Lo demás sigue igual: solo barra de menús, fija apps con ⌘O, quítalas con ⌫ y deshaz con ⌘Z, anuncios de VoiceOver y el slider de alto contraste.

**Requiere** macOS 26 (Tahoe) o posterior, en un Mac con Apple silicon (M1 o posterior). En macOS 14.2–15 usa la [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2); en un Mac Intel, la [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1).

**Instalación**: abre `PinVol.dmg` y arrastra PinVol a Aplicaciones. La app está firmada ad-hoc y no notarizada; si macOS dice que está «dañada», ejecuta:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```
