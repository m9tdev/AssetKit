import Foundation
import Testing
@testable import AssetKit

/// The classic macOS layout actool 27.0 writes for `--platform macosx`
/// (oracle: the OpenDisplay `.icon`, alone, with an imageset and a colorset,
/// and with a symbolset).
@Suite("Classic macOS schema")
struct ClassicMacSchemaTests {
    static let color = Rendition(
        name: "Tint", idiom: .universal, scale: .x1,
        body: .color(ColorBody(components: [1, 0.5, 0, 1], colorSpaceID: 1)))

    static func icon(scale: Scale, index: UInt16, side: UInt32) -> Rendition {
        Rendition(
            name: "AppIcon", idiom: .universal, scale: scale, iconIndex: index,
            body: .bitmap(BitmapBody(
                width: side, height: side,
                pixelsBGRA: [UInt8](repeating: 255, count: Int(side * side) * 4),
                colorSpaceID: 1, kind: .appIcon, renditionName: "AppIcon.png")))
    }

    @Test("Key format: classic order, dimension2 only with app icons")
    func keyFormat() {
        #expect(KeyFormat.classicMac(for: [Self.color]).map(\.rawValue) == [7, 13, 1, 2, 3, 17, 11, 12])
        #expect(KeyFormat.classicMac(for: [Self.color, Self.icon(scale: .x2, index: 1, side: 32)])
            .map(\.rawValue) == [7, 13, 1, 2, 3, 17, 9, 11, 12])
    }

    @Test("BITMAPKEYS descriptors match actool's words")
    func bitmapKeys() {
        func words(_ data: Data) -> [UInt32] {
            stride(from: 0, to: data.count, by: 4).map { i in
                data[i..<i + 4].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
            }
        }
        let format = KeyFormat.classicMac(for: [Self.icon(scale: .x2, index: 1, side: 32)])
        let none = UInt32.max
        #expect(words(BitmapKeys.classicMacDescriptor(renditions: [Self.color], keyFormat: format))
            == [1, 0, 40, 9, none, 1, none, none, 1, none, 1, 1, 2])
        let icons = [Self.icon(scale: .x2, index: 1, side: 32), Self.icon(scale: .x1, index: 7, side: 1024)]
        #expect(words(BitmapKeys.classicMacDescriptor(renditions: icons, keyFormat: format))
            == [1, 0, 40, 9, none, 1, none, none, 1, none, 255, 1, 6])
    }

    @Test("The car says macosx and uses NSAppearance names")
    func header() throws {
        var writer = CARWriter(deploymentTarget: "14.0", renditions: [Self.color])
        writer.classicMacSchema = true
        let data = try writer.write()
        func contains(_ text: String) -> Bool { data.range(of: Data(text.utf8)) != nil }
        #expect(contains("macosx"))
        #expect(contains("NSAppearanceNameSystem"))
        #expect(!contains("UIAppearanceAny"))
        // CARHEADER keySemantics (offset 432 in the 'RATC' block) is 1.
        let header = try #require(data.range(of: Data("RATC".utf8)))
        let semantics = data[header.lowerBound + 432..<header.lowerBound + 436]
        #expect(Array(semantics) == [1, 0, 0, 0])
    }
}
