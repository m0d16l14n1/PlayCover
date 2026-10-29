//
//  CLIAppCommands.swift
//  PlayCover
//

import Foundation

enum CLIAppCommands {
    static func list(_ args: CLIArguments) async throws {
        try args.expectPositionals(0)
        let apps = PlayCoverCLI.installedApps()

        if args.has("json") {
            CLITerminal.output(try CLITerminal.json(apps.map { summary(of: $0) }))
            return
        }
        guard !apps.isEmpty else {
            CLITerminal.printError("No apps installed")
            return
        }
        let width = (apps.map { $0.info.bundleIdentifier.count }.max() ?? 0) + 2
        for app in apps {
            let identifier = app.info.bundleIdentifier.padding(toLength: width, withPad: " ", startingAt: 0)
            CLITerminal.output("\(identifier)\(PlayCoverCLI.displayName(app)) \(app.info.bundleVersion)")
        }
    }

    static func info(_ args: CLIArguments) async throws {
        try args.expectPositionals(1)
        let app = try PlayCoverCLI.findApp(try args.positional(0, "app"))

        var details = summary(of: app)
        details["executable"] = app.executable.path
        details["minimumOSVersion"] = app.info.minimumOSVersion
        details["playTools"] = app.hasPlayTools()
        details["alias"] = app.aliasURL.path
        details["settingsFile"] = app.settings.settingsUrl.path
        details["keymapsDirectory"] = app.keymapping.baseKeymapURL.path
        details["dataContainer"] = app.container.containerUrl.path
        details["preferencesFile"] = app.container.userPrefsUrl.path
        details["playChain"] = app.playChainURL.path
        details["entitlementsFile"] = app.entitlements.path
        details["plugins"] = PlayTools.userDylibs(bundleIdentifier: app.info.bundleIdentifier)
            .map { $0.lastPathComponent }

        if args.has("json") {
            CLITerminal.output(try CLITerminal.json(details))
        } else {
            printKeyValues(details)
        }
    }

    static func devices(_ args: CLIArguments) async throws {
        try args.expectPositionals(0)
        if args.has("json") {
            CLITerminal.output(try CLITerminal.json(IOSDevice.all.map {
                ["id": $0.id, "alias": $0.alias, "name": $0.name, "chip": $0.chip, "memory": $0.memory]
            }))
            return
        }
        let idWidth = (IOSDevice.all.map { $0.id.count }.max() ?? 0) + 2
        let aliasWidth = (IOSDevice.all.map { $0.alias.count }.max() ?? 0) + 2
        for device in IOSDevice.all {
            CLITerminal.output(device.id.padding(toLength: idWidth, withPad: " ", startingAt: 0)
                  + device.alias.padding(toLength: aliasWidth, withPad: " ", startingAt: 0)
                  + device.label)
        }
    }

    static func settings(_ args: CLIArguments) async throws {
        let action = try args.positional(0, "action (show, set or reset)")
        try args.expectPositionals(2)
        let app = try PlayCoverCLI.findApp(try args.positional(1, "app"))
        if action != "set" && CLISettings.hasSettingOptions(args) {
            throw CLIError.usage("Setting options only apply to 'settings set'")
        }

        switch action {
        case "show":
            let settings = try CLISettings.describe(app)
            if args.has("json") {
                CLITerminal.output(try CLITerminal.json(settings))
            } else {
                printKeyValues(settings)
            }
        case "set":
            guard CLISettings.hasSettingOptions(args) else {
                throw CLIError.usage("No setting options given. Run 'playcover help options' to list them.")
            }
            let patch = try CLISettings.patch(for: app, from: args)
            await CLISettings.apply(patch, to: app)
            CLITerminal.output("Updated settings for \(app.info.bundleIdentifier)")
        case "reset":
            guard try CLITerminal.confirm("Reset all settings of \(app.name)?", assumeYes: args.has("yes")) else {
                return
            }
            app.settings.reset()
            CLITerminal.output("Reset settings for \(app.info.bundleIdentifier)")
        default:
            throw CLIError.usage("Unknown settings action '\(action)'")
        }
    }

    static func playTools(_ args: CLIArguments) async throws {
        try args.expectPositionals(2)
        let app = try PlayCoverCLI.findApp(try args.positional(0, "app"))
        let action = try args.positional(1, "action (status, install or remove)")

        switch action {
        case "status":
            CLITerminal.output(app.hasPlayTools() ? "installed" : "not installed")
        case "install":
            guard !app.hasPlayTools() else {
                CLITerminal.output("PlayTools is already injected into \(app.info.bundleIdentifier)")
                return
            }
            try await PlayTools.installInIPA(app.executable)
            CLITerminal.output("Injected PlayTools into \(app.info.bundleIdentifier)")
        case "remove":
            guard app.hasPlayTools() else {
                CLITerminal.output("PlayTools is not injected into \(app.info.bundleIdentifier)")
                return
            }
            await PlayTools.removeFromApp(app.executable)
            CLITerminal.output("Removed PlayTools from \(app.info.bundleIdentifier)")
        default:
            throw CLIError.usage("Unknown playtools action '\(action)'")
        }
    }

    static func plugins(_ args: CLIArguments) async throws {
        let app = try PlayCoverCLI.findApp(try args.positional(0, "app"))
        let action = try args.positional(1, "action (list, add or remove)")
        let bundleID = app.info.bundleIdentifier

        switch action {
        case "list":
            try args.expectPositionals(2)
            for dylib in PlayTools.userDylibs(bundleIdentifier: bundleID) {
                CLITerminal.output(dylib.lastPathComponent)
            }
        case "add":
            try args.expectPositionals(3)
            guard app.hasPlayTools() else {
                throw CLIError.failed("Custom plugins are loaded by PlayTools, which is not injected into \(bundleID)")
            }
            let path = (try args.positional(2, "path to a .dylib") as NSString).expandingTildeInPath
            try PlayTools.addUserDylib(at: URL(fileURLWithPath: path), bundleIdentifier: bundleID,
                                       appExecutable: app.executable)
            CLITerminal.output("Added \(URL(fileURLWithPath: path).lastPathComponent) to \(bundleID)")
        case "remove":
            try args.expectPositionals(3)
            let given = try args.positional(2, "plugin name")
            // Accept the name as listed (Plugin.dylib) or without the extension
            guard let name = PlayTools.userDylibs(bundleIdentifier: bundleID).map({ $0.lastPathComponent })
                .first(where: { $0 == given || $0 == given + ".dylib" }) else {
                throw CLIError.failed("\(bundleID) has no plugin named '\(given)'")
            }
            try PlayTools.removeUserDylib(named: name, bundleIdentifier: bundleID, appExecutable: app.executable)
            CLITerminal.output("Removed \(name) from \(bundleID)")
        default:
            throw CLIError.usage("Unknown plugins action '\(action)'")
        }
    }

    // MARK: - Helpers
    static func summary(of app: BaseApp) -> [String: Any] {
        [
            "bundleIdentifier": app.info.bundleIdentifier,
            "name": PlayCoverCLI.displayName(app),
            "version": app.info.bundleVersion,
            "path": app.url.path,
            "applicationCategoryType": CLISettingOption.categoryName(app.info.applicationCategoryType)
        ]
    }

    static func printKeyValues(_ values: [String: Any]) {
        let width = (values.keys.map { $0.count }.max() ?? 0) + 2
        for (key, value) in values.sorted(by: { $0.key < $1.key }) {
            CLITerminal.output("\(key.padding(toLength: width, withPad: " ", startingAt: 0))\(format(value))")
        }
    }

    private static func format(_ value: Any) -> String {
        switch value {
        // Only real booleans: a plain `as Bool` cast would also match integer NSNumbers
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            return number.boolValue ? "on" : "off"
        case let list as [Any]:
            return list.map { format($0) }.joined(separator: ", ")
        case let dictionary as [String: Any]:
            return dictionary.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\(format($0.value))" }
                .joined(separator: " ")
        default:
            return "\(value)"
        }
    }
}
