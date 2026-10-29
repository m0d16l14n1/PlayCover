//
//  UpdateScheme.swift
//  PlayCover
//
//  Created by TheMoonThatRises on 7/6/24.
//

import AppKit

class UpdateScheme {
    public static let versionsFile = PlayTools.playCoverContainer.appendingPathComponent("VERSION")
    public static var currentVersion: String {
        (try? String(contentsOf: UpdateScheme.versionsFile)) ?? "3.1"
    }
    struct Version: Hashable {
        let components: [Int]
        init(_ string: String) {
            var comps = string.split(separator: ".").compactMap { Int($0) }
            while comps.last == 0 && comps.count > 1 {
                comps.removeLast()
            }
            self.components = comps
        }
    }

    struct Migration {
        let fromVersion: String
        let toVersion: String
        let action: () throws -> Void
    }

    private static let migrations: [Version: Migration] = [
        Version("2"): Migration(
            fromVersion: "2",
            toVersion: "3",
            action: updateFromV2ToV3
        ),
        Version("3"): Migration(
            fromVersion: "3",
            toVersion: "3.1",
            action: updateFromV3ToV3p1
        )
    ]

    public static func checkForUpdate() {
        let maxSteps = migrations.count
        var steps = 0

        while steps < maxSteps {
            let currentVer = Version(currentVersion.trimmingCharacters(in: .whitespacesAndNewlines))

            guard let migration = migrations[currentVer] else {
                print("No more migrations needed")
                return
            }

            do {
                print("Migrating \(migration.fromVersion) → \(migration.toVersion)")
                try migration.action()
            } catch {
                Log.shared.error(error)
                return
            }

            steps += 1
        }
    }

    private static func updateFromV2ToV3() throws {
        try FileManager.default.createDirectory(at: AppsVM.appDirectory, withIntermediateDirectories: true)

        let directoryContents = try FileManager.default
            .contentsOfDirectory(at: PlayTools.playCoverContainer, includingPropertiesForKeys: nil, options: [])

        let subdirs = directoryContents.filter { $0.hasDirectoryPath }

        for sub in subdirs {
            if sub.pathExtension.contains("app") &&
                FileManager.default.fileExists(atPath: sub.appendingPathComponent("Info")
                    .appendingPathExtension("plist")
                    .path) {
                let app = PlayApp(appUrl: sub)
                app.removeAlias()
                try FileManager.default.moveItem(at: app.url,
                                                 to: AppsVM.appDirectory
                    .appendingPathComponent(app.info.bundleIdentifier)
                    .appendingPathExtension("app"))
            }
        }

        try "3".write(to: UpdateScheme.versionsFile, atomically: false, encoding: .utf8)
    }

    private static func updateFromV3ToV3p1() throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml

        let directoryContents = try FileManager.default
            .contentsOfDirectory(at: Keymapping.keymappingDir, includingPropertiesForKeys: nil, options: [])

        for file in directoryContents where file.pathExtension.contains("plist") {
            let bundleId = file.deletingPathExtension().lastPathComponent
            let appKeymapDir = Keymapping.keymappingDir.appendingPathComponent(bundleId)
            let keymapFileURL = appKeymapDir.appendingPathComponent("default")
                                            .appendingPathExtension("plist")

            try FileManager.default.createDirectory(at: appKeymapDir,
                                                    withIntermediateDirectories: true)

            try FileManager.default.moveItem(at: file, to: keymapFileURL
            )

            do {
                let data = try encoder.encode(KeymapConfig(defaultKm: keymapFileURL, keymapOrder: [keymapFileURL]))
                try data.write(to: appKeymapDir.appendingPathComponent(".config")
                                               .appendingPathExtension("plist"))
            } catch {
                print(error)
            }
        }

        try "3.1".write(to: UpdateScheme.versionsFile, atomically: false, encoding: .utf8)
    }

}

// MARK: - Library location
extension UpdateScheme {
    /// Where some development builds kept the library, to stop macOS asking whether games may "access data from
    /// other apps". That did not stop the prompt on macOS 26, so the library is back in PlayTools.playCoverContainer
    /// and anything those builds moved is moved back.
    static let legacyLibrary = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library")
        .appendingPathComponent("Application Support")
        .appendingPathComponent("io.playcover.PlayCover")

    /// Everything PlayCover keeps in its library
    private static let libraryItems = ["Applications", "App Settings", "Entitlements", "Keymapping", "PlayTools",
                                       "CACHE", "Sources.plist", "VERSION"]

    /// Moves PlayCover's items back from the legacy library, rebuilds the aliases and re-signs the moved apps so
    /// their sandbox matches the library again, also when started from Launchpad. Items are renamed, never copied,
    /// and an item that already exists in the library is never overwritten. Returns what the user should be told.
    static func moveLibraryBackToContainer() -> [String] {
        let library = PlayTools.playCoverContainer
        // Also repairs configs whose files were moved back by hand
        rewriteKeymapConfigs(in: library.appendingPathComponent("Keymapping"))
        let knownApps = knownBundleIdentifiers()
        let legacyChains = legacyChainFiles(of: knownApps)
        guard library.standardizedFileURL != legacyLibrary.standardizedFileURL,
              libraryItems.contains(where: { FileManager.default.fileExists(atPath: legacyItem($0).path) })
                || !legacyChains.isEmpty else {
            removeEmptyLegacyFolders()
            return []
        }

        // Moving files under a running PlayCover or a running game would pull them away from it; try next time
        let others = NSWorkspace.shared.runningApplications.filter {
            ($0.bundleIdentifier == Bundle.main.bundleIdentifier
                && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier)
            || $0.bundleURL?.path.hasPrefix(legacyItem("Applications").path) == true
        }
        if !others.isEmpty {
            return ["PlayCover's library will move back to \(library.path) once PlayCover and its apps are closed"]
        }

        var conflicts: [String] = []
        let appsBefore = Set(installedApps(in: library.appendingPathComponent("Applications")))
        for item in libraryItems {
            merge(legacyItem(item), into: library.appendingPathComponent(item), conflicts: &conflicts)
        }
        // Take only the chains of PlayCover's apps
        for chain in legacyChains {
            merge(chain, into: library.appendingPathComponent("PlayChain")
                .appendingPathComponent(chain.lastPathComponent), conflicts: &conflicts)
        }
        // Before any PlayApp exists: loading a keymap config whose files are missing replaces them with blank keymaps
        rewriteKeymapConfigs(in: library.appendingPathComponent("Keymapping"))

        var messages = ["Moved PlayCover's library back to \(library.path)"]
        let movedApps = Set(installedApps(in: library.appendingPathComponent("Applications"))).subtracting(appsBefore)
        for app in movedApps.sorted(by: { $0.path < $1.path }) {
            do {
                try PlayApp(appUrl: app).signApp() // PlayApp's initializer also rebuilds the alias
            } catch {
                messages.append("Could not re-sign \(app.lastPathComponent): \(error.localizedDescription)")
            }
        }
        removeEmptyLegacyFolders()
        if !conflicts.isEmpty {
            messages.append("Left in \(legacyLibrary.path) because the library already has them: "
                            + conflicts.joined(separator: ", "))
        }
        return messages
    }

    private static func legacyChainFiles(of apps: Set<String>) -> [URL] {
        let chains = (try? FileManager.default.contentsOfDirectory(at: legacyItem("PlayChain"),
                                                                   includingPropertiesForKeys: nil)) ?? []
        return chains.filter {
            ["db", "keyCover"].contains($0.pathExtension) && apps.contains($0.deletingPathExtension().lastPathComponent)
        }
    }

    /// Keymap configs store absolute file URLs: point the ones into the legacy library at the library
    private static func rewriteKeymapConfigs(in keymapping: URL) {
        let library = PlayTools.playCoverContainer.standardizedFileURL.path
        let legacy = legacyLibrary.standardizedFileURL.path
        func moved(_ url: URL) -> URL {
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(legacy + "/") else { return url }
            return URL(fileURLWithPath: library + path.dropFirst(legacy.count))
        }

        let folders = (try? FileManager.default.contentsOfDirectory(at: keymapping, includingPropertiesForKeys: nil))
            ?? []
        for folder in folders {
            let configURL = folder.appendingPathComponent(".config").appendingPathExtension("plist")
            guard let data = try? Data(contentsOf: configURL),
                  let original = try? PropertyListDecoder().decode(KeymapConfig.self, from: data) else { continue }
            var config = original
            config.defaultKm = moved(config.defaultKm)
            var order: [URL] = []
            for keymap in config.keymapOrder.map(moved) where !order.contains(keymap) {
                order.append(keymap)
            }
            guard config.defaultKm != original.defaultKm || order != original.keymapOrder else { continue }
            config.keymapOrder = order
            do {
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .xml
                try encoder.encode(config).write(to: configURL)
            } catch {
                Log.shared.error(error)
            }
        }
    }

    /// Removes the legacy folder once nothing is left in it (it is not a container, so this is allowed)
    private static func removeEmptyLegacyFolders() {
        for folder in libraryItems + ["PlayChain", ""] {
            let url = folder.isEmpty ? legacyLibrary : legacyItem(folder)
            if (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.filter({ $0 != ".DS_Store" })
                .isEmpty == true {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func legacyItem(_ name: String) -> URL {
        legacyLibrary.appendingPathComponent(name)
    }

    /// Moves `source` to `destination`, merging directories that exist on both sides
    private static func merge(_ source: URL, into destination: URL, conflicts: inout [String]) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else { return }
        do {
            if !fileManager.fileExists(atPath: destination.path) {
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
                try fileManager.moveItem(at: source, to: destination)
            } else if isDirectory(source) && isDirectory(destination) {
                for child in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                    merge(child, into: destination.appendingPathComponent(child.lastPathComponent),
                          conflicts: &conflicts)
                }
                if (try? fileManager.contentsOfDirectory(atPath: source.path))?.isEmpty == true {
                    try fileManager.removeItem(at: source)
                }
            } else {
                conflicts.append(source.path.replacingOccurrences(of: legacyLibrary.path + "/", with: ""))
            }
        } catch {
            Log.shared.error(error)
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func installedApps(in directory: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "app" }
    }

    /// Bundle identifiers of the apps PlayCover knows about, installed or with settings left behind
    private static func knownBundleIdentifiers() -> Set<String> {
        var identifiers = Set<String>()
        for app in installedApps(in: legacyItem("Applications"))
            + installedApps(in: PlayTools.playCoverContainer.appendingPathComponent("Applications")) {
            if let identifier = NSDictionary(contentsOf: app.appendingPathComponent("Info.plist"))?[
                "CFBundleIdentifier"] as? String {
                identifiers.insert(identifier)
            }
        }
        for folder in ["App Settings", "Entitlements", "Keymapping"] {
            for root in [legacyItem(folder), PlayTools.playCoverContainer.appendingPathComponent(folder)] {
                let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
                identifiers.formUnion(names.map { ($0 as NSString).deletingPathExtension })
            }
        }
        return identifiers
    }
}
