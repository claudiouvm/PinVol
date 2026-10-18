# PinVol 1.11

## English

Keeps the volume of the apps you choose fixed, no matter what the system volume is.

**What's new since 1.10**

- **The window no longer resizes when you change tabs.** Its height is the tallest tab, so Apps, Settings and About share the same frame.
- **About looks like the other tabs:** same header and left alignment, without the large logo.
- **Less empty space at the top, and the footer stays at the bottom,** so nothing is cut off.
- Update buttons now have specific VoiceOver names (check, download, install, retry).
- Numbers follow the Mac's region: 45% and 11,9 dB in Chile.

**Requires** macOS 26 (Tahoe) or later, on a Mac with Apple silicon (M1 or later). On macOS 14.2–15 use [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2); on an Intel Mac, [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1).

**Install**: open `PinVol.dmg` and drag PinVol to Applications. The app is ad-hoc signed and not notarized; if macOS says it is "damaged", run:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```

## Español

Mantiene fijo el volumen de las apps que elijas, sin importar el volumen del sistema.

**Novedades desde la 1.10**

- **La ventana ya no cambia de tamaño al cambiar de pestaña.** Su alto es el de la pestaña más alta, así que Apps, Ajustes y Acerca de comparten el mismo marco.
- **Acerca de se ve como las otras pestañas:** misma cabecera y alineación a la izquierda, sin el logo grande.
- **Menos espacio arriba y el pie queda abajo,** así no se corta nada.
- Los botones de actualización tienen nombres propios en VoiceOver (buscar, descargar, instalar, reintentar).
- Los números siguen la región del Mac: 45% y 11,9 dB en Chile.

**Requiere** macOS 26 (Tahoe) o posterior, en un Mac con Apple silicon (M1 o posterior). En macOS 14.2–15 usa la [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2); en un Mac Intel, la [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1).

**Instalación**: abre `PinVol.dmg` y arrastra PinVol a Aplicaciones. La app está firmada ad-hoc y no notarizada; si macOS dice que está «dañada», ejecuta:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```
