# PinVol 1.4

## English

Keeps the volume of the apps you choose fixed, no matter what the system volume is.

**What's new since 1.3**

- **Starts in the menu bar when the Mac turns on.** With "Open at login" on and apps already pinned, PinVol goes straight to the menu bar (or to the Dock, if the menu bar icon is off) and does not open its window. Open it from there whenever you need it. The window still opens when you launch the app yourself, and the first time, while nothing is pinned yet.

**Requires** macOS 26 (Tahoe) or later, on a Mac with Apple silicon (M1 or later). On macOS 14.2–15 use [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2); on an Intel Mac, [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1).

**Install**: open `PinVol.dmg` and drag PinVol to Applications. The app is ad-hoc signed and not notarized; if macOS says it is "damaged", run:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```

## Español

Mantiene fijo el volumen de las apps que elijas, sin importar el volumen del sistema.

**Novedades desde la 1.3**

- **Arranca en la barra de menús al encender el Mac.** Con «Abrir al iniciar sesión» activado y apps ya fijadas, PinVol pasa directo a la barra de menús (o al Dock, si el ícono de la barra está desactivado) y no abre su ventana. Ábrela desde ahí cuando la necesites. La ventana sigue abriéndose cuando abres la app tú mismo y la primera vez, mientras no hay nada fijado.

**Requiere** macOS 26 (Tahoe) o posterior, en un Mac con Apple silicon (M1 o posterior). En macOS 14.2–15 usa la [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2); en un Mac Intel, la [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1).

**Instalación**: abre `PinVol.dmg` y arrastra PinVol a Aplicaciones. La app está firmada ad-hoc y no notarizada; si macOS dice que está «dañada», ejecuta:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```
