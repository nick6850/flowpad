# Flowpad

Flowpad is a native macOS utility for assigning keyboard shortcuts or application launches to trackpad gestures.

## Features

- 61 gesture definitions across one to five fingers and Force Touch.
- Two action types: keyboard shortcut and launch application.
- Searchable gesture library and grouped active bindings.
- Versioned, atomic JSON persistence with backups and per-record quarantine.
- Optional menu-bar item, launch at login, haptic feedback, precision and sensitivity controls.
- Dynamic MultitouchSupport loading, so the app remains buildable without private headers or link-time dependencies.
- Preferences window always remains recoverable from the Dock, Finder, menu item, or Command-comma.

## Build

```sh
swift build
.build/debug/Flowpad --self-test
./Scripts/build-app.sh
```

The build script creates `.build/app-bundle/Flowpad.app` and signs it ad hoc for local use.

Keyboard shortcut actions require Accessibility permission in System Settings. Launch Application actions do not.
