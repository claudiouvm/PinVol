# PinVol 1.17

## English

Keeps the volume of the apps you choose fixed, no matter what the system volume is.

**What's new since 1.16**

- Internal cleanup: removed dead code (unused variables in About and in the accessibility test) and fixed a stale comment. No change in behavior.
- Build: upgraded the GitHub Actions to `actions/checkout@v7` and `actions/upload-artifact@v7`.

**Requires** macOS 26 (Tahoe) or later, on a Mac with Apple silicon (M1 or later). On macOS 14.2–15 use [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2); on an Intel Mac, [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1).

**Install**: open `PinVol.dmg` and drag PinVol to Applications. The app is ad-hoc signed and not notarized; if macOS says it is "damaged", run:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```

## Español

Mantiene fijo el volumen de las apps que elijas, sin importar el volumen del sistema.

**Novedades desde la 1.16**

- Limpieza interna: se eliminó código muerto (variables sin uso en Acerca de y en la prueba de accesibilidad) y se corrigió un comentario desactualizado. Sin cambios de comportamiento.
- Compilación: se actualizaron las GitHub Actions a `actions/checkout@v7` y `actions/upload-artifact@v7`.

**Requiere** macOS 26 (Tahoe) o posterior, en un Mac con Apple silicon (M1 o posterior). En macOS 14.2–15 usa la [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2); en un Mac Intel, la [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1).

**Instalación**: abre `PinVol.dmg` y arrastra PinVol a Aplicaciones. La app está firmada ad-hoc y no notarizada; si macOS dice que está «dañada», ejecuta:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```
