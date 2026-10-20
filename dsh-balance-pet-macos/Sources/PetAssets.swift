import AppKit

/// Built-in characters and the original Windows sound are bundled unchanged.
enum PetAssets {
    /// Bundle lookup is independent of the current working directory. The source
    /// fallback also supports running a freshly compiled development executable.
    static func resourceURL(named name: String) -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent(name),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        // A damaged application bundle must not silently use the developer's
        // checkout. Raw development binaries may use a neighbouring Resources.
        guard Bundle.main.bundleURL.pathExtension != "app" else { return nil }
        let directory = PetPaths.executableDir
        let candidates = [directory, directory.deletingLastPathComponent()].map {
            $0.appendingPathComponent("Resources").appendingPathComponent(name)
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    struct Sprite {
        let image: CGImage
        private let bitmap: NSBitmapImageRep

        init?(url: URL) {
            guard let data = try? Data(contentsOf: url),
                  let bitmap = NSBitmapImageRep(data: data),
                  let image = bitmap.cgImage else { return nil }
            self.image = image
            self.bitmap = bitmap
        }

        var size: CGSize { CGSize(width: image.width, height: image.height) }

        /// Normalized position measured from the lower-left, like an NSView.
        /// Bitmap pixels use the opposite vertical direction.
        func isOpaque(at point: CGPoint) -> Bool {
            guard point.x >= 0, point.x < 1, point.y >= 0, point.y < 1 else { return false }
            let x = min(bitmap.pixelsWide - 1, Int(point.x * CGFloat(bitmap.pixelsWide)))
            let y = bitmap.pixelsHigh - 1 - min(bitmap.pixelsHigh - 1, Int(point.y * CGFloat(bitmap.pixelsHigh)))
            return (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 8.0 / 255.0
        }
    }

    private static let sprites: [PetCharacter: [PetExpression: Sprite]] = {
        var result: [PetCharacter: [PetExpression: Sprite]] = [:]
        for character in PetCharacter.allCases {
            let expressions = character.expressions.isEmpty ? [PetExpression.happy] : character.expressions
            var loaded: [PetExpression: Sprite] = [:]
            for expression in expressions {
                let name = character.resourceName(for: expression)
                guard let url = resourceURL(named: name), let sprite = Sprite(url: url) else {
                    Log.write("\(name) is missing or unreadable")
                    continue
                }
                loaded[expression] = sprite
            }
            result[character] = loaded
        }
        return result
    }()

    static let deepseekOffline: Sprite? = {
        guard let url = resourceURL(named: "sprite-deepseek-offline.png"),
              let sprite = Sprite(url: url) else {
            Log.write("sprite-deepseek-offline.png is missing or unreadable")
            return nil
        }
        return sprite
    }()

    /// Falls back to the neutral face when a single expression is missing, so a
    /// partial install still shows a pet instead of an empty window.
    static func sprite(for character: PetCharacter, expression: PetExpression = .happy) -> Sprite? {
        guard let set = sprites[character] else { return nil }
        return set[expression] ?? set[.happy] ?? set.values.first
    }
}
