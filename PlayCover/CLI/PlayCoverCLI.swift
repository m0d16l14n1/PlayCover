//
//  PlayCoverCLI.swift
//  PlayCover
//
//  Command line interface, run by the PlayCover executable itself:
//  PlayCover.app/Contents/MacOS/PlayCover <command> [arguments]
//

import AppKit
import Foundation

struct CLICommand {
    let name: String
    let usage: String
    let summary: String
    let flags: Set<String>
    let values: Set<String>
    /// Whether the per-app setting options (--keymapping, --resolution, ...) are accepted
    let acceptsSettings: Bool
    let run: (CLIArguments) async throws -> Void
}

enum PlayCoverCLI {
    static let commonFlags: Set<String> = ["help", "verbose"]

    static let commands: [CLICommand] = [
        CLICommand(name: "list", usage: "list [--json]", summary: "List installed apps",
                   flags: ["json"], values: [], acceptsSettings: false, run: CLIAppCommands.list),
        CLICommand(name: "info", usage: "info <app> [--json]", summary: "Show details about an installed app",
                   flags: ["json"], values: [], acceptsSettings: false, run: CLIAppCommands.info),
        CLICommand(name: "devices", usage: "devices [--json]", summary: "List iOS devices an app can report as",
                   flags: ["json"], values: [], acceptsSettings: false, run: CLIAppCommands.devices),
        CLICommand(name: "launch", usage: "launch <app> [setting options] [--save] [--wait] [--lldb | --lldb-terminal]"
                   + " [--keycover-password-stdin]",
                   summary: "Launch an app, optionally with one-off setting overrides",
                   flags: ["save", "wait", "lldb", "lldb-terminal", "keycover-password-stdin"], values: [],
                   acceptsSettings: true, run: CLILaunchCommand.run),
        CLICommand(name: "settings", usage: "settings show <app> [--json] | settings set <app> <setting options>"
                   + " | settings reset <app> [--yes]",
                   summary: "Show, change or reset an app's settings",
                   flags: ["json", "yes"], values: [], acceptsSettings: true, run: CLIAppCommands.settings),
        CLICommand(name: "install", usage: "install <file.ipa> [--playtools on|off] [setting options] [--launch]",
                   summary: "Install an IPA, optionally applying settings",
                   flags: ["launch"], values: ["playtools"], acceptsSettings: true,
                   run: CLIInstallCommands.install),
        CLICommand(name: "export", usage: "export <file.ipa> [--output <file.ipa>]",
                   summary: "Inject PlayTools into an IPA for sideloading",
                   flags: [], values: ["output"], acceptsSettings: false, run: CLIInstallCommands.export),
        CLICommand(name: "uninstall", usage: "uninstall <app> [--data] [--preferences] [--keymap] [--settings]"
                   + " [--entitlements] [--playchain] [--all] [--yes]",
                   summary: "Remove an app, and optionally everything it left behind",
                   flags: CLIInstallCommands.cleanupFlags.union(["entitlements", "yes"]), values: [],
                   acceptsSettings: false, run: CLIInstallCommands.uninstall),
        CLICommand(name: "clear", usage: "clear <app> [--data] [--preferences] [--playchain] [--settings]"
                   + " [--keymap] [--all] [--yes]",
                   summary: "Clear app data, app preferences, PlayChain data, settings or keymaps",
                   flags: CLIInstallCommands.cleanupFlags.union(["yes"]), values: [], acceptsSettings: false,
                   run: CLIInstallCommands.clear),
        CLICommand(name: "playtools", usage: "playtools <app> status|install|remove",
                   summary: "Inject PlayTools into, or remove it from, an installed app",
                   flags: [], values: [], acceptsSettings: false, run: CLIAppCommands.playTools),
        CLICommand(name: "plugins", usage: "plugins <app> list | plugins <app> add <file.dylib>"
                   + " | plugins <app> remove <name>",
                   summary: "Manage custom dylib plugins loaded by PlayTools",
                   flags: [], values: [], acceptsSettings: false, run: CLIAppCommands.plugins),
        CLICommand(name: "automate", usage: CLIAutomateCommand.usage,
                   summary: "Inspect and drive a running app: view tree, screenshots, taps, swipes, typing",
                   flags: CLIAutomateCommand.flags, values: CLIAutomateCommand.values, acceptsSettings: false,
                   run: CLIAutomateCommand.run),
        CLICommand(name: "link", usage: "link [--dir <directory>]",
                   summary: "Install a 'playcover' shell command (default ~/.local/bin)",
                   flags: [], values: ["dir"], acceptsSettings: false, run: CLIInstallCommands.link),
        CLICommand(name: "help", usage: "help [command | options]", summary: "Show help",
                   flags: [], values: [], acceptsSettings: false, run: { args in
                       try args.expectPositionals(1)
                       let topic = args.positionals.first
                       if let topic = topic, topic != "options", topic != "settings-options",
                          !commands.contains(where: { $0.name == topic }) {
                           throw CLIError.usage("Unknown command '\(topic)'. Run 'playcover help' for usage.")
                       }
                       CLITerminal.output(help(for: topic))
                   }),
        CLICommand(name: "version", usage: "version", summary: "Print the PlayCover version",
                   flags: [], values: [], acceptsSettings: false, run: { _ in
                       let info = Bundle.main.infoDictionary
                       CLITerminal.output("PlayCover \(info?["CFBundleShortVersionString"] ?? "?") "
                             + "(\(info?["CFBundleVersion"] ?? "?"))")
                   })
    ]

    /// Whether the process was started as a command (rather than as the app from Finder or Xcode)
    static func shouldHandle(_ arguments: [String]) -> Bool {
        guard arguments.count > 1 else { return false }
        let first = arguments[1]
        if ["--help", "-h", "--version"].contains(first) {
            return true
        }
        // Launch Services and Xcode only pass options (-psn_…, -NSDocumentRevisionsDebugMode) or file paths,
        // so any other plain word is a command, possibly a mistyped one that should get an error
        return !first.hasPrefix("-") && !FileManager.default.fileExists(atPath: first)
    }

    static func run(_ arguments: [String]) -> Never {
        Log.shared.consoleMode = true
        setvbuf(stdout, nil, _IOLBF, 0)

        Task {
            let code = await execute(Array(arguments.dropFirst()))
            exit(code)
        }
        // Run the main run loop rather than dispatchMain(): besides the main queue (MainActor work such as
        // install progress), it delivers the AppKit updates NSRunningApplication and NSWorkspace rely on
        let keepAlive = Timer(timeInterval: 3600, repeats: true) { _ in }
        RunLoop.main.add(keepAlive, forMode: .default)
        while true {
            RunLoop.main.run(mode: .default, before: .distantFuture)
        }
    }

    static func execute(_ arguments: [String]) async -> Int32 {
        var arguments = arguments
        if arguments.first == "--help" || arguments.first == "-h" {
            arguments[0] = "help"
        } else if arguments.first == "--version" {
            arguments[0] = "version"
        }

        guard let name = arguments.first, let command = commands.first(where: { $0.name == name }) else {
            CLITerminal.printError(help(for: nil))
            return 2
        }

        do {
            let valueNames = command.values.union(command.acceptsSettings ? CLISettingOption.names : [])
            let booleanNames = valueNames.intersection(CLISettingOption.booleanNames.union(["playtools"]))
            let parsed = try CLIArguments(Array(arguments.dropFirst()),
                                          flagNames: command.flags.union(commonFlags), valueNames: valueNames,
                                          booleanNames: booleanNames)
            if parsed.has("help") {
                CLITerminal.output(help(for: command.name))
                return 0
            }
            Log.shared.verbose = parsed.has("verbose")
            CLITerminal.captureStrayOutput(verbose: Log.shared.verbose)
            for message in UpdateScheme.moveLibraryBackToContainer() {
                CLITerminal.printError("note: " + message)
            }
            try await command.run(parsed)
            return Log.shared.errorCount == 0 ? 0 : 1
        } catch let error as CLIError {
            CLITerminal.printError("error: \(error.localizedDescription)")
            if case .usage = error {
                CLITerminal.printError("usage: playcover \(command.usage)")
            }
            return error.exitCode
        } catch {
            CLITerminal.printError("error: \(error.localizedDescription)")
            return 1
        }
    }

    // MARK: - App lookup
    static func installedApps() -> [BaseApp] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: AppsVM.appDirectory,
                                                                     includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { $0.pathExtension == "app" && FileManager.default.fileExists(
                atPath: $0.appendingPathComponent("Info.plist").path) }
            .map { BaseApp(appUrl: $0) }
            .sorted { displayName($0).lowercased() < displayName($1).lowercased() }
    }

    static func displayName(_ app: BaseApp) -> String {
        app.info.displayName.isEmpty ? app.info.bundleName : app.info.displayName
    }

    /// Finds an installed app by bundle identifier, name (case-insensitive) or path to its .app bundle
    static func findApp(_ query: String) throws -> PlayApp {
        let apps = installedApps()
        if let app = apps.first(where: { $0.info.bundleIdentifier == query }) {
            return PlayApp(appUrl: app.url)
        }

        let matches = apps.filter {
            displayName($0).lowercased() == query.lowercased() || $0.info.bundleName.lowercased() == query.lowercased()
        }
        if matches.count == 1 {
            return PlayApp(appUrl: matches[0].url)
        } else if matches.count > 1 {
            let ids = matches.map { $0.info.bundleIdentifier }.joined(separator: ", ")
            throw CLIError.usage("'\(query)' matches several apps (\(ids)). Use the bundle identifier instead.")
        }

        let path = URL(fileURLWithPath: (query as NSString).expandingTildeInPath).standardizedFileURL
        if let app = apps.first(where: { $0.url.standardizedFileURL == path }) {
            return PlayApp(appUrl: app.url)
        }
        // Any other bundle of the app, such as its alias in ~/Applications/PlayCover, by bundle identifier
        let bundleID = [path.appendingPathComponent("Info.plist"), path.appendingPathComponent("Contents/Info.plist")]
            .lazy.compactMap { NSDictionary(contentsOf: $0)?["CFBundleIdentifier"] as? String }.first
        if let bundleID = bundleID, let app = apps.first(where: { $0.info.bundleIdentifier == bundleID }) {
            return PlayApp(appUrl: app.url)
        }

        throw CLIError.failed("No installed app matches '\(query)'. Run 'playcover list' to see installed apps.")
    }
}

// MARK: - Help
extension PlayCoverCLI {
    static func help(for topic: String?) -> String {
        if topic == "options" || topic == "settings-options" {
            return settingOptionsHelp()
        }
        if let topic = topic, let command = commands.first(where: { $0.name == topic }) {
            var text = "usage: playcover \(command.usage)\n\n\(command.summary)\n"
            if command.name == "automate" {
                text += CLIAutomateCommand.help
            }
            if command.acceptsSettings {
                text += "\n" + settingOptionsHelp()
            }
            return text
        }

        let width = (commands.map { $0.name.count }.max() ?? 0) + 2
        let lines = commands.map { "  \($0.name.padding(toLength: width, withPad: " ", startingAt: 0))\($0.summary)" }
        return """
        PlayCover command line interface

        usage: playcover <command> [arguments] [--verbose]

        Commands:
        \(lines.joined(separator: "\n"))

        <app> is a bundle identifier, an app name or the path to the installed .app.
        Run 'playcover help <command>' for details or 'playcover help options' for all setting options.
        """
    }

    static func settingOptionsHelp() -> String {
        var text = "Setting options (same as the app settings window; booleans take on|off, a bare --name means on):\n"
        let width = 42
        for section in CLISettingOption.Section.allCases {
            text += "\n  \(section.rawValue):\n"
            for option in CLISettingOption.all where option.section == section {
                let left = "--\(option.name) <\(option.valueHint)>"
                if left.count >= width {
                    // Long value lists get a line of their own
                    text += "    \(left)\n    \(String(repeating: " ", count: width))\(option.help)\n"
                } else {
                    text += "    \(left.padding(toLength: width, withPad: " ", startingAt: 0))\(option.help)\n"
                }
            }
        }
        return text
    }
}
