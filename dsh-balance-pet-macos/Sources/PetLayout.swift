import AppKit

/// Coordinates for the tail-completed 1536 × 1024 artwork. A size preset still
/// means body height, so adding the tail does not shrink the face or balance.
enum PetLayout {
    static let artworkSize = CGSize(width: 1536, height: 1024)
    static let aspectRatio = artworkSize.width / artworkSize.height
    static let floatBand: CGFloat = 0.55
    static let tabletBounds = CGRect(x: 0, y: 0, width: 400, height: 220)

    static func windowSize(side: CGFloat) -> CGSize {
        CGSize(width: side * aspectRatio, height: side * (1 + floatBand))
    }

    static func bodyHeight(in bounds: CGRect) -> CGFloat {
        bounds.width / aspectRatio
    }

    static func spriteRect(in bounds: CGRect) -> CGRect {
        let side = bodyHeight(in: bounds)
        let size = CGSize(width: side * 0.94 * aspectRatio, height: side * 0.94)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.minY + side * 0.03,
                      width: size.width, height: size.height)
    }

    static func tabletTransform(in bounds: CGRect) -> CGAffineTransform {
        // Safe text region, measured from the new PNG's upper-left:
        // TL (1060,699), TR (1413,644), BL (1090,889), BR (1443,834).
        // This inset avoids the bezel and both hands. Convert to bottom-origin
        // source coordinates, then use the exact same scale as the sprite.
        let rect = spriteRect(in: bounds)
        let scale = rect.width / artworkSize.width
        return CGAffineTransform(a: 353 / tabletBounds.width * scale,
                                 b: 55 / tabletBounds.width * scale,
                                 c: -30 / tabletBounds.height * scale,
                                 d: 190 / tabletBounds.height * scale,
                                 tx: rect.minX + 1090 * scale,
                                 ty: rect.minY + (artworkSize.height - 889) * scale)
    }
}
