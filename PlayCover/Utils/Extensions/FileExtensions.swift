//
//  FileExtensions.swift
//  PlayCover
//

import Foundation
import UniformTypeIdentifiers

extension FileManager {
    func delete(at url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(atPath: url.path)
            } catch {
                Log.shared.error(error)
            }
        }
    }
}

extension NSOpenPanel {
    static func selectIPA(completion: @escaping (_ result: Result<URL, Error>) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(importedAs: "com.apple.itunes.ipa")]
        panel.canChooseFiles = true
        panel.begin { result in
            if result == .OK {
                if let url = panel.urls.first {
                    completion(.success(url))
                }
            }
        }
    }

    static func selectDylib(completion: @escaping (_ result: Result<URL, Error>) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "dylib") ?? .unixExecutable]
        panel.begin { result in
            if result == .OK {
                if let url = panel.urls.first {
                    completion(.success(url))
                }
            }
        }
    }
}

extension FileManager {
    /// Whether `target` holds the same bundle as `source`, ignoring code signatures: signing the app re-signs the
    /// bundles inside it, so their executables never match byte for byte
    func bundleMatches(_ source: URL, _ target: URL) -> Bool {
        guard let sourceFiles = enumerator(atPath: source.path)?.allObjects as? [String],
              let targetFiles = enumerator(atPath: target.path)?.allObjects as? [String] else {
            return false
        }
        let unsigned = { (files: [String]) in Set(files.filter { !$0.contains("_CodeSignature") }) }
        guard unsigned(sourceFiles) == unsigned(targetFiles) else { return false }

        for file in unsigned(sourceFiles) {
            let sourceFile = source.appendingPathComponent(file)
            let targetFile = target.appendingPathComponent(file)
            var isDirectory: ObjCBool = false
            guard fileExists(atPath: sourceFile.path, isDirectory: &isDirectory) else { return false }
            if isDirectory.boolValue || contentsEqual(atPath: sourceFile.path, andPath: targetFile.path) {
                continue
            }
            guard let sourceData = try? unsignedData(sourceFile),
                  sourceData == (try? unsignedData(targetFile)) else { return false }
        }
        return true
    }

    /// A Mach-O file's contents without its code signature
    private func unsignedData(_ url: URL) throws -> Data {
        let copy = temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: copy) }
        try copyItem(at: url, to: copy)
        try Shell.run(print: false, "/usr/bin/codesign", "--remove-signature", copy.path)
        return try Data(contentsOf: copy)
    }
}
