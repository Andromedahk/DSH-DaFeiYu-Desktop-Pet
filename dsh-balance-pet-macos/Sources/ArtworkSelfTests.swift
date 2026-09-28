import AppKit

enum ArtworkSelfTests {
    static func run(_ expect: (Bool, String) -> Void) {
        guard let sprite = PetAssets.sprite,
              let url = PetAssets.resourceURL(named: "sprite.png"),
              let data = try? Data(contentsOf: url),
              let bitmap = NSBitmapImageRep(data: data) else {
            expect(false, "tail-completed sprite loads")
            return
        }
        expect(sprite.image.width == 1536 && sprite.image.height == 1024,
               "tail-completed 1536 × 1024 sprite loads")

        // Independent source landmarks, measured in the supplied PNG.
        let tail = CGPoint(x: 300, y: 450)
        let body = CGPoint(x: 1150, y: 500)
        let clear = CGPoint(x: 450, y: 100)
        func normalized(_ source: CGPoint) -> CGPoint {
            CGPoint(x: source.x / 1536, y: 1 - source.y / 1024)
        }
        expect(sprite.isOpaque(at: normalized(tail)), "the new whale tail has an interactive alpha mask")
        expect(sprite.isOpaque(at: normalized(body)), "the character body has an interactive alpha mask")
        expect(!sprite.isOpaque(at: normalized(clear)), "empty space above the tail is transparent")

        for preset in PetController.sizePresets {
            let side = preset.side
            let name = "\(Int(side))pt"
            let frame = CGRect(origin: .zero, size: PetLayout.windowSize(side: side))
            let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            let view = PetView(model: PetModel())
            window.contentView = view
            let rect = PetLayout.spriteRect(in: view.bounds)
            expect(abs(rect.width / rect.height - 1.5) < 0.00001
                   && abs(rect.height - side * 0.94) < 0.00001,
                   "\(name): source aspect ratio and existing character height are preserved")

            // Expected placement is calculated from source landmarks, separately
            // from the production rectangle used by drawing and hit testing.
            func point(_ source: CGPoint) -> CGPoint {
                CGPoint(x: side * 0.045 + source.x * side * 0.94 / 1024,
                        y: side * 0.03 + (1024 - source.y) * side * 0.94 / 1024)
            }
            expect(view.containsInteractivePoint(point(tail)), "\(name): the tail accepts clicks")
            expect(view.containsInteractivePoint(point(body)), "\(name): the body accepts clicks")
            expect(!view.containsInteractivePoint(point(clear)), "\(name): transparent interior pixels pass clicks through")
            expect(!view.containsInteractivePoint(CGPoint(x: 1, y: 1)), "\(name): the outer margin passes clicks through")
            expect(!view.containsInteractivePoint(CGPoint(x: frame.midX, y: side * 1.2)),
                   "\(name): floating amounts pass clicks through")

            // Check the full text region against actual PNG pixels, not merely
            // against a second copy of the transform constants. A shifted old
            // anchor would hit hair/hands/bezel and fail this check.
            let transform = PetLayout.tabletTransform(in: view.bounds)
            var blackScreenOnly = true
            for row in 0...10 {
                for column in 0...10 {
                    let panel = CGPoint(x: CGFloat(column) * 40, y: CGFloat(row) * 22)
                    let mapped = panel.applying(transform)
                    let x = Int((mapped.x - side * 0.045) * 1024 / (side * 0.94))
                    let y = Int(1024 - (mapped.y - side * 0.03) * 1024 / (side * 0.94))
                    guard x >= 0, x < bitmap.pixelsWide, y >= 0, y < bitmap.pixelsHigh,
                          let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                        blackScreenOnly = false
                        continue
                    }
                    if color.alphaComponent < 0.95
                        || max(color.redComponent, color.greenComponent, color.blueComponent) > 0.15 {
                        blackScreenOnly = false
                    }
                }
            }
            expect(blackScreenOnly, "\(name): all 121 text-region samples lie on the tablet's black screen")

            // The entire sprite remains in the body region even at maximum shake.
            let motionBounds = rect.insetBy(dx: -min(3.2, side * 0.025),
                                           dy: -min(3.2, side * 0.025) * 0.875)
            expect(CGRect(x: 0, y: 0, width: side * 1.5, height: side).contains(motionBounds),
                   "\(name): shake cannot crop the tail or body")
        }
        if let url = PetPaths.soundURL, let sound = NSSound(contentsOf: url, byReference: false) {
            expect(url.lastPathComponent == "hit.mp3" && sound.duration > 0, "original MP3 loads and decodes")
        } else { expect(false, "original MP3 loads and decodes") }
    }
}
