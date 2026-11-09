# EdgeSwipe

A free MacBook menu bar app for trackpad edge controls: volume, display and keyboard brightness, app switching, video seeking and media. Includes configurable taps and haptics.

Supports built-in Force Touch and Magic Trackpad on Apple Silicon, macOS 14+. External brightness uses DDC/CI, software dimming on direct displays, or a compatible DisplayLink connection.

## Install

Open the DMG, drag **EdgeSwipe.app** to **Applications**, and follow the permission guide.

Ad-hoc builds may require **Privacy & Security → Open Anyway** on first launch. Enable **Input Monitoring** if requested.

## Build

With Xcode Command Line Tools installed:

```sh
./test.sh
./build-app.sh
open dist/EdgeSwipe.app
```

[Releases](https://github.com/winnercup1602/EdgeSwipe/releases) · [Features](FEATURES.md) · [Release guide](RELEASING.md) · [MIT](LICENSE)

[Credits](CREDITS.md).
