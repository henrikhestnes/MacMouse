# MacMouse

Pointer speed, scroll wheel and mouse button settings for mice, from the menu bar. A small, dependency-free port of [LinearMouse](https://github.com/linearmouse/linearmouse) that behaves like it for one scheme: one set of settings for the mice you pick. Swift, AppKit and SwiftUI. Requires macOS 14 or newer.

Settings apply only to the mice chosen under **Apply to**, by default the Logitech USB Receiver (046d:c548). Other mice and all trackpads are left alone.

## Install

```sh
brew install --cask henrikhestnes/tap/macmouse
```

Update with `brew update` and `brew upgrade --cask macmouse`. You can also download `MacMouse.zip` from the [latest release](https://github.com/henrikhestnes/MacMouse/releases/latest) and move **MacMouse.app** to **Applications**. The release is signed with a self-signed certificate and not notarized by Apple, so macOS may block it through Gatekeeper.

To build from source instead:

```sh
./scripts/build.sh
cp -R dist.noindex/MacMouse.app /Applications/
open /Applications/MacMouse.app
```

`./scripts/build.sh --universal` builds for both Apple silicon and Intel.

MacMouse turns on **Launch at Login** the first time it runs. Turn it off from the menu bar icon or the settings window; MacMouse won't turn it back on.

On first launch, macOS asks for **Accessibility** access, which MacMouse needs to change scroll wheel and button events. Enable it in **System Settings → Privacy & Security → Accessibility**. MacMouse picks the permission up within two seconds, without a relaunch. Pointer speed works without it.

Releases are signed with the same self-signed "MacSnip Release" certificate as MacSnip, so the permission carries over to upgrades. Every build uses the hardened runtime, which stops other processes from injecting code into an app that holds this permission. Builds from source are ad-hoc signed unless that certificate is in your keychain, and macOS treats every ad-hoc rebuild as a new app and silently stops honoring the permission. After rebuilding, remove MacMouse from that list (−), add it again, and relaunch.

Quit LinearMouse before using MacMouse: if both reverse the wheel, the reversals cancel out. While LinearMouse runs, the menu says so and offers **Quit LinearMouse**.

## Settings

Open **Settings…** from the menu bar icon, or open the app again from Finder.

| Setting | Default | Effect |
| --- | --- | --- |
| Apply to | USB Receiver (046d:c548) | The mice the settings below apply to, or *All mice* |
| Pointer speed | 0.10 | 0 slowest, 1 fastest |
| Pointer acceleration | 5.0 | 0 to 20; macOS's own is about 0.7 |
| Disable pointer acceleration | Off | Linear pointer movement |
| Reverse vertical / horizontal scrolling | On / On | |
| Vertical / horizontal distance | 4 / 5 lines | Lines per wheel tick, or *System* for macOS's accelerated scrolling |
| ⌘ + scroll zooms | On | Presses ⌘+ or ⌘− for your keyboard layout, at most once every 0.3 seconds |
| Middle button | Default | |
| Back button | Back | |
| Forward button | Forward | |
| Button 6 | Mission Control | |

Buttons can do Default, Back, Forward, Middle Click, Mission Control, App Exposé, Show Desktop, or nothing. As in LinearMouse, a mapping applies only when no modifier key is held as the button goes down; Back, Forward and Middle Click remap the whole click, and the other actions run when the button is released. **Restore Defaults** puts everything back. **Enabled** in the menu pauses MacMouse and restores each mouse's own pointer values, as does quitting.

## How it works

MacMouse ports the parts of LinearMouse its settings use, in the same order and with the same arithmetic, so a LinearMouse configuration like the default one behaves the same:

- **Devices**: pointing devices are the HID services with the mouse or pointer usage; trackpads (touchpad digitizers, except the Magic Mouse) are never matched. Each event is attributed to a device by its HID sender ID. Events without one, such as those other apps post, belong to the pointing device used last. Events posted by Shottr and Homerow are left alone, as in LinearMouse.
- **Pointer**: sets `HIDPointerResolution` (LinearMouse's speed-to-resolution mapping) and the acceleration property on each matching mouse through a full `IOHIDEventSystemClient`. Pausing or quitting restores the mouse's initial resolution and the system's acceleration. MacMouse checks every two seconds and rewrites any value a reconnect or System Settings reset.
- **Scrolling and buttons**: a Quartz event tap at the HID level, on its own thread, runs LinearMouse's pipeline: reverse, fixed line distance (horizontal, then vertical), then ⌘ zoom, with the zoomed gesture's momentum discarded. The rules live in `MacMouseCore` and are unit tested.
- **Zoom keys**: found the way LinearMouse does, by asking AppKit which main-row key with ⌘ triggers a localized + or − menu shortcut, and posted as hardware-like key events followed by a modifier restore.

Not ported, because the default settings don't use them: smoothed scrolling, pixel distances, scroll acceleration and speed, Logitech HID++ features (DPI, high-resolution wheel, diverted buttons), gestures, auto scroll, per-app and per-display schemes.

`IOHIDEventSystemClientCreate`, `CGEventCopyIOHIDEvent`, `IOHIDEventGetSenderID` and `CoreDockSendNotification` (Mission Control, App Exposé, Show Desktop) are private but long-stable functions, also used by LinearMouse. A future macOS update could break them.

Parts of this logic are ported from LinearMouse, which is MIT licensed; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Development

```sh
swift build
swift test
```
