import AppKit

/// Faces shipped for the blue pet. Characters with a single artwork always use
/// their one image, so the expression is ignored for them.
enum PetExpression: String, CaseIterable {
    case happy, angry, nervous

    var displayName: String {
        switch self {
        case .happy: return "平时"
        case .angry: return "失去焦点"
        case .nervous: return "扣费中"
        }
    }
}

/// Decides which face to show. Kept pure so the timing rules can be tested
/// without a window server.
enum PetExpressionPolicy {
    /// How long the nervous face stays after the deduction animation ends.
    static let holdAfterHit: CFTimeInterval = 1.0

    /// Nervous wins over everything: a deduction must stay visible even while
    /// the host is in the background. Angry needs a visible host window that is
    /// merely unfocused; a closed or minimised host is not "lost focus".
    static func expression(now: CFTimeInterval,
                           nervousUntil: CFTimeInterval,
                           hostVisible: Bool,
                           hostForeground: Bool) -> PetExpression {
        if now < nervousUntil { return .nervous }
        if hostVisible && !hostForeground { return .angry }
        return .happy
    }
}

/// Stable IDs are persisted; display names can change without losing a choice.
enum PetCharacter: String, CaseIterable {
    case deepseek, gpt, claude, gemini

    var displayName: String {
        switch self {
        case .deepseek: return "蓝色大肥鱼"
        case .gpt: return "GPT龙娘"
        case .claude: return "大小姐Claude"
        case .gemini: return "北美猫娘Gemini"
        }
    }

    /// Size of the source PNG. The blue pet ships a 1024 × 1024 expression set;
    /// every other character keeps its 1536 × 1024 artwork.
    var artworkSize: CGSize {
        self == .deepseek ? CGSize(width: 1024, height: 1024)
                          : CGSize(width: 1536, height: 1024)
    }

    var aspectRatio: CGFloat { artworkSize.width / artworkSize.height }

    /// Empty for single-artwork characters.
    var expressions: [PetExpression] {
        self == .deepseek ? PetExpression.allCases : []
    }

    func resourceName(for expression: PetExpression) -> String {
        guard !expressions.isEmpty else { return "sprite-\(rawValue).png" }
        return "expression_\(expression.rawValue).png"
    }

    /// The default face, used by single-artwork characters and as a fallback.
    var resourceName: String { resourceName(for: .happy) }

    /// Safe text corners measured in the character's own PNG, from the upper-left.
    /// All text stays inside the screen and clear of the bezel and fingers.
    func tabletCorners(for expression: PetExpression) -> (topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint) {
        if self == .deepseek {
            // Measured on the 1024 × 1024 expression set; identical in all three.
            return (CGPoint(x: 583, y: 713), CGPoint(x: 919, y: 655), CGPoint(x: 602, y: 896))
        }
        if self == .gemini {
            // Gemini's right fingers reach farther into the screen.
            return (CGPoint(x: 1065, y: 699), CGPoint(x: 1400, y: 646), CGPoint(x: 1095, y: 889))
        }
        return (CGPoint(x: 1060, y: 699), CGPoint(x: 1413, y: 644), CGPoint(x: 1090, y: 889))
    }

    var tabletCorners: (topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint) {
        tabletCorners(for: .happy)
    }
}
