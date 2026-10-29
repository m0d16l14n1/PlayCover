//
//  CLILaunchCommand.swift
//  PlayCover
//

import AppKit
import Foundation

/// `playcover launch`: the same steps as PlayApp.launch, without dialogs
enum CLILaunchCommand {
    struct Options {
        var wait = false
        var lldb = false
        var lldbInTerminal = false
        var passwordFromStdin = false
    }

    static func run(_ args: CLIArguments) async throws {
        try args.expectPositionals(1)
        if args.has("lldb") && args.has("lldb-terminal") {
            throw CLIError.usage("Use either --lldb or --lldb-terminal")
        }
        let app = try PlayCoverCLI.findApp(try args.positional(0, "app"))

        // One-off overrides are rolled back once the app quits, unless --save is given
        var snapshot: CLISettings.Snapshot?
        if CLISettings.hasSettingOptions(args) {
            let patch = try CLISettings.patch(for: app, from: args)
            if !args.has("save") {
                snapshot = try CLISettings.snapshot(app)
            }
            await CLISettings.apply(patch, to: app)
        }

        let options = Options(wait: args.has("wait"), lldb: args.has("lldb"), lldbInTerminal: args.has("lldb-terminal"),
                              passwordFromStdin: args.has("keycover-password-stdin"))
        try await launch(app, options: options, snapshot: snapshot)
    }

    static func launch(_ app: PlayApp, options: Options, snapshot: CLISettings.Snapshot? = nil) async throws {
        let session = LaunchSession(app: app, snapshot: snapshot)
        // An interactive lldb session handles Ctrl-C itself
        session.handleTerminationSignals(includingInterrupt: !options.lldb)
        do {
            try await prepare(app)
            await session.unlockKeyCover(passwordFromStdin: options.passwordFromStdin)

            if options.lldb || options.lldbInTerminal {
                try runWithLLDB(app, inTerminalWindow: options.lldbInTerminal)
                await session.finish()
                return
            }

            let runningApp = try await open(app)
            CLITerminal.output("Launched \(app.info.bundleIdentifier) (pid \(runningApp.processIdentifier))")

            if options.wait || session.needsCleanup {
                if !options.wait {
                    CLITerminal.printError("Waiting for \(app.name) to quit to "
                                           + (snapshot != nil
                                              ? "restore its settings (use --save to keep them)"
                                              : "lock its PlayChain"))
                }
                await waitForExit(runningApp, app: app)
                await session.finish()
            }
        } catch {
            await session.finish()
            throw error
        }
    }

    /// Validation, signing and PlayTools checks from PlayApp.launch
    static func prepare(_ app: PlayApp) async throws {
        if app.prohibitedToPlay {
            await app.clearAllCache()
            throw PlayCoverError.appProhibited
        } else if app.maliciousProhibited {
            await app.clearAllCache()
            app.deleteApp(refreshLibrary: false)
            throw PlayCoverError.appMaliciousProhibited
        }

        app.settings.sync()

        if app.hasPlayTools() {
            try PlayTools.installPluginInIPA(app.url)
        }
        if try !Entitlements.areEntitlementsValid(app: app) {
            app.sign()
        }
        if try !app.isInfoPlistSigned() {
            try Shell.signApp(app.executable)
        }

        // The GUI refreshes ~/Library/Frameworks/PlayTools.framework on every start; do the same when stale
        if try !PlayTools.isInstalled() || !PlayTools.isSystemCopyCurrent() {
            try PlayTools.installOnSystemNow()
        }
        guard try PlayTools.isInstalled() else {
            throw CLIError.failed("PlayTools are not installed! Please move PlayCover.app into Applications!")
        }
        guard try Macho.isMachoValidArch(app.executable) else {
            throw CLIError.failed("The app threw an error during conversion.")
        }

        app.clearDebugAffectingEnvironment()
        // The bundle may have been re-signed above, so rebuild the alias to keep its Info.plist in sync
        app.removeAlias()
        app.createAlias()
    }

    static func open(_ app: PlayApp) async throws -> NSRunningApplication {
        let aliasURL = app.aliasURL
        let name = app.name
        return try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: aliasURL,
                                               configuration: NSWorkspace.OpenConfiguration()) { runningApp, error in
                if let runningApp = runningApp {
                    continuation.resume(returning: runningApp)
                } else {
                    continuation.resume(throwing: error ?? CLIError.failed("Could not launch \(name)"))
                }
            }
        }
    }

    /// Mirrors PlayApp.runAppExec: keep the display awake while the app is frontmost
    static func waitForExit(_ runningApp: NSRunningApplication, app: PlayApp) async {
        let pid = runningApp.processIdentifier
        // kill(pid, 0) as a backstop in case the terminated state is not delivered
        while !runningApp.isTerminated && (kill(pid, 0) == 0 || errno != ESRCH) {
            if runningApp.isActive {
                app.disableTimeOut()
            } else {
                app.enableTimeOut()
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        app.enableTimeOut()
    }

    static func runWithLLDB(_ app: PlayApp, inTerminalWindow: Bool) throws {
        if inTerminalWindow {
            try Shell.lldb(app.executable, withTerminalWindow: true)
            return
        }
        // Attach lldb to this terminal so it stays interactive
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lldb")
        process.arguments = ["-o", "run", app.executable.path]
        process.standardOutput = CLITerminal.standardOutput
        try process.run()
        process.waitUntilExit()
    }
}

/// State that has to be put back after the launched app quits
final class LaunchSession {
    let app: PlayApp
    let snapshot: CLISettings.Snapshot?
    private var chainToLock: KeyCoverKey?
    private var playChainBeforeSession: Bool?
    private var finished = false
    private var signalSources: [DispatchSourceSignal] = []

    init(app: PlayApp, snapshot: CLISettings.Snapshot?) {
        self.app = app
        self.snapshot = snapshot
    }

    var needsCleanup: Bool {
        snapshot != nil || chainToLock != nil || playChainBeforeSession != nil
    }

    /// Mirrors PlayApp.unlockKeyCover, reading the master password from the terminal instead of a window
    func unlockKeyCover(passwordFromStdin: Bool) async {
        // Checked without touching KeyCover.shared, whose initializer reads the master password from the keychain
        let keychain = KeyCoverKey(appBundleID: app.info.bundleIdentifier)
        guard KeyCoverPreferences.shared.keyCoverEnabled != .disabled else { return }
        guard keychain.chainEncryptionStatus else {
            // Like PlayApp.lockKeyCover, encrypt the chain after the app quits even when it was not locked before:
            // the app may create it during this session
            chainToLock = keychain
            return
        }

        if KeyCover.shared.keyCoverPlainTextKey == nil, let password = readPassword(fromStdin: passwordFromStdin) {
            if KeyCoverPassword.shared.validatePassword(password) {
                KeyCover.shared.keyCoverPlainTextKey = password
            } else {
                CLITerminal.printError("error: incorrect KeyCover password")
            }
        }

        if KeyCover.shared.keyCoverPlainTextKey != nil {
            do {
                try keychain.decryptKeyDB()
                chainToLock = keychain
                return
            } catch {
                Log.shared.error(error)
            }
        }

        CLITerminal.printError("warning: PlayChain is locked by KeyCover; it is disabled for this session")
        playChainBeforeSession = app.settings.settings.playChain
        app.settings.settings.playChain = false
    }

    private func readPassword(fromStdin: Bool) -> String? {
        if fromStdin {
            return readLine(strippingNewline: true)
        }
        guard CLITerminal.isInteractive else { return nil }
        var buffer = [CChar](repeating: 0, count: 1024)
        guard let result = readpassphrase("KeyCover password: ", &buffer, buffer.count, 0) else { return nil }
        return String(cString: result)
    }

    func finish() async {
        guard !finished else { return }
        finished = true

        if let playChain = playChainBeforeSession {
            app.settings.settings.playChain = playChain
        }
        if let chainToLock = chainToLock, !chainToLock.chainEncryptionStatus,
           FileManager.default.fileExists(atPath: chainToLock.decryptedKeyDB.path) {
            do {
                try KeyCover.shared.lockChain(chainToLock)
            } catch {
                Log.shared.error(error)
            }
        }
        if let snapshot = snapshot {
            await CLISettings.restore(snapshot, to: app)
            CLITerminal.printError("Restored the settings of \(app.info.bundleIdentifier)")
        }
    }

    /// Ctrl-C (or kill) still restores settings and relocks PlayChain; an app that was launched keeps running
    func handleTerminationSignals(includingInterrupt: Bool) {
        for signalNumber in includingInterrupt ? [SIGINT, SIGTERM, SIGHUP] : [SIGTERM, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in
                Task {
                    await self?.finish()
                    exit(128 + signalNumber)
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
