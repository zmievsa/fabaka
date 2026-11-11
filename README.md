# Flick

A personal ⌘Tab window switcher for macOS 26. It does what AltTab did for me, without screen capture, settings or a paid tier. Built after reading [MacTab](https://github.com/samuelcolvin/MacTab) and [AltTab](https://github.com/lwouis/alt-tab-macos).

## Behavior

- Hold ⌘ and press Tab to open the Switcher. Tab moves down, ⇧Tab moves up, and releasing ⌘ focuses the selected window.
- The Switcher appears the moment you press ⌘Tab. There are no built-in waits.
- While the Switcher is open (⌘ still held):
  - ↑ ↓ ← → move the selection.
  - Return focuses the selected window, and Esc cancels.
  - A click on a row focuses that window.
  - W closes the selected window, and Q quits its app.
- The list shows windows from every Space and every screen, including minimized windows, windows of hidden apps and full-screen windows. Apps with no windows are left out.
- Most recently focused windows come first.
- The Switcher appears on the screen of the focused window.
- Fathom is never listed. Remote desktop and VM apps keep ⌘Tab while they are full screen.
- Flick has no settings, no menu-bar icon, no auto-updates and no telemetry. It starts at login.

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
make release   # notarizes, publishes a GitHub release and bumps the Homebrew cask (maintainer only)
```
