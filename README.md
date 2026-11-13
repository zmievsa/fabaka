# Flick

A personal ⌘Tab window switcher for macOS 26. It does what AltTab did for me, without screen capture, settings or a paid tier. Built after reading [MacTab](https://github.com/samuelcolvin/MacTab) and [AltTab](https://github.com/lwouis/alt-tab-macos).

## Behavior

- Hold ⌘ and press Tab to open the Switcher. Tab moves down, ⇧Tab moves up, and releasing ⌘ focuses the selected window.
- The Switcher appears the moment you press ⌘Tab. Settings can make it wait (0–300 ms), so a quick tap back to the previous window doesn't flash it; Tab or an arrow still shows it at once.
- While the Switcher is open (⌘ still held):
  - ↑ ↓ ← → move the selection.
  - Return focuses the selected window, and Esc cancels.
  - A click on a row focuses that window.
  - W closes the selected window, and Q quits its app.
- The list shows windows from every Space and every screen, including minimized windows, windows of hidden apps and full-screen windows.
- Below the windows come the Dock's running apps that have no windows, including frozen ones, so Q quits them too. Choosing one works like clicking it in the Dock. Resident apps are left out.
- Most recently focused windows come first.
- The Switcher appears on the screen of the focused window.
- Fathom is never listed. Remote desktop and VM apps keep ⌘Tab while they are full screen.
- Flick's few settings (Resident apps, and the quick-tap wait) sit behind its menu-bar icon. No auto-updates and no telemetry. It starts at login.

## Resident apps

Some apps run all the time on purpose: Tailscale keeps the VPN up, Ghostty answers its quick-terminal hotkey, macOS restarts Finder. With no windows open they aren't leftovers to quit, so ⌘Tab doesn't list them. Their windows are still listed.

Open Settings from the menu-bar icon (or open Flick.app again) and click an app to move it between the Stays and Flickable shelves. Apps that aren't running can be dragged from Finder onto Stays. Finder, Tailscale and Ghostty stay by default.

## Permissions

Flick needs Accessibility only, never Screen Recording ([ADR 0001](docs/adr/0001-no-screen-capture.md)).

## When ⌘Tab shows the system switcher instead

macOS hides key presses from every app while Secure Input is on, so Flick can't see ⌘Tab. A focused password field turns it on for a moment, but it can get stuck on for the whole session, often after a background app turns it on and never off. Lock and unlock the Mac (⌃⌘Q) to clear it. `make logs` reports it the next time you press ⌘; the holder macOS names there is often just the front app.

## Install

Flick needs macOS 26 on Apple silicon.

```sh
brew install zmievsa/tap/flick
open /Applications/Flick.app
```

Grant Accessibility when macOS asks. Flick starts working without a relaunch. Quit it with `pkill -x Flick`.

## Build from source

```sh
make install   # builds, signs with your Developer ID or Apple Development cert if you have one, copies to /Applications, starts it
make uninstall # stops it and removes it
make logs      # streams its log
make test      # end-to-end tests against a stand-in busy app; stops the installed Flick for ~2 minutes
make release   # notarizes, publishes a GitHub release and bumps the Homebrew cask (maintainer only)
```
