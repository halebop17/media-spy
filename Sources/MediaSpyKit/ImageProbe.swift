import Foundation
import ImageIO

/// Still-image facts read via macOS ImageIO. Complements libmediainfo: it gives
/// authoritative rendered pixel dimensions and bit depth, and covers formats
/// libmediainfo doesn't parse at all (e.g. JPEG XL). Reads metadata only — it
/// does not decode pixels.
public struct ImageInfo: Sendable, Equatable {
    public let width: Int
    public let height: Int
    /// Bits per component (8, 10, 16, …), when reported.
    public let bitDepth: Int?
    /// Color model — "RGB", "Gray", "CMYK", "Lab".
    public let colorModel: String?
    public let hasAlpha: Bool
    /// Uniform Type Identifier of the file, e.g. "public.jpeg-xl".
    public let utiType: String?

    /// Friendly format name derived from the UTI ("HEIC", "JPEG XL", …).
    public var formatName: String? { ImageProbe.formatName(forUTI: utiType) }
}

public enum ImageProbe {
    /// Read image properties, or nil if the file isn't a decodable image.
    public static func probe(_ url: URL) -> ImageInfo? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = props[kCGImagePropertyPixelWidth] as? Int,
            let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }

        return ImageInfo(
            width: width,
            height: height,
            bitDepth: props[kCGImagePropertyDepth] as? Int,
            colorModel: props[kCGImagePropertyColorModel] as? String,
            hasAlpha: (props[kCGImagePropertyHasAlpha] as? Bool) ?? false,
            utiType: CGImageSourceGetType(source).map { $0 as String }
        )
    }

    static func formatName(forUTI uti: String?) -> String? {
        switch uti {
        case "public.heic", "public.heif", "public.heics": return "HEIC"
        case "public.avif": return "AVIF"
        case "public.jpeg-xl": return "JPEG XL"
        case "public.png": return "PNG"
        case "public.jpeg": return "JPEG"
        case "com.google.webp", "org.webmproject.webp", "public.webp": return "WebP"
        case "public.tiff": return "TIFF"
        case "com.compuserve.gif": return "GIF"
        case "com.microsoft.bmp": return "BMP"
        default: return nil
        }
    }
}
