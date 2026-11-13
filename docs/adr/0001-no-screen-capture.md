# No screen capture, so no window pictures

Fabaka never captures the screen and never asks for Screen Recording permission. The Window list shows icons and titles instead of thumbnails or live previews. AltTab's window capture is known to stall every screenshot tool on the Mac for tens of seconds ([alt-tab-macos#5861](https://github.com/lwouis/alt-tab-macos/issues/5861), [#6143](https://github.com/lwouis/alt-tab-macos/issues/6143)), and that matched the Shottr breakage that started this project. Titles come from the Accessibility API, because `kCGWindowName` is blank without Screen Recording.

## Consequences

Never add a feature that needs `ScreenCaptureKit`, `CGWindowListCreateImage` or `CGSHWCaptureWindowList`. That includes "just one small preview".
