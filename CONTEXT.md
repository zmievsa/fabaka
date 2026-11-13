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
A running app the Dock shows that has no window in the Window list. It gets a row of its own, below every window.
_Avoid_: Empty app, background app

**Selection**:
The one row in the Window list that releasing ⌘ will focus.
_Avoid_: Highlight, cursor

**Excluded app**:
An app whose windows never appear in the Window list.
_Avoid_: Exception, blacklist, ignored app

**Pass-through app**:
An app that keeps ⌘Tab for itself while one of its windows is full screen, such as a remote desktop or VM viewer.
_Avoid_: Exception, ignored app
