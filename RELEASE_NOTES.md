# PinVol 1.1

## English

Keeps the volume of the apps you choose fixed, no matter what the system volume is.

**What's new since 1.0**

- **Up to 5 apps at once**, each with its own fixed level (1.0 handled a single app). Your 1.0 settings migrate automatically.
- **Adaptive drop zone**: a large card when empty, a compact strip with 1–4 apps, hidden at 5. The window grows and shrinks with a consistent animation (it respects *Reduce motion*).
- **Tabs**: Apps, Settings and About (large logo, version and credits).
- **Update check**: once a day (optional) it looks at the latest GitHub release and shows a banner in the window and an item in the menu. It never downloads or installs anything by itself.
- **New app icon** and menu bar glyph.
- Apps that share a bundle-id prefix (for example `com.google.Chrome` and `com.google.Chrome.canary`) no longer steal each other's audio processes.

**Install**: open `PinVol.dmg` and drag PinVol to Applications. Universal binary (Apple Silicon and Intel), macOS 14.2 or later. The app is ad-hoc signed and not notarized; if macOS says it is "damaged", run:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```

## Español

Mantiene fijo el volumen de las apps que elijas, sin importar el volumen del sistema.

**Novedades desde la 1.0**

- **Hasta 5 apps a la vez**, cada una con su propio nivel fijo (la 1.0 manejaba una sola). Los ajustes de la 1.0 se migran solos.
- **Zona de arrastre adaptable**: tarjeta grande sin apps, franja compacta con 1 a 4 y oculta con 5. La ventana crece y se encoge con una animación consistente (respeta *Reducir movimiento*).
- **Pestañas**: Apps, Ajustes y Acerca de (logo grande, versión y créditos).
- **Búsqueda de actualizaciones**: una vez al día (opcional) consulta la última release de GitHub y muestra un aviso en la ventana y una entrada en el menú. Nunca descarga ni instala nada por su cuenta.
- **Ícono nuevo** de la app y de la barra de menús.
- Las apps que comparten prefijo de bundle id (por ejemplo `com.google.Chrome` y `com.google.Chrome.canary`) ya no se quitan los procesos de audio entre sí.

**Instalación**: abre `PinVol.dmg` y arrastra PinVol a Aplicaciones. Binario universal (Apple Silicon e Intel), macOS 14.2 o posterior. La app está firmada ad-hoc y no notarizada; si macOS dice que está «dañada», ejecuta:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```
