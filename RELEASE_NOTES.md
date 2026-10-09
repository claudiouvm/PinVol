# PinVol 1.3

## English

Keeps the volume of the apps you choose fixed, no matter what the system volume is.

**What's new since 1.2**

- **English and Spanish interface.** PinVol now follows your Mac's language: Spanish if your Mac is set to Spanish, English otherwise (it used to be Spanish only).
- **Requires macOS 26 (Tahoe) or later**, on a Mac with Apple silicon (M1 or later). PinVol is now built with the macOS 26 toolchain. On macOS 14.2–15 keep using [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2); on an Intel Mac, [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1).

**Install**: open `PinVol.dmg` and drag PinVol to Applications. The app is ad-hoc signed and not notarized; if macOS says it is "damaged", run:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```

## Español

Mantiene fijo el volumen de las apps que elijas, sin importar el volumen del sistema.

**Novedades desde la 1.2**

- **Interfaz en inglés y en español.** PinVol ahora sigue el idioma de tu Mac: en español si tu Mac está en español, y en inglés en cualquier otro caso (antes solo estaba en español).
- **Requiere macOS 26 (Tahoe) o posterior**, en un Mac con Apple silicon (M1 o posterior). PinVol ahora se compila con las herramientas de macOS 26. En macOS 14.2–15 sigue usando la [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2); en un Mac Intel, la [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1).

**Instalación**: abre `PinVol.dmg` y arrastra PinVol a Aplicaciones. La app está firmada ad-hoc y no notarizada; si macOS dice que está «dañada», ejecuta:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```
