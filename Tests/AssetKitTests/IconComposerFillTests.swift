import Foundation
import PNG
import Testing
@testable import AssetKit

/// Background and dark-layer fill rules of Icon Composer icons, from
/// actool 27.0 oracles (the same for macosx and iphoneos).
@Suite("Icon Composer fills")
struct IconComposerFillTests {
    typealias C = IconComposerCompiler

    static func model(fill: Any?, layerFill: Any? = nil, layerExtra: [String: Any] = [:]) throws -> C.IconModel {
        var layer: [String: Any] = ["image-name": "ring.svg", "name": "ring"]
        if let layerFill { layer["fill"] = layerFill }
        layer.merge(layerExtra) { $1 }
        var json: [String: Any] = ["groups": [["layers": [layer]]]]
        if let fill { json["fill"] = fill }
        return try C.parseModel(json)
    }

    static let red = C.IconColor(colorSpaceID: 3, components: [0.9, 0.1, 0.1, 1])
    static let halfRed = C.IconColor(colorSpaceID: 3, components: [0.9, 0.1, 0.1, 0.5])
    static var ringGradient: [String: Any] { ["linear-gradient": [
        "display-p3:1.00000,1.00000,1.00000,1.00000", "display-p3:0.80000,0.90000,1.00000,1.00000"]] }

    @Test("No fill: white in light, system-dark in dark, white on dark layers")
    func noFill() throws {
        let m = try Self.model(fill: nil)
        #expect(C.backgroundFill(m, appearance: nil) == .solid(C.white))
        #expect(C.backgroundFill(m, appearance: .tinted) == .solid(C.white))
        #expect(C.backgroundFill(m, appearance: .dark) == C.presetFill("system-dark"))
        #expect(C.automaticDarkFill(m, layer: m.groups[0].layers[0], lightShape: true) == .solid(C.white))
        #expect(C.automaticDarkFill(m, layer: m.groups[0].layers[0], lightShape: false) == nil)
    }

    @Test("automatic is system-light; dark layers take system-light")
    func automatic() throws {
        let m = try Self.model(fill: "automatic")
        #expect(C.backgroundFill(m, appearance: nil) == C.presetFill("system-light"))
        #expect(C.automaticDarkFill(m, layer: m.groups[0].layers[0], lightShape: true) == C.presetFill("system-light"))
    }

    @Test("A clear fill stays clear in dark; layers keep their own fill")
    func clearFill() throws {
        let clear = C.IconColor(colorSpaceID: 3, components: [0, 0, 0, 0])
        let m = try Self.model(fill: ["solid": "display-p3:0.00000,0.00000,0.00000,0.00000"], layerFill: Self.ringGradient)
        #expect(C.backgroundFill(m, appearance: .dark) == .solid(clear))
        #expect(C.automaticDarkFill(m, layer: m.groups[0].layers[0], lightShape: true) == nil)
        #expect(C.resolveFill(m.groups[0].layers[0].fills, appearance: .dark) != nil)
    }

    @Test("A plain layer fill gives way in dark, opaque for a solid background")
    func plainLayerFill() throws {
        let half = ["solid": "display-p3:0.90000,0.10000,0.10000,0.50000"]
        let withFill = try Self.model(fill: half, layerFill: Self.ringGradient)
        #expect(withFill.groups[0].layers[0].plainFill)
        #expect(C.resolveFill(withFill.groups[0].layers[0].fills, appearance: nil) != nil)
        #expect(C.automaticDarkFill(withFill, layer: withFill.groups[0].layers[0], lightShape: true) == .solid(Self.red))
        let without = try Self.model(fill: half)
        #expect(C.automaticDarkFill(without, layer: without.groups[0].layers[0], lightShape: true) == .solid(Self.halfRed))
    }

    /// An empty or null fill-specializations list next to a plain fill is
    /// the same layer as one with only the plain fill.
    @Test("An empty fill-specializations list does not hide a plain layer fill", arguments: ["[]", "null"])
    func emptySpecializationsPlainFill(spelling: String) throws {
        let half = ["solid": "display-p3:0.90000,0.10000,0.10000,0.50000"]
        let specializations: Any = spelling == "null" ? NSNull() : [[String: Any]]()
        let m = try Self.model(fill: half, layerFill: Self.ringGradient,
                               layerExtra: ["fill-specializations": specializations])
        let layer = m.groups[0].layers[0]
        #expect(layer.plainFill)
        #expect(layer.fills.count == 1)
        #expect(C.automaticDarkFill(m, layer: layer, lightShape: true) == .solid(Self.red))
    }

    static func iconDirectory(layerExtra: [String: Any]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fill-\(UUID().uuidString).icon")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("Assets"), withIntermediateDirectories: true)
        let side = 256
        let pixels = [PNG.RGBA<UInt8>](repeating: PNG.RGBA(255, 255, 255, 255), count: side * side)
        let image = PNG.Image(packing: pixels, size: (side, side),
                              layout: .init(format: .rgba8(palette: [], fill: nil)))
        try image.compress(path: dir.appendingPathComponent("Assets/ring.png").path, level: 9)
        var layer: [String: Any] = ["image-name": "ring.png", "name": "ring", "fill": ringGradient]
        layer.merge(layerExtra) { $1 }
        let json: [String: Any] = [
            "fill": ["solid": "display-p3:0.90000,0.10000,0.10000,0.50000"],
            "groups": [["layers": [layer]]],
        ]
        try JSONSerialization.data(withJSONObject: json).write(to: dir.appendingPathComponent("icon.json"))
        return dir
    }

    static func darkLayerFillNames(_ result: C.Result) -> [String?] {
        result.renditions.flatMap { r -> [String?] in
            guard r.appearance == .dark, case .iconGroup(let body) = r.body else { return [] }
            return body.layers.map(\.fillName)
        }
    }

    @Test("An empty fill-specializations list compiles the same dark icon", arguments: ["iphoneos", "macosx"])
    func emptySpecializationsCompile(platform: String) throws {
        let plain = try Self.iconDirectory(layerExtra: [:])
        let empty = try Self.iconDirectory(layerExtra: ["fill-specializations": [[String: Any]]()])
        defer {
            try? FileManager.default.removeItem(at: plain)
            try? FileManager.default.removeItem(at: empty)
        }
        let expected = try C.compile(input: .init(name: "AppIcon", directory: plain, idioms: ["iphone"], platform: platform))
        let actual = try C.compile(input: .init(name: "AppIcon", directory: empty, idioms: ["iphone"], platform: platform))
        #expect(!Self.darkLayerFillNames(expected).isEmpty)
        #expect(Self.darkLayerFillNames(actual) == Self.darkLayerFillNames(expected))
    }
}
