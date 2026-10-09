# Development

*Español: [DESARROLLO.md](DESARROLLO.md)*

## Requirements

To build PinVol you need:

- A Mac with **Apple Silicon** (M1 or later), on **macOS 26 (Tahoe)** or later. `build.sh` refuses to run on Intel or under Rosetta, because the app is arm64-only.
- **Xcode 26** or its command line tools (Swift 6.2): the app targets macOS 26 (`Package.swift`) and is built with that SDK, both on the CI and in the releases. The package itself declares `swift-tools-version:5.9` and builds in Swift 5 language mode.
- No external dependencies. Only `tools/make-icon.py` needs more: Python 3 and Pillow (`pip3 install pillow`).

## How it works

macOS has no per-app volume. PinVol uses **Core Audio process taps** (`AudioHardwareCreateProcessTap`, an API that exists since macOS 14.2; PinVol itself requires macOS 26):

1. It creates a tap on the app's processes, helpers included (it matches by bundle-id prefix, which browsers and Electron apps need). The original audio is muted. Each pinned app has its own tap and its own level; if two apps share a prefix (`com.google.Chrome` and `com.google.Chrome.canary`), the processes go to the more specific one.
2. It plays that audio through a private aggregate device, applying a gain.
3. The gain is `pinned level ÷ system volume`, recomputed whenever the volume or the mute state changes, with a soft limiter and a +24 dB cap.

The important detail is how decibels are measured. The standard scalar→dB conversion that Core Audio exposes **does not match the curve the system really applies** (on Macs with built-in speakers it is quadratic: `dB = −63.5 × (1 − √volume)`). Using it makes the app get louder or quieter as you move the volume. PinVol reads the device's real dB (`kAudioDevicePropertyVolumeDecibels`) and inverts the device's own dB→scalar conversion to translate the slider level.

## Architecture

PinVol runs as **two instances of the same app**:

- **Resident**: Dock and menu bar, audio engines and saved settings. Always alive.
- **Interface** (`--ui`): shows the window and quits when it is closed.

They talk through `DistributedNotificationCenter`. The reason is memory: opening a window makes AppKit reserve about 8 MB to draw it, plus 5–7 MB for the native switches and slider, and the system does not give them back when you close the window. With the window in another process, that memory is released on close. With the window closed the resident process uses about 15–20 MB; while it is open, the interface instance adds about 22–25 MB. These figures were measured on the original single-app version and have not been measured again with five apps or on macOS 26.

All controls are native AppKit (`NSSwitch`, `NSSlider`, SF Symbols). They follow light and dark mode and, since the app is built with the macOS 26 SDK, the system's current look.

The code lives in `Sources/PinVol/`, split by responsibility:

| File | Contents |
|---|---|
| `main.swift` | Resident instance (Dock, menu bar) and startup |
| `UIDelegate.swift` | Interface instance (`--ui`) and the main menu |
| `Controller.swift` | Saved state, one `Engine` per app, interface messages and the update check |
| `Audio.swift` | Core Audio: tap, aggregate device, gain, system volume |
| `Model.swift` | `AppState`, `PinnedApp`, inter-process messaging |
| `SettingsWindow.swift` | Tabbed window (Apps, Settings, About) and its resize animation |
| `AppsPanel.swift` | Drop zone and app rows |
| `Style.swift` | Shared labels, cards and settings rows |
| `Strings.swift` | Interface text (`L("…")`) and language-aware number formats |
| `Updates.swift` | Latest-release lookup on GitHub |
| `Snapshot.swift` | Development only: window screenshots |

## Languages

The interface is in English and Spanish and follows the Mac's language: Spanish when it is the preferred language, English in any other case (English is also the fallback).

- Every user-facing text goes through `L("English text")` (`Strings.swift`): the English text is the key. `Resources/es.lproj/Localizable.strings` holds the Spanish translation, and `InfoPlist.strings` (in `en.lproj` and `es.lproj`) the localized texts of `Info.plist`, such as the audio-permission prompt. Formats use `%@` and `%ld`.
- Numbers follow the interface language, not the Mac's region: `45%` and `+11.9 dB` in English, `45 %` and `+11,9 dB` in Spanish.
- To add a text, use `L("…")` in the code and add its line to `es.lproj/Localizable.strings`. `tools/check-strings.py` (the CI runs it too) fails if a text has no translation, if a translation is no longer used or if the format specifiers differ.
- To add a language, create `Resources/<code>.lproj/` with the same two files and add the code to `CFBundleLocalizations` in `Info.plist`; the script checks it all.
- To try a language without changing the Mac's, run the binary with `-AppleLanguages "(es)"`, or set it for PinVol only in System Settings → General → Language & Region → Applications.
- The resident instance writes the status texts, so it keeps the language it started with: after changing the Mac's language, quit PinVol and open it again.

## Commands

| Command | What it does |
|---|---|
| `./build.sh` | Builds `build/PinVol.app` (Apple Silicon only: it refuses to run on Intel or under Rosetta) |
| `./build.sh install` | Also installs it in `/Applications` and opens it |
| `tools/make-dmg.sh` | Builds the arm64 app and produces `dist/PinVol.dmg` (fails if the binary is not arm64-only) |
| `./snapshot.sh` | Builds a development variant and renders PNG screenshots of the window (light/dark, 1 and 5 apps, every tab) in English and Spanish into `build/snapshots/en` and `build/snapshots/es`, with no screen-recording permission needed |
| `python3 tools/check-strings.py` | Checks that every interface text has its translation (the CI runs it too; it needs no Mac) |
| `python3 tools/make-icon.py` | Regenerates `Resources/AppIcon.icns` and the menu bar glyphs (`MenuBar*Template*.png`). Everything is drawn in code |

`snapshot.sh` builds with `-DSNAPSHOT` and uses a different bundle identifier (`com.claudiouvm.pinvol.dev`), so it does not touch the real app's settings or permissions. The options of the development binary are listed at the top of `Snapshot.swift`. The script can be tuned with environment variables:

- `APPS=com.apple.Music,com.apple.Safari,… ./snapshot.sh` chooses the five apps of the mockups. The default is Music, Safari, Spotify, IINA and TIDAL, all of which play audio; any that is not installed shows its bundle id.
- `SYSTEM=0.4 ./snapshot.sh` sets the system volume the mockups assume (50 % by default). The gains shown (for example −2.3 dB or +11.9 dB) are the real ones: the script computes them with the engine's formula, `dB(pinned level) − dB(system volume)`, on the speakers' quadratic curve.
- `LANGS=en ./snapshot.sh` renders a single language (`en es` by default). The development binary takes the language from `-AppleLanguages "(es)"`, like any app.
- On macOS 26 the system generates the icons of freshly installed apps on demand (separately for light and dark) and draws a dashed placeholder until they are ready. So before capturing, the development binary draws each icon of the window and checks that it is not that placeholder; if it is, it exits with code 3 and the script retries in a new process (up to 30 times, 2 s apart), and as a last resort captures anyway with `--force` and warns.

## CI

All workflows run on the `macos-26` runner (Apple Silicon, Xcode 26) except the last one.

| Workflow | When | What it does |
|---|---|---|
| `Release` (`release.yml`) | Pull requests and pushes to `main` (skipped if only `dist/`, `docs/` or `.md` files change) | Checks the translations (`tools/check-strings.py`). Compiles the screenshot variant too, so the `-DSNAPSHOT` code is checked. Builds the arm64 `.dmg` and checks `Info.plist`, the icon, the bundle resources, that the binary is arm64-only and that `RELEASE_NOTES.md` names the version. Uploads the `PinVol-dmg` and `capturas` artifacts. On `main` it also commits `dist/PinVol.dmg` (a bot commit marked `[skip ci]`) and creates the release `v<version>` if it does not exist yet. |
| `Screenshots` (`screenshots.yml`) | Manual, or in a pull request that changes `snapshot.sh` or the workflow itself | Installs Spotify, IINA and TIDAL, takes the screenshots (English and Spanish) and uploads them as `capturas-portada`. The front-page images are `en/light-five.png` and `en/dark-five.png` from that artifact (`docs/apps-claro.png` and `docs/apps-oscuro.png`, for `README.md`) and `es/light-five.png` and `es/dark-five.png` (`docs/apps-claro.es.png` and `docs/apps-oscuro.es.png`, for `README.es.md`). |
| `Release notes` (`release-notes.yml`, `ubuntu-latest`) | Manual | Copies `RELEASE_NOTES.md` to the release of the version in `Info.plist`. |

Swift cannot be compiled on Linux, so the CI is the real build. The artifacts are the way to review the window's design.

## Updates and releases

PinVol checks the latest GitHub release once a day (and on demand in **About**) and compares it with its own version. If there is a newer one it shows a banner in the window and a menu item that opens the release page; it never downloads or installs anything. It can be turned off in **Settings**. The check uses GitHub's public API, so the repository must be public.

To publish a version: raise `CFBundleShortVersionString` (and `CFBundleVersion`) in `Info.plist`, update `RELEASE_NOTES.md` (English first, then Spanish; CI requires its first line to name the version) and merge to `main`. The `Release` workflow then builds the arm64 `.dmg`, commits it to `dist/PinVol.dmg` and creates the release `v<version>` with those notes if it does not exist yet. If you only change the notes, run the manual `Release notes` workflow to copy them to the existing release.

Raise the version whenever the binary or its requirements change (chip, macOS, behavior): otherwise `dist/PinVol.dmg` and the attached `.dmg` of the existing release stop matching.

To label a version as beta, add `PinVolReleaseChannel` = `Beta` to `Info.plist` (it shows in About and in the release title). Do not mark the release as "pre-release" on GitHub: the `releases/latest` API, which the app uses, ignores pre-releases.

## Conventions

- Descriptions on GitHub (pull requests, releases, issues) go in English first, then Spanish. Code, comments and commit messages are in Spanish.
- `README.md` and `README.es.md`, and this file and `DESARROLLO.md`, are mirrors: change one, change the other.
- Interface text goes through `L("English text")`, with its Spanish translation in `Resources/es.lproj/Localizable.strings` (see [Languages](#languages)).
- Merge to `main` once the CI is green.

## Known limits

- Apple Silicon only (arm64) and macOS 26 (Tahoe) or later. The process-tap API itself exists since macOS 14.2, but that is not what PinVol is built and tested on. Intel Macs and older macOS are not supported (use [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2) on macOS 14.2–15, or [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1) on Intel).
- At most 5 apps at once (`maxPinnedApps` in `Model.swift`): each one opens its own tap and aggregate device.
- With a very low system volume and a high pinned level the gain reaches its maximum (+24 dB) and can't compensate any further; the status line says so.
- On outputs without software volume control (some HDMI or USB devices) there is nothing to compensate and the app says so.
- Apps with DRM or protected processes may not be capturable.
- The `.dmg` is not notarized (that would need an Apple developer account).
- Because it is ad-hoc signed, every rebuild changes the signature and macOS may ask for the audio permission again.
