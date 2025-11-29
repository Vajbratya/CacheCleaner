# CacheCleaner

A minimal macOS menu bar app to scan and clean cache files.

![Menu Bar](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## Features

- Lives in your menu bar (no dock icon)
- Scans multiple cache locations:
  - System Caches (`~/Library/Caches`)
  - Xcode (DerivedData, Archives)
  - npm/bun/pnpm caches
  - node_modules (finds all in home directory)
  - .next builds
  - Docker, Homebrew, CocoaPods
  - Gradle/Maven, Python pip
  - Logs
- Filter by age: 7, 14, 21, 30, 60, or 90 days
- Shows disk space before/after cleanup
- Native macOS notifications
- Launch at login option

## Installation

### Download DMG
Download the latest `.dmg` from [Releases](../../releases/latest).

### Build from source
```bash
git clone https://github.com/YOUR_USERNAME/CacheCleaner.git
cd CacheCleaner
swift build -c release
```

## Usage

1. Click the ✨ icon in your menu bar
2. Select "Older than X days" to set the age filter
3. Click "Scan for Cache" to find old cache files
4. Review the breakdown by category
5. Click "Clean All Cache" to remove them

## License

MIT
