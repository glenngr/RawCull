//
//  NikonMakerNoteParser.swift
//  RawCull
//
//  Parses Nikon NEF raw files to extract AF focus location natively.
//  Pilot target: Nikon Z9 (AFInfoVersion "0300"+). Older DSLRs may fall
//  through and return nil until their AFInfo2 layout is added.
//
//  Technical background
//  ─────────────────────
//  NEF is TIFF-based. Focus location lives in:
//    TIFF IFD0 → ExifIFD (tag 0x8769) → MakerNote (tag 0x927C)
//      → "Nikon\0" + 4-byte version + inner TIFF header
//      → Nikon IFD → AFInfo2 (tag 0x00B7)
//
//  Nikon Type-3 MakerNote layout (Z-series and most modern DSLRs):
//    Offset 0..5   "Nikon\0"                  6 bytes ASCII signature
//    Offset 6..9   version (e.g. 0x02 0x11 0x00 0x00)
//    Offset 10..   inner TIFF header (II/MM + 0x2A + IFD0 offset)
//  Inner TIFF offsets are RELATIVE to the MakerNote TIFF header start
//  (MakerNote base + 10), NOT to the file start.
//
//  AFInfo2 (tag 0x00B7) is an UNDEFINED blob. For AFInfoVersion "0300"
//  and later (Z-series), the relevant fields are uint16 LE:
//    0x26 (38): AFImageWidth
//    0x28 (40): AFImageHeight
//    0x2A (42): AFAreaXPosition   (center of AF area, pixel coords)
//    0x2C (44): AFAreaYPosition
//    0x2E (46): AFAreaWidth
//    0x30 (48): AFAreaHeight
//

import Foundation

enum NikonMakerNoteParser {
    /// Returns "width height x y" for the AF focus location encoded in the
    /// Nikon MakerNote's AFInfo2 tag. Shape matches `SonyMakerNoteParser.focusLocation`
    /// so `ScanFiles.parseFocusNormalized` consumes both identically.
    nonisolated static func focusLocation(from url: URL) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }

        // Fast path: first 4 MB covers the MakerNote for typical NEF files.
        guard let data = try? fh.read(upToCount: 4 * 1024 * 1024) else { return nil }
        if let result = NikonTIFFParser(data: data)?.parseAFFocusLocation() {
            return "\(result.width) \(result.height) \(result.x) \(result.y)"
        }

        // Slow path: full-file read in case the MakerNote falls beyond the
        // 4 MB window on some bodies (parallel to SonyMakerNoteParser).
        try? fh.seek(toOffset: 0)
        guard let full = try? fh.read(upToCount: Int.max),
              full.count > data.count,
              let result = NikonTIFFParser(data: full)?.parseAFFocusLocation()
        else { return nil }
        return "\(result.width) \(result.height) \(result.x) \(result.y)"
    }
}

// MARK: - TIFF + Nikon MakerNote parser

private struct NikonTIFFParser {
    let data: Data
    let le: Bool // outer (file) endianness

    nonisolated init?(data: Data) {
        guard data.count >= 8 else { return nil }
        let b0 = data[0], b1 = data[1]
        if b0 == 0x49, b1 == 0x49 { le = true } else if b0 == 0x4D, b1 == 0x4D { le = false } else { return nil }
        self.data = data
    }

    /// Walks IFD0 → ExifIFD → MakerNote, detects the Nikon Type-3 signature,
    /// then parses the inner TIFF to find AFInfo2 and extract AF coordinates.
    nonisolated func parseAFFocusLocation() -> (width: Int, height: Int, x: Int, y: Int)? {
        guard let ifd0 = readU32(at: 4, littleEndian: le).map(Int.init) else { return nil }

        // IFD0 → ExifIFD (tag 0x8769 is a LONG pointer to the ExifIFD offset)
        guard let exifIFD = subIFDOffset(in: ifd0, tag: 0x8769, littleEndian: le),
              let (mnOffset, mnSize) = tagDataRange(in: exifIFD, tag: 0x927C, littleEndian: le),
              mnSize >= 18, // "Nikon\0" + 4 version + min inner TIFF header (8)
              mnOffset + 18 <= data.count
        else { return nil }

        // Detect the Nikon Type-3 signature: ASCII "Nikon\0".
        let sig: [UInt8] = [0x4E, 0x69, 0x6B, 0x6F, 0x6E, 0x00] // "Nikon\0"
        for (i, b) in sig.enumerated() where data[mnOffset + i] != b {
            return nil
        }

        // Inner TIFF header starts 10 bytes into the MakerNote.
        // (6 bytes "Nikon\0" + 4 bytes version)
        let innerTIFF = mnOffset + 10
        guard innerTIFF + 8 <= data.count else { return nil }

        let innerLE: Bool
        let ib0 = data[innerTIFF], ib1 = data[innerTIFF + 1]
        if ib0 == 0x49, ib1 == 0x49 { innerLE = true } else if ib0 == 0x4D, ib1 == 0x4D { innerLE = false } else { return nil }

        // Inner TIFF magic 0x2A at offset +2 (skip — optional sanity check)
        guard let ifdRelRaw = readU32(at: innerTIFF + 4, littleEndian: innerLE) else { return nil }
        let nikonIFD = innerTIFF + Int(ifdRelRaw) // inner offsets are relative to innerTIFF

        // Find AFInfo2 (tag 0x00B7). Offsets inside the Nikon IFD are relative to innerTIFF.
        guard let (afRel, afSize) = tagDataRange(
            in: nikonIFD,
            tag: 0x00B7,
            littleEndian: innerLE,
            offsetBase: innerTIFF,
        ), afSize >= 0x38 // need at least through offset 0x30 + 2
        else { return nil }

        let afStart = afRel // already absolute in `data`
        guard afStart + 0x32 <= data.count else { return nil }

        // AFInfoVersion at offset 0: 4 ASCII bytes. "0300"+ is Z-series and modern
        // DSLRs; older versions (0100, 0101, 0102, 0103) use a different layout
        // and are deferred until fixtures are available.
        let v0 = data[afStart + 0]
        let v1 = data[afStart + 1]
        let v2 = data[afStart + 2]
        let v3 = data[afStart + 3]
        // Accept "0300", "0301", "0302", "0400" and similar — first char '0', second >= '3'.
        guard v0 == 0x30, v1 >= 0x33, v1 <= 0x39,
              isASCIIDigit(v2), isASCIIDigit(v3) else { return nil }

        // Z-series layout: widths/positions at 0x26..0x2C, each uint16 in innerLE.
        let width = Int(readU16(at: afStart + 0x26, littleEndian: innerLE))
        let height = Int(readU16(at: afStart + 0x28, littleEndian: innerLE))
        let x = Int(readU16(at: afStart + 0x2A, littleEndian: innerLE))
        let y = Int(readU16(at: afStart + 0x2C, littleEndian: innerLE))

        // Sanity gate: dimensions must be plausible for modern bodies,
        // and focus point must fall within the image.
        guard width >= 2000, height >= 1000,
              x >= 0, y >= 0, x <= width, y <= height,
              x > 0 || y > 0 else { return nil }

        return (width, height, x, y)
    }

    // MARK: - Binary helpers

    private nonisolated func isASCIIDigit(_ b: UInt8) -> Bool {
        b >= 0x30 && b <= 0x39
    }

    private nonisolated func subIFDOffset(in ifdOffset: Int, tag: UInt16, littleEndian: Bool) -> Int? {
        guard let (valLoc, _) = tagDataRange(in: ifdOffset, tag: tag, littleEndian: littleEndian) else { return nil }
        return readU32(at: valLoc, littleEndian: littleEndian).map(Int.init)
    }

    /// Locates the data range for an IFD entry's value. For offset-style values
    /// (bytes > 4), the returned `dataOffset` is absolute within `data`, computed
    /// as `offsetBase + relativeOffset` when a non-nil base is given (used for
    /// Nikon inner-TIFF offsets which are relative to the inner TIFF header).
    /// When `offsetBase` is nil, the stored offset is treated as absolute
    /// (matches Sony MakerNote ProcessExif behaviour).
    private nonisolated func tagDataRange(
        in ifdOffset: Int,
        tag: UInt16,
        littleEndian: Bool,
        offsetBase: Int? = nil,
    ) -> (dataOffset: Int, byteCount: Int)? {
        guard ifdOffset + 2 <= data.count else { return nil }
        let entryCount = Int(readU16(at: ifdOffset, littleEndian: littleEndian))
        for i in 0 ..< entryCount {
            let e = ifdOffset + 2 + i * 12
            guard e + 12 <= data.count else { break }
            if readU16(at: e, littleEndian: littleEndian) == tag {
                let type = Int(readU16(at: e + 2, littleEndian: littleEndian))
                let count = Int(readU32(at: e + 4, littleEndian: littleEndian) ?? 0)
                let sizes = [0, 1, 1, 2, 4, 8, 1, 1, 2, 4, 8, 4, 8, 4]
                let bytes = count * (type < sizes.count ? sizes[type] : 1)

                if bytes <= 4 { return (e + 8, bytes) }
                guard let ptr = readU32(at: e + 8, littleEndian: littleEndian) else { return nil }
                let base = offsetBase ?? 0
                return (base + Int(ptr), bytes)
            }
        }
        return nil
    }

    private nonisolated func readU16(at offset: Int, littleEndian: Bool) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return littleEndian ? UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8) :
            (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }

    private nonisolated func readU32(at offset: Int, littleEndian: Bool) -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        return littleEndian ?
            UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24) :
            (UInt32(data[offset]) << 24) | (UInt32(data[offset + 1]) << 16) | (UInt32(data[offset + 2]) << 8) | UInt32(data[offset + 3])
    }
}
