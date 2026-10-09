<p align="center">
  <img src="docs/icon.png" width="128" alt="PinVol icon">
</p>

<h1 align="center">PinVol</h1>

<p align="center">
  <b>Pin the volume of your Mac apps.</b><br>
  Keep up to 5 apps at a fixed level, no matter what the system volume is.
</p>

<p align="center">
  <b>English</b> | <a href="README.es.md">Español</a>
</p>

<p align="center">
  <a href="https://github.com/claudiouvm/PinVol/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/claudiouvm/PinVol?style=flat-square&color=blue"></a>
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2014.2%2B-lightgrey?style=flat-square">
  <img alt="Architecture" src="https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-universal-orange?style=flat-square">
  <img alt="Made in Chile" src="https://img.shields.io/badge/made%20in-Chile-red?style=flat-square">
</p>

<p align="center">
  <img src="docs/apps-claro.png" width="300" alt="PinVol with five pinned apps, light mode">
  <img src="docs/apps-oscuro.png" width="300" alt="PinVol with five pinned apps, dark mode">
</p>

<p align="center">
  <a href="https://github.com/claudiouvm/PinVol/releases/latest/download/PinVol.dmg"><b>⬇️ Download PinVol.dmg</b></a>
</p>

* * *

## Why PinVol?

- 🔒 **It stays put.** Lower the system volume to enjoy music or a video; the apps you pinned keep exactly the level you chose.
- 🎛️ **Up to 5 apps**, each with its own slider. Drop the `.app` in and you're done.
- 🪶 **Tiny and native.** AppKit and Core Audio only: no dependencies, no drivers, about 15–20 MB of memory.
- 🕊️ **No telemetry.** The only network request is an optional once-a-day check for a new release on GitHub.

## Features

| Feature | What it does |
|---|---|
| **Fixed level per app** | Each pinned app keeps its own level, on the same scale as the system volume. |
| **Drag and drop** | Drop one or several `.app` files; the window grows and shrinks with them. |
| **Menu bar and Dock** | Open it from either one, and launch it at login. |
| **Light and dark** | Native controls that follow your appearance. |
| **Update check** | Tells you when a new version is out. It never installs anything by itself. |

## Install

1. [Download `PinVol.dmg`](https://github.com/claudiouvm/PinVol/releases/latest/download/PinVol.dmg) and drag PinVol to **Applications**.
2. Open it and drag the app you want to pin onto the dotted area.
3. Allow **System Audio Recording** when macOS asks.

Requires macOS 14.2 or later. Keep PinVol in `/Applications`: on macOS 27 the menu bar icon only shows from there.

PinVol is ad-hoc signed and not notarized. If macOS says it is "damaged", run:

```sh
xattr -dr com.apple.quarantine /Applications/PinVol.app
```

**Build from source:** `./build.sh install` (needs the Xcode command line tools).

## How it works

macOS has no per-app volume. PinVol taps the audio of each pinned app, mutes the original and plays it back through your output device with a gain of *pinned level ÷ system volume*, recomputed whenever the system volume changes. More in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

* * *

Made in Chile by Claudiouvm and Claude <3 · If PinVol is useful to you, a ⭐ helps.
