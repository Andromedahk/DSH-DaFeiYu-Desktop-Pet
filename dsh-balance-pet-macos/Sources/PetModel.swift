import AppKit

/// Balance bookkeeping + animation state.
///
/// Money is kept in **cents** so stepping the display down one fen at a time can
/// never accumulate floating point drift.
final class PetModel {

    struct FloatLabel {
        let text: String
        let color: NSColor
        var age: Double
        var x: CGFloat          // 0..1, horizontal centre
    }

    // MARK: Accounting

    private(set) var displayedCents: Int?
    private(set) var realCents: Int?
    private(set) var spentCny: Double?
    private(set) var connected = false
    private(set) var statusText = "连接中…"
    private(set) var lastError: String?
    private(set) var credentialSource: String?
    private(set) var lastUpdate: Date?

    private var pendingSteps = 0      // real deductions still to animate
    private var demoRemaining = 0     // menu demo, visual only

    // MARK: Animation

    private(set) var floating: [FloatLabel] = []
    private(set) var shakeTime: Double = 0
    private(set) var flashTime: Double = 0
    private(set) var topupTime: Double = 0
    private(set) var clock: Double = 0

    private var stepCooldown: Double = 0
    let stepInterval: Double = 0.2
    let hitDuration: Double = 0.55
    /// How long a floating number lives. Kept just above stepInterval * 5 so a
    /// full combo is on screen at once without the labels piling up.
    let floatLifetime: Double = 0.95

    /// Called once per animated deduction so the controller can play the sound.
    var onHit: (() -> Void)?

    var displayString: String {
        guard let c = displayedCents else { return "--" }
        return String(format: "%.2f", Double(c) / 100.0)
    }

    var realString: String {
        guard let c = realCents else { return "--" }
        return String(format: "%.2f", Double(c) / 100.0)
    }

    // MARK: - Server readings

    /// `snap` = jump straight to the value (first read, or the "refresh now" menu item).
    /// Otherwise a drop walks down one fen at a time, each step animated.
    func apply(reading: BalanceReading, snap: Bool) {
        let cents = Int((reading.totalCny * 100).rounded())
        realCents = cents
        spentCny = reading.spentCny
        connected = true
        statusText = "已连接"
        lastError = nil
        lastUpdate = Date()

        guard let current = displayedCents else {
            displayedCents = cents
            pendingSteps = 0
            return
        }

        if snap {
            displayedCents = cents
            pendingSteps = 0
            return
        }

        if cents < current {
            let steps = current - cents
            if steps > 400 {
                // Absurd jump (first poll after a long sleep, or a correction):
                // snapping beats animating thousands of hits.
                displayedCents = cents
                pendingSteps = 0
                Log.write("jump too large (\(steps) fen), snapping")
            } else {
                pendingSteps = steps
            }
        } else if cents > current {
            // Top-up: snap up immediately and celebrate.
            displayedCents = cents
            pendingSteps = 0
            topupTime = 0.9
            floating.append(FloatLabel(text: "+" + fenString(cents - current),
                                       color: NSColor.systemGreen, age: 0, x: 0.5))
        } else {
            pendingSteps = 0
        }
    }

    func fail(_ error: FetchError) {
        connected = false
        lastError = error.describe
        statusText = "离线"
        Log.write("poll failed: \(error.describe)")
    }

    func setNoCredential() {
        connected = false
        lastError = "找不到凭证"
        statusText = "未配置"
        credentialSource = nil
    }

    func setCredentialSource(_ s: String?) {
        credentialSource = s
    }

    /// Right-click → 立即刷新余额 / 测试一次扣费.
    func forceSnapToReal() {
        if let r = realCents { displayedCents = r }
        pendingSteps = 0
    }

    func playOneHit() {
        demoRemaining += 1
        stepCooldown = 0
    }

    /// 演示连续扣费 ▸ n 次
    func playDemo(times: Int) {
        demoRemaining += max(1, min(times, 200))
        stepCooldown = 0
    }

    // MARK: - Frame tick

    func tick(_ dt: Double) {
        clock += dt
        stepCooldown -= dt

        if shakeTime > 0 { shakeTime = max(0, shakeTime - dt) }
        if flashTime > 0 { flashTime = max(0, flashTime - dt) }
        if topupTime > 0 { topupTime = max(0, topupTime - dt) }

        for i in floating.indices { floating[i].age += dt }
        floating.removeAll { $0.age > floatLifetime }
        if floating.count > 60 { floating.removeFirst(floating.count - 60) }

        if stepCooldown <= 0 {
            if demoRemaining > 0 {
                demoRemaining -= 1
                performStep(revertWhenDone: demoRemaining == 0)
            } else if pendingSteps > 0 {
                pendingSteps -= 1
                performStep(revertWhenDone: false)
            }
        }
    }

    private func performStep(revertWhenDone: Bool) {
        stepCooldown = stepInterval

        if revertWhenDone {
            // End of a menu demo: put the readout back on the true balance.
            forceSnapToReal()
        } else if let c = displayedCents {
            displayedCents = max(0, c - 1)
        }

        shakeTime = hitDuration
        flashTime = hitDuration
        floating.append(FloatLabel(text: "-0.01", color: NSColor.systemRed, age: 0, x: 0.5))
        onHit?()
    }

    // MARK: - Animation helpers used by the view

    /// 0 at the end of the hurt animation, 1 at the moment of impact.
    var impact: Double {
        guard shakeTime > 0 else { return 0 }
        let t = hitDuration - shakeTime        // elapsed
        if t < 0.08 { return min(1, t / 0.08) }  // fast attack
        return max(0, 1 - (t - 0.08) / (hitDuration - 0.08))
    }

    private func fenString(_ fen: Int) -> String {
        String(format: "%.2f", Double(fen) / 100.0)
    }
}
