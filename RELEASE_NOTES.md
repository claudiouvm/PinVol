# PinVol 1.10

## English

Keeps the volume of the apps you choose fixed, no matter what the system volume is.

**What's new since 1.9**

- **Accessibility.** Pin an app without dragging (**Pin App…**, ⌘O), remove it with ⌫ and undo with ⌘Z. VoiceOver hears status changes, errors and update results, and errors say what to do, with **Open System Settings** and **Retry**.
- **Easier to read.** States and errors use words, not only colors. Controls keep at least 3:1 contrast, the selected tab reaches 4.5:1, and text follows the system text size. The window resizes and scrolls when it needs to.
- **Fewer surprises.** Quitting asks first; a removed app keeps its level when you pin it again; dragging a new app tells you when fixed levels turn on; update results stay in the menu bar menu, and downloads show a progress bar.
- **From anywhere.** ⌥⌘P opens PinVol even when its window is behind.
- Numbers follow the Mac's region: 45% and 11,9 dB in Chile.

**Requires** macOS 26 (Tahoe) or later, on a Mac with Apple silicon (M1 or later). On macOS 14.2–15 use [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2); on an Intel Mac, [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1).

**Install**: open `PinVol.dmg` and drag PinVol to Applications. The app is ad-hoc signed and not notarized; if macOS says it is "damaged", run:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```

## Español

Mantiene fijo el volumen de las apps que elijas, sin importar el volumen del sistema.

**Novedades desde la 1.9**

- **Accesibilidad.** Fija una app sin arrastrar (**Fijar app…**, ⌘O), quítala con ⌫ y deshaz con ⌘Z. VoiceOver oye los cambios de estado, los errores y el resultado de las actualizaciones, y los errores dicen qué hacer, con **Abrir Ajustes del Sistema** y **Reintentar**.
- **Más fácil de leer.** Los estados y errores usan palabras, no solo color. Los controles mantienen al menos 3:1 de contraste, la pestaña seleccionada llega a 4,5:1 y el texto sigue el tamaño del sistema. La ventana se redimensiona y hace scroll si hace falta.
- **Menos sorpresas.** Salir pregunta antes; una app quitada conserva su nivel al volver a fijarla; al arrastrar una app nueva se avisa si se activan los niveles fijos; el resultado de las actualizaciones queda en el menú de la barra y las descargas muestran barra de progreso.
- **Desde cualquier sitio.** ⌥⌘P abre PinVol aunque su ventana esté detrás.
- Los números siguen la región del Mac: 45% y 11,9 dB en Chile.

**Requiere** macOS 26 (Tahoe) o posterior, en un Mac con Apple silicon (M1 o posterior). En macOS 14.2–15 usa la [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2); en un Mac Intel, la [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1).

**Instalación**: abre `PinVol.dmg` y arrastra PinVol a Aplicaciones. La app está firmada ad-hoc y no notarizada; si macOS dice que está «dañada», ejecuta:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```
