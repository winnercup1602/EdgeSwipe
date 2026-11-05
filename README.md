# EdgeSwipe

A free macOS menu bar app that turns the edges of a Force Touch trackpad into volume and brightness controls.

- Swipe up or down along the **left edge** to adjust the default audio output.
- Swipe up or down along the **right edge** to adjust the display under the pointer when the gesture starts.
- An accepted gesture briefly holds the pointer in place. Confirmed steps provide a haptic tick on the trackpad in use.

## Status and compatibility

This repository is available as a **source preview**. The signed installer will be published in [Releases](https://github.com/winnercup1602/EdgeSwipe/releases) when available. The current menu is in Korean.

| Feature | Scope |
| --- | --- |
| Mac and trackpad | Apple Silicon. Tested on an M2 MacBook Air running macOS 27.2, with its built-in trackpad and a Bluetooth Magic Trackpad. |
| Brightness | MacBook display and external displays with a usable hardware brightness path. Direct DDC/CI was tested with an LG HDR 4K monitor. |
| DisplayLink | Requires DisplayLink Manager to report a valid hardware brightness value. The Dell P2723D was adjustable on some connections or sessions and unavailable on others with the same setup. |
| Brightness feedback | The MacBook display uses standard macOS brightness-key events when available. Confirmed external brightness changes request the macOS brightness indicator on the selected display. |
| Audio | The default audio device must expose a writable system volume. |

The project builds with a macOS 14 deployment target. The table lists the hardware and OS verified in use. Global touch coordinates, per-device haptics, and some brightness routes use undocumented macOS interfaces and may need updates after OS changes.

## Build and run locally

On an Apple Silicon Mac with the Xcode Command Line Tools:

```sh
git clone https://github.com/winnercup1602/EdgeSwipe.git
cd EdgeSwipe
./test.sh
./build-app.sh
open dist/EdgeSwipe.app
```

To make a local test installer, run `./build-dmg.sh --local`. The local image contains an ad hoc-signed app. See [release instructions](RELEASING.md) for Developer ID signing and notarization.

1. Launch EdgeSwipe and open its trackpad icon in the menu bar.
2. Grant the app access in **System Settings → Privacy & Security → Accessibility**. On macOS versions that use the **Device Control & Data Access** label, select that entry.
3. If the menu asks for **Input Monitoring**, enable it for EdgeSwipe as well.
4. Place one finger at the left or right edge and swipe vertically. Use **일시정지** to pause or **EdgeSwipe 종료** to quit.

## Privacy and license

Touch frames are processed locally for gesture recognition. The app uses local preferences and system logs, and communicates with DisplayLink Manager through local notifications. EdgeSwipe contains no account, telemetry, or network client.

The source is licensed under [MIT](LICENSE). The [AppleSiliconDDC MIT notice](Assets/AppleSiliconDDC-LICENSE.txt) accompanies the app. The DDC/CI implementation references [AppleSiliconDDC](https://github.com/waydabber/AppleSiliconDDC). [EdgePad](https://github.com/forkiron/EdgePad) and [Mac Trackpad Wizard](https://github.com/jasonhejiahuan/Mac-Trackpad-Wizard) are references for the macOS multitouch and actuator interfaces.
