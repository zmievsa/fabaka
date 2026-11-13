# Fabaka

[fabaka.dev](https://fabaka.dev)

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
- Fabaka has no menu-bar icon. Open Fabaka.app again (from Spotlight, Raycast or Finder) to get its few settings: Resident apps, the quick-tap wait, and a Quit button. No auto-updates and no telemetry. It starts at login.

## Resident apps

Some apps run all the time on purpose: Tailscale keeps the VPN up, Ghostty answers its quick-terminal hotkey, macOS restarts Finder. With no windows open they aren't leftovers to quit, so ⌘Tab doesn't list them. Their windows are still listed.

Open Fabaka.app again to get Settings, and click an app to move it between the Stay and Free to go shelves. Apps that aren't running can be dragged from Finder onto Stay. Finder, Tailscale and Ghostty stay by default.

## Permissions

Fabaka needs Accessibility only, never Screen Recording ([ADR 0001](docs/adr/0001-no-screen-capture.md)).

## When ⌘Tab shows the system switcher instead

macOS hides key presses from every app while Secure Input is on, so Fabaka can't see ⌘Tab. A focused password field turns it on for a moment, but it can get stuck on for the whole session, often after a background app turns it on and never off. Lock and unlock the Mac (⌃⌘Q) to clear it. `make logs` reports it the next time you press ⌘; the holder macOS names there is often just the front app.

## Install

Fabaka needs macOS 26 on Apple silicon.

```sh
brew install zmievsa/tap/fabaka
open /Applications/Fabaka.app
```

Grant Accessibility when macOS asks. Fabaka starts working without a relaunch. Quit it from Settings, or with `pkill -x Fabaka`.

### Coming from Flick

Fabaka used to be called Flick. Installing Fabaka replaces Flick.app and carries its settings over, but macOS asks for Accessibility again because it's a new app to macOS.

```sh
brew update && brew install --cask zmievsa/tap/fabaka && open /Applications/Fabaka.app
```

## Build from source

```sh
make install   # builds, signs with your Developer ID or Apple Development cert if you have one, copies to /Applications, starts it
make uninstall # stops it and removes it
make logs      # streams its log
make test      # end-to-end tests against a stand-in busy app; stops the installed Fabaka for ~2 minutes
make release   # notarizes, publishes a GitHub release and bumps the Homebrew cask (maintainer only)
make site      # deploys site/public to fabaka.dev (Cloudflare Workers static assets)
```
