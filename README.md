# MacMouse

Pointer speed, scroll wheel and mouse button settings for mice, from the menu bar. A small, dependency-free take on [LinearMouse](https://github.com/linearmouse/linearmouse), with its settings in one window instead of per-device schemes. Swift, AppKit and SwiftUI. Requires macOS 14 or newer.

Settings apply to mice only. Trackpads keep the settings from System Settings.

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
| Pointer speed | 0.10 | 0 slowest, 1 fastest |
| Pointer acceleration | 5.0 | 0 to 20; macOS's own is about 0.7 |
| Disable pointer acceleration | Off | Linear pointer movement |
| Reverse vertical / horizontal scrolling | On / On | Reverses the wheel, not the trackpad |
| Vertical / horizontal distance | 4 / 5 lines | Lines per wheel tick, or *System* for macOS's accelerated scrolling |
| ⌘ + scroll zooms | On | Presses ⌘+ or ⌘− (at most about three steps a second) |
| Middle button | Default | |
| Back button | Back | |
| Forward button | Forward | |
| Button 6 | Mission Control | |

Buttons can do Default, Back, Forward, Middle Click, Mission Control, App Exposé, Show Desktop, or nothing. **Restore Defaults** puts everything back. **Enabled** in the menu pauses MacMouse and restores each mouse's own pointer values, as does quitting.

## How it works

- **Pointer**: MacMouse sets `HIDPointerResolution` and the acceleration property on each mouse's HID service through a full `IOHIDEventSystemClient`, using LinearMouse's mapping from speed to resolution. Trackpads are skipped (the Magic Mouse counts as a mouse). It reapplies the values every two seconds if a reconnecting mouse or System Settings resets them; it only writes values that differ.
- **Scroll wheel and buttons**: a Quartz event tap rewrites wheel ticks (non-continuous scroll events, so trackpad and Magic Mouse scrolling are left alone) and the extra mouse buttons. The rules live in `MacMouseCore` and are unit tested.

`IOHIDEventSystemClientCreate` and `CoreDockSendNotification` (Mission Control, App Exposé, Show Desktop) are private but long-stable functions, also used by LinearMouse. A future macOS update could break them.

## Development

```sh
swift build
swift test
```
