//
//  CLISettingOptions.swift
//  PlayCover
//

import Foundation

/// Per-app settings requested on the command line, collected before they are written
struct CLISettingsPatch {
    var data: AppSettingsData
    var customWidth: Int?
    var customHeight: Int?
    var resolutionChanged = false
    var resizableAspectRatioChanged = false
    var resolutionGiven = false
    var resizableAspectRatioTypeGiven = false

    // These live in the app bundle (Info.plist / code signature), not in the settings plist
    var introspection: Bool?
    var iosFrameworks: Bool?
    var category: LSApplicationCategoryType?

    let originalWidth: Int
    let originalHeight: Int
    let originalScaler: Double

    init(_ data: AppSettingsData) {
        self.data = data
        originalWidth = data.windowWidth
        originalHeight = data.windowHeight
        originalScaler = data.customScaler
    }
}

/// One `--option value` that maps onto a setting from the app settings window
struct CLISettingOption {
    enum Section: String, CaseIterable {
        case keymapping = "Keymapping"
        case graphics = "Graphics"
        case fixes = "Fixes"
        case misc = "Misc"
    }

    let name: String
    let section: Section
    let valueHint: String
    let help: String
    let apply: (inout CLISettingsPatch, String) throws -> Void

    static func toggle(_ name: String, _ section: Section, _ help: String,
                       _ keyPath: WritableKeyPath<AppSettingsData, Bool>) -> CLISettingOption {
        CLISettingOption(name: name, section: section, valueHint: "on|off", help: help) { patch, value in
            patch.data[keyPath: keyPath] = try CLIValue.bool(value, for: name)
        }
    }

    static func choice(_ name: String, _ section: Section, _ help: String, _ choices: [String],
                       _ keyPath: WritableKeyPath<AppSettingsData, Int>,
                       then: ((inout CLISettingsPatch) -> Void)? = nil) -> CLISettingOption {
        CLISettingOption(name: name, section: section, valueHint: choices.joined(separator: "|"),
                         help: help) { patch, value in
            patch.data[keyPath: keyPath] = try CLIValue.choice(value, for: name, choices: choices)
            then?(&patch)
        }
    }

    static func discord(_ name: String, _ help: String, valueHint: String = "text",
                        _ update: @escaping (DiscordActivity, String) throws -> Void) -> CLISettingOption {
        CLISettingOption(name: name, section: .misc, valueHint: valueHint, help: help) { patch, value in
            // DiscordActivity is a class: copy it so a saved snapshot of the settings is never mutated
            let activity = DiscordActivity()
            activity.enable = patch.data.discordActivity.enable
            activity.applicationID = patch.data.discordActivity.applicationID
            activity.details = patch.data.discordActivity.details
            activity.state = patch.data.discordActivity.state
            activity.image = patch.data.discordActivity.image
            try update(activity, value)
            patch.data.discordActivity = activity
        }
    }
}

extension CLISettingOption {
    static let resolutionChoices = ["app-default", "auto", "1080p", "1440p", "4k", "custom", "resizable"]
    static let aspectRatioChoices = ["4:3", "16:9", "16:10"]
    static let resizableAspectRatioChoices = ["free", "custom", "4:3", "16:9", "16:10"]
    static let windowFixMethodChoices = ["normal", "alternate"]
    static let rotationChoices = ["default", "portrait", "landscape-right", "portrait-upside-down", "flip-fix"]

    static let all: [CLISettingOption] = keymappingOptions + graphicsOptions + fixesOptions + miscOptions

    static let names = Set(all.map { $0.name })
    /// Options that take on/off, so a bare `--name` can mean on
    static let booleanNames = Set(all.filter { $0.valueHint == "on|off" }.map { $0.name })

    static func named(_ name: String) -> CLISettingOption? {
        all.first { $0.name == name }
    }

    static let keymappingOptions: [CLISettingOption] = [
        toggle("keymapping", .keymapping, "Keymapping", \.keymapping),
        toggle("smart-keymap", .keymapping,
               "Smart Keymap: turn keymapping off automatically while typing into a text field", \.noKMOnInput),
        toggle("scroll-wheel", .keymapping, "Enable the scroll wheel", \.enableScrollWheel),
        toggle("disable-builtin-mouse", .keymapping, "Disable built-in mouse support", \.disableBuiltinMouse),
        CLISettingOption(name: "sensitivity", section: .keymapping, valueHint: "0-100",
                         help: "Mouse sensitivity") { patch, value in
            patch.data.sensitivity = Float(try CLIValue.double(value, for: "sensitivity", range: 0...100))
        }
    ]

    static let graphicsOptions: [CLISettingOption] = [
        CLISettingOption(name: "device", section: .graphics, valueHint: "id|alias",
                         help: "iOS device to report, e.g. iPad17,3 or ipad-pro-13-m5 (see 'playcover devices')"
        ) { patch, value in
            guard let device = IOSDevice.find(value) else {
                throw CLIError.usage("Unknown device '\(value)'. Run 'playcover devices' to list them.")
            }
            patch.data.iosDeviceModel = device.id
        },
        choice("resolution", .graphics, "Resolution preset", resolutionChoices, \.resolution) { patch in
            patch.resolutionChanged = true
            patch.resolutionGiven = true
        },
        choice("aspect-ratio", .graphics, "Aspect ratio used by the 1080p, 1440p and 4k presets",
               aspectRatioChoices, \.aspectRatio) { $0.resolutionChanged = true },
        CLISettingOption(name: "width", section: .graphics, valueHint: "pixels",
                         help: "Custom width (implies --resolution custom)") { patch, value in
            patch.customWidth = try CLIValue.int(value, for: "width", range: 1...16384)
            patch.resolutionChanged = true
        },
        CLISettingOption(name: "height", section: .graphics, valueHint: "pixels",
                         help: "Custom height (implies --resolution custom)") { patch, value in
            patch.customHeight = try CLIValue.int(value, for: "height", range: 1...16384)
            patch.resolutionChanged = true
        },
        CLISettingOption(name: "scale", section: .graphics, valueHint: "0.5-10",
                         help: "Resolution scaler") { patch, value in
            patch.data.customScaler = try CLIValue.double(value, for: "scale", range: 0.5...10)
        },
        choice("resizable-aspect-ratio", .graphics, "Aspect ratio of the resizable window",
               resizableAspectRatioChoices, \.resizableAspectRatioType) { patch in
            patch.resizableAspectRatioChanged = true
            patch.resizableAspectRatioTypeGiven = true
        },
        CLISettingOption(name: "resizable-aspect-width", section: .graphics, valueHint: "number",
                         help: "Custom resizable aspect ratio width (implies --resizable-aspect-ratio custom)"
        ) { patch, value in
            patch.data.resizableAspectRatioWidth = try CLIValue.int(value, for: "resizable-aspect-width",
                                                                    range: 1...10000)
            patch.resizableAspectRatioChanged = true
        },
        CLISettingOption(name: "resizable-aspect-height", section: .graphics, valueHint: "number",
                         help: "Custom resizable aspect ratio height (implies --resizable-aspect-ratio custom)"
        ) { patch, value in
            patch.data.resizableAspectRatioHeight = try CLIValue.int(value, for: "resizable-aspect-height",
                                                                     range: 1...10000)
            patch.resizableAspectRatioChanged = true
        },
        toggle("window-fix", .graphics, "Fix window display issues (only with --resolution app-default)",
               \.inverseScreenValues),
        choice("window-fix-method", .graphics, "Window fix method", windowFixMethodChoices, \.windowFixMethod),
        choice("rotation", .graphics, "Device orientation", rotationChoices, \.displayRotation),
        toggle("disable-display-sleep", .graphics, "Disable display sleep", \.disableTimeout),
        toggle("hide-title-bar", .graphics, "Hide the title bar", \.hideTitleBar),
        toggle("floating-window", .graphics, "Keep the window above other windows", \.floatingWindow)
    ]

    static let fixesOptions: [CLISettingOption] = [
        toggle("playchain", .fixes, "PlayChain (keychain emulation)", \.playChain),
        toggle("playchain-debugging", .fixes, "PlayChain debug logging", \.playChainDebugging),
        toggle("jailbreak-bypass", .fixes, "Jailbreak detection bypass", \.bypass),
        CLISettingOption(name: "introspection", section: .fixes, valueHint: "on|off",
                         help: "Insert introspection libraries (re-signs the app)") { patch, value in
            patch.introspection = try CLIValue.bool(value, for: "introspection")
        },
        CLISettingOption(name: "ios-frameworks", section: .fixes, valueHint: "on|off",
                         help: "Force insert iOS frameworks (re-signs the app)") { patch, value in
            patch.iosFrameworks = try CLIValue.bool(value, for: "ios-frameworks")
        },
        toggle("mic-permission-sync", .fixes, "Check microphone permission synchronously",
               \.checkMicPermissionSync),
        toggle("block-sleep-spamming", .fixes, "Prevent usleep call spamming", \.blockSleepSpamming)
    ]

    static let miscOptions: [CLISettingOption] = [
        CLISettingOption(name: "category", section: .misc, valueHint: "type",
                         help: "Application type, e.g. games, utilities, none (re-signs the app)") { patch, value in
            patch.category = try CLISettingOption.category(value)
        },
        toggle("metal-hud", .misc, "Metal performance HUD", \.metalHUD),
        toggle("root-work-dir", .misc, "Start the app at the root directory", \.rootWorkDir),
        toggle("limit-motion-updates", .misc, "Limit motion sensor update frequency", \.limitMotionUpdateFrequency),
        toggle("ignore-unity-keyboard-error", .misc, "Ignore Unity keyboard initialization error",
               \.ignoreUnityKeyboardInitializationError),
        discord("discord", "Discord activity", valueHint: "on|off") {
            $0.enable = try CLIValue.bool($1, for: "discord")
        },
        discord("discord-app-id", "Custom Discord application ID") { $0.applicationID = $1 },
        discord("discord-details", "Discord activity details line") { $0.details = $1 },
        discord("discord-state", "Discord activity state line") { $0.state = $1 },
        discord("discord-image", "Discord activity image key") { $0.image = $1 }
    ]

    static func category(_ value: String) throws -> LSApplicationCategoryType {
        let prefix = "public.app-category."
        let lowered = value.lowercased()
        let match = LSApplicationCategoryType.allCases.first {
            $0.rawValue == lowered || $0.rawValue == prefix + lowered
        }
        guard let match = match else {
            let names = LSApplicationCategoryType.allCases.map { categoryName($0) }
            throw CLIError.usage("Unknown category '\(value)'. Expected one of \(names.joined(separator: ", "))")
        }
        return match
    }

    static func categoryName(_ category: LSApplicationCategoryType) -> String {
        category.rawValue.replacingOccurrences(of: "public.app-category.", with: "")
    }
}

// MARK: - Applying
enum CLISettings {
    /// Builds a patch from the setting options present in `arguments`, in the order they were given
    static func patch(for app: PlayApp, from arguments: CLIArguments) throws -> CLISettingsPatch {
        var patch = CLISettingsPatch(app.settings.settings)
        for name in arguments.order where CLISettingOption.names.contains(name) {
            guard let option = CLISettingOption.named(name), let value = arguments.value(name) else { continue }
            try option.apply(&patch, value)
        }
        finalize(&patch)
        return patch
    }

    static func hasSettingOptions(_ arguments: CLIArguments) -> Bool {
        arguments.order.contains { CLISettingOption.names.contains($0) }
    }

    private static func finalize(_ patch: inout CLISettingsPatch) {
        if (patch.customWidth != nil || patch.customHeight != nil) && !patch.resolutionGiven {
            patch.data.resolution = 5
        }
        if patch.resolutionChanged {
            patch.data.applyResolutionPreset(customWidth: patch.customWidth ?? patch.data.windowWidth,
                                             customHeight: patch.customHeight ?? patch.data.windowHeight)
        }
        if patch.resizableAspectRatioChanged {
            if !patch.resizableAspectRatioTypeGiven {
                patch.data.resizableAspectRatioType = 1
            }
            patch.data.applyResizableAspectRatioPreset()
        }
        // Only warn when this command changes the resolution, not on every later change to an app that has one
        let originalSize = (patch.originalWidth, patch.originalHeight, patch.originalScaler)
        let size = (patch.data.windowWidth, patch.data.windowHeight, patch.data.customScaler)
        if size != originalSize && patch.data.exceedsHighResolutionThreshold {
            CLITerminal.printError("warning: \(patch.data.windowWidth)x\(patch.data.windowHeight) at scale "
                                   + "\(patch.data.customScaler) is very high and may crash some apps")
        }
    }

    /// Writes the patch: settings plist first, then the bundle-level options (which re-sign the app)
    static func apply(_ patch: CLISettingsPatch, to app: PlayApp) async {
        let metalHUDChanged = patch.data.metalHUD != app.settings.settings.metalHUD
        app.settings.settings = patch.data
        if metalHUDChanged {
            // Assigning the whole struct does not run metalHUD's didSet
            do {
                try Shell.setMetalHUD(app.info.bundleIdentifier, enabled: patch.data.metalHUD)
            } catch {
                Log.shared.error(error)
            }
        }

        if let introspection = patch.introspection, introspection != hasIntrospection(app) {
            _ = await app.changeDyldLibraryPath(set: introspection, path: PlayApp.introspection)
        }
        if let iosFrameworks = patch.iosFrameworks, iosFrameworks != hasIosFrameworks(app) {
            _ = await app.changeDyldLibraryPath(set: iosFrameworks, path: PlayApp.iosFrameworks)
        }
        if let category = patch.category, category != app.info.applicationCategoryType {
            app.info.applicationCategoryType = category
            do {
                try Shell.signApp(app.executable)
            } catch {
                Log.shared.error(error)
            }
        }
    }

    static func hasIntrospection(_ app: PlayApp) -> Bool {
        (app.info.lsEnvironment["DYLD_LIBRARY_PATH"] ?? "").contains(PlayApp.introspection)
    }

    static func hasIosFrameworks(_ app: PlayApp) -> Bool {
        (app.info.lsEnvironment["DYLD_LIBRARY_PATH"] ?? "").contains(PlayApp.iosFrameworks)
    }

    // MARK: Snapshot for one-off launches
    struct Snapshot {
        let settings: Data
        let introspection: Bool
        let iosFrameworks: Bool
        let category: LSApplicationCategoryType
    }

    static func snapshot(_ app: PlayApp) throws -> Snapshot {
        Snapshot(settings: try PropertyListEncoder().encode(app.settings.settings),
                 introspection: hasIntrospection(app),
                 iosFrameworks: hasIosFrameworks(app),
                 category: app.info.applicationCategoryType)
    }

    static func restore(_ snapshot: Snapshot, to app: PlayApp) async {
        do {
            var patch = CLISettingsPatch(try PropertyListDecoder().decode(AppSettingsData.self,
                                                                          from: snapshot.settings))
            patch.introspection = snapshot.introspection
            patch.iosFrameworks = snapshot.iosFrameworks
            patch.category = snapshot.category
            await apply(patch, to: app)
        } catch {
            Log.shared.error(error)
        }
    }

    // MARK: Display
    static func describe(_ app: PlayApp) throws -> [String: Any] {
        let data = try PropertyListEncoder().encode(app.settings.settings)
        var settings = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
        settings["introspection"] = hasIntrospection(app)
        settings["iosFrameworks"] = hasIosFrameworks(app)
        settings["applicationCategoryType"] = CLISettingOption.categoryName(app.info.applicationCategoryType)
        settings["playTools"] = app.hasPlayTools()
        return settings
    }
}
