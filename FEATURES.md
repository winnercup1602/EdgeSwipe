# Controls

| Gesture or setting | Behavior |
| --- | --- |
| Left / right edge | Volume / display brightness; sides can be swapped. |
| Top / bottom edge | Choose App Switching, Video Seeking, Keyboard Brightness, Media or Off independently. |
| App Switching | Shows the native ⌘Tab switcher while sliding. Right selects next, left selects previous; lift to confirm. Interruptions cancel. |
| Media edge | Tap to play/pause; slide left/right for previous/next track. |
| Video edge | Sends left/right arrow keys to the frontmost player. The player must support those seek shortcuts. |
| Corner double tap | Assign Mute, Screenshot Toolbar or Off to each corner. Corners start off. |
| Three-finger tap | Optional middle click at the Quartz cursor position, including external screens. Starts off. |
| Precision | Quarter-sized volume/brightness steps (1/64 instead of 1/16). |
| Haptics | Off, Light, Medium, Strong; level controls retain a nonzero floor and linear gain. Only the input trackpad vibrates. |
| Edge width | Narrow, Standard, Wide. |
| Bottom quarter | Restricts the left/right sliders to their lower quarter. |
| Gesture key | None, Option, Control, Shift, Command or Fn; held or press-to-toggle mode. |
| Cursor freeze | Optional; released on gesture end, click, interruption, pause or permission loss. |
| Accidental input | Multitouch, palm-sized contacts and recent typing cancel sliders; recognition waits for stable single-finger input. |
| Per-app pause | Pause in the current app or add apps from a picker; remove entries from the same menu. |
| Lifecycle | Rediscover trackpads and display backends after wake/reconnection. |
| Setup | A small drag card follows System Settings and closes when permission is granted. Includes What's New and Reset to Defaults. |
| Login | Uses macOS Login Items; requires system approval if macOS requests it. |
| Updates | Sparkle with Ed25519-signed archives and signed feeds. Automatic checking is opt-in. |

Built-in brightness uses standard macOS brightness keys and confirms the result through DisplayServices. Direct displays use DDC/CI when available and software dimming otherwise. Brightness keys follow the pointer on supported direct displays, and swipes target the display under the pointer at gesture start. DisplayLink uses confirmed backlight writes.

Three-finger middle click can conflict with macOS three-finger dragging or Look Up. EdgeSwipe leaves those system settings under the user's control. The menu also provides per-app pause.

Inputs are processed locally. Update checks request the public GitHub feed; Sparkle profile submission is disabled. There is no account, trial limit or license activation.

## Verification

The automated suite covers all four edges, cancellation, direction reversal, two-finger arrival, edge regions, tap timing, click-pair suppression, haptic levels, precision, key modes and app-switcher key cleanup. Application self-tests cover preference migration, persistence, defaults and menu actions.

Local control-path checks on an M2 MacBook Air / macOS 27.2 confirmed normal and fine volume/brightness changes, brightness cancellation, and keyboard backlight changes, then restored the original values. Trackpad callbacks and haptic handles were opened successfully.

Native app-switcher input checks confirmed app activation and return to the original app, reverse-selection confirmation, cancellation, and release after missing frames. Hardware modifier state stayed separate from the synthetic Command key.

On a direct BenQ GW2760HS, the software fallback was checked through the swipe adjustment path and normal, repeated and fine brightness key events. The original color curve was restored after the test. Physical Magic Trackpad gestures and the full range of external backlight connections still require hardware validation.
