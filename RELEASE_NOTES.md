# PinVol 1.2

## English

Keeps the volume of the apps you choose fixed, no matter what the system volume is.

**What's new since 1.1**

- **Apple Silicon only.** PinVol is now a native arm64 app for Macs with Apple silicon (M1 or later) running macOS 14.2 or later, and the download is smaller. Intel Macs are no longer supported; [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1), the last universal build, keeps working there.
- **Smoother window**: switching tabs or adding and removing apps always uses the same short animation (it respects *Reduce motion*).
- About shows the version without the build number.
- Released under the MIT license.

**Install**: open `PinVol.dmg` and drag PinVol to Applications. Needs a Mac with Apple silicon and macOS 14.2 or later. The app is ad-hoc signed and not notarized; if macOS says it is "damaged", run:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```

## Español

Mantiene fijo el volumen de las apps que elijas, sin importar el volumen del sistema.

**Novedades desde la 1.1**

- **Solo Apple Silicon.** PinVol ahora es una app arm64 nativa para Mac con Apple silicon (M1 o posterior) y macOS 14.2 o posterior, y la descarga es más liviana. Ya no se soportan los Mac Intel; la [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1), la última versión universal, sigue funcionando ahí.
- **Ventana más fluida**: al cambiar de pestaña o al añadir y quitar apps siempre se usa la misma animación breve (respeta *Reducir movimiento*).
- Acerca de muestra la versión sin el número de build.
- Publicada bajo la licencia MIT.

**Instalación**: abre `PinVol.dmg` y arrastra PinVol a Aplicaciones. Necesita un Mac con Apple silicon y macOS 14.2 o posterior. La app está firmada ad-hoc y no notarizada; si macOS dice que está «dañada», ejecuta:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```
