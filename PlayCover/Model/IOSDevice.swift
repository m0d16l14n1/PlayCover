//
//  IOSDevice.swift
//  PlayCover
//

import Foundation

/// An iOS device PlayTools can report itself as. The matching board IDs live in PlayTools' PlaySettings.oemID
struct IOSDevice: Identifiable, Hashable {
    /// Machine identifier, e.g. "iPad17,3"
    let id: String
    let name: String
    let chip: String
    let memory: String
    /// Short name accepted by the command line interface, e.g. "ipad-pro-13-m5"
    let alias: String

    var label: String {
        "\(name) | \(chip) | \(memory)"
    }

    var isIPad: Bool {
        id.hasPrefix("iPad")
    }

    static let all: [IOSDevice] = [
        IOSDevice(id: "iPad6,7", name: "iPad Pro (12.9-inch) (1st gen)", chip: "A9X", memory: "4GB",
                  alias: "ipad-pro-12.9-1st-gen"),
        IOSDevice(id: "iPad8,6", name: "iPad Pro (12.9-inch) (3rd gen)", chip: "A12X", memory: "4GB",
                  alias: "ipad-pro-12.9-3rd-gen"),
        IOSDevice(id: "iPad13,8", name: "iPad Pro (12.9-inch) (5th gen)", chip: "M1", memory: "8GB",
                  alias: "ipad-pro-12.9-m1"),
        IOSDevice(id: "iPad14,5", name: "iPad Pro (12.9-inch) (6th gen)", chip: "M2", memory: "8GB",
                  alias: "ipad-pro-12.9-m2"),
        IOSDevice(id: "iPad16,6", name: "iPad Pro (13-inch) (7th gen)", chip: "M4", memory: "8GB",
                  alias: "ipad-pro-13-m4"),
        IOSDevice(id: "iPad17,3", name: "iPad Pro (13-inch) (8th gen)", chip: "M5", memory: "12GB",
                  alias: "ipad-pro-13-m5"),
        IOSDevice(id: "iPhone14,3", name: "iPhone 13 Pro Max", chip: "A15", memory: "6GB",
                  alias: "iphone-13-pro-max"),
        IOSDevice(id: "iPhone15,3", name: "iPhone 14 Pro Max", chip: "A16", memory: "6GB",
                  alias: "iphone-14-pro-max"),
        IOSDevice(id: "iPhone16,2", name: "iPhone 15 Pro Max", chip: "A17 Pro", memory: "8GB",
                  alias: "iphone-15-pro-max"),
        IOSDevice(id: "iPhone17,2", name: "iPhone 16 Pro Max", chip: "A18 Pro", memory: "8GB",
                  alias: "iphone-16-pro-max"),
        IOSDevice(id: "iPhone18,3", name: "iPhone 17", chip: "A19", memory: "8GB",
                  alias: "iphone-17"),
        IOSDevice(id: "iPhone18,4", name: "iPhone Air", chip: "A19 Pro", memory: "12GB",
                  alias: "iphone-air"),
        IOSDevice(id: "iPhone18,1", name: "iPhone 17 Pro", chip: "A19 Pro", memory: "12GB",
                  alias: "iphone-17-pro"),
        IOSDevice(id: "iPhone18,2", name: "iPhone 17 Pro Max", chip: "A19 Pro", memory: "12GB",
                  alias: "iphone-17-pro-max")
    ]

    static var iPads: [IOSDevice] {
        all.filter { $0.isIPad }
    }

    static var iPhones: [IOSDevice] {
        all.filter { !$0.isIPad }
    }

    /// Looks a device up by machine identifier or alias, ignoring case
    static func find(_ query: String) -> IOSDevice? {
        let lowered = query.lowercased()
        return all.first { $0.id.lowercased() == lowered || $0.alias == lowered }
    }
}
