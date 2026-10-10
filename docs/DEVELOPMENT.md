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

The resident opens the window by launching the interface with `--ui` (or, if it is already running, by sending it a `show` message). To open it on a given tab — **About PinVol** in the menu bar icon's menu opens the About tab — the launch adds `--tab about` and the message carries a `tab` field (`openWindow` in `main.swift`, `UIDelegate`).

All controls are native AppKit (`NSSwitch`, `NSSlider`, SF Symbols). They follow light and dark mode and, since the app is built with the macOS 26 SDK, the system's current look.

The code lives in `Sources/PinVol/`, split by responsibility:

| File | Contents |
|---|---|
| `main.swift` | Resident instance (Dock, menu bar) and startup |
| `UIDelegate.swift` | Interface instance (`--ui`) and the main menu |
| `Controller.swift` | Saved state, one `Engine` per app, interface messages and the update check |
| `Audio.swift` | Core Audio: tap, aggregate device, gain, system volume |
| `Model.swift` | `AppState`, `PinnedApp`, inter-process messaging |
| `SettingsWindow.swift` | Tabbed window (Apps, Settings, About) and its resize animation. The **Buy me a coffee!** button in About opens the PayPal donation page (`donateURL`) |
| `AppsPanel.swift` | Drop zone and app rows |
| `Style.swift` | Shared labels, cards and settings rows |
| `Strings.swift` | Interface text (`L("…")`) and language-aware number formats |
| `Updates.swift` | Latest-release lookup on GitHub (version, `.dmg` and its checksum) |
| `Installer.swift` | Download and install of a new version (resident instance only) |
| `Snapshot.swift` | Development only: window screenshots |
| `SelfTest.swift` | Development only: `--selftest-install`, the update installer test the CI runs |

## Startup at login

When "Open at login" launches PinVol (for instance when the Mac is turned on) and at least one app is already pinned (`Controller.isConfigured`), the resident instance goes straight to the menu bar, or to the Dock if the menu bar icon is off, and does not open the window. When the user opens the app, or while nothing is pinned yet, the window opens as usual.

macOS marks a login-item launch in the open-application Apple event, but not always, so there is a fallback: a start a few seconds after the user's session began (the start time of their `loginwindow` process) counts as a login start too: within a minute when "Open at login" is on, within 25 seconds otherwise, so that a manual launch right after logging in is not mistaken for it. If the session cannot be found, only a Mac turned on less than two minutes ago counts, and only with "Open at login" on. A reopen event in the first 10 seconds is ignored for the same reason. The decision is logged: `log show --last 10m --predicate 'subsystem == "com.claudiouvm.pinvol"'`.

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
| `tools/test-install.sh` | Tests the update installer on a real macOS: mounts the freshly built `.dmg` and swaps an older "installed" app (marked with the quarantine flag, as a browser leaves it) for it, checking that the new one does not keep the mark (needs `tools/make-dmg.sh` and the `-DSNAPSHOT` build first; the CI runs it) |
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
| `Release` (`release.yml`) | Pull requests and pushes to `main` (skipped if only `dist/`, `docs/`, `.md` files or `.github/FUNDING.yml` change) | Checks the translations (`tools/check-strings.py`). Compiles the screenshot variant too, so the `-DSNAPSHOT` code is checked. Builds the arm64 `.dmg` and checks `Info.plist`, the icon, the bundle resources, that the binary is arm64-only and that `RELEASE_NOTES.md` names the version. Tests the update installer (`tools/test-install.sh`). Uploads the `PinVol-dmg` and `capturas` artifacts. On `main` it also commits `dist/PinVol.dmg` (a bot commit marked `[skip ci]`) and creates the release `v<version>` if it does not exist yet. |
| `Screenshots` (`screenshots.yml`) | Manual, or in a pull request that changes `snapshot.sh` or the workflow itself | Installs Spotify, IINA and TIDAL, takes the screenshots (English and Spanish) and uploads them as `capturas-portada`. The front-page images are `en/light-five.png` and `en/dark-five.png` from that artifact (`docs/apps-claro.png` and `docs/apps-oscuro.png`, for `README.md`) and `es/light-five.png` and `es/dark-five.png` (`docs/apps-claro.es.png` and `docs/apps-oscuro.es.png`, for `README.es.md`). |
| `Release notes` (`release-notes.yml`, `ubuntu-latest`) | Manual | Copies `RELEASE_NOTES.md` to the release of the version in `Info.plist`. |

Swift cannot be compiled on Linux, so the CI is the real build. The artifacts are the way to review the window's design.

## Updates and releases

PinVol checks the latest GitHub release once a day (and on demand in **About**, or with **Check for updates…** in the menu bar icon's menu) and compares it with its own version. If there is a newer one it shows a banner in the window and a menu item; nothing is downloaded or installed until the user asks (see below). It can be turned off in **Settings**. From the menu bar the resident instance has no window to show the result in, so it appears next to the icon for a few seconds (`noteInMenuBar` in `main.swift`). The check uses GitHub's public API, so the repository must be public.

**In-app install.** **Download** (banner, About or the menu bar icon's menu) downloads the release's `PinVol.dmg` to `~/Library/Caches/com.claudiouvm.pinvol/Updates` and checks it against the SHA-256 that the GitHub API publishes for the asset (`digest`); the item then becomes **Install PinVol X and restart**. Installing (`UpdateInstaller.install`) mounts the image read-only and hidden, checks that the app inside has the same bundle identifier, the expected version (newer than the installed one) and an intact signature, copies it next to the installed one, swaps them with `FileManager.replaceItemAt`, removes the quarantine mark from the installed app (the swap can leave the old app's attributes on the new one) and removes the image. Then the resident instance stops its engines, opens a new instance with `--updated` (it starts without the window and shows "Updated to X" next to the icon) and quits. If the new instance can't be opened, it keeps running with its engines and shows "Installed · reopen PinVol" instead of leaving the Mac without PinVol (`relaunch` in `main.swift`). Trust is the same as downloading the `.dmg` by hand: the app is ad-hoc signed, so there is no identity to verify and the checksum only guards against damaged downloads.

If the app's folder is not writable (not in Applications, or running from a disk image) or macOS refuses (Privacy & Security → App Management), the installer fails with `.notWritable` or `.permission` and the disk image is opened so the user can drag the app, as before. Other failures show their reason in About and the state goes back to "available". Updating changes the ad-hoc signature, so macOS may ask for the audio permission again. The steps are logged under the `com.claudiouvm.pinvol` subsystem, category `update`. The CI tests the installer for real (`tools/test-install.sh` runs `--selftest-install` of the `-DSNAPSHOT` binary against the `.dmg` it just built), so keep `SelfTest.swift` in step with `Installer.swift`.

To publish a version: raise `CFBundleShortVersionString` (and `CFBundleVersion`) in `Info.plist`, update `RELEASE_NOTES.md` (English first, then Spanish; CI requires its first line to name the version) and merge to `main`. The `Release` workflow then builds the arm64 `.dmg`, commits it to `dist/PinVol.dmg` and creates the release `v<version>` with those notes if it does not exist yet. If you only change the notes, run the manual `Release notes` workflow to copy them to the existing release.

Raise the version whenever the binary or its requirements change (chip, macOS, behavior): otherwise `dist/PinVol.dmg` and the attached `.dmg` of the existing release stop matching.

To label a version as beta, add `PinVolReleaseChannel` = `Beta` to `Info.plist` (it shows in About and in the release title). Do not mark the release as "pre-release" on GitHub: the `releases/latest` API, which the app uses, ignores pre-releases.

## Conventions

- Descriptions on GitHub (pull requests, releases, issues) go in English first, then Spanish. Code, comments and commit messages are in Spanish.
- `README.md` and `README.es.md`, and this file and `DESARROLLO.md`, are mirrors: change one, change the other.
- Interface text goes through `L("English text")`, with its Spanish translation in `Resources/es.lproj/Localizable.strings` (see [Languages](#languages)).
- Merge to `main` once the CI is green.
- The donation link is in two places that must match: the **Buy me a coffee!** button of About (`SettingsWindow.donateURL`) and GitHub's **Sponsor** button (`.github/FUNDING.yml`).

## Known limits

- Apple Silicon only (arm64) and macOS 26 (Tahoe) or later. The process-tap API itself exists since macOS 14.2, but that is not what PinVol is built and tested on. Intel Macs and older macOS are not supported (use [1.2](https://github.com/claudiouvm/PinVol/releases/tag/v1.2) on macOS 14.2–15, or [1.1](https://github.com/claudiouvm/PinVol/releases/tag/v1.1) on Intel).
- At most 5 apps at once (`maxPinnedApps` in `Model.swift`): each one opens its own tap and aggregate device.
- With a very low system volume and a high pinned level the gain reaches its maximum (+24 dB) and can't compensate any further; the status line says so.
- On outputs without software volume control (some HDMI or USB devices) there is nothing to compensate and the app says so.
- Apps with DRM or protected processes may not be capturable.
- The `.dmg` is not notarized (that would need an Apple developer account).
- Because it is ad-hoc signed, every rebuild or update changes the signature and macOS may ask for the audio permission again.
- The in-app install needs a writable folder and, on some Macs, the App Management permission; the first version with it (1.6) has to be installed by hand.
