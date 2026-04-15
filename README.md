# Desknet

Lightweight network debugging for macOS apps inspired by Netfox.

## Features

- Captures HTTP/HTTPS requests and responses.
- Independent desktop log window (`NSWindow`) for live inspection.
- Default shortcut `⌘⌃Z` (same as iOS simulator shake gesture).
- Netfox-style lifecycle: `start()`, `stop()`, `show()`, `hide()`.
- URL ignore patterns for noisy hosts.
- Search requests by URL/path/method/status/error text.

## Quick Start

```swift
import Desknet

// App startup (Debug builds only)
Desknet.shared.start()
```

Use `⌘⌃Z` while your app is focused to toggle the network window.

## Optional APIs

```swift
Desknet.shared.ignoreURL("analytics.example.com")
Desknet.shared.show()
Desknet.shared.hide()
Desknet.shared.setGesture(.custom(.init(key: "l", modifiers: [.command, .option])))
Desknet.shared.stop(clearLogs: true)
```

## Notes

- Intended for local development and QA builds.
- Interception is based on `URLProtocol`, so requests must flow through `URLSession`/URL loading system.
- Clicking a request row updates details in the same Desknet window.

## Debug Logs

Desknet now emits internal diagnostics for tap/selection/detail rendering and network interception.

```swift
Desknet.shared.setDebugLoggingEnabled(true)
let lines = Desknet.shared.debugLogs()
print(lines.joined(separator: "\n"))
```

You can also stream unified logs from Terminal:

```bash
log stream --level debug --predicate 'subsystem == "Desknet"'
```
