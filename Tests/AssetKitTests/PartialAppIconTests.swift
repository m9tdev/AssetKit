import Foundation
import PNG
import Testing
@testable import AssetKit

/// App icon sets with empty slots (no `filename`), as Xcode and the React
/// Native and Expo templates write them. actool skips the empty slots, and
/// warns only when a required size is empty (`A 1024x1024 app store icon is
/// required for iOS apps`, ...). A set with no images at all gives no icon.
@Suite("Partly filled app icon sets")
struct PartialAppIconTests {
    /// The iPhone slots of Xcode's classic AppIcon template, plus the App
    /// Store icon.
    static let iphoneSlots: [(size: String, scale: String)] = [
        ("20x20", "2x"), ("20x20", "3x"), ("29x29", "2x"), ("29x29", "3x"),
        ("40x40", "2x"), ("40x40", "3x"), ("60x60", "2x"), ("60x60", "3x"),
    ]
    static let ipadSlots: [(size: String, scale: String)] = [
        ("20x20", "1x"), ("20x20", "2x"), ("29x29", "1x"), ("29x29", "2x"),
        ("40x40", "1x"), ("40x40", "2x"), ("76x76", "1x"), ("76x76", "2x"),
        ("83.5x83.5", "2x"),
    ]

    struct Slot {
        var idiom: String
        var size: String
        var scale: String
    }

    static func slots(ipad: Bool) -> [Slot] {
        iphoneSlots.map { Slot(idiom: "iphone", size: $0.size, scale: $0.scale) }
            + (ipad ? ipadSlots.map { Slot(idiom: "ipad", size: $0.size, scale: $0.scale) } : [])
            + [Slot(idiom: "ios-marketing", size: "1024x1024", scale: "1x")]
    }

    /// A catalog with one AppIcon set over `slots`; the slots in `filled`
    /// ("idiom size scale") get a PNG of the right pixel size.
    static func catalog(slots: [Slot], filled: Set<String>) throws -> URL {
        let fm = FileManager.default
        let catalog = fm.temporaryDirectory
            .appendingPathComponent("partial-\(UUID().uuidString)")
            .appendingPathComponent("Assets.xcassets")
        let set = catalog.appendingPathComponent("AppIcon.appiconset")
        try fm.createDirectory(at: set, withIntermediateDirectories: true)
        try Data(#"{"info":{"author":"xcode","version":1}}"#.utf8)
            .write(to: catalog.appendingPathComponent("Contents.json"))
        var images: [[String: String]] = []
        for slot in slots {
            var entry = ["idiom": slot.idiom, "size": slot.size, "scale": slot.scale]
            if filled.contains("\(slot.idiom) \(slot.size) \(slot.scale)") {
                let points = Double(slot.size.split(separator: "x")[0])!
                let side = Int((points * Double(slot.scale.dropLast())!).rounded())
                let filename = "\(slot.idiom)-\(slot.size)@\(slot.scale).png"
                try writePNG(side: side, to: set.appendingPathComponent(filename))
                entry["filename"] = filename
            }
            images.append(entry)
        }
        let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
        try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
            .write(to: set.appendingPathComponent("Contents.json"))
        return catalog
    }

    /// The rendition keys of the same set with only its filled slots listed.
    static func filledOnlyKeys(slots: [Slot], filled: Set<String>, devices: [String],
                               platform: String = "iphoneos") async throws -> [String] {
        let catalog = try catalog(slots: slots.filter { filled.contains("\($0.idiom) \($0.size) \($0.scale)") }, filled: filled)
        defer { try? FileManager.default.removeItem(at: catalog.deletingLastPathComponent()) }
        let result = try await XCAssetCompiler(deploymentTarget: "15.1", platform: platform, targetDevices: devices)
            .compile(catalog: catalog, appIconName: "AppIcon")
        return try CARReader(result.carData).renditionKeys
    }

    static func writePNG(side: Int, to url: URL) throws {
        let pixels = [PNG.RGBA<UInt8>](repeating: PNG.RGBA(30, 120, 220, 255), count: side * side)
        let image = PNG.Image(packing: pixels, size: (side, side), layout: .init(format: .rgba8(palette: [], fill: nil)))
        try image.compress(path: url.path, level: 9)
    }

    static func compile(_ catalog: URL, devices: [String]) async throws -> CompileResult {
        try await XCAssetCompiler(deploymentTarget: "15.1", platform: "iphoneos", targetDevices: devices)
            .compile(catalog: catalog, appIconName: "AppIcon")
    }

    static let appStore = "A 1024x1024 app store icon is required for iOS apps"
    static let iphone60 = "A 60x60@2x app icon is required for iPhone apps targeting iOS 7.0 and later"
    static let ipad76 = "A 76x76@2x app icon is required for iPad apps targeting iOS 7.0 and later"
    static let ipad83 = "A 83.5x83.5@2x app icon is required for iPad apps targeting iOS 9.0 and later"

    @Test("Empty slots are skipped; the filled ones compile")
    func filledSlotsCompile() async throws {
        let filled: Set<String> = ["iphone 60x60 2x", "iphone 60x60 3x"]
        let catalog = try Self.catalog(slots: Self.slots(ipad: false), filled: filled)
        defer { try? FileManager.default.removeItem(at: catalog.deletingLastPathComponent()) }
        let result = try await Self.compile(catalog, devices: ["iphone"])

        // The car holds the two filled icons (Part 220: icon images, at 2x
        // and 3x), the same renditions as a set that lists only them.
        let keys = try CARReader(result.carData).renditionKeys
        #expect(keys.contains("AppIcon|Scale=2,Idiom=1,Dimension2=1,Element=85,Part=220"), "\(keys)")
        #expect(keys.contains("AppIcon|Scale=3,Idiom=1,Dimension2=1,Element=85,Part=220"), "\(keys)")
        #expect(keys == (try await Self.filledOnlyKeys(slots: Self.slots(ipad: false), filled: filled, devices: ["iphone"])))

        let icons = result.appIconBundle?.infoPlistAdditions["CFBundleIcons"] as? [String: any Sendable]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: any Sendable]
        #expect(primary?["CFBundleIconFiles"] as? [String] == ["AppIcon60x60"])
        #expect(result.appIconBundle?.looseFiles.map(\.name).sorted() == ["AppIcon60x60@2x.png", "AppIcon60x60@3x.png"])
        // The App Store slot is the only required one left empty.
        #expect(result.warnings == [CompileWarning(path: "./AppIcon.appiconset", message: Self.appStore)])
    }

    @Test("Each empty required size is one warning, for the target devices")
    func requiredSizeWarnings() async throws {
        let filled: Set<String> = ["iphone 40x40 2x"]
        let catalog = try Self.catalog(slots: Self.slots(ipad: true), filled: filled)
        defer { try? FileManager.default.removeItem(at: catalog.deletingLastPathComponent()) }

        let iphone = try await Self.compile(catalog, devices: ["iphone"])
        #expect(iphone.warnings.map(\.message) == [Self.iphone60, Self.appStore])

        let both = try await Self.compile(catalog, devices: ["iphone", "ipad"])
        #expect(both.warnings.map(\.message) == [Self.iphone60, Self.ipad76, Self.ipad83, Self.appStore])
        #expect(both.warnings.allSatisfy { $0.path == "./AppIcon.appiconset" })
        #expect(try CARReader(both.carData).renditionKeys
            == (try await Self.filledOnlyKeys(slots: Self.slots(ipad: true), filled: filled, devices: ["iphone", "ipad"])))
    }

    /// The shape of an Apple actool run on a public CI log (Xcode 26,
    /// `--platform iphonesimulator --target-device iphone`): the iPhone 60 pt
    /// and iPad 76/83.5 pt slots filled, the others and the App Store slot
    /// empty. actool printed one warning:
    /// `Assets.xcassets:./AppIcon.appiconset: warning: A 1024x1024 app store icon is required for iOS apps`
    /// (https://github.com/cgrindel/rules_swift_package_manager/issues/2023).
    @Test("Only the App Store icon is missing: one warning, as actool")
    func appStoreOnly() async throws {
        let filled: Set<String> = [
            "iphone 60x60 2x", "iphone 60x60 3x", "ipad 76x76 1x", "ipad 76x76 2x", "ipad 83.5x83.5 2x",
        ]
        let catalog = try Self.catalog(slots: Self.slots(ipad: true), filled: filled)
        defer { try? FileManager.default.removeItem(at: catalog.deletingLastPathComponent()) }
        let result = try await XCAssetCompiler(deploymentTarget: "13.0", platform: "iphonesimulator", targetDevices: ["iphone"])
            .compile(catalog: catalog, appIconName: "AppIcon")
        #expect(result.warnings.map(\.message) == [Self.appStore])
        #expect(try CARReader(result.carData).renditionKeys
            == (try await Self.filledOnlyKeys(slots: Self.slots(ipad: true), filled: filled, devices: ["iphone"],
                                              platform: "iphonesimulator")))
    }

    @Test("A fully filled set has no warnings")
    func fullSet() async throws {
        let slots = Self.slots(ipad: true)
        let catalog = try Self.catalog(slots: slots, filled: Set(slots.map { "\($0.idiom) \($0.size) \($0.scale)" }))
        defer { try? FileManager.default.removeItem(at: catalog.deletingLastPathComponent()) }
        let result = try await Self.compile(catalog, devices: ["iphone", "ipad"])
        #expect(result.warnings.isEmpty)
    }

    @Test("An empty set gives no icon, no warning and no error")
    func emptySet() async throws {
        let catalog = try Self.catalog(slots: Self.slots(ipad: false), filled: [])
        defer { try? FileManager.default.removeItem(at: catalog.deletingLastPathComponent()) }
        let result = try await Self.compile(catalog, devices: ["iphone"])
        #expect(result.renditionCount == 0)
        #expect(result.appIconBundle == nil)
        #expect(result.warnings.isEmpty)
    }

    @Test("A partly filled macOS set compiles its filled slots, without iOS warnings")
    func macPartial() async throws {
        let fm = FileManager.default
        let catalog = fm.temporaryDirectory
            .appendingPathComponent("partial-mac-\(UUID().uuidString)")
            .appendingPathComponent("Assets.xcassets")
        let set = catalog.appendingPathComponent("AppIcon.appiconset")
        try fm.createDirectory(at: set, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: catalog.deletingLastPathComponent()) }
        try Data(#"{"info":{"author":"xcode","version":1}}"#.utf8)
            .write(to: catalog.appendingPathComponent("Contents.json"))
        try Self.writePNG(side: 256, to: set.appendingPathComponent("icon_128@2x.png"))
        let json = """
        {"images":[
          {"idiom":"mac","size":"16x16","scale":"1x"},
          {"idiom":"mac","size":"128x128","scale":"2x","filename":"icon_128@2x.png"},
          {"idiom":"mac","size":"512x512","scale":"2x"}
        ],"info":{"author":"xcode","version":1}}
        """
        try Data(json.utf8).write(to: set.appendingPathComponent("Contents.json"))
        let result = try await XCAssetCompiler(deploymentTarget: "14.0", platform: "macosx", targetDevices: ["mac"])
            .compile(catalog: catalog, appIconName: "AppIcon")
        #expect(result.renditionCount > 0)
        #expect(result.warnings.isEmpty)
        #expect(result.appIconBundle?.looseFiles.map(\.name) == ["AppIcon.icns"])
    }

    /// macOS only: Apple's actool compiles the same partly filled set, and
    /// prints the same warnings.
    @Test("Apple's actool prints the same warnings", .enabled(if: AppleActool.isAvailable))
    func appleActool() async throws {
        let catalog = try Self.catalog(slots: Self.slots(ipad: true), filled: ["iphone 40x40 2x", "iphone 60x60 3x"])
        defer { try? FileManager.default.removeItem(at: catalog.deletingLastPathComponent()) }
        for devices in [["iphone"], ["iphone", "ipad"]] {
            let ours = try await XCAssetCompiler(deploymentTarget: "15.0", platform: "iphonesimulator", targetDevices: devices)
                .compile(catalog: catalog, appIconName: "AppIcon")
            let apple = try AppleActool.warnings(catalog: catalog, devices: devices)
            #expect(ours.warnings.map { "Assets.xcassets:\($0.path): warning: \($0.message)" }.sorted() == apple.sorted(),
                    "\(devices)")
        }
    }
}

enum AppleActool {
    static var isAvailable: Bool {
        #if os(macOS)
        return FileManager.default.fileExists(atPath: "/usr/bin/xcrun")
        #else
        return false
        #endif
    }

    /// The `warning:` lines of `actool --compile` for `catalog`.
    static func warnings(catalog: URL, devices: [String]) throws -> [String] {
        let out = catalog.deletingLastPathComponent().appendingPathComponent("apple-out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var arguments = [
            "actool", "--warnings", "--output-format", "human-readable-text",
            "--platform", "iphonesimulator", "--minimum-deployment-target", "15.0",
            "--app-icon", "AppIcon",
            "--output-partial-info-plist", out.appendingPathComponent("partial.plist").path,
            "--compile", out.path,
        ]
        for device in devices { arguments += ["--target-device", device] }
        arguments.append(catalog.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // From the catalog's name on: actool prints the catalog's absolute path.
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n").map(String.init)
            .filter { $0.contains(": warning: ") }
            .compactMap { line in line.range(of: "Assets.xcassets:").map { String(line[$0.lowerBound...]) } }
    }
}
