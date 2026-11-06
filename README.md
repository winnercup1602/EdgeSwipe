# EdgeSwipe

A free MacBook menu bar app. Swipe the trackpad's **left edge for volume** and **right edge for brightness**, with haptic feedback. Swap sides or pause from the menu.

Supports built-in Force Touch and Magic Trackpad on Apple Silicon, macOS 14+. Brightness requires the MacBook's built-in screen to be the only online display.

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

[Releases](https://github.com/winnercup1602/EdgeSwipe/releases) · [Release guide](RELEASING.md) · [MIT](LICENSE)

API references: [EdgePad](https://github.com/forkiron/EdgePad), [Mac Trackpad Wizard](https://github.com/jasonhejiahuan/Mac-Trackpad-Wizard).
