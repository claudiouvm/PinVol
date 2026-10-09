# Development

*Español: [DESARROLLO.md](DESARROLLO.md)*

## How it works

macOS has no per-app volume. PinVol uses **Core Audio process taps** (`AudioHardwareCreateProcessTap`, macOS 14.2+):

1. It creates a tap on the app's processes, helpers included (it matches by bundle-id prefix, which browsers and Electron apps need). The original audio is muted. Each pinned app has its own tap and its own level; if two apps share a prefix (`com.google.Chrome` and `com.google.Chrome.canary`), the processes go to the more specific one.
2. It plays that audio through a private aggregate device, applying a gain.
3. The gain is `pinned level ÷ system volume`, recomputed whenever the volume or the mute state changes, with a soft limiter and a +24 dB cap.

The important detail is how decibels are measured. The standard scalar→dB conversion that Core Audio exposes **does not match the curve the system really applies** (on Macs with built-in speakers it is quadratic: `dB = −63.5 × (1 − √volume)`). Using it makes the app get louder or quieter as you move the volume. PinVol reads the device's real dB (`kAudioDevicePropertyVolumeDecibels`) and inverts the device's own dB→scalar conversion to translate the slider level.

## Architecture

PinVol runs as **two instances of the same app**:

- **Resident**: Dock and menu bar, audio engines and saved settings. Always alive.
- **Interface** (`--ui`): shows the window and quits when it is closed.

They talk through `DistributedNotificationCenter`. The reason is memory: opening a window makes AppKit reserve about 8 MB to draw it, plus 5–7 MB for the native switches and slider, and the system does not give them back when you close the window. With the window in another process, that memory is released on close. With the window closed the resident process uses about 15–20 MB; while it is open, the interface instance adds about 22–25 MB.

All controls are native AppKit (`NSSwitch`, `NSSlider`, SF Symbols) and follow light and dark mode.

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
| `Updates.swift` | Latest-release lookup on GitHub |
| `Snapshot.swift` | Development only: window screenshots |

## Commands

| Command | What it does |
|---|---|
| `./build.sh` | Builds `build/PinVol.app` |
| `./build.sh install` | Also installs it in `/Applications` and opens it |
| `tools/make-dmg.sh` | Builds a universal binary and produces `dist/PinVol.dmg` |
| `./snapshot.sh` | Builds a development variant and renders PNG screenshots of the window (light/dark, 1 and 5 apps, every tab) into `build/snapshots/`, with no screen-recording permission needed |
| `python3 tools/make-icon.py` | Regenerates `Resources/AppIcon.icns` and the menu bar glyphs (`MenuBar*Template*.png`). Everything is drawn in code; needs `pip3 install pillow` |

`snapshot.sh` builds with `-DSNAPSHOT` and uses a different bundle identifier (`com.claudiouvm.pinvol.dev`), so it does not touch the real app's settings or permissions.

## Updates and releases

PinVol checks the latest GitHub release once a day (and on demand in **About**) and compares it with its own version. If there is a newer one it shows a banner in the window and a menu item that opens the release page; it never downloads or installs anything. It can be turned off in **Settings**. The check uses GitHub's public API, so the repository must be public.

To publish a version: raise `CFBundleShortVersionString` (and `CFBundleVersion`) in `Info.plist`, update `RELEASE_NOTES.md` (English first, then Spanish; CI requires its first line to name the version) and merge to `main`. The `Release` workflow then builds the universal `.dmg`, commits it to `dist/PinVol.dmg` and creates the release `v<version>` with those notes if it does not exist yet. If you only change the notes, run the manual `Release notes` workflow to copy them to the existing release.

To label a version as beta, add `PinVolReleaseChannel` = `Beta` to `Info.plist` (it shows in About and in the release title). Do not mark the release as "pre-release" on GitHub: the `releases/latest` API, which the app uses, ignores pre-releases.

## Known limits

- At most 5 apps at once (`maxPinnedApps` in `Model.swift`): each one opens its own tap and aggregate device.
- With a very low system volume and a high pinned level the gain reaches its maximum (+24 dB) and can't compensate any further; the status line says so.
- On outputs without software volume control (some HDMI or USB devices) there is nothing to compensate and the app says so.
- Apps with DRM or protected processes may not be capturable.
- The `.dmg` is not notarized (that would need an Apple developer account).
- Because it is ad-hoc signed, every rebuild changes the signature and macOS may ask for the audio permission again.
