import AppKit

// Behavioral regressions exercise the actual bundled artwork, without user settings.
enum ArtworkSelfTests {
    private final class ImageOnlyView: NSView {
        let image: CGImage
        let character: PetCharacter
        init(image: CGImage, character: PetCharacter, frame: CGRect) {
            self.image = image
            self.character = character
            super.init(frame: frame)
        }
        required init?(coder: NSCoder) { fatalError("unused") }
        override func draw(_ dirtyRect: NSRect) {
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            ctx.clear(bounds)
            ctx.interpolationQuality = .high
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            let rect = PetLayout.spriteRect(in: bounds, character: character)
            let artwork = CGSize(width: image.width, height: image.height)
            ctx.draw(image, in: PetLayout.contentRect(for: artwork, in: rect))
            ctx.endTransparencyLayer()
        }
    }

    private struct Fixture {
        let sprite: PetAssets.Sprite
        let bitmap: NSBitmapImageRep
        let leftLandmark: CGPoint
        let clearLandmark: CGPoint
    }

    private static func normalized(_ source: CGPoint, in character: PetCharacter) -> CGPoint {
        let size = character.artworkSize
        return CGPoint(x: source.x / size.width, y: 1 - source.y / size.height)
    }

    private static func point(_ n: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + n.x * rect.width, y: rect.minY + n.y * rect.height)
    }

    private static func alpha(_ bitmap: NSBitmapImageRep, at n: CGPoint) -> CGFloat? {
        let x = min(bitmap.pixelsWide - 1, Int(n.x * CGFloat(bitmap.pixelsWide)))
        let y = bitmap.pixelsHigh - 1 - min(bitmap.pixelsHigh - 1, Int(n.y * CGFloat(bitmap.pixelsHigh)))
        return bitmap.colorAt(x: x, y: y)?.alphaComponent
    }

    /// Independently chosen opaque and transparent landmarks per artwork.
    private static func landmarks(for character: PetCharacter) -> (left: CGPoint, clear: CGPoint) {
        switch character {
        case .deepseek: return (CGPoint(x: 150, y: 600), CGPoint(x: 350, y: 120))
        case .gpt: return (CGPoint(x: 100, y: 400), CGPoint(x: 450, y: 100))
        case .claude: return (CGPoint(x: 450, y: 850), CGPoint(x: 450, y: 100))
        case .gemini: return (CGPoint(x: 180, y: 500), CGPoint(x: 450, y: 100))
        }
    }

    private static func faceLandmark(for character: PetCharacter) -> CGPoint {
        character == .deepseek ? CGPoint(x: 700, y: 400) : CGPoint(x: 1150, y: 500)
    }

    private static func renderedData(_ view: NSView) -> Data? {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }

    /// First normalized position whose alpha differs strongly between two
    /// characters, so the switching test can prove the new mask is in use.
    private static func strongAlphaDifference(_ before: Fixture, _ after: Fixture) -> CGPoint? {
        for row in 0..<64 {
            for column in 0..<64 {
                let n = CGPoint(x: (CGFloat(column) + 0.5) / 64, y: (CGFloat(row) + 0.5) / 64)
                guard let a = alpha(before.bitmap, at: n), let b = alpha(after.bitmap, at: n) else { continue }
                if (a < 0.01 && b > 0.99) || (a > 0.99 && b < 0.01) { return n }
            }
        }
        return nil
    }

    static func run(_ expect: (Bool, String) -> Void) {
        var fixtures: [PetCharacter: Fixture] = [:]
        for character in PetCharacter.allCases {
            guard let sprite = PetAssets.sprite(for: character),
                  let url = PetAssets.resourceURL(named: character.resourceName),
                  let data = try? Data(contentsOf: url),
                  let bitmap = NSBitmapImageRep(data: data) else {
                expect(false, "\(character.displayName): bundled sprite loads")
                continue
            }
            let size = character.artworkSize
            expect(CGFloat(sprite.image.width) == size.width && CGFloat(sprite.image.height) == size.height,
                   "\(character.displayName): \(Int(size.width)) × \(Int(size.height)) sprite loads")
            let marks = landmarks(for: character)
            fixtures[character] = Fixture(sprite: sprite, bitmap: bitmap,
                                          leftLandmark: marks.left, clearLandmark: marks.clear)
            expect(sprite.isOpaque(at: normalized(marks.left, in: character)),
                   "\(character.displayName): left silhouette has an interactive alpha mask")
            expect(sprite.isOpaque(at: normalized(faceLandmark(for: character), in: character)),
                   "\(character.displayName): face has an interactive alpha mask")
            expect(!sprite.isOpaque(at: normalized(marks.clear, in: character)),
                   "\(character.displayName): empty upper-left space is transparent")
        }

        // The blue pet must ship every expression, each with its own mask.
        for expression in PetExpression.allCases {
            guard let sprite = PetAssets.sprite(for: .deepseek, expression: expression) else {
                expect(false, "deepseek: \(expression.rawValue) face loads")
                continue
            }
            expect(sprite.image.width == 1024 && sprite.image.height == 1024,
                   "deepseek: \(expression.rawValue) face keeps its 1024 × 1024 artwork")
        }
        expect(PetAssets.sprite(for: .gpt, expression: .angry)?.image.width == 1536,
               "single-artwork characters fall back to their only image")

        for preset in PetController.sizePresets {
            let side = preset.side

            for character in PetCharacter.allCases {
                guard let fixture = fixtures[character] else { continue }
                let name = "\(character.displayName), \(Int(side))pt"
                let frame = CGRect(origin: .zero,
                                   size: PetLayout.windowSize(side: side, character: character))
                let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
                let connectedModel = PetModel()
                connectedModel.apply(reading: BalanceReading(normalCny: 38.61, bonusCny: 0, spentCny: nil, raw: ""), snap: true)
                let view = PetView(model: connectedModel, character: character)
                window.contentView = view
                let rect = PetLayout.spriteRect(in: view.bounds, character: character)
                expect(abs(rect.width / rect.height - character.aspectRatio) < 0.00001
                       && abs(rect.height - side * 0.94) < 0.00001,
                       "\(name): source aspect ratio and character height are preserved")
                expect(view.containsInteractivePoint(point(normalized(fixture.leftLandmark, in: character), in: rect)),
                       "\(name): left silhouette accepts clicks")
                expect(view.containsInteractivePoint(point(normalized(faceLandmark(for: character), in: character), in: rect)),
                       "\(name): face accepts clicks")
                expect(!view.containsInteractivePoint(point(normalized(fixture.clearLandmark, in: character), in: rect)),
                       "\(name): transparent interior passes clicks through")
                expect(!view.containsInteractivePoint(CGPoint(x: 1, y: 1)),
                       "\(name): outer margin passes clicks through")
                expect(!view.containsInteractivePoint(CGPoint(x: frame.midX, y: side * 1.2)),
                       "\(name): floating amounts pass clicks through")

                // Check actual PNG pixels: shifted text anchors must fail when
                // they cross hair, hands, or the bezel.
                let transform = PetLayout.tabletTransform(in: view.bounds, character: character)
                let artwork = character.artworkSize
                let scale = rect.width / artwork.width
                var blackScreenOnly = true
                for row in 0...10 {
                    for column in 0...10 {
                        let panel = CGPoint(x: CGFloat(column) * 40, y: CGFloat(row) * 22)
                        let mapped = panel.applying(transform)
                        let x = Int((mapped.x - rect.minX) / scale)
                        let y = Int(artwork.height - (mapped.y - rect.minY) / scale)
                        guard x >= 0, x < fixture.bitmap.pixelsWide, y >= 0, y < fixture.bitmap.pixelsHigh,
                              let color = fixture.bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                            blackScreenOnly = false
                            continue
                        }
                        if color.alphaComponent < 0.95
                            || max(color.redComponent, color.greenComponent, color.blueComponent) > 0.15 {
                            blackScreenOnly = false
                        }
                    }
                }
                expect(blackScreenOnly, "\(name): all 121 text-region samples lie on the black tablet screen")
                let motionBounds = rect.insetBy(dx: -min(3.2, side * 0.025),
                                                dy: -min(3.2, side * 0.025) * 0.875)
                expect(CGRect(x: 0, y: 0, width: frame.width, height: side).contains(motionBounds),
                       "\(name): shake cannot crop the silhouette")
            }

            let model = PetModel()
            model.apply(reading: BalanceReading(normalCny: 38.61, bonusCny: 0, spentCny: nil, raw: ""), snap: true)
            let startFrame = CGRect(origin: .zero,
                                    size: PetLayout.windowSize(side: side, character: .deepseek))
            let window = NSWindow(contentRect: startFrame, styleMask: [.borderless], backing: .buffered, defer: false)
            let view = PetView(model: model, character: .deepseek)
            window.contentView = view
            var previous = PetCharacter.deepseek
            var previousPixels = renderedData(view)
            for next in [PetCharacter.gpt, .claude, .gemini, .deepseek] {
                let name = "\(Int(side))pt, \(previous.rawValue) → \(next.rawValue)"
                guard let before = fixtures[previous], let after = fixtures[next] else { continue }
                let changed = strongAlphaDifference(before, after)
                let nextFrame = CGRect(origin: .zero,
                                       size: PetLayout.windowSize(side: side, character: next))
                // The controller widens or narrows the window when the canvas
                // aspect changes; mirror that here before drawing.
                view.frame = nextFrame
                view.needsDisplay = false
                view.setCharacter(next)
                expect(view.character == next && view.needsDisplay && model.displayedCents == 3861,
                       "\(name): switching invalidates the same view and preserves the balance")
                if let n = changed {
                    let rect = PetLayout.spriteRect(in: view.bounds, character: next)
                    let nextHit = view.containsInteractivePoint(point(n, in: rect))
                    expect(nextHit == after.sprite.isOpaque(at: n),
                           "\(name): switching changes hit testing to the new silhouette")
                } else {
                    expect(false, "\(name): independent alpha difference is available for switching regression")
                }
                let actual = renderedData(view)
                let fresh = PetView(model: model, character: next)
                fresh.frame = nextFrame
                let expectedWindow = NSWindow(contentRect: nextFrame, styleMask: [.borderless], backing: .buffered, defer: false)
                expectedWindow.contentView = fresh
                // A window may round its content rect to whole device pixels,
                // so hand the fresh view the exact bounds the switched view has;
                // otherwise the two renderings differ by a hairline.
                fresh.frame = CGRect(origin: .zero, size: view.bounds.size)
                let expected = renderedData(fresh)
                expect(actual != nil && expected != nil && actual == expected && actual != previousPixels,
                       "\(name): switched drawing matches a fresh view of the selected character")
                previous = next
                previousPixels = actual
            }
        }

        expressionTests(expect)
        offlineArtworkTests(expect)
        stateTests(expect)
        if let url = PetPaths.soundURL, let sound = NSSound(contentsOf: url, byReference: false) {
            expect(url.lastPathComponent == "hit.mp3" && sound.duration > 0, "original MP3 loads and decodes")
        } else { expect(false, "original MP3 loads and decodes") }
    }

    /// Each face must draw a different picture, and each keeps the text on the
    /// same tablet screen.
    private static func expressionTests(_ expect: (Bool, String) -> Void) {
        let side: CGFloat = 150
        let frame = CGRect(origin: .zero, size: PetLayout.windowSize(side: side, character: .deepseek))
        let model = PetModel()
        model.apply(reading: BalanceReading(normalCny: 38.61, bonusCny: 0, spentCny: nil, raw: ""), snap: true)
        let view = PetView(model: model, character: .deepseek)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view

        var renders: [PetExpression: Data] = [:]
        for expression in PetExpression.allCases {
            view.expression = expression
            expect(view.expression == expression, "expression \(expression.rawValue): selected on the view")
            renders[expression] = renderedData(view)
        }
        expect(renders[.happy] != nil && renders[.happy] != renders[.angry],
               "happy and angry faces render differently")
        expect(renders[.nervous] != nil && renders[.nervous] != renders[.happy]
               && renders[.nervous] != renders[.angry],
               "nervous face renders differently from the other two")

        // Every expression maps text onto the same measured tablet corners.
        let corners = PetCharacter.deepseek.tabletCorners(for: .happy)
        for expression in PetExpression.allCases {
            let other = PetCharacter.deepseek.tabletCorners(for: expression)
            expect(other.topLeft == corners.topLeft && other.topRight == corners.topRight
                   && other.bottomLeft == corners.bottomLeft,
                   "expression \(expression.rawValue): shares the measured tablet corners")
        }

        // Face-selection rules: happy, angry on lost focus, nervous on spend.
        expect(PetExpressionPolicy.holdAfterHit == 1.0,
               "nervous face is held for exactly one second after the hit animation")
        func face(_ now: Double, nervousUntil: Double = 0,
                  visible: Bool = true, foreground: Bool = true) -> PetExpression {
            PetExpressionPolicy.expression(now: now, nervousUntil: nervousUntil,
                                           hostVisible: visible, hostForeground: foreground)
        }
        expect(face(100) == .happy, "focused host shows the happy face")
        expect(face(100, visible: true, foreground: false) == .angry,
               "unfocused but visible host shows the angry face")
        expect(face(100, visible: false, foreground: false) == .happy,
               "a hidden or minimised host does not show the angry face")
        let hitEnds = 0.55
        expect(face(hitEnds, nervousUntil: hitEnds + 1.0, foreground: false) == .nervous,
               "deduction keeps the nervous face while the host is unfocused")
        expect(face(hitEnds + 0.99, nervousUntil: hitEnds + 1.0) == .nervous,
               "nervous face survives the hold window")
        expect(face(hitEnds + 1.01, nervousUntil: hitEnds + 1.0) == .happy,
               "nervous face ends exactly one second after the animation")
    }

    private static func offlineArtworkTests(_ expect: (Bool, String) -> Void) {
        guard let sprite = PetAssets.deepseekOffline else {
            expect(false, "offline bowl artwork loads")
            return
        }
        expect(sprite.image.width == 1536 && sprite.image.height == 1024,
               "offline artwork preserves supplied dimensions")
        for preset in PetController.sizePresets {
            let model = PetModel()
            let frame = CGRect(origin: .zero,
                               size: PetLayout.windowSize(side: preset.side, character: .deepseek))
            let view = PetView(model: model)
            let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view
            let initial = renderedData(view)
            let imageOnly = ImageOnlyView(image: sprite.image, character: .deepseek, frame: frame)
            let referenceWindow = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            referenceWindow.contentView = imageOnly
            expect(initial != nil && initial == renderedData(imageOnly),
                   "offline rendering contains only supplied artwork, without any text or status dot")
            model.setNoCredential()
            expect(initial != nil && view.showsOfflineArtwork && renderedData(view) == initial,
                   "unconfigured and connecting blue pet show the same bowl artwork")
            let reading = BalanceReading(normalCny: 38.61, bonusCny: 0, spentCny: nil, raw: "")
            model.apply(reading: reading, snap: true)
            let online = renderedData(view)
            expect(!view.showsOfflineArtwork && online != initial,
                   "successful connection restores tablet artwork and balance")
            model.fail(.transport("offline fixture"))
            expect(view.showsOfflineArtwork && renderedData(view) == initial,
                   "connection failure hides stale balance and restores clean bowl artwork")
            // Hit testing must use the bowl silhouette, not the former tablet.
            let spriteRect = PetLayout.spriteRect(in: frame, character: .deepseek)
            let artwork = CGSize(width: sprite.image.width, height: sprite.image.height)
            let rect = PetLayout.contentRect(for: artwork, in: spriteRect)
            var maskMatches = true
            for y in stride(from: 32, to: 1024, by: 64) {
                for x in stride(from: 32, to: 1536, by: 64) {
                    let n = CGPoint(x: (Double(x) + 0.5) / 1536, y: 1 - (Double(y) + 0.5) / 1024)
                    if view.containsInteractivePoint(point(n, in: rect)) != sprite.isOpaque(at: n) {
                        maskMatches = false
                    }
                }
            }
            expect(maskMatches, "offline hit testing follows the bowl image alpha")
            for character in [PetCharacter.gpt, .claude, .gemini] {
                view.setCharacter(character)
                expect(!view.showsOfflineArtwork && renderedData(view) != initial,
                       "other characters retain their artwork when offline")
            }
            view.setCharacter(.deepseek)
            model.apply(reading: reading, snap: true)
            expect(renderedData(view) == online, "reconnection restores identical normal rendering")
        }
    }

    private static func stateTests(_ expect: (Bool, String) -> Void) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dsh-character-state-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        for character in PetCharacter.allCases {
            var state = PetState()
            state.character = character
            state.sizeIndex = 2
            state.soundOn = false
            state.save(to: url)
            let restored = PetState.load(from: url)
            expect(restored.character == character && restored.sizeIndex == 2 && !restored.soundOn,
                   "\(character.displayName): selection survives saving and loading settings")
        }
        for json in ["{\"sizeIndex\":2}", "{\"sizeIndex\":2,\"character\":\"unknown-future-character\"}"] {
            do {
                try Data(json.utf8).write(to: url)
                let restored = PetState.load(from: url)
                expect(restored.character == .deepseek && restored.sizeIndex == 2,
                       "legacy or unknown character settings preserve preferences and use the blue pet")
            } catch { expect(false, "character settings fixture can be written") }
        }
    }
}
