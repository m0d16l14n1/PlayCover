//
//  CLIInstallCommands.swift
//  PlayCover
//

import AppKit
import Combine
import Foundation

enum CLIInstallCommands {
    static let cleanupFlags: Set<String> = ["data", "preferences", "keymap", "settings", "playchain", "all"]

    // MARK: - install / export
    static func install(_ args: CLIArguments) async throws {
        try args.expectPositionals(1)
        let ipa = try ipaURL(try args.positional(0, "path to an .ipa file"))
        // Same default as the install dialog: inject PlayTools unless asked not to
        let installPlayTools = try args.value("playtools").map { try CLIValue.bool($0, for: "playtools") } ?? true
        let category = try args.value("category").map { try CLISettingOption.category($0) }

        guard let url = await runInstaller(ipa, export: false, installPlayTools: installPlayTools,
                                           applicationType: category) else {
            throw CLIError.failed("Installation of \(ipa.lastPathComponent) failed")
        }
        let app = PlayApp(appUrl: url)
        CLITerminal.output("Installed \(app.info.bundleIdentifier) (\(app.name) \(app.info.bundleVersion)) "
                           + "at \(url.path)")

        if CLISettings.hasSettingOptions(args) {
            var patch = try CLISettings.patch(for: app, from: args)
            // Already applied by the installer, before signing
            patch.category = nil
            await CLISettings.apply(patch, to: app)
            CLITerminal.output("Applied settings to \(app.info.bundleIdentifier)")
        }

        if args.has("launch") {
            try await CLILaunchCommand.launch(app, options: CLILaunchCommand.Options())
        }
    }

    static func export(_ args: CLIArguments) async throws {
        try args.expectPositionals(1)
        let ipa = try ipaURL(try args.positional(0, "path to an .ipa file"))
        let output = args.value("output").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        if let output = output, output.pathExtension.lowercased() != "ipa" {
            throw CLIError.usage("--output must end in .ipa")
        }
        guard var url = await runInstaller(ipa, export: true, installPlayTools: true, applicationType: nil),
              Log.shared.errorCount == 0 else {
            throw CLIError.failed("Export of \(ipa.lastPathComponent) failed")
        }
        if let output = output, output.standardizedFileURL != url.standardizedFileURL {
            if FileManager.default.fileExists(atPath: output.path) {
                try FileManager.default.removeItem(at: output)
            }
            try FileManager.default.moveItem(at: url, to: output)
            url = output
        }
        CLITerminal.output("Exported \(url.path)")
    }

    private static func ipaURL(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CLIError.failed("\(url.path) does not exist")
        }
        guard url.pathExtension.lowercased() == "ipa" else {
            throw CLIError.usage("\(url.lastPathComponent) is not an .ipa file")
        }
        return url
    }

    private static func runInstaller(_ ipa: URL, export: Bool, installPlayTools: Bool,
                                     applicationType: LSApplicationCategoryType?) async -> URL? {
        // Echo the installer steps the progress bar would show
        var lastStatus: InstallStepsNative?
        let progress = InstallVM.shared.$status.receive(on: DispatchQueue.main).sink { status in
            guard status != lastStatus else { return }
            lastStatus = status
            CLITerminal.printError("» " + NSLocalizedString(status.rawValue, comment: ""))
        }
        defer { progress.cancel() }

        return await withCheckedContinuation { continuation in
            Installer.install(ipaUrl: ipa, export: export, installPlayTools: installPlayTools,
                              applicationType: applicationType) { url in
                continuation.resume(returning: url)
            }
        }
    }

    // MARK: - uninstall / clear
    static func uninstall(_ args: CLIArguments) async throws {
        try args.expectPositionals(1)
        let app = try PlayCoverCLI.findApp(try args.positional(0, "app"))
        try ensureNotRunning(app)

        let all = args.has("all")
        let options = UninstallOptions(clearAppData: all || args.has("data"),
                                       removeAppKeymap: all || args.has("keymap"),
                                       removeAppSettings: all || args.has("settings"),
                                       removeAppEntitlements: all || args.has("entitlements"),
                                       removePlayChain: all || args.has("playchain"))
        let removePreferences = all || args.has("preferences")

        var removed = ["the app"]
        if options.clearAppData { removed.append("its data (moved to the Trash)") }
        if removePreferences && !options.clearAppData { removed.append("its preferences") }
        if options.removeAppSettings { removed.append("its PlayCover settings") }
        if options.removeAppKeymap { removed.append("its keymaps") }
        if options.removeAppEntitlements { removed.append("its entitlements") }
        if options.removePlayChain { removed.append("its PlayChain") }
        guard try CLITerminal.confirm("Uninstall \(app.name) (\(app.info.bundleIdentifier)): remove "
                                      + removed.joined(separator: ", ") + "?", assumeYes: args.has("yes")) else {
            return
        }

        if removePreferences && !options.clearAppData {
            FileManager.default.delete(at: app.container.userPrefsUrl)
        }
        await Uninstaller.uninstall(app, options: options, refreshLibrary: false)
        CLITerminal.output("Uninstalled \(app.info.bundleIdentifier)")
        if options.clearAppData {
            try ensureDataCleared(app)
        }
    }

    static func clear(_ args: CLIArguments) async throws {
        try args.expectPositionals(1)
        let app = try PlayCoverCLI.findApp(try args.positional(0, "app"))
        let all = args.has("all")
        let selected = cleanupFlags.subtracting(["all"]).filter { all || args.has($0) }
        guard !selected.isEmpty else {
            throw CLIError.usage("Choose what to clear: --data, --preferences, --playchain, --settings, --keymap "
                                 + "or --all")
        }
        try ensureNotRunning(app)

        let descriptions = ["data": "app data (moved to the Trash)", "preferences": "app preferences",
                            "playchain": "PlayChain data", "settings": "PlayCover settings", "keymap": "keymaps"]
        let list = selected.sorted().compactMap { descriptions[$0] }.joined(separator: ", ")
        guard try CLITerminal.confirm("Clear \(list) of \(app.name)?", assumeYes: args.has("yes")) else {
            return
        }

        if selected.contains("preferences") {
            FileManager.default.delete(at: app.container.userPrefsUrl)
        }
        if selected.contains("data") {
            Uninstaller.clearExternalCache(app.info.bundleIdentifier)
            try ensureDataCleared(app)
        }
        if selected.contains("playchain") {
            app.clearPlayChain()
        }
        if selected.contains("settings") {
            app.settings.reset()
        }
        if selected.contains("keymap") {
            FileManager.default.delete(at: app.keymapping.baseKeymapURL)
        }
        CLITerminal.output("Cleared \(list) of \(app.info.bundleIdentifier)")
    }

    /// Uninstaller.clearExternalCache does not report failures, so check that the data container is gone.
    /// macOS only lets PlayCover's own window move a container folder; a command started from a terminal is refused,
    /// but may still change what is inside, so fall back to emptying the container's folders.
    private static func ensureDataCleared(_ app: PlayApp) throws {
        guard app.container.doesExist() else { return }

        let data = app.container.containerUrl.appendingPathComponent("Data")
        var failed: [String] = []
        // Desktop, Downloads, Pictures… in a container are symlinks to the user's own folders: never touch those
        for folder in realChildren(of: data) {
            for item in realChildren(of: folder) {
                do {
                    try FileManager.default.trashItem(at: item, resultingItemURL: nil)
                } catch {
                    failed.append(item.path)
                }
            }
        }
        guard failed.isEmpty else {
            throw CLIError.failed("Could not move \(failed.count) item(s) of \(data.path) to the Trash, e.g. "
                                  + "\(failed[0]). Allow your terminal Full Disk Access in System Settings › "
                                  + "Privacy & Security, or clear the data from the PlayCover window.")
        }
        CLITerminal.printError("note: macOS only lets the PlayCover window remove the container folder itself; "
                               + "its contents were moved to the Trash instead")
    }

    private static func realChildren(of url: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? []
        return items.filter { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true }
    }

    private static func ensureNotRunning(_ app: PlayApp) throws {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: app.info.bundleIdentifier).isEmpty {
            throw CLIError.failed("\(app.name) is running. Quit it first.")
        }
    }

    // MARK: - link
    static let shimMarker = "# Generated by PlayCover: runs the PlayCover command line interface"

    static func link(_ args: CLIArguments) async throws {
        try args.expectPositionals(0)
        let directory = URL(fileURLWithPath: ((args.value("dir") ?? "~/.local/bin") as NSString)
            .expandingTildeInPath)
        let target = directory.appendingPathComponent("playcover")

        if FileManager.default.fileExists(atPath: target.path) {
            let existing = (try? String(contentsOf: target, encoding: .utf8)) ?? ""
            guard existing.contains(shimMarker) else {
                throw CLIError.failed("\(target.path) already exists and was not created by PlayCover")
            }
        }

        let executableName = Bundle.main.executableURL?.lastPathComponent ?? "PlayCover"
        let script = """
        #!/bin/sh
        \(shimMarker)
        APP="${PLAYCOVER_APP:-\(Bundle.main.bundlePath)}"
        if [ ! -x "$APP/Contents/MacOS/\(executableName)" ]; then
            APP="$(mdfind 'kMDItemCFBundleIdentifier == "io.playcover.PlayCover"' 2>/dev/null | head -n 1)"
        fi
        if [ -z "$APP" ] || [ ! -x "$APP/Contents/MacOS/\(executableName)" ]; then
            echo "playcover: PlayCover.app not found, set PLAYCOVER_APP to its path" >&2
            exit 1
        fi
        # Without arguments the executable opens the PlayCover window; from a shell, show help instead
        [ $# -eq 0 ] && set -- help
        exec "$APP/Contents/MacOS/\(executableName)" "$@"

        """

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try script.write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        CLITerminal.output("Installed \(target.path)")

        let path = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        if !path.contains(directory.path) {
            CLITerminal.printError("note: \(directory.path) is not in your PATH. Add it with:\n"
                                   + "  echo 'export PATH=\"\(directory.path):$PATH\"' >> ~/.zshrc")
        }
    }
}
