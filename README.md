# EdgeSwipe

A free MacBook menu bar app for volume and built-in display brightness gestures on a Force Touch trackpad.

- Swipe vertically along the **left edge** to adjust the default audio output.
- Swipe vertically along the **right edge** to adjust the MacBook display brightness.
- Swap the two controls from **가장자리 기능** in the menu. The choice is saved across app restarts.
- Swipe up to increase and down to decrease. Confirmed changes produce a haptic tick on the trackpad in use, with strength proportional to the resulting level.
- The pointer stays still during a recognized gesture and releases when the gesture ends or input is interrupted.

## Download and install

Download the Apple Silicon DMG from [Releases](https://github.com/winnercup1602/EdgeSwipe/releases). Open it and drag **EdgeSwipe.app** into **Applications**.

The downloadable build uses ad-hoc signing. First launch can require approval in **System Settings → Privacy & Security → Open Anyway**. Apple's [unknown developer guide](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac) explains the approval process.

1. Open EdgeSwipe from Applications. A setup guide appears when Accessibility access is missing; you can also open it from the menu bar.
2. Use the guide's **설정 열기** button, then drag its app icon into the settings list and turn on EdgeSwipe. If it is already listed, turn on its switch. You can also add the app with the list's **+** button. The guide detects permission changes without restarting. Some macOS versions label this access **Device Control & Data Access**; the guide uses the system's name. Apple's [accessibility permission guide](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac) explains the system permission controls.
3. If the menu requests **Input Monitoring**, enable it for EdgeSwipe as well.
4. Start one finger in the outer 5% of either trackpad edge and swipe vertically. Clicking, adding another finger, moving sideways, or leaving the edge cancels the gesture.
5. Use **일시정지** to pause and **EdgeSwipe 종료** to quit.

An ad-hoc signed update can require granting access again. The menu shows permission and device status. The current menu is in Korean.

## Supported setup

| Feature | Scope |
| --- | --- |
| Mac | Apple Silicon MacBook with a Force Touch trackpad. |
| Display | The MacBook's built-in screen must be the only online display for brightness gestures. The menu reports when a different display configuration is connected. |
| Trackpads | Built-in Force Touch trackpad and supported Magic Trackpad devices over Bluetooth or USB. |
| Brightness | Standard macOS brightness-key input, confirmed by reading the built-in display level. Brightness stays at or above one system step. |
| Audio | The default output device must expose a writable system volume. |
| Feedback | macOS displays its system controls. Other applications that handle brightness keys can affect their behavior. |

Hardware testing used an M2 MacBook Air running macOS 27.2, its built-in trackpad, and a Bluetooth Magic Trackpad. CI builds and tests on macOS 26. The deployment target is macOS 14. Trackpad input and per-device haptics use undocumented macOS interfaces, so hardware and OS compatibility require verification on each supported setup.

## Build from source

Install the Xcode Command Line Tools on an Apple Silicon Mac, then run the following.

```sh
git clone https://github.com/winnercup1602/EdgeSwipe.git
cd EdgeSwipe
./test.sh
./build-app.sh
open dist/EdgeSwipe.app
```

Create an ad-hoc signed DMG with `./build-dmg.sh --local`. See [release instructions](RELEASING.md) for packaging, hardware checks, and Developer ID signing.

The earlier external-display implementation is preserved on [experimental/external-displays](https://github.com/winnercup1602/EdgeSwipe/tree/experimental/external-displays).

## Privacy and license

Touch frames are processed locally. Preferences and diagnostic system logs stay on the Mac. EdgeSwipe has no account, analytics, or network client.

The source is licensed under [MIT](LICENSE). [EdgePad](https://github.com/forkiron/EdgePad) and [Mac Trackpad Wizard](https://github.com/jasonhejiahuan/Mac-Trackpad-Wizard) provide references for the macOS multitouch and actuator interfaces.
