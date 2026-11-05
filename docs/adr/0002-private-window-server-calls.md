# Private macOS calls for other Spaces and focus

Flick lists and focuses windows on every Space, like AltTab. Public APIs can't do that: `kAXWindows` hides other-Space windows, and since macOS 14 `NSRunningApplication.activate` is only a request. So Flick uses the same private calls as AltTab and yabai:
- `_AXUIElementCreateWithRemoteToken` brute force to reach other-Space windows
- `_SLPSSetFrontProcessWithOptions` plus a synthetic `SLPSPostEventRecordTo` mouse-down to make a window key
- `_AXUIElementGetWindow` to map Accessibility elements to window IDs

MacTab avoids these and only switches within the current Space. Flick rejected that because it doesn't match how AltTab behaves.

## Consequences

A macOS update can break these calls. When it does, check how [alt-tab-macos](https://github.com/lwouis/alt-tab-macos/blob/master/src/macos/api-wrappers/SkyLight.framework.swift) fixed it first.
