<p align="center">
  <img src="docs/icon.png" width="360" alt="Ícono de PinVol">
</p>

<h1 align="center">PinVol</h1>

<p align="center">
  <b>Volumen fijo para las apps de tu Mac.</b><br>
  Fija hasta 5 apps en su propio nivel, sin importar el volumen del sistema.
</p>

<p align="center">
  <a href="README.md">English</a> | <b>Español</b>
</p>

<p align="center">
  <a href="https://github.com/claudiouvm/PinVol/stargazers"><img alt="Estrellas" src="https://img.shields.io/github/stars/claudiouvm/PinVol?style=flat-square&color=gold&label=estrellas"></a>
  <a href="https://github.com/claudiouvm/PinVol/releases/latest"><img alt="Versión" src="https://img.shields.io/github/v/release/claudiouvm/PinVol?style=flat-square&color=blue&label=versi%C3%B3n"></a>
  <a href="https://github.com/claudiouvm/PinVol/releases"><img alt="Descargas" src="https://img.shields.io/github/downloads/claudiouvm/PinVol/total?style=flat-square&color=blue&label=descargas"></a>
  <img alt="Plataforma" src="https://img.shields.io/badge/plataforma-macOS%2026%2B-lightgrey?style=flat-square">
  <img alt="Chip" src="https://img.shields.io/badge/chip-Apple%20Silicon-black?style=flat-square&logo=apple&logoColor=white">
  <img alt="Swift" src="https://img.shields.io/badge/swift-6.2%2B-orange?style=flat-square">
  <img alt="Telemetría" src="https://img.shields.io/badge/telemetr%C3%ADa-ninguna-brightgreen?style=flat-square">
  <a href="LICENSE"><img alt="Licencia" src="https://img.shields.io/badge/licencia-MIT-green?style=flat-square"></a>
  <a href="https://github.com/claudiouvm/PinVol/pulls"><img alt="PRs bienvenidos" src="https://img.shields.io/badge/PRs-bienvenidos-ff69b4?style=flat-square"></a>
</p>

<p align="center">
  <img src="docs/apps-claro.png" width="390" alt="PinVol con cinco apps fijadas, modo claro">
  <img src="docs/apps-oscuro.png" width="390" alt="PinVol con cinco apps fijadas, modo oscuro">
</p>

<p align="center">
  <a href="https://github.com/claudiouvm/PinVol/releases/latest/download/PinVol.dmg"><b>⬇️ Descargar PinVol.dmg</b></a>
</p>

* * *

## ¿Por qué PinVol?

- 🔒 **Se queda donde lo dejas.** Baja el volumen del sistema para escuchar música o ver un video; las apps que fijaste mantienen exactamente el nivel que elegiste.
- 🎛️ **Hasta 5 apps**, cada una con su propio slider. Arrastra el `.app` y listo.
- 🪶 **Pequeña y nativa.** Hecha para Apple Silicon con solo AppKit y Core Audio: sin dependencias, sin drivers, unos 15–20 MB de memoria.
- 🕊️ **Sin telemetría.** La única conexión es una consulta opcional, una vez al día, para saber si hay una versión nueva en GitHub.

## Funciones

| Función | Qué hace |
|---|---|
| **Nivel fijo por app** | Cada app fijada conserva su propio nivel, en la misma escala que el volumen del sistema. |
| **Arrastrar y soltar** | Suelta uno o varios `.app`; la ventana crece y se encoge con ellos. |
| **Barra de menús y Dock** | Ábrela desde cualquiera de los dos, y haz que se abra al iniciar sesión. |
| **Claro y oscuro** | Controles nativos que siguen tu apariencia. |
| **Búsqueda de actualizaciones** | Te avisa cuando sale una versión nueva. Nunca instala nada por su cuenta. |

## Instalación

1. [Descarga `PinVol.dmg`](https://github.com/claudiouvm/PinVol/releases/latest/download/PinVol.dmg) y arrastra PinVol a **Aplicaciones**.
2. Ábrela y arrastra la app que quieres fijar a la zona punteada.
3. Permite **Grabación de audio del sistema** cuando macOS lo pida.

**Requiere un Mac con Apple Silicon (M1 o posterior) y macOS 26 Tahoe o posterior.** En macOS 14.2–15 usa la [versión 1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2); en un Mac Intel, la [versión 1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1), la última universal. Deja PinVol en `/Applications`: en macOS 27 el ícono de la barra de menús solo aparece desde ahí.

PinVol va firmada ad-hoc y no está notarizada. Si macOS dice que está «dañada», ejecuta:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```

**Compilar desde el código:** `./build.sh install` en un Mac con Apple Silicon (necesita las herramientas de línea de comandos de Xcode 26).

## Cómo funciona

macOS no tiene volumen por app. PinVol captura el audio de cada app fijada, silencia el original y lo reproduce por tu dispositivo de salida con una ganancia de *nivel fijo ÷ volumen del sistema*, que recalcula cada vez que cambia el volumen del sistema. Más detalle en [docs/DESARROLLO.md](docs/DESARROLLO.md).

## Licencia

[MIT](LICENSE) © Claudiouvm

* * *

Hecho en Chile por Claudiouvm y Claude <3 · Si PinVol te sirve, una ⭐ ayuda.
