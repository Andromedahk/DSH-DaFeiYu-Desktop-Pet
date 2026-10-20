import AppKit

/// Layout of a character's artwork inside its window. A size preset means body
/// height, so switching between the 1:1 expression set and the 3:2 artwork set
/// keeps the pet the same height instead of the same width.
enum PetLayout {
    static let floatBand: CGFloat = 0.55
    static let tabletBounds = CGRect(x: 0, y: 0, width: 400, height: 220)

    static func windowSize(side: CGFloat, character: PetCharacter) -> CGSize {
        CGSize(width: side * character.aspectRatio, height: side * (1 + floatBand))
    }

    static func bodyHeight(in bounds: CGRect, character: PetCharacter) -> CGFloat {
        bounds.width / character.aspectRatio
    }

    static func spriteRect(in bounds: CGRect, character: PetCharacter) -> CGRect {
        let side = bodyHeight(in: bounds, character: character)
        let size = CGSize(width: side * 0.94 * character.aspectRatio, height: side * 0.94)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.minY + side * 0.03,
                      width: size.width, height: size.height)
    }

    /// Space between the window's bottom edge and the lowest drawn pixel. The
    /// window keeps a floating band above the pet, so its frame reaches further
    /// down than the artwork; snapping subtracts this to make the pet itself
    /// touch the edge of the screen.
    static func artworkBottomInset(in bounds: CGRect, character: PetCharacter) -> CGFloat {
        spriteRect(in: bounds, character: character).minY - bounds.minY
    }

    /// Aspect-preserving, bottom-aligned draw rect. Used when the artwork's own
    /// aspect differs from the character's canvas, such as the 3:2 offline bowl
    /// on the square expression canvas.
    static func contentRect(for artwork: CGSize, in rect: CGRect) -> CGRect {
        guard artwork.width > 0, artwork.height > 0, rect.width > 0, rect.height > 0 else { return rect }
        let scale = min(rect.width / artwork.width, rect.height / artwork.height)
        let fitted = CGSize(width: artwork.width * scale, height: artwork.height * scale)
        return CGRect(x: rect.midX - fitted.width / 2, y: rect.minY,
                      width: fitted.width, height: fitted.height)
    }

    static func tabletTransform(in bounds: CGRect,
                                character: PetCharacter,
                                expression: PetExpression = .happy) -> CGAffineTransform {
        // Convert the selected image's measured corners to bottom-origin source
        // coordinates, using the exact same scale as its sprite and alpha mask.
        let corners = character.tabletCorners(for: expression)
        let rect = spriteRect(in: bounds, character: character)
        let artwork = character.artworkSize
        let scale = rect.width / artwork.width
        return CGAffineTransform(a: (corners.topRight.x - corners.topLeft.x) / tabletBounds.width * scale,
                                 b: (corners.topLeft.y - corners.topRight.y) / tabletBounds.width * scale,
                                 c: (corners.topLeft.x - corners.bottomLeft.x) / tabletBounds.height * scale,
                                 d: (corners.bottomLeft.y - corners.topLeft.y) / tabletBounds.height * scale,
                                 tx: rect.minX + corners.bottomLeft.x * scale,
                                 ty: rect.minY + (artwork.height - corners.bottomLeft.y) * scale)
    }
}
