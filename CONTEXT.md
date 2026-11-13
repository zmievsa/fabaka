# Flick

A personal macOS window switcher that replaces ⌘Tab. It behaves like AltTab as its one user set it up, minus window pictures.

## Language

**Switcher**:
The panel that lists windows while ⌘ is held after pressing Tab.
_Avoid_: Picker, overlay, HUD

**Window list**:
The rows the Switcher shows, each with the app icon, window title and app name: one per window, then one per Windowless app.
_Avoid_: Thumbnails, previews, grid

**Recency order**:
Windows sorted by when they last had focus, most recent first.
_Avoid_: Z-order, stacking order, MRU

**Windowless app**:
A running app the Dock shows that has no window in the Window list. Unless it is a Resident app, it gets a row of its own, below every window.
_Avoid_: Empty app, background app

**Resident app**:
An app that runs all the time on purpose, such as a VPN or a terminal with a global hotkey, so it never gets a Windowless app row. Its windows are listed as usual. The one list Settings edits.
_Avoid_: Pinned app, whitelist, background app

**Lingering app**:
An app that keeps running after its last window closed only because closing a window doesn't quit it. What Windowless app rows are for.
_Avoid_: Zombie, leftover

**Selection**:
The one row in the Window list that releasing ⌘ will focus.
_Avoid_: Highlight, cursor

**Excluded app**:
An app whose windows never appear in the Window list.
_Avoid_: Exception, blacklist, ignored app

**Pass-through app**:
An app that keeps ⌘Tab for itself while one of its windows is full screen, such as a remote desktop or VM viewer.
_Avoid_: Exception, ignored app
