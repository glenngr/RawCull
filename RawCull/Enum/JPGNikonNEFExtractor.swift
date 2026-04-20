//
//  JPGNikonNEFExtractor.swift
//  RawCull
//
//  Extracts the largest embedded JPEG from a Nikon NEF using ImageIO.
//  Mirrors the shape of `JPGSonyARWExtractor`. No binary fallback is
//  needed for macOS 26 on Z-series and D850+ bodies, whose NEF is fully
//  supported by the system RAW pipeline.
//

@preconcurrency import AppKit
import Foundation
import ImageIO
import OSLog

enum JPGNikonNEFExtractor {
    static func jpgNikonNEFExtractor(
        from nefURL: URL,
        fullSize: Bool = false,
    ) async -> CGImage? {
        let maxThumbnailSize: CGFloat = fullSize ? 8640 : 4320

        return await withCheckedContinuation { (continuation: CheckedContinuation<CGImage?, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
                guard let imageSource = CGImageSourceCreateWithURL(nefURL as CFURL, sourceOptions) else {
                    Logger.process.warning("JPGNikonNEFExtractor: failed to create image source")
                    continuation.resume(returning: nil)
                    return
                }

                let imageCount = CGImageSourceGetCount(imageSource)
                var targetIndex: Int = -1
                var targetWidth = 0

                // 1. Find the LARGEST embedded JPEG across all sub-images.
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
                    Logger.process.warning("JPGNikonNEFExtractor: no embedded JPEG found via ImageIO")
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
}
