# Desknet

Desknet is a lightweight network inspector for macOS desktop development. It is inspired by Netfox, but built for Mac apps: start it from your app, capture HTTP/HTTPS traffic, and open an independent SwiftUI network log window with the same `Command-Control-Z` shortcut used for the iOS Simulator shake gesture.

<img width="1092" height="732" alt="Screenshot 2026-04-15 at 21 49 30" src="https://github.com/user-attachments/assets/30141382-1e87-4317-9702-af280ea25a1c" />


Desknet is intended for debug, local development, and QA builds. It should not be shipped in production builds unless you have made an intentional security and privacy review.

## Features

- Captures eligible `http` and `https` traffic through Foundation URL loading.
- Opens a standalone resizable `NSWindow` titled `Desknet Network Logs`.
- Uses a SwiftUI monitor UI hosted from AppKit for easy desktop integration.
- Toggles with `Command-Control-Z` by default.
- Supports custom shortcuts or disabling the shortcut entirely.
- Shows request method, status, duration, response size, base URL, endpoint, headers, request body, and response body.
- Splits long URLs into `Base URL` and `Endpoint` so the detail panel stays readable.
- Formats JSON request and response bodies when possible.
- Provides search across URL, path, host, method, status, and error text.
- Lets you ignore noisy URLs by substring match against the host or absolute URL.
- Exposes captured logs through `Desknet.shared.capturedRequests`.
- Includes optional in-memory and unified logging diagnostics.

## Requirements

- macOS 11 or newer.
- Swift 5.10 or newer.
- A macOS app using Foundation URL loading APIs such as `URLSession`.

Desknet is a Swift Package Manager library target and currently declares `.macOS(.v11)` for Big Sur compatibility.

## Installation

Add Desknet as a Swift Package dependency in Xcode:

```shell
https://github.com/AriestaAgung/Desknet.git
```

Then link the `Desknet` product to your macOS app target.

## Quick Start

Start Desknet when your app launches. The safest pattern is to include it only in debug builds:

```swift
import Desknet

#if DEBUG
Desknet.shared.start()
#endif
```

Press `Command-Control-Z` while your app is focused to show or hide the network monitor window.

You can also open it manually:

```swift
#if DEBUG
Desknet.shared.show()
#endif
```

## SwiftUI App Example

For a SwiftUI macOS app, start Desknet from your `App` initializer:

```swift
import SwiftUI
import Desknet

@main
struct ExampleApp: App {
    init() {
        #if DEBUG
        Desknet.shared.start()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

## AppKit App Example

For an AppKit app, start it from `applicationDidFinishLaunching`:

```swift
import AppKit
import Desknet

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        Desknet.shared.start()
        #endif
    }
}
```

## API

### Start and Stop

```swift
Desknet.shared.start()
Desknet.shared.start(gesture: .simulatorShakeShortcut)
Desknet.shared.stop(clearLogs: true)
```

`start()` enables capture, registers Desknet's `URLProtocol`, and starts the shortcut monitor.

`stop(clearLogs:)` unregisters capture, stops the shortcut monitor, hides the window, and optionally clears stored requests.

### Window Control

```swift
Desknet.shared.show()
Desknet.shared.hide()
Desknet.shared.toggle()
```

The monitor opens in its own `NSWindow`. Desknet enforces a minimum window size and resets saved frames that are too small, so the monitor should not reopen in a collapsed state.

### Shortcuts

The default shortcut is equivalent to the iOS Simulator shake shortcut. It is implemented as a local key monitor, so the app must be focused for the shortcut to fire:

```swift
Desknet.shared.start(gesture: .simulatorShakeShortcut)
```

Use a custom shortcut:

```swift
Desknet.shared.start(
    gesture: .custom(
        DesknetShortcut(key: "l", modifiers: [.command, .option])
    )
)
```

Disable the shortcut while still allowing manual `show()`, `hide()`, and `toggle()`:

```swift
Desknet.shared.start(gesture: .disabled)
```

You can change the active shortcut after start:

```swift
Desknet.shared.setGesture(.custom(.init(key: "n", modifiers: [.command, .control])))
```

### Ignoring URLs

Ignore noisy hosts or URL substrings:

```swift
Desknet.shared.ignoreURL("analytics.example.com")
Desknet.shared.ignoreURL("/health")
```

Clear all ignored patterns:

```swift
Desknet.shared.clearIgnoredURLs()
```

Ignored patterns are case-insensitive substring matches against both the request host and the full absolute URL.

### Reading Captured Requests

Desknet stores completed requests in memory:

```swift
let requests = Desknet.shared.capturedRequests
```

Each item is a `NetworkLogEntry`:

```swift
public struct NetworkLogEntry: Identifiable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date?
    public let method: String
    public let url: URL
    public let requestHeaders: [String: String]
    public let requestBody: Data
    public let statusCode: Int?
    public let responseHeaders: [String: String]
    public let responseBody: Data
    public let mimeType: String?
    public let errorDescription: String?
    public var duration: TimeInterval? { get }
}
```

Clear captured entries:

```swift
Desknet.shared.clear()
```

## Monitor UI

The Desknet window is a SwiftUI interface with a sidebar and detail panel.

The sidebar includes:

- Search field.
- Endpoint-only row titles.
- Method pill and HTTP status.
- Success/error accent colors.
- Duration and response size.
- Neutral custom selected state instead of the macOS blue list highlight.

The detail panel includes:

- Method and status pills.
- Separate `Base URL` and `Endpoint` fields.
- Duration, request size, response size, and timestamp.
- Full-width collapsible sections for request headers, request body, response headers, and response body.
- Subtle section-specific content tints.
- Copy buttons for header values and body blocks.

## Search

The search field filters completed requests by:

- Full URL.
- Path.
- Host.
- HTTP method.
- Status code.
- Error description.

Selection is preserved when the selected request still exists in the filtered results. Otherwise, Desknet automatically selects the newest visible request.

## Diagnostics

Enable diagnostics when you need to debug capture, shortcut, store, or UI behavior:

```swift
Desknet.shared.setDebugLoggingEnabled(true)
```

Read the in-memory diagnostic buffer:

```swift
let lines = Desknet.shared.debugLogs()
print(lines.joined(separator: "\n"))
```

Clear diagnostics:

```swift
Desknet.shared.clearDebugLogs()
```

You can also stream unified logs from Terminal:

```bash
log stream --level debug --predicate 'subsystem == "Desknet"'
```

Diagnostics are disabled by default. The in-memory buffer keeps the latest 400 lines.

## How Capture Works

Desknet internally registers a custom `URLProtocol` when `start()` is called.

For each eligible request, Desknet:

1. Checks that the scheme is `http` or `https`.
2. Applies ignored URL patterns.
3. Marks the request as handled to avoid recursive interception.
4. Starts an internal `URLSessionDataTask`.
5. Records request metadata, response metadata, response chunks, completion, and errors.
6. Publishes store updates to the SwiftUI monitor.

The capture store is in memory only. Requests are sorted newest first.

## Limitations

- Desknet only captures requests that are eligible for `URLProtocol` interception.
- Requests made through `Network.framework`, raw sockets, some WebKit flows, and some background/custom `URLSessionConfiguration` setups may not appear.
- Request bodies are captured from `URLRequest.httpBody`; streamed bodies and upload streams may not be fully represented.
- Response bodies are accumulated in memory, so very large responses can increase memory usage.
- Captured data may contain tokens, cookies, personal data, or secrets. Keep Desknet out of production builds unless explicitly reviewed.
- The current UI is optimized for completed requests. In-flight requests are tracked internally but the public snapshot returns completed entries.

## Development

Run the test suite:

```bash
swift test
```

The tests cover:

- Ignored URL filtering.
- Text detail formatting.
- SwiftUI monitor view-model filtering and selection.
- Section expansion state.

## Project Structure

```text
Sources/Desknet/
  Desknet.swift                  Public singleton API and lifecycle
  DesknetRuntime.swift           Shared runtime state
  DesknetURLProtocol.swift       Network interception
  DesknetStore.swift             In-memory request store
  DesknetRequestFilter.swift     Ignored URL filtering
  DesknetShortcutMonitor.swift   Local keyboard shortcut monitor
  DesknetWindowController.swift  Standalone monitor window
  DesknetLogViewController.swift SwiftUI monitor hosted in AppKit
  DesknetDetailFormatter.swift   Text formatter and cURL builder
  DesknetDiagnostics.swift       Optional debug logging
```

## Recommended Usage

Use Desknet as a development-only helper:

```swift
#if DEBUG
Desknet.shared.start()
#endif
```

Keep sensitive environments in mind. Network inspectors are useful precisely because they expose request and response data, so treat the monitor as a local debugging tool rather than an end-user feature.
