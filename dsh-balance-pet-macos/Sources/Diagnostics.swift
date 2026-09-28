import AppKit
import CoreGraphics

/// Head-less verification entry points. These exist so the app can be checked
/// without screen-recording permission: `--selftest` exercises the accounting,
/// `--check` performs one real request, `--snapshot` renders the widget
/// off-screen to PNG, and `--windows` reports the live overlay geometry.
enum Diagnostics {

    static func wantsRun() -> Bool {
        let a = CommandLine.arguments
        return a.contains("--selftest") || a.contains("--check")
            || a.contains("--snapshot") || a.contains("--windows")
            || a.contains("--screens") || a.contains("--reset")
    }

    static func run() -> Int32 {
        let a = CommandLine.arguments
        if a.contains("--selftest") { return selfTest() }
        if a.contains("--screens") { return screens() }
        if a.contains("--windows") { return windowProbe() }
        if a.contains("--reset") { return reset() }
        if let i = a.firstIndex(of: "--snapshot") {
            return snapshot(into: i + 1 < a.count ? a[i + 1] : "./snapshots")
        }
        return check()
    }

    /// Forget the saved window position so the next launch starts clean.
    static func reset() -> Int32 {
        let fm = FileManager.default
        var removed: [String] = []
        for url in [PetPaths.stateURL, PetPaths.statusURL] {
            guard fm.fileExists(atPath: url.path) else { continue }
            do { try fm.removeItem(at: url); removed.append(url.lastPathComponent) }
            catch { print("could not remove \(url.path): \(error.localizedDescription)") }
        }
        print(removed.isEmpty ? "nothing to reset" : "removed: " + removed.joined(separator: ", "))
        print("pet.log left in place: \(PetPaths.logURL.path)")
        Log.write("reset: " + (removed.isEmpty ? "nothing to remove" : removed.joined(separator: ", ")))
        return 0
    }

    /// Print the real NSScreen layout, which does not always match what
    /// system_profiler reports (scaled HiDPI modes, virtual displays).
    static func screens() -> Int32 {
        _ = NSApplication.shared
        print("screens: \(NSScreen.screens.count)")
        for (i, s) in NSScreen.screens.enumerated() {
            let f = s.frame, v = s.visibleFrame
            print(String(format: "  [%d] %@", i, s.localizedName))
            print(String(format: "      frame        (%.0f,%.0f %.0fx%.0f)", f.origin.x, f.origin.y, f.width, f.height))
            print(String(format: "      visibleFrame (%.0f,%.0f %.0fx%.0f)", v.origin.x, v.origin.y, v.width, v.height))
            print(String(format: "      backingScale %.1f", s.backingScaleFactor))
        }
        if let m = NSScreen.main {
            print(String(format: "main: %@ visibleFrame (%.0f,%.0f %.0fx%.0f)",
                         m.localizedName, m.visibleFrame.origin.x, m.visibleFrame.origin.y,
                         m.visibleFrame.width, m.visibleFrame.height))
        } else {
            print("main: nil")
        }
        return 0
    }

    // MARK: - Accounting self-test

    private static var failures = 0

    private static func expect(_ condition: Bool, _ label: String) {
        print((condition ? "  PASS  " : "  FAIL  ") + label)
        if !condition { failures += 1 }
    }

    private static func reading(_ cny: Double) -> BalanceReading {
        BalanceReading(normalCny: cny, bonusCny: 0, spentCny: nil, raw: "")
    }

    /// Advance the model until no real deduction is left to animate.
    private static func drain(_ model: PetModel) {
        for _ in 0..<6000 {
            model.tick(1.0 / 60.0)
            if model.displayedCents == model.realCents { return }
        }
    }

    static func selfTest() -> Int32 {
        print("== accounting self-test ==")

        let m = PetModel()
        m.apply(reading: reading(30.00), snap: true)
        expect(m.displayedCents == 3000, "first reading snaps to 3000 fen")

        m.apply(reading: reading(29.99), snap: false)
        drain(m)
        expect(m.displayedCents == 2999, "a one-fen drop lands exactly on 2999")

        m.apply(reading: reading(29.95), snap: false)
        drain(m)
        expect(m.displayedCents == 2995, "a five-fen drop walks down to 2995")

        // No drift across many readings, including fractional fen values.
        let m2 = PetModel()
        m2.apply(reading: reading(50.00), snap: true)
        var value = 50.00
        for _ in 0..<150 {
            value -= 0.01
            m2.apply(reading: reading(value), snap: false)
            drain(m2)
        }
        // 150 drops of one fen take 50.00 down to 48.50 exactly.
        expect(m2.displayedCents == 4850,
               "150 successive drops leave no drift (expected 4850, got \(m2.displayedCents.map(String.init) ?? "nil"), real \(m2.realCents.map(String.init) ?? "nil"))")

        // Top-up snaps upward immediately.
        let m3 = PetModel()
        m3.apply(reading: reading(10.00), snap: true)
        m3.apply(reading: reading(25.00), snap: false)
        expect(m3.displayedCents == 2500, "a top-up snaps straight up")
        expect(m3.topupTime > 0, "a top-up triggers the celebration")

        // A fractional balance rounds to the nearest fen.
        let m4 = PetModel()
        m4.apply(reading: BalanceReading(normalCny: 38.6177, bonusCny: 0, spentCny: nil, raw: ""), snap: true)
        expect(m4.displayedCents == 3862, "38.6177 renders as 38.62")

        // Bonus wallet is added to the total.
        let m5 = PetModel()
        m5.apply(reading: BalanceReading(normalCny: 10.00, bonusCny: 5.50, spentCny: nil, raw: ""), snap: true)
        expect(m5.displayedCents == 1550, "bonus wallet is added to the balance")

        // A demo never moves the real balance.
        let m6 = PetModel()
        m6.apply(reading: reading(20.00), snap: true)
        m6.playDemo(times: 5)
        for _ in 0..<400 { m6.tick(1.0 / 60.0) }
        expect(m6.displayedCents == 2000, "a demo returns to the true balance")

        // Click-through: the floating lane and the transparent corners must let
        // clicks reach whatever is behind the pet.
        let side: CGFloat = 150
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: side, height: side * (1 + PetView.floatBand)),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        let pv = PetView(model: PetModel())
        win.contentView = pv
        func hits(_ x: CGFloat, _ y: CGFloat) -> Bool {
            win.contentView?.hitTest(NSPoint(x: x, y: y)) === pv
        }
        expect(hits(75, 75), "the body accepts clicks")
        expect(!hits(75, 215), "the floating-number lane is click-through")
        expect(!hits(1, 1), "the transparent corner is click-through")
        expect(!hits(149, 149), "the opposite corner is click-through")

        // Parsing the live payload shape.
        let payload = """
        {"code":0,"data":{"biz_code":0,"biz_data":{
          "normal_wallets":[{"currency":"CNY","balance":"38.6177023600000000","token_estimation":"0"}],
          "bonus_wallets":[{"currency":"CNY","balance":"1.5"}],
          "total_costs":[{"currency":"CNY","amount":"31.38"}]}}}
        """
        if let data = payload.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Mirror BalanceClient.parseAccount via a real fetch path is not possible
            // offline, so just assert the shape the parser walks.
            expect((obj["data"] as? [String: Any])?["biz_data"] != nil, "account envelope has data.biz_data")
        }

        print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
        return failures == 0 ? 0 : 1
    }

    // MARK: - Live request

    static func check() -> Int32 {
        print("== credential ==")
        guard let cred = CredentialStore.resolve() else {
            print("no credential found")
            return 1
        }
        print("mode:     \(cred.mode)")
        print("endpoint: \(cred.endpoint.absoluteString)")
        print("source:   \(cred.source)")
        print("token:    \(cred.token.count) chars")

        print("\n== live request ==")
        do {
            let r = try BalanceClient.fetch(cred)
            print(String(format: "normal CNY: %.4f", r.normalCny))
            print(String(format: "bonus  CNY: %.4f", r.bonusCny))
            print(String(format: "TOTAL  CNY: %.6f  -> displays as %.2f",
                         r.totalCny, Double(Int((r.totalCny * 100).rounded())) / 100))
            if let s = r.spentCny { print(String(format: "spent  CNY: %.2f", s)) }
            return 0
        } catch let e as FetchError {
            print("FAILED: \(e.describe)")
            return 2
        } catch {
            print("FAILED: \(error)")
            return 2
        }
    }

    // MARK: - Off-screen render

    private static func render(_ view: NSView, to url: URL) -> Bool {
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        view.cacheDisplay(in: bounds, to: rep)

        let canvas = NSImage(size: bounds.size)
        canvas.lockFocus()
        NSColor(srgbRed: 0.90, green: 0.91, blue: 0.93, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: bounds.size)).fill()
        rep.draw(in: NSRect(origin: .zero, size: bounds.size))
        canvas.unlockFocus()

        guard let tiff = canvas.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }

    static func snapshot(into directory: String) -> Int32 {
        _ = NSApplication.shared
        let dir = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let side: CGFloat = 240
        let frame = NSRect(x: 0, y: 0, width: side, height: side * (1 + PetView.floatBand))

        func makeView(_ model: PetModel) -> PetView {
            let v = PetView(model: model)
            v.frame = frame
            return v
        }

        var written: [String] = []

        // 1. Connected, idle
        let idle = PetModel()
        idle.apply(reading: BalanceReading(normalCny: 38.61, bonusCny: 0, spentCny: 31.38, raw: ""), snap: true)
        let v1 = makeView(idle)
        if render(v1, to: dir.appendingPathComponent("01-connected.png")) { written.append("01-connected.png") }

        // 2. Hurt animation: four "-0.01" labels in flight, held at peak impact
        //    so the red flash and shake offset are both visible.
        let hit = PetModel()
        hit.apply(reading: BalanceReading(normalCny: 38.65, bonusCny: 0, spentCny: 31.34, raw: ""), snap: true)
        hit.apply(reading: BalanceReading(normalCny: 38.61, bonusCny: 0, spentCny: 31.38, raw: ""), snap: false)
        var frames = 0
        while (hit.floating.count < 4 || hit.impact < 0.95) && frames < 120 {
            hit.tick(1.0 / 60.0)
            frames += 1
        }
        let v2 = makeView(hit)
        if render(v2, to: dir.appendingPathComponent("02-hit.png")) { written.append("02-hit.png") }

        // 3. Top-up celebration
        let top = PetModel()
        top.apply(reading: BalanceReading(normalCny: 20.00, bonusCny: 0, spentCny: nil, raw: ""), snap: true)
        top.apply(reading: BalanceReading(normalCny: 50.00, bonusCny: 5.50, spentCny: nil, raw: ""), snap: false)
        for _ in 0..<8 { top.tick(1.0 / 60.0) }
        let v3 = makeView(top)
        if render(v3, to: dir.appendingPathComponent("03-topup.png")) { written.append("03-topup.png") }

        // 4. No credential / offline
        let off = PetModel()
        off.setNoCredential()
        let v4 = makeView(off)
        if render(v4, to: dir.appendingPathComponent("04-offline.png")) { written.append("04-offline.png") }

        print("wrote \(written.count) snapshot(s) to \(dir.path)")
        for w in written { print("  " + w) }
        return written.count == 4 ? 0 : 1
    }

    // MARK: - Live status
    //
    // Reading another process's window through CGWindowListCopyWindowInfo needs
    // Screen Recording permission, so the running pet publishes its own geometry
    // and connection state to status.json instead and we read that.

    static func windowProbe() -> Int32 {
        guard let data = try? Data(contentsOf: PetPaths.statusURL) else {
            print("no status file at \(PetPaths.statusURL.path)")
            print("(the pet has not run yet, or it cannot write there)")
            return 1
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("status file is not valid JSON")
            return 1
        }
        if let updated = obj["updatedAt"] as? Double {
            let age = Date().timeIntervalSince1970 - updated
            print(String(format: "status age: %.1fs%@", age, age > 5 ? "  <-- stale, pet is probably not running" : ""))
        }
        let keys = ["running", "pid", "connected", "display", "real", "statusText",
                    "lastError", "credential", "spentCny",
                    "windowX", "windowY", "windowW", "windowH",
                    "windowLevel", "windowVisible", "onActiveSpace", "opaque", "screen"]
        for k in keys {
            if let v = obj[k] { print("  \(k.padding(toLength: 15, withPad: " ", startingAt: 0)) \(v)") }
        }
        return 0
    }
}
