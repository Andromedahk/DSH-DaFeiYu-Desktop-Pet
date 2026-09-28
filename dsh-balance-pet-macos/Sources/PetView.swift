import AppKit

/// Draws the pet and handles drag / right-click.
///
/// The window is taller than the character: the bottom square holds the pet, and
/// the band above it is the lane the floating "-0.01" numbers rise through. That
/// band is click-through, so the pet never steals clicks more widely than it looks.
final class PetView: NSView {

    weak var controller: PetController?
    let model: PetModel

    private var dragStartMouse: NSPoint = .zero
    private var dragStartOrigin: NSPoint = .zero
    private var dragging = false

    /// Extra vertical room above the character, as a fraction of the pet size.
    /// Wide enough to keep five staggered "-0.01" labels from colliding.
    static let floatBand: CGFloat = 0.55

    init(model: PetModel) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: 150, height: 150 * (1 + Self.floatBand)))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { false }

    // MARK: - Interaction

    /// Per-region click-through: transparent areas (and the floating-number lane)
    /// fall through to whatever is behind the pet.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = superview != nil ? convert(point, from: superview) : point
        let s = bounds.width
        guard p.y <= s else { return nil }                       // floating lane
        let body = NSRect(x: 0.04 * s, y: 0.02 * s, width: 0.92 * s, height: 0.96 * s)
        return body.contains(p) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragging = true
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging, let w = window else { return }
        let now = NSEvent.mouseLocation
        w.setFrameOrigin(NSPoint(x: dragStartOrigin.x + (now.x - dragStartMouse.x),
                                 y: dragStartOrigin.y + (now.y - dragStartMouse.y)))
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        dragging = false
        controller?.dragDidEnd()
    }

    override func rightMouseDown(with event: NSEvent) {
        controller?.showContextMenu()
    }

    // MARK: - Drawing

    private func px(_ v: CGFloat) -> CGFloat { bounds.width * v }

    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: px(x), y: px(y), width: px(w), height: px(h))
    }

    private func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private func fill(_ ctx: CGContext, _ path: CGPath, _ color: NSColor) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setFillColor(color.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }

    private func stroke(_ ctx: CGContext, _ path: CGPath, _ color: NSColor, _ width: CGFloat) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawText(_ ctx: CGContext, _ text: String, font: NSFont, color: NSColor, center: CGPoint) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let s = NSAttributedString(string: text, attributes: attrs)
        let size = s.size()
        s.draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)

        let s = bounds.width
        let impact = CGFloat(model.impact)

        ctx.saveGState()
        // Minecraft-hurt style shake, plus a slow idle bob.
        var dx: CGFloat = 0
        var dy: CGFloat = sin(CGFloat(model.clock) * 1.8) * 0.006 * s
        if impact > 0.001 {
            dx += sin(CGFloat(model.clock) * 58) * 0.030 * s * impact
            dy += cos(CGFloat(model.clock) * 41) * 0.024 * s * impact
        }
        ctx.translateBy(x: dx, y: dy)

        drawCharacter(ctx, impact: impact)
        ctx.restoreGState()

        drawFloating(ctx)
    }

    private func drawCharacter(_ ctx: CGContext, impact: CGFloat) {
        let body = rect(0.10, 0.07, 0.80, 0.83)
        let bodyPath = rounded(body, px(0.26))

        // Top-up celebration: a green ring that expands and fades behind the character.
        if model.topupTime > 0 {
            let p = 1 - CGFloat(model.topupTime / 0.9)          // 0 -> 1 over the celebration
            let grow = px(0.015 + 0.13 * p)
            let ring = body.insetBy(dx: -grow, dy: -grow)
            stroke(ctx, rounded(ring, px(0.26) + grow * 0.7),
                   NSColor.systemGreen.withAlphaComponent(0.85 * (1 - p)), px(0.022))
        }

        // Antenna
        ctx.saveGState()
        ctx.setStrokeColor(NSColor(srgbRed: 0.16, green: 0.60, blue: 0.55, alpha: 1).cgColor)
        ctx.setLineWidth(px(0.016))
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: px(0.5), y: px(0.86)))
        ctx.addLine(to: CGPoint(x: px(0.5), y: px(0.965)))
        ctx.strokePath()
        ctx.restoreGState()
        fill(ctx, CGPath(ellipseIn: rect(0.465, 0.945, 0.07, 0.07), transform: nil),
             NSColor(srgbRed: 1.0, green: 0.78, blue: 0.28, alpha: 1))

        // Body gradient
        ctx.saveGState()
        ctx.addPath(bodyPath)
        ctx.clip()
        let colors = [
            NSColor(srgbRed: 0.68, green: 0.94, blue: 0.90, alpha: 1).cgColor,
            NSColor(srgbRed: 0.13, green: 0.70, blue: 0.63, alpha: 1).cgColor,
        ] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(grad,
                                   start: CGPoint(x: body.midX, y: body.maxY),
                                   end: CGPoint(x: body.midX, y: body.minY),
                                   options: [])
        }
        ctx.restoreGState()
        stroke(ctx, bodyPath, NSColor(srgbRed: 0.08, green: 0.50, blue: 0.45, alpha: 1), px(0.012))

        // Hurt flash
        if impact > 0.001 {
            fill(ctx, bodyPath, NSColor.systemRed.withAlphaComponent(0.62 * impact))
        }

        // Blush
        fill(ctx, CGPath(ellipseIn: rect(0.175, 0.50, 0.115, 0.085), transform: nil),
             NSColor(srgbRed: 1.0, green: 0.55, blue: 0.62, alpha: 0.55))
        fill(ctx, CGPath(ellipseIn: rect(0.71, 0.50, 0.115, 0.085), transform: nil),
             NSColor(srgbRed: 1.0, green: 0.55, blue: 0.62, alpha: 0.55))

        // Eyes
        for cx in [CGFloat(0.36), CGFloat(0.64)] {
            fill(ctx, CGPath(ellipseIn: rect(cx - 0.075, 0.665, 0.15, 0.15), transform: nil), .white)
            let pupilShift: CGFloat = impact > 0.001 ? 0.0 : 0.004
            fill(ctx, CGPath(ellipseIn: rect(cx - 0.040 + pupilShift, 0.705, 0.080, 0.080), transform: nil),
                 NSColor(srgbRed: 0.09, green: 0.12, blue: 0.18, alpha: 1))
            fill(ctx, CGPath(ellipseIn: rect(cx - 0.018 + pupilShift, 0.760, 0.030, 0.030), transform: nil),
                 NSColor.white.withAlphaComponent(0.92))
        }

        // Mouth: content when connected, flat when offline.
        ctx.saveGState()
        ctx.setStrokeColor(NSColor(srgbRed: 0.09, green: 0.30, blue: 0.32, alpha: 0.85).cgColor)
        ctx.setLineWidth(px(0.014))
        ctx.setLineCap(.round)
        if model.connected {
            ctx.move(to: CGPoint(x: px(0.455), y: px(0.605)))
            ctx.addQuadCurve(to: CGPoint(x: px(0.545), y: px(0.605)),
                             control: CGPoint(x: px(0.5), y: px(0.570)))
        } else {
            ctx.move(to: CGPoint(x: px(0.462), y: px(0.590)))
            ctx.addLine(to: CGPoint(x: px(0.538), y: px(0.590)))
        }
        ctx.strokePath()
        ctx.restoreGState()

        // Body outline redraw on top so the flash stays inside the silhouette
        stroke(ctx, bodyPath, NSColor(srgbRed: 0.08, green: 0.50, blue: 0.45, alpha: 0.9), px(0.010))

        drawTablet(ctx, impact: impact)
    }

    private func drawTablet(_ ctx: CGContext, impact: CGFloat) {
        let bezel = rect(0.185, 0.145, 0.63, 0.355)
        let bezelPath = rounded(bezel, px(0.055))

        // Arms holding the tablet
        fill(ctx, rounded(rect(0.115, 0.245, 0.10, 0.115), px(0.035)),
             NSColor(srgbRed: 0.16, green: 0.76, blue: 0.69, alpha: 1))
        fill(ctx, rounded(rect(0.785, 0.245, 0.10, 0.115), px(0.035)),
             NSColor(srgbRed: 0.16, green: 0.76, blue: 0.69, alpha: 1))

        // Soft drop shadow so the tablet reads as held in front
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -px(0.012)), blur: px(0.05),
                      color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.addPath(bezelPath)
        ctx.setFillColor(NSColor(srgbRed: 0.10, green: 0.12, blue: 0.15, alpha: 1).cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        stroke(ctx, bezelPath, NSColor(srgbRed: 0.32, green: 0.36, blue: 0.42, alpha: 1), px(0.008))

        // Screen
        let screen = bezel.insetBy(dx: px(0.024), dy: px(0.024))
        let screenPath = rounded(screen, px(0.035))
        ctx.saveGState()
        ctx.addPath(screenPath)
        ctx.clip()
        let colors = [
            NSColor(srgbRed: 0.06, green: 0.12, blue: 0.14, alpha: 1).cgColor,
            NSColor(srgbRed: 0.02, green: 0.04, blue: 0.06, alpha: 1).cgColor,
        ] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(grad,
                                   start: CGPoint(x: screen.midX, y: screen.maxY),
                                   end: CGPoint(x: screen.midX, y: screen.minY),
                                   options: [])
        }
        ctx.restoreGState()

        if impact > 0.001 {
            fill(ctx, screenPath, NSColor.systemRed.withAlphaComponent(0.30 * impact))
        }

        // Screen readout
        let labelColor = NSColor(srgbRed: 0.55, green: 0.72, blue: 0.74, alpha: 1)
        let valueColor = model.connected ? NSColor.white
                                         : NSColor(srgbRed: 0.55, green: 0.60, blue: 0.64, alpha: 1)
        drawText(ctx, "DSH 余额",
                 font: NSFont.systemFont(ofSize: px(0.052), weight: .medium),
                 color: labelColor,
                 center: CGPoint(x: px(0.5), y: px(0.425)))

        let numberFont = NSFont.monospacedDigitSystemFont(ofSize: px(0.135), weight: .bold)
        drawText(ctx, model.displayString, font: numberFont, color: valueColor,
                 center: CGPoint(x: px(0.5), y: px(0.290)))

        // Connection dot
        let dotColor: NSColor = model.connected ? .systemGreen
                              : (model.lastError == nil ? .systemYellow : .systemRed)
        fill(ctx, CGPath(ellipseIn: rect(0.745, 0.415, 0.038, 0.038), transform: nil), dotColor)
    }

    private func drawFloating(_ ctx: CGContext) {
        // The lane starts just above the antenna and ends near the top edge.
        // Labels are born 0.2 s apart and live `floatLifetime`, so linear travel
        // spaces a whole combo evenly instead of stacking them on one spot.
        let start = px(1.00)
        let top = bounds.height - px(0.09)
        let font = NSFont.monospacedDigitSystemFont(ofSize: px(0.080), weight: .heavy)

        for label in model.floating {
            let progress = min(1, label.age / model.floatLifetime)
            let y = start + (top - start) * CGFloat(progress)
            let alpha = max(0, 1 - pow(progress, 1.6))

            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: label.color.withAlphaComponent(alpha),
            ]
            let text = NSAttributedString(string: label.text, attributes: attrs)
            let size = text.size()
            let x = bounds.width * label.x - size.width / 2

            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: px(0.022),
                          color: NSColor.black.withAlphaComponent(0.40 * alpha).cgColor)
            text.draw(at: NSPoint(x: x, y: y))
            ctx.restoreGState()
        }
    }
}

/// Borderless overlay window that can still take key status for its menu.
final class PetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
