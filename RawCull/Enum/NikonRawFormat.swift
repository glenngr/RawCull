//
//  NikonRawFormat.swift
//  RawCull
//
//  `RawFormat` conformer for Nikon NEF. Uses ImageIO's embedded-JPEG path
//  for thumbnails and full-resolution previews — no binary fallback is
//  needed for macOS 26 on Z-series and D850+ bodies, whose NEF is fully
//  supported by the system RAW pipeline.
//

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import OSLog

enum NikonRawFormat: RawFormat {
    nonisolated static let extensions: Set<String> = ["nef"]
    nonisolated static let displayName: String = "Nikon NEF"

    // MARK: - Thumbnail

    nonisolated static func extractThumbnail(
        from url: URL,
        maxDimension: CGFloat,
        qualityCost: Int,
    ) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let image = try extractThumbnailSync(
                        from: url,
                        maxDimension: maxDimension,
                        qualityCost: qualityCost,
                    )
                    continuation.resume(returning: image)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private nonisolated static func extractThumbnailSync(
        from url: URL,
        maxDimension: CGFloat,
        qualityCost: Int,
    ) throws -> CGImage {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            throw ThumbnailError.invalidSource
        }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let raw = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            throw ThumbnailError.generationFailed
        }
        return try rerender(raw, qualityCost: qualityCost)
    }

    private nonisolated static func rerender(_ image: CGImage, qualityCost: Int) throws -> CGImage {
        let interpolationQuality: CGInterpolationQuality = switch qualityCost {
        case 1 ... 2: .low
        case 3 ... 4: .medium
        default: .high
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw ThumbnailError.contextCreationFailed
        }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue,
        ) else {
            throw ThumbnailError.contextCreationFailed
        }
        context.interpolationQuality = interpolationQuality
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let result = context.makeImage() else {
            throw ThumbnailError.generationFailed
        }
        return result
    }

    // MARK: - Full-resolution embedded JPEG

    nonisolated static func extractFullJPEG(from url: URL, fullSize: Bool) async -> CGImage? {
        let maxThumbnailSize: CGFloat = fullSize ? 8640 : 4320

        return await withCheckedContinuation { (continuation: CheckedContinuation<CGImage?, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
                guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
                    Logger.process.warning("NikonRawFormat: failed to create image source")
                    continuation.resume(returning: nil)
                    return
                }

                let imageCount = CGImageSourceGetCount(imageSource)
                var targetIndex: Int = -1
                var targetWidth = 0

                // Find the largest embedded JPEG across all sub-images.
                for index in 0 ..< imageCount {
                    guard let properties = CGImageSourceCopyPropertiesAtIndex(
                        imageSource, index, nil,
                    ) as? [CFString: Any] else { continue }

                    let hasJFIF = (properties[kCGImagePropertyJFIFDictionary] as? [CFString: Any]) != nil
                    let tiffDict = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
                    let compression = tiffDict?[kCGImagePropertyTIFFCompression] as? Int
                    let isJPEG = hasJFIF || (compression == 6)

                    if let width = getWidth(from: properties), isJPEG, width > targetWidth {
                        targetWidth = width
                        targetIndex = index
                    }
                }

                var result: CGImage?
                if targetIndex != -1 {
                    let requiresDownsampling = CGFloat(targetWidth) > maxThumbnailSize
                    if requiresDownsampling {
                        let options: [CFString: Any] = [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: Int(maxThumbnailSize)
                        ]
                        result = CGImageSourceCreateThumbnailAtIndex(imageSource, targetIndex, options as CFDictionary)
                    } else {
                        let decodeOptions = [kCGImageSourceShouldCache: false] as CFDictionary
                        result = CGImageSourceCreateImageAtIndex(imageSource, targetIndex, decodeOptions)
                    }
                } else {
                    Logger.process.warning("NikonRawFormat: no embedded JPEG found via ImageIO")
                }

                for i in 0 ..< imageCount {
                    CGImageSourceRemoveCacheAtIndex(imageSource, i)
                }

                continuation.resume(returning: result)
            }
        }
    }

    private nonisolated static func getWidth(from properties: [CFString: Any]) -> Int? {
        if let width = properties[kCGImagePropertyPixelWidth] as? Int { return width }
        if let width = properties[kCGImagePropertyPixelWidth] as? Double { return Int(width) }
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            if let width = tiff[kCGImagePropertyPixelWidth] as? Int { return width }
            if let width = tiff[kCGImagePropertyPixelWidth] as? Double { return Int(width) }
        }
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let width = exif[kCGImagePropertyExifPixelXDimension] as? Int { return width }
            if let width = exif[kCGImagePropertyExifPixelXDimension] as? Double { return Int(width) }
        }
        return nil
    }

    // MARK: - AF focus location

    nonisolated static func focusLocation(from url: URL) -> String? {
        NikonMakerNoteParser.focusLocation(from: url)
    }

    // MARK: - Compression + size class

    /// Nikon TIFF Compression tag values seen in NEF files.
    nonisolated static func rawFileTypeString(compressionCode: Int) -> String {
        switch compressionCode {
        case 1: "Uncompressed"
        case 34713: "NEF Compressed" // lossy or lossless depending on body/version
        case 34892: "Lossy NEF"
        default: "Unknown (\(compressionCode))"
        }
    }

    /// Nikon Z-series + D850 MP thresholds. Z9/Z8/Z7/D850 are ~45 MP; Z6 is ~24 MP.
    nonisolated static func sizeClassThresholds(camera: String) -> (L: Double, M: Double) {
        let upper = camera.uppercased()
        if upper.contains("Z 9") || upper.contains("Z9") { return (40, 18) } // Z9: 45/25/11 MP
        if upper.contains("Z 8") || upper.contains("Z8") { return (40, 18) } // Z8: 45/25/11 MP
        if upper.contains("Z 7") || upper.contains("Z7") { return (40, 18) } // Z7/Z7 II: 45/25/11 MP
        if upper.contains("Z 6") || upper.contains("Z6") { return (22, 11) } // Z6/Z6 II/III: 24/14/6 MP
        if upper.contains("D850") { return (40, 18) } // D850: 45/25/11 MP
        return (25, 10) // generic fallback
    }
}
