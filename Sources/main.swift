import Cocoa
import UserNotifications
import ServiceManagement

// MARK: - Cache Scanner
class CacheScanner {
    struct CacheCategory {
        let name: String
        let size: Int64
        let count: Int

        var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
    }

    struct ScanResult {
        let categories: [CacheCategory]
        let totalSize: Int64
        let totalItems: Int

        var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
        }
    }

    // Cache locations to scan
    static let cacheLocations: [(name: String, paths: [String], pattern: String?)] = [
        ("System Caches", ["~/Library/Caches"], nil),
        ("Xcode", ["~/Library/Developer/Xcode/DerivedData", "~/Library/Developer/Xcode/Archives"], nil),
        ("npm/bun/pnpm", ["~/.npm/_cacache", "~/.bun/install/cache", "~/.pnpm-store"], nil),
        ("node_modules", ["~"], "node_modules"),
        (".next builds", ["~"], ".next"),
        ("Claude/AI Tools", ["~/.claude/debug", "~/.cursor", "~/.continue"], nil),
        ("Docker", ["~/Library/Containers/com.docker.docker/Data/vms"], nil),
        ("Homebrew", ["~/Library/Caches/Homebrew"], nil),
        ("CocoaPods", ["~/Library/Caches/CocoaPods"], nil),
        ("Gradle/Maven", ["~/.gradle/caches", "~/.m2/repository"], nil),
        ("Python", ["~/.cache/pip", "~/Library/Caches/pip"], nil),
        ("Logs", ["~/Library/Logs"], nil)
    ]

    static var isScanning = false
    static var shouldCancel = false

    static func scan(olderThanDays: Int, progress: @escaping (String) -> Void, completion: @escaping (ScanResult) -> Void) {
        guard !isScanning else { return }
        isScanning = true
        shouldCancel = false

        DispatchQueue.global(qos: .userInitiated).async {
            var categories: [CacheCategory] = []
            var totalSize: Int64 = 0
            var totalItems = 0
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -olderThanDays, to: Date())!
            let fileManager = FileManager.default

            for location in cacheLocations {
                guard !shouldCancel else { break }

                DispatchQueue.main.async {
                    progress(location.name)
                }

                var categorySize: Int64 = 0
                var categoryCount = 0

                for pathTemplate in location.paths {
                    guard !shouldCancel else { break }
                    let basePath = NSString(string: pathTemplate).expandingTildeInPath

                    if let pattern = location.pattern {
                        // Search for pattern (like node_modules, .next)
                        let result = findDirectories(named: pattern, in: basePath, olderThan: cutoffDate)
                        categorySize += result.size
                        categoryCount += result.count
                    } else {
                        // Direct path scanning
                        guard fileManager.fileExists(atPath: basePath) else { continue }
                        let result = scanDirectory(path: basePath, olderThan: cutoffDate)
                        categorySize += result.size
                        categoryCount += result.count
                    }
                }

                if categorySize > 0 {
                    categories.append(CacheCategory(name: location.name, size: categorySize, count: categoryCount))
                    totalSize += categorySize
                    totalItems += categoryCount
                }
            }

            // Sort by size descending
            categories.sort { $0.size > $1.size }

            isScanning = false

            DispatchQueue.main.async {
                completion(ScanResult(categories: categories, totalSize: totalSize, totalItems: totalItems))
            }
        }
    }

    static func findDirectories(named pattern: String, in basePath: String, olderThan cutoffDate: Date) -> (size: Int64, count: Int) {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        var count = 0

        // Use find command for efficiency
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/find")
        task.arguments = [basePath, "-name", pattern, "-type", "d", "-prune"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            if let output = String(data: data, encoding: .utf8) {
                let paths = output.components(separatedBy: "\n").filter { !$0.isEmpty }

                for path in paths {
                    guard !shouldCancel else { break }
                    if let attrs = try? fileManager.attributesOfItem(atPath: path),
                       let modDate = attrs[.modificationDate] as? Date,
                       modDate < cutoffDate {
                        if let size = directorySize(path: path) {
                            totalSize += size
                            count += 1
                        }
                    }
                }
            }
        } catch {}

        return (totalSize, count)
    }

    static func scanDirectory(path: String, olderThan cutoffDate: Date) -> (size: Int64, count: Int) {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        var count = 0

        guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else {
            return (0, 0)
        }

        for item in contents {
            guard !shouldCancel else { break }
            let itemPath = (path as NSString).appendingPathComponent(item)

            if let attrs = try? fileManager.attributesOfItem(atPath: itemPath),
               let modDate = attrs[.modificationDate] as? Date,
               modDate < cutoffDate {
                if let size = directorySize(path: itemPath) {
                    totalSize += size
                    count += 1
                }
            }
        }

        return (totalSize, count)
    }

    static func clean(olderThanDays: Int, progress: @escaping (String, Int64) -> Void, completion: @escaping (Int64) -> Void) {
        guard !isScanning else { return }
        isScanning = true
        shouldCancel = false

        DispatchQueue.global(qos: .userInitiated).async {
            var freedSize: Int64 = 0
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -olderThanDays, to: Date())!
            let fileManager = FileManager.default

            for location in cacheLocations {
                guard !shouldCancel else { break }

                DispatchQueue.main.async {
                    progress(location.name, freedSize)
                }

                for pathTemplate in location.paths {
                    guard !shouldCancel else { break }
                    let basePath = NSString(string: pathTemplate).expandingTildeInPath

                    if let pattern = location.pattern {
                        // Find and delete directories matching pattern
                        freedSize += deleteDirectories(named: pattern, in: basePath, olderThan: cutoffDate)
                    } else {
                        // Delete contents of cache directory
                        freedSize += cleanDirectory(path: basePath, olderThan: cutoffDate)
                    }
                }
            }

            isScanning = false

            DispatchQueue.main.async {
                completion(freedSize)
            }
        }
    }

    static func deleteDirectories(named pattern: String, in basePath: String, olderThan cutoffDate: Date) -> Int64 {
        let fileManager = FileManager.default
        var freedSize: Int64 = 0

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/find")
        task.arguments = [basePath, "-name", pattern, "-type", "d", "-prune"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            if let output = String(data: data, encoding: .utf8) {
                let paths = output.components(separatedBy: "\n").filter { !$0.isEmpty }

                for path in paths {
                    guard !shouldCancel else { break }
                    if let attrs = try? fileManager.attributesOfItem(atPath: path),
                       let modDate = attrs[.modificationDate] as? Date,
                       modDate < cutoffDate {
                        if let size = directorySize(path: path) {
                            freedSize += size
                        }
                        try? fileManager.removeItem(atPath: path)
                    }
                }
            }
        } catch {}

        return freedSize
    }

    static func cleanDirectory(path: String, olderThan cutoffDate: Date) -> Int64 {
        let fileManager = FileManager.default
        var freedSize: Int64 = 0

        guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else {
            return 0
        }

        for item in contents {
            guard !shouldCancel else { break }
            let itemPath = (path as NSString).appendingPathComponent(item)

            if let attrs = try? fileManager.attributesOfItem(atPath: itemPath),
               let modDate = attrs[.modificationDate] as? Date,
               modDate < cutoffDate {
                if let size = directorySize(path: itemPath) {
                    freedSize += size
                }
                try? fileManager.removeItem(atPath: itemPath)
            }
        }

        return freedSize
    }

    static func directorySize(path: String) -> Int64? {
        // Use `du` command to get REAL disk usage (handles sparse files correctly)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        task.arguments = ["-sk", path] // -s = summary, -k = kilobytes

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            if let output = String(data: data, encoding: .utf8),
               let sizeStr = output.split(separator: "\t").first,
               let sizeKB = Int64(sizeStr) {
                return sizeKB * 1024 // Convert KB to bytes
            }
        } catch {}

        return 0
    }

    static func cancel() {
        shouldCancel = true
    }

    static func getDiskSpace() -> (total: Int64, free: Int64)? {
        let fileManager = FileManager.default
        do {
            let attrs = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let total = attrs[.systemSize] as? Int64,
               let free = attrs[.systemFreeSize] as? Int64 {
                return (total, free)
            }
        } catch {}
        return nil
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var scanResult: CacheScanner.ScanResult?
    var selectedDays: Int = 30
    var launchAtLogin: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request notification permission
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        // Check launch at login status
        launchAtLogin = SMAppService.mainApp.status == .enabled

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Cache Cleaner")
            button.image?.isTemplate = true
        }

        setupMenu()
    }

    func setupMenu() {
        menu = NSMenu()
        menu.autoenablesItems = false

        // Header with disk space
        let headerItem = NSMenuItem(title: "Cache Cleaner", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        if let (total, free) = CacheScanner.getDiskSpace() {
            let freeStr = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
            let totalStr = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            headerItem.title = "💾 \(freeStr) free of \(totalStr)"
        }
        menu.addItem(headerItem)

        menu.addItem(NSMenuItem.separator())

        // Scan button
        let scanItem = NSMenuItem(title: "Scan for Cache", action: #selector(startScan), keyEquivalent: "s")
        scanItem.target = self
        scanItem.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        menu.addItem(scanItem)

        menu.addItem(NSMenuItem.separator())

        // Time filter submenu
        let filterItem = NSMenuItem(title: "Older than \(selectedDays) days", action: nil, keyEquivalent: "")
        filterItem.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)
        let filterSubmenu = NSMenu()

        for days in [7, 14, 21, 30, 60, 90] {
            let dayItem = NSMenuItem(title: "\(days) days", action: #selector(selectDays(_:)), keyEquivalent: "")
            dayItem.target = self
            dayItem.tag = days
            dayItem.state = days == selectedDays ? .on : .off
            filterSubmenu.addItem(dayItem)
        }

        filterItem.submenu = filterSubmenu
        menu.addItem(filterItem)

        menu.addItem(NSMenuItem.separator())

        // Results section
        let resultHeaderItem = NSMenuItem(title: "Scan Results", action: nil, keyEquivalent: "")
        resultHeaderItem.isEnabled = false
        resultHeaderItem.tag = 99
        menu.addItem(resultHeaderItem)

        let resultItem = NSMenuItem(title: "Click 'Scan' to find cache", action: nil, keyEquivalent: "")
        resultItem.isEnabled = false
        resultItem.tag = 100
        menu.addItem(resultItem)

        menu.addItem(NSMenuItem.separator())

        // Clean button
        let cleanItem = NSMenuItem(title: "Clean All Cache", action: #selector(cleanCache), keyEquivalent: "c")
        cleanItem.target = self
        cleanItem.isEnabled = false
        cleanItem.tag = 101
        cleanItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(cleanItem)

        menu.addItem(NSMenuItem.separator())

        // Settings submenu
        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        let settingsSubmenu = NSMenu()

        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = launchAtLogin ? .on : .off
        launchItem.tag = 200
        settingsSubmenu.addItem(launchItem)

        settingsItem.submenu = settingsSubmenu
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc func startScan() {
        guard !CacheScanner.isScanning else {
            CacheScanner.cancel()
            return
        }

        // Update UI for scanning state
        if let scanItem = menu.items.first(where: { $0.action == #selector(startScan) }) {
            scanItem.title = "Cancel Scan"
            scanItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        }
        if let resultItem = menu.item(withTag: 100) {
            resultItem.title = "Scanning..."
        }
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Scanning")
        }

        // Remove old category items
        while let item = menu.item(withTag: 102) {
            menu.removeItem(item)
        }

        CacheScanner.scan(olderThanDays: selectedDays, progress: { [weak self] category in
            if let resultItem = self?.menu.item(withTag: 100) {
                resultItem.title = "Scanning \(category)..."
            }
        }) { [weak self] result in
            guard let self = self else { return }
            self.scanResult = result

            // Update scan button
            if let scanItem = self.menu.items.first(where: { $0.title == "Cancel Scan" }) {
                scanItem.title = "Scan for Cache"
                scanItem.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
            }

            // Update result display
            if let resultItem = self.menu.item(withTag: 100) {
                if result.totalSize > 0 {
                    resultItem.title = "Total: \(result.formattedSize) (\(result.totalItems) items)"
                } else {
                    resultItem.title = "No old cache found"
                }
            }

            // Add category breakdown
            if let resultIndex = self.menu.items.firstIndex(where: { $0.tag == 100 }) {
                var insertIndex = resultIndex + 1
                for category in result.categories.prefix(6) {
                    let catItem = NSMenuItem(title: "  \(category.name): \(category.formattedSize)", action: nil, keyEquivalent: "")
                    catItem.isEnabled = false
                    catItem.tag = 102
                    self.menu.insertItem(catItem, at: insertIndex)
                    insertIndex += 1
                }
            }

            // Enable clean button
            if let cleanItem = self.menu.item(withTag: 101) {
                cleanItem.isEnabled = result.totalSize > 0
            }

            // Reset icon
            if let button = self.statusItem.button {
                button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Cache Cleaner")
            }

            // Update disk space
            if let headerItem = self.menu.items.first,
               let (_, free) = CacheScanner.getDiskSpace() {
                let freeStr = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
                let potentialFree = ByteCountFormatter.string(fromByteCount: free + result.totalSize, countStyle: .file)
                if result.totalSize > 0 {
                    headerItem.title = "💾 \(freeStr) free → \(potentialFree) after clean"
                }
            }

            // Send notification
            self.sendNotification(
                title: "Scan Complete",
                body: result.totalSize > 0
                    ? "Found \(result.formattedSize) of cache older than \(self.selectedDays) days"
                    : "No old cache found"
            )
        }
    }

    @objc func selectDays(_ sender: NSMenuItem) {
        selectedDays = sender.tag

        // Update checkmarks
        if let filterItem = menu.items.first(where: { $0.title.contains("Older than") }),
           let submenu = filterItem.submenu {
            for item in submenu.items {
                item.state = item.tag == selectedDays ? .on : .off
            }
            filterItem.title = "Older than \(selectedDays) days"
        }

        // Clear previous scan
        scanResult = nil
        if let resultItem = menu.item(withTag: 100) {
            resultItem.title = "Click 'Scan' to find cache"
        }
        if let cleanItem = menu.item(withTag: 101) {
            cleanItem.isEnabled = false
        }

        // Remove category items
        while let item = menu.item(withTag: 102) {
            menu.removeItem(item)
        }

        // Reset header
        if let headerItem = menu.items.first,
           let (total, free) = CacheScanner.getDiskSpace() {
            let freeStr = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
            let totalStr = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            headerItem.title = "💾 \(freeStr) free of \(totalStr)"
        }
    }

    @objc func cleanCache() {
        guard scanResult != nil, !CacheScanner.isScanning else { return }

        // Update UI
        if let cleanItem = menu.item(withTag: 101) {
            cleanItem.title = "Cleaning..."
            cleanItem.isEnabled = false
        }
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Cleaning")
        }

        CacheScanner.clean(olderThanDays: selectedDays, progress: { [weak self] category, freed in
            if let resultItem = self?.menu.item(withTag: 100) {
                let freedStr = ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)
                resultItem.title = "Cleaning \(category)... (\(freedStr) freed)"
            }
        }) { [weak self] freedSize in
            guard let self = self else { return }
            self.scanResult = nil

            let formattedSize = ByteCountFormatter.string(fromByteCount: freedSize, countStyle: .file)

            // Update UI
            if let resultItem = self.menu.item(withTag: 100) {
                resultItem.title = "✓ Cleaned \(formattedSize)"
            }
            if let cleanItem = self.menu.item(withTag: 101) {
                cleanItem.title = "Clean All Cache"
                cleanItem.isEnabled = false
            }
            if let button = self.statusItem.button {
                button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Cache Cleaner")
            }

            // Remove category items
            while let item = self.menu.item(withTag: 102) {
                self.menu.removeItem(item)
            }

            // Update disk space
            if let headerItem = self.menu.items.first,
               let (total, free) = CacheScanner.getDiskSpace() {
                let freeStr = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
                let totalStr = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
                headerItem.title = "💾 \(freeStr) free of \(totalStr)"
            }

            // Send notification
            self.sendNotification(
                title: "Cache Cleaned!",
                body: "Freed \(formattedSize) of disk space"
            )
        }
    }

    @objc func toggleLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            launchAtLogin.toggle()

            if let launchItem = menu.item(withTag: 200) {
                launchItem.state = launchAtLogin ? .on : .off
            }
        } catch {
            print("Failed to toggle launch at login: \(error)")
        }
    }

    func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - Main
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
