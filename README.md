# Flick

A personal ⌘Tab window switcher for macOS 26. It does what AltTab did for me, without screen capture, settings or a paid tier. Built after reading [MacTab](https://github.com/samuelcolvin/MacTab) and [AltTab](https://github.com/lwouis/alt-tab-macos).

## Behavior

- Hold ⌘ and press Tab to open the Switcher. Tab moves down, ⇧Tab moves up, and releasing ⌘ focuses the selected window.
- If you release within 100 ms, nothing appears and you jump back to the previous window.
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

## Install

```sh
make install   # builds, signs with the Apple Development cert, copies to /Applications, starts it
make uninstall # stops it and removes it
make logs      # streams its log
```

Quit it with `pkill -x Flick`.
