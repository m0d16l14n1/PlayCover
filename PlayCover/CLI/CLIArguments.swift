//
//  CLIArguments.swift
//  PlayCover
//

import Foundation

enum CLIError: LocalizedError {
    case usage(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message), .failed(let message):
            return message
        }
    }

    var exitCode: Int32 {
        switch self {
        case .usage:
            return 2
        case .failed:
            return 1
        }
    }
}

/// Parsed command line: positional arguments plus `--name value`, `--name=value` and valueless `--flag` options
struct CLIArguments {
    private(set) var positionals: [String] = []
    private(set) var values: [String: String] = [:]
    private(set) var flags: Set<String> = []
    /// Option names in the order they were given
    private(set) var order: [String] = []

    /// - Parameters:
    ///   - arguments: Arguments after the command name
    ///   - flagNames: Options that never take a value
    ///   - valueNames: Options that require a value
    init(_ arguments: [String], flagNames: Set<String>, valueNames: Set<String>) throws {
        var index = 0
        var onlyPositionals = false
        while index < arguments.count {
            let argument = arguments[index]
            index += 1

            if onlyPositionals || !argument.hasPrefix("-") || argument == "-" {
                positionals.append(argument)
                continue
            }
            if argument == "--" {
                onlyPositionals = true
                continue
            }

            var name = argument.hasPrefix("--") ? String(argument.dropFirst(2)) : String(argument.dropFirst())
            var inlineValue: String?
            if let equals = name.firstIndex(of: "=") {
                inlineValue = String(name[name.index(after: equals)...])
                name = String(name[..<equals])
            }
            name = CLIArguments.shortNames[name] ?? name

            if flagNames.contains(name) {
                if inlineValue != nil {
                    throw CLIError.usage("--\(name) does not take a value")
                }
                flags.insert(name)
            } else if valueNames.contains(name) {
                if let inlineValue = inlineValue {
                    values[name] = inlineValue
                } else if index < arguments.count {
                    values[name] = arguments[index]
                    index += 1
                } else {
                    throw CLIError.usage("--\(name) requires a value")
                }
            } else {
                throw CLIError.usage("Unknown option '\(argument)'. Run 'playcover help' for usage.")
            }
            order.append(name)
        }
    }

    private static let shortNames = ["y": "yes", "h": "help", "v": "verbose"]

    func has(_ flag: String) -> Bool {
        flags.contains(flag)
    }

    func value(_ name: String) -> String? {
        values[name]
    }

    func positional(_ index: Int, _ what: String) throws -> String {
        guard index < positionals.count else {
            throw CLIError.usage("Missing \(what)")
        }
        return positionals[index]
    }

    func expectPositionals(_ count: Int) throws {
        if positionals.count > count {
            throw CLIError.usage("Unexpected argument '\(positionals[count])'")
        }
    }
}

// MARK: - Value parsing
enum CLIValue {
    static func bool(_ value: String, for name: String) throws -> Bool {
        switch value.lowercased() {
        case "1", "on", "yes", "true", "enable", "enabled":
            return true
        case "0", "off", "no", "false", "disable", "disabled":
            return false
        default:
            throw CLIError.usage("--\(name) expects on or off, got '\(value)'")
        }
    }

    static func int(_ value: String, for name: String, range: ClosedRange<Int>? = nil) throws -> Int {
        guard let number = Int(value), range?.contains(number) ?? true else {
            let expected = range.map { "a whole number between \($0.lowerBound) and \($0.upperBound)" }
                ?? "a whole number"
            throw CLIError.usage("--\(name) expects \(expected), got '\(value)'")
        }
        return number
    }

    static func double(_ value: String, for name: String, range: ClosedRange<Double>) throws -> Double {
        guard let number = Double(value), range.contains(number) else {
            throw CLIError.usage("--\(name) expects a number between \(range.lowerBound) and \(range.upperBound), "
                                 + "got '\(value)'")
        }
        return number
    }

    /// Picks the index of `value` in `choices`; a plain index is accepted too
    static func choice(_ value: String, for name: String, choices: [String]) throws -> Int {
        if let index = choices.firstIndex(of: value.lowercased()) {
            return index
        }
        if let index = Int(value), choices.indices.contains(index) {
            return index
        }
        throw CLIError.usage("--\(name) expects one of \(choices.joined(separator: ", ")), got '\(value)'")
    }
}

// MARK: - Terminal helpers
enum CLITerminal {
    /// The real standard output; fd 1 itself is redirected by captureStrayOutput
    private(set) static var standardOutput = FileHandle.standardOutput

    /// Shared app code prints diagnostics with print(). Keep them out of stdout so command output (and --json)
    /// stays machine readable: they go to stderr with --verbose and are discarded otherwise.
    static func captureStrayOutput(verbose: Bool) {
        fflush(stdout)
        let saved = dup(STDOUT_FILENO)
        guard saved >= 0 else { return }
        standardOutput = FileHandle(fileDescriptor: saved, closeOnDealloc: false)
        let target = verbose ? STDERR_FILENO : open("/dev/null", O_WRONLY)
        if target >= 0 {
            dup2(target, STDOUT_FILENO)
        }
    }

    /// Command output, written to the real standard output
    static func output(_ text: String) {
        standardOutput.write(Data("\(text)\n".utf8))
    }

    static func printError(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }

    static var isInteractive: Bool {
        isatty(STDIN_FILENO) != 0
    }

    /// Asks a yes/no question; refuses when not attached to a terminal unless `assumeYes` is set
    static func confirm(_ question: String, assumeYes: Bool) throws -> Bool {
        if assumeYes {
            return true
        }
        guard isInteractive else {
            throw CLIError.usage("Refusing to continue without confirmation. Pass --yes to proceed non-interactively.")
        }
        FileHandle.standardError.write(Data("\(question) [y/N] ".utf8))
        let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        return answer == "y" || answer == "yes"
    }

    static func json(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}
