# ServerList

ServerList is a small macOS menu bar app for starting and stopping local development servers from selected folders.

It supports:

- PHP built-in server: `php -S localhost:<port> -t <folder>`
- Python static server: `python3 -m http.server <port> --directory <folder>`
- menu bar quick actions: start, stop, restart, and open in browser
- saved server profiles in macOS `UserDefaults`
- detection of already running local PHP/Python server processes

The interface is currently in Russian.

## Requirements

- macOS 12 or newer
- Swift 5.9 or newer
- Xcode Command Line Tools
- Python 3 at `/usr/bin/python3`
- PHP at `/opt/homebrew/bin/php` for PHP servers

Install command line tools if needed:

```bash
xcode-select --install
```

## Build

Build the executable:

```bash
cd FolderServer
swift build -c release
```

Build a macOS `.app` bundle into `dist/`:

```bash
./scripts/build-app.sh
```

Run the app:

```bash
open dist/ServerList.app
```

## Development

Generate an Xcode project with XcodeGen:

```bash
cd FolderServer
xcodegen generate
open ServerList.xcodeproj
```

Or work directly with SwiftPM:

```bash
cd FolderServer
swift build
swift run ServerList
```

## Notes

ServerList is a menu bar agent. It starts without a Dock icon and opens the main window from the menu bar popover.

PHP path detection is not automatic yet. On Apple Silicon Macs with Homebrew PHP, `/opt/homebrew/bin/php` is expected.

## License

MIT
