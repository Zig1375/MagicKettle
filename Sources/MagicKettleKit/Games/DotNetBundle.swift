import Foundation

/// A .NET program published as a single file: its `runtimeconfig.json` is inside the exe, not beside it.
/// HedgeModManager 8 is one: with nothing beside it to read, it got no .NET and stopped on "You must install
/// .NET Desktop Runtime to run this application".
///
/// The host part of the exe keeps the bundle's header offset in the 8 bytes before `signature`; a plain apphost
/// keeps zero there. The header (version 2 and later, .NET 5+) gives where the `runtimeconfig.json` lies.
enum DotNetBundle {
    /// SHA-256 of ".net core bundle", which the SDK writes into every apphost.
    static let signature = Data([
        0x8B, 0x12, 0x02, 0xB9, 0x6A, 0x61, 0x20, 0x38, 0x72, 0x7B, 0x93, 0x02, 0x14, 0xD7, 0xA0, 0x32,
        0x13, 0xF5, 0xB9, 0xE6, 0xEF, 0xAE, 0x33, 0x18, 0xEE, 0x3B, 0x2D, 0xCE, 0x24, 0xB3, 0x6A, 0xAE,
    ])

    /// The `runtimeconfig.json` bundled into the exe, or nil when it isn't a single-file bundle.
    static func runtimeConfig(in executable: URL) -> Data? {
        guard let data = try? Data(contentsOf: executable, options: .alwaysMapped) else { return nil }
        return runtimeConfig(inBundle: data)
    }

    static func runtimeConfig(inBundle data: Data) -> Data? {
        guard let found = data.range(of: signature), found.lowerBound >= data.startIndex + 8,
              let header = integer(Int64.self, in: data, at: found.lowerBound - 8), header > 0,
              var cursor = Int(exactly: header).map({ data.startIndex + $0 }),
              let major = integer(Int32.self, in: data, at: cursor), major >= 2 else { return nil }
        cursor += 12 // major, minor, file count
        guard let idLength = varint(in: data, at: &cursor) else { return nil }
        cursor += idLength + 16 // bundle ID, deps.json offset and size
        guard let offset = integer(Int64.self, in: data, at: cursor),
              let size = integer(Int64.self, in: data, at: cursor + 8), offset > 0, size > 0,
              let start = Int(exactly: offset), let length = Int(exactly: size),
              start <= data.count, length <= data.count - start else { return nil }
        return data.subdata(in: data.startIndex + start..<data.startIndex + start + length)
    }

    /// A little-endian integer at `index`, nil past the end.
    private static func integer<T: FixedWidthInteger>(_: T.Type, in data: Data, at index: Int) -> T? {
        let size = MemoryLayout<T>.size
        guard index >= data.startIndex, index <= data.endIndex - size else { return nil }
        return data[index..<index + size].reversed().reduce(T.zero) { $0 << 8 | T(truncatingIfNeeded: $1) }
    }

    /// .NET's 7-bit encoded length, as `BinaryWriter` writes a string's.
    private static func varint(in data: Data, at cursor: inout Int) -> Int? {
        var value = 0
        for shift in stride(from: 0, to: 35, by: 7) {
            guard cursor < data.endIndex else { return nil }
            let byte = data[cursor]
            cursor += 1
            value |= Int(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
        }
        return nil
    }
}
