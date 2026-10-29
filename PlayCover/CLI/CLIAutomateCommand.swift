//
//  CLIAutomateCommand.swift
//  PlayCover
//

import Foundation

/// `playcover automate <app> <action>`: inspects and drives a running app through PlayTools' automation server
enum CLIAutomateCommand {
    static let flags: Set<String> = ["json", "all", "exact", "gone", "window", "replace"]
    static let values: Set<String> = ["depth", "label", "id", "class", "path", "duration", "timeout", "scale"]

    static let usage = """
        automate <app> info|tree|find|tap|longpress|swipe|type|key|screenshot|wait|run ... (see 'help automate')
        """

    static let help = """

        The app must run with automation allowed: 'playcover launch <app> --automation' (this launch only) or
        'playcover settings set <app> --automation'. Coordinates are points in the app's window, as reported by
        tree and find. Elements can be chosen by text (or label, --id, --class, --path) instead of coordinates.

        Actions:
          info [--json]                              Window size, scale, window number, focused field
          tree [--depth N] [--all] [--json]          The view hierarchy (visible views only unless --all)
          find [<text>] [--label L] [--id I] [--class C] [--exact] [--json]
                                                     Visible elements that match, with their frames
          tap <x> <y> | tap [<text>] [query options] Tap a point or the center of the first match
          longpress <x> <y> | [<text>] [--duration S]
          swipe <x1> <y1> <x2> <y2> [--duration S]
          type <text> [--replace]                    Type into the focused text field (--replace: instead of
                                                     what it holds)
          key return|tab|delete
          screenshot <file.png> [--window] [--scale N]
                                                     The window rendered by the app; --window captures the real
                                                     window instead (needed for Metal games; asks for Screen
                                                     Recording permission)
          wait [<text>] [query options] [--gone] [--timeout S]
                                                     Wait until an element appears (or with --gone, disappears)
          run <script>                               Run actions from a file, one per line ('sleep S' pauses,
                                                     '#' starts a comment); stops at the first failure
        """

    static func run(_ args: CLIArguments) async throws {
        let app = try PlayCoverCLI.findApp(try args.positional(0, "app"))
        let action = try args.positional(1, "action")
        let client = try AutomationClient(app: app)
        try await perform(action, Array(args.positionals.dropFirst(2)), args, client: client)
    }

    // MARK: - Actions
    private static func perform(_ action: String, _ rest: [String], _ args: CLIArguments,
                                client: AutomationClient) async throws {
        switch action {
        case "info":
            try expect(rest, 0)
            let response = try client.request("info")
            try print(response, args) { CLIAppCommands.printKeyValues(response.filter { $0.key != "ok" }) }
        case "tree":
            try expect(rest, 0)
            var request: [String: Any] = ["all": args.has("all")]
            if let depth = args.value("depth") {
                request["depth"] = try CLIValue.int(depth, for: "depth", range: 0...1000)
            }
            let response = try client.request("tree", request)
            try print(response, args) { printTree(response["root"] as? [String: Any] ?? [:], indent: "") }
        case "find":
            let response = try client.request("find", try query(rest, args))
            try print(response, args) {
                for element in response["matches"] as? [[String: Any]] ?? [] {
                    CLITerminal.output(line(for: element))
                }
            }
        case "tap", "longpress":
            var request = try target(rest, args, action: action)
            if action == "longpress" {
                request["duration"] = try args.value("duration")
                    .map { try CLIValue.double($0, for: "duration", range: 0...600) } ?? 1
            }
            let response = try client.request(action, request)
            CLITerminal.output("Tapped (\(number(response["x"])), \(number(response["y"])))")
        default:
            try await performMore(action, rest, args, client: client)
        }
    }

    private static func performMore(_ action: String, _ rest: [String], _ args: CLIArguments,
                                    client: AutomationClient) async throws {
        switch action {
        case "swipe":
            try expect(rest, 4)
            let numbers = try rest.map { try CLIValue.double($0, for: "swipe", range: -100_000...100_000) }
            var request: [String: Any] = ["x1": numbers[0], "y1": numbers[1], "x2": numbers[2], "y2": numbers[3]]
            if let duration = args.value("duration") {
                request["duration"] = try CLIValue.double(duration, for: "duration", range: 0...600)
            }
            _ = try client.request("swipe", request)
        case "type":
            try expect(rest, 1)
            _ = try client.request("type", ["text": rest[0], "replace": args.has("replace")])
        case "key":
            try expect(rest, 1)
            _ = try client.request("key", ["key": rest[0]])
        case "screenshot":
            try expect(rest, 1)
            try screenshot(to: rest[0], args, client: client)
        case "wait":
            try await wait(rest, args, client: client)
        case "run":
            try expect(rest, 1)
            try await runScript(rest[0], client: client)
        default:
            throw CLIError.usage("Unknown automate action '\(action)'. Run 'playcover help automate'.")
        }
    }

    private static func screenshot(to path: String, _ args: CLIArguments, client: AutomationClient) throws {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        if args.has("window") {
            // The window as the screen shows it, Metal content included
            let window = try client.request("info")["window"] as? [String: Any]
            guard let number = window?["number"] as? Int, number > 0 else {
                throw CLIError.failed("The app's window number is unknown")
            }
            try Shell.run(print: false, "/usr/sbin/screencapture", "-x", "-o", "-l\(number)", url.path)
        } else {
            var request: [String: Any] = [:]
            if let scale = args.value("scale") {
                request["scale"] = try CLIValue.double(scale, for: "scale", range: 0.1...8)
            }
            let response = try client.request("screenshot", request)
            guard let base64 = response["png"] as? String, let png = Data(base64Encoded: base64) else {
                throw CLIError.failed("The app sent no image")
            }
            try png.write(to: url)
        }
        CLITerminal.output("Saved \(url.path)")
    }

    private static func wait(_ rest: [String], _ args: CLIArguments, client: AutomationClient) async throws {
        let request = try query(rest, args)
        let timeout = try args.value("timeout").map { try CLIValue.double($0, for: "timeout", range: 0...86_400) } ?? 30
        let gone = args.has("gone")
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let matches = try client.request("find", request)["matches"] as? [[String: Any]] ?? []
            if matches.isEmpty == gone {
                if let first = matches.first {
                    CLITerminal.output(line(for: first))
                }
                return
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        } while Date() < deadline
        throw CLIError.failed("Timed out after \(number(timeout))s waiting for "
                              + (gone ? "the element to disappear" : "the element"))
    }

    /// Each line is an automate action with its arguments, as typed after 'playcover automate <app>'
    private static func runScript(_ path: String, client: AutomationClient) async throws {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines)
        for (index, text) in lines.enumerated() {
            let words = try shellWords(text)
            guard let action = words.first, !action.hasPrefix("#") else { continue }
            do {
                if action == "sleep" {
                    let seconds = try CLIValue.double(words.dropFirst().first ?? "", for: "sleep", range: 0...86_400)
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    continue
                }
                guard action != "run" else { throw CLIError.usage("'run' cannot be nested") }
                let args = try CLIArguments(Array(words.dropFirst()), flagNames: flags, valueNames: values)
                try await perform(action, args.positionals, args, client: client)
            } catch let error as CLIError {
                throw CLIError.failed("\(url.lastPathComponent):\(index + 1): \(error.errorDescription ?? "")")
            }
        }
    }

    // MARK: - Arguments
    private static func expect(_ rest: [String], _ count: Int) throws {
        if rest.count > count {
            throw CLIError.usage("Unexpected argument '\(rest[count])'")
        } else if rest.count < count {
            throw CLIError.usage("Missing argument; run 'playcover help automate'")
        }
    }

    private static func query(_ rest: [String], _ args: CLIArguments) throws -> [String: Any] {
        try expect(rest, min(rest.count, 1))
        var request: [String: Any] = ["exact": args.has("exact")]
        request["text"] = rest.first
        request["label"] = args.value("label")
        request["identifier"] = args.value("id")
        request["class"] = args.value("class")
        request["path"] = args.value("path")
        guard request.count > 1 else {
            throw CLIError.usage("Give text, --label, --id, --class or --path")
        }
        return request
    }

    private static func target(_ rest: [String], _ args: CLIArguments, action: String) throws -> [String: Any] {
        if rest.count == 2, let pointX = Double(rest[0]), let pointY = Double(rest[1]) {
            return ["x": pointX, "y": pointY]
        }
        return try query(rest, args)
    }

    /// Splits a script line like a shell would: whitespace separates words, quotes group them, \ escapes
    static func shellWords(_ line: String) throws -> [String] {
        var words: [String] = []
        var current = ""
        var quote: Character?
        var inWord = false
        var escaped = false
        for character in line {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" && quote != "'" {
                escaped = true
                inWord = true
            } else if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
                inWord = true
            } else if character.isWhitespace {
                if inWord { words.append(current) }
                current = ""
                inWord = false
            } else {
                current.append(character)
                inWord = true
            }
        }
        guard quote == nil else { throw CLIError.usage("Unclosed quote in '\(line)'") }
        if inWord { words.append(current) }
        return words
    }

}

// MARK: - Output
extension CLIAutomateCommand {
    private static func print(_ response: [String: Any], _ args: CLIArguments, text: () -> Void) throws {
        if args.has("json") {
            CLITerminal.output(try CLITerminal.json(response.filter { $0.key != "ok" }))
        } else {
            text()
        }
    }

    private static func printTree(_ node: [String: Any], indent: String) {
        CLITerminal.output(indent + line(for: node))
        for child in node["children"] as? [[String: Any]] ?? [] {
            printTree(child, indent: indent + "  ")
        }
    }

    /// `0.1.3 UIButton "Play" label="Start" id=play [x y w h]`
    private static func line(for element: [String: Any]) -> String {
        var parts = [element["path"] as? String ?? "", element["class"] as? String ?? "?"]
        if let text = element["text"] as? String {
            parts.append("\"\(text.replacingOccurrences(of: "\n", with: "\\n"))\"")
        }
        if let label = element["label"] as? String, label != element["text"] as? String {
            parts.append("label=\"\(label)\"")
        }
        if let identifier = element["identifier"] as? String {
            parts.append("id=\(identifier)")
        }
        if let frame = element["frame"] as? [Any] {
            parts.append("[" + frame.map { number($0) }.joined(separator: " ") + "]")
        }
        if element["enabled"] as? Bool == false {
            parts.append("disabled")
        }
        if element["focused"] as? Bool == true {
            parts.append("focused")
        }
        return parts.joined(separator: " ")
    }

    private static func number(_ value: Any?) -> String {
        guard let value = value as? Double else { return "\(value ?? "")" }
        return value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// Talks to PlayTools' automation server in a running app (one JSON object per line over loopback TCP)
struct AutomationClient {
    let port: UInt16
    let token: String

    init(app: PlayApp) throws {
        let bundleID = app.info.bundleIdentifier
        let endpointURL = PlayTools.playCoverContainer.appendingPathComponent("Automation")
            .appendingPathComponent(bundleID).appendingPathExtension("json")
        let hint = "Start it with 'playcover launch \(bundleID) --automation', or allow automation with "
            + "'playcover settings set \(bundleID) --automation' and start it."
        guard let data = try? Data(contentsOf: endpointURL),
              let endpoint = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let port = endpoint["port"] as? Int, let token = endpoint["token"] as? String,
              let pid = endpoint["pid"] as? Int32 else {
            throw CLIError.failed("\(app.name) is not running with automation allowed. " + hint)
        }
        guard kill(pid, 0) == 0 || errno == EPERM else {
            try? FileManager.default.removeItem(at: endpointURL)
            throw CLIError.failed("\(app.name) is not running. " + hint)
        }
        self.port = UInt16(port)
        self.token = token
    }

    func request(_ command: String, _ args: [String: Any] = [:]) throws -> [String: Any] {
        var line = try JSONSerialization.data(withJSONObject: ["token": token, "command": command, "args": args])
        line.append(UInt8(ascii: "\n"))
        let response = try exchange(line)
        guard let object = try JSONSerialization.jsonObject(with: response) as? [String: Any] else {
            throw CLIError.failed("The app sent an unreadable answer")
        }
        guard object["ok"] as? Bool == true else {
            throw CLIError.failed(object["error"] as? String ?? "The app refused '\(command)'")
        }
        return object
    }

    private func exchange(_ request: Data) throws -> Data {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { throw CLIError.failed("Could not open a socket") }
        defer { close(socket) }

        var timeout = timeval(tv_sec: 60, tv_usec: 0)
        setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else {
            throw CLIError.failed("Could not reach the app's automation server (is the app still starting?)")
        }
        _ = request.withUnsafeBytes { send(socket, $0.baseAddress, request.count, 0) }

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while !response.contains(UInt8(ascii: "\n")) {
            let count = recv(socket, &buffer, buffer.count, 0)
            guard count > 0 else { throw CLIError.failed("The app closed the connection or did not answer") }
            response.append(contentsOf: buffer[0..<count])
        }
        return response.prefix { $0 != UInt8(ascii: "\n") }
    }
}
