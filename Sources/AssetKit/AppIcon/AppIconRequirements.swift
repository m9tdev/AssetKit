import Foundation

/// A warning about the catalog that does not stop the compile, in the form
/// actool prints it: `<catalog>:<path>: warning: <message>`.
public struct CompileWarning: Sendable, Equatable {
    /// The asset, relative to the catalog root, the way actool writes it
    /// (`./AppIcon.appiconset`).
    public var path: String
    public var message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

/// The app icon sizes actool requires for an iOS app. An app icon set may
/// leave slots empty (no `filename`): actool skips them, and warns only when
/// a required size is empty. The messages are Apple's
/// (AssetCatalogCocoaTouchFoundation, Xcode 16), for example:
///
///     Assets.xcassets:./AppIcon.appiconset: warning: A 1024x1024 app store icon is required for iOS apps
///
/// The warnings for iOS releases before 10.0 (57x57, 72x72, 76x76@1x) are not
/// listed: no supported deployment target reaches them.
enum AppIconRequirements {
    struct Requirement {
        var device: String
        var idiom: Idiom
        var size: Double
        var scale: Scale
        var message: String
    }

    /// In the order of Apple's strings.
    static let requirements: [Requirement] = [
        .init(device: "iphone", idiom: .iphone, size: 60, scale: .x2,
              message: "A 60x60@2x app icon is required for iPhone apps targeting iOS 7.0 and later"),
        .init(device: "ipad", idiom: .ipad, size: 76, scale: .x2,
              message: "A 76x76@2x app icon is required for iPad apps targeting iOS 7.0 and later"),
        .init(device: "ipad", idiom: .ipad, size: 83.5, scale: .x2,
              message: "A 83.5x83.5@2x app icon is required for iPad apps targeting iOS 9.0 and later"),
    ]
    static let appStoreMessage = "A 1024x1024 app store icon is required for iOS apps"

    /// The platforms these requirements apply to.
    static let iosPlatforms: Set<String> = ["iphoneos", "iphonesimulator"]

    /// True when at least one slot of the set has an image.
    static func hasImages(_ appIcon: LoadedAppIcon) -> Bool {
        appIcon.contents.images.contains { !($0.filename ?? "").isEmpty }
    }

    /// The required sizes the primary app icon set leaves empty, for
    /// `targetDevices` (actool's `--target-device` values).
    ///
    /// - An empty set (no images at all) gives no warnings: it compiles to
    ///   no icon.
    /// - A single-size set (one 1024 pt image that actool scales for every
    ///   size) needs nothing else.
    static func warnings(
        for appIcon: LoadedAppIcon, platform: String, targetDevices: [String], path: String
    ) -> [CompileWarning] {
        guard iosPlatforms.contains(platform), hasImages(appIcon) else { return [] }
        let filled = appIcon.contents.images.filter { !($0.filename ?? "").isEmpty && $0.appearances == nil }
        let singleSize = filled.contains {
            [.universal, .iphone, .ipad].contains($0.idiom) && $0.pointSize?.0 == 1024
        }
        guard !singleSize else { return [] }

        func has(_ idiom: Idiom, _ size: Double, _ scale: Scale?) -> Bool {
            filled.contains { $0.idiom == idiom && $0.pointSize?.0 == size && ($0.scale ?? .x1) == (scale ?? .x1) }
        }
        var messages = requirements
            .filter { targetDevices.contains($0.device) && !has($0.idiom, $0.size, $0.scale) }
            .map(\.message)
        let iOSDevice = targetDevices.contains("iphone") || targetDevices.contains("ipad")
        if iOSDevice && !has(.marketing, 1024, .x1) {
            messages.append(appStoreMessage)
        }
        return messages.map { CompileWarning(path: path, message: $0) }
    }
}
