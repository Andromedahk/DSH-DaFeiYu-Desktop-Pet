import AppKit

final class ActionBox: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func fire(_ sender: Any?) { handler() }
}

final class PetController: NSObject, NSApplicationDelegate {

    let model = PetModel()
    private var view: PetView!
    private var window: PetWindow!
    private var statusItem: NSStatusItem?
    private var state = PetState.load()
    private var credential: Credential?

    private var tickTimer: Timer?
    private var lastFrame: CFTimeInterval = CACurrentMediaTime()
    private var pollAccum: Double = 0
    private var currentDelay: Double = 30
    private var polling = false
    private var didStartupPoll = false
    private var statusAccum: Double = 0

    private var statusBoxes: [ActionBox] = []
    private var popupBoxes: [ActionBox] = []

    private let soundQueue = DispatchQueue(label: "dshpet.sound")
    private var soundPlayers: [NSSound] = []
    private var soundIndex = 0

    static let sizePresets: [(title: String, side: CGFloat)] = [
        ("小", 110), ("中", 150), ("大", 210), ("特大", 280),
    ]

    private var side: CGFloat {
        let i = min(max(state.sizeIndex, 0), Self.sizePresets.count - 1)
        return Self.sizePresets[i].side
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        credential = CredentialStore.resolve()

        view = PetView(model: model)
        view.controller = self

        let content = NSRect(x: 0, y: 0, width: side, height: side * (1 + PetView.floatBand))
        window = PetWindow(contentRect: content,
                           styleMask: [.borderless],
                           backing: .buffered,
                           defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = false
        window.contentView = view
        window.alphaValue = 1.0

        model.setCredentialSource(credentialSourceLabel())
        model.onHit = { [weak self] in self?.playHit() }

        placeWindow()
        window.orderFrontRegardless()

        buildStatusItem()
        startTick()

        let f = window.frame
        Log.write(String(format: "started: size=%.0fpt frame=(%.0f,%.0f %.0fx%.0f) screen=%@ credential=%@",
                         side, f.origin.x, f.origin.y, f.width, f.height,
                         window.screen?.localizedName ?? "?",
                         credential?.shortDescription ?? "none"))
        if credential == nil {
            Log.write("no credential found; right-click the pet → 设置 API Key…")
        }

        writeStatus()
        // Fire the first request right away instead of waiting a full interval.
        pollAccum = currentDelay
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.windowOrigin = window?.frame.origin
        state.save()
    }

    // MARK: - Window placement

    private func placeWindow() {
        let size = window.frame.size
        if let origin = state.windowOrigin, isOnScreen(origin: origin, size: size) {
            window.setFrameOrigin(origin)
            return
        }
        // First run: land on the primary display (the one with the menu bar)
        // rather than whichever screen the fresh window happened to open on.
        snapToCorner(animated: false, on: NSScreen.screens.first)
    }

    private func isOnScreen(origin: NSPoint, size: NSSize) -> Bool {
        let frame = NSRect(origin: origin, size: size)
        return NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
    }

    /// Snap to the bottom-left corner. `on` defaults to the screen the pet is
    /// currently sitting on, so dragging it to another display keeps it there.
    func snapToCorner(animated: Bool, on screen: NSScreen? = nil) {
        guard let target = screen ?? window.screen ?? NSScreen.main else { return }
        let vf = target.visibleFrame
        let origin = NSPoint(x: vf.minX + 14, y: vf.minY + 14)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrameOrigin(origin)
            }
        } else {
            window.setFrameOrigin(origin)
        }
        state.windowOrigin = origin
    }

    func dragDidEnd() {
        state.windowOrigin = window.frame.origin
        if state.snapOnRelease { snapToCorner(animated: true) }
        state.save()
    }

    // MARK: - Tick

    private func startTick() {
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.frameTick() }
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t
    }

    private func frameTick() {
        let now = CACurrentMediaTime()
        let dt = min(0.1, now - lastFrame)
        lastFrame = now

        model.tick(dt)
        view.needsDisplay = true

        pollAccum += dt
        if !polling && pollAccum >= currentDelay {
            pollAccum = 0
            poll(snap: !didStartupPoll)
            didStartupPoll = true
        }

        statusAccum += dt
        if statusAccum >= 1.0 {
            statusAccum = 0
            writeStatus()
        }
    }

    /// Publish a small liveness/geometry snapshot so the pet can be inspected
    /// from another process without screen-recording permission.
    private func writeStatus() {
        let f = window.frame
        let obj: [String: Any] = [
            "running": true,
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "connected": model.connected,
            "display": model.displayString,
            "real": model.realString,
            "statusText": model.statusText,
            "lastError": model.lastError ?? "",
            "credential": model.credentialSource ?? "",
            "spentCny": model.spentCny ?? -1,
            "windowX": Double(f.origin.x),
            "windowY": Double(f.origin.y),
            "windowW": Double(f.width),
            "windowH": Double(f.height),
            "windowLevel": Double(window.level.rawValue),
            "windowVisible": window.isVisible,
            "onActiveSpace": window.isOnActiveSpace,
            "opaque": window.isOpaque,
            "screen": window.screen?.localizedName ?? "",
            "updatedAt": Date().timeIntervalSince1970,
        ]
        if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: PetPaths.statusURL)
        }
    }

    // MARK: - Polling

    private func poll(snap: Bool) {
        guard let cred = credential else {
            model.setNoCredential()
            model.setCredentialSource(credentialSourceLabel())
            return
        }
        polling = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let outcome: Result<BalanceReading, Error>
            do { outcome = .success(try BalanceClient.fetch(cred)) }
            catch { outcome = .failure(error) }

            DispatchQueue.main.async {
                self.polling = false
                switch outcome {
                case .success(let reading):
                    let wasDisconnected = !self.model.connected
                    if snap || wasDisconnected {
                        self.model.apply(reading: reading, snap: true)
                    } else {
                        self.model.apply(reading: reading, snap: false)
                    }
                    self.currentDelay = self.state.pollSeconds
                    Log.write(String(format: "poll ok: CNY %.4f (normal %.4f + bonus %.4f)",
                                     reading.totalCny, reading.normalCny, reading.bonusCny))
                case .failure(let error):
                    let fe = (error as? FetchError) ?? .transport(error.localizedDescription)
                    self.model.fail(fe)
                    if case .rateLimited(let retryAfter) = fe {
                        let backoff = retryAfter ?? min(self.currentDelay * 2, 300)
                        self.currentDelay = min(max(backoff, 10), 300)
                        Log.write(String(format: "rate limited, next poll in %.0fs", self.currentDelay))
                    } else {
                        self.currentDelay = self.state.pollSeconds
                    }
                }
            }
        }
    }

    private func credentialSourceLabel() -> String? {
        credential?.shortDescription
    }

    // MARK: - Sound

    private func playHit() {
        guard state.soundOn, let url = PetPaths.soundURL else { return }
        soundQueue.async { [weak self] in
            guard let self = self else { return }
            if self.soundPlayers.isEmpty {
                for _ in 0..<4 {
                    if let s = NSSound(contentsOf: url, byReference: true) {
                        s.volume = 0.7
                        self.soundPlayers.append(s)
                    }
                }
            }
            guard !self.soundPlayers.isEmpty else { return }
            DispatchQueue.main.async {
                let player = self.soundPlayers[self.soundIndex % self.soundPlayers.count]
                self.soundIndex += 1
                player.stop()
                player.play()
            }
        }
    }

    // MARK: - Menus

    private func buildMenu(into boxes: inout [ActionBox]) -> NSMenu {
        boxes.removeAll()
        let menu = NSMenu()
        menu.autoenablesItems = false

        func item(_ title: String, _ enabled: Bool = true, _ handler: @escaping () -> Void) -> NSMenuItem {
            let box = ActionBox(handler)
            boxes.append(box)
            let mi = NSMenuItem(title: title, action: #selector(ActionBox.fire(_:)), keyEquivalent: "")
            mi.target = box
            mi.isEnabled = enabled
            return mi
        }

        let status = NSMenuItem(title: model.connected
                                ? "余额 ¥\(model.realString)  ·  已连接"
                                : "余额 --  ·  \(model.lastError ?? model.statusText)",
                                action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if let src = model.credentialSource {
            let s = NSMenuItem(title: "凭证：" + src, action: nil, keyEquivalent: "")
            s.isEnabled = false
            menu.addItem(s)
        }
        if let spent = model.spentCny {
            let s = NSMenuItem(title: String(format: "累计消费 ¥%.2f", spent), action: nil, keyEquivalent: "")
            s.isEnabled = false
            menu.addItem(s)
        }
        menu.addItem(.separator())

        menu.addItem(item("立即刷新余额") { [weak self] in
            self?.pollAccum = 0
            self?.poll(snap: true)
        })
        menu.addItem(item("测试一次扣费") { [weak self] in self?.model.playOneHit() })

        let demo = NSMenuItem(title: "演示连续扣费", action: nil, keyEquivalent: "")
        let demoMenu = NSMenu()
        for fen in [5, 10, 20, 50, 100] {
            let title = String(format: "-%.2f（%d 次）", Double(fen) / 100.0, fen)
            let box = ActionBox { [weak self] in self?.model.playDemo(times: fen) }
            boxes.append(box)
            let mi = NSMenuItem(title: title, action: #selector(ActionBox.fire(_:)), keyEquivalent: "")
            mi.target = box
            demoMenu.addItem(mi)
        }
        menu.addItem(demo)
        menu.setSubmenu(demoMenu, for: demo)

        let sizeMenu = NSMenu()
        for (i, preset) in Self.sizePresets.enumerated() {
            let box = ActionBox { [weak self] in self?.setSize(index: i) }
            boxes.append(box)
            let mi = NSMenuItem(title: "\(preset.title)（\(Int(preset.side))pt）",
                                action: #selector(ActionBox.fire(_:)), keyEquivalent: "")
            mi.target = box
            mi.state = (i == state.sizeIndex) ? .on : .off
            sizeMenu.addItem(mi)
        }
        let sizeItem = NSMenuItem(title: "尺寸", action: nil, keyEquivalent: "")
        menu.addItem(sizeItem)
        menu.setSubmenu(sizeMenu, for: sizeItem)

        menu.addItem(item(state.snapOnRelease ? "✓ 松手吸附左下角" : "　松手吸附左下角") { [weak self] in
            guard let self = self else { return }
            self.state.snapOnRelease.toggle()
            self.state.save()
        })
        menu.addItem(item(state.soundOn ? "✓ 音效" : "　音效") { [weak self] in
            guard let self = self else { return }
            self.state.soundOn.toggle()
            self.state.save()
        })

        let intervalMenu = NSMenu()
        for seconds in [10.0, 30.0, 60.0, 300.0] {
            let title = seconds < 60 ? "\(Int(seconds)) 秒" : "\(Int(seconds / 60)) 分钟"
            let box = ActionBox { [weak self] in
                guard let self = self else { return }
                self.state.pollSeconds = seconds
                self.currentDelay = seconds
                self.pollAccum = 0
                self.state.save()
            }
            boxes.append(box)
            let mi = NSMenuItem(title: title, action: #selector(ActionBox.fire(_:)), keyEquivalent: "")
            mi.target = box
            mi.state = (abs(seconds - state.pollSeconds) < 0.5) ? .on : .off
            intervalMenu.addItem(mi)
        }
        let intervalItem = NSMenuItem(title: "刷新间隔", action: nil, keyEquivalent: "")
        menu.addItem(intervalItem)
        menu.setSubmenu(intervalMenu, for: intervalItem)

        menu.addItem(.separator())
        menu.addItem(item("设置 API Key…") { [weak self] in self?.askForKey() })
        menu.addItem(item("重新读取凭证") { [weak self] in self?.reloadCredential() })
        menu.addItem(item("吸附回左下角") { [weak self] in self?.snapToCorner(animated: true) })
        menu.addItem(item("打开日志") {
            NSWorkspace.shared.open(PetPaths.logURL)
        })
        menu.addItem(item("打开配置文件夹") {
            NSWorkspace.shared.open(PetPaths.support)
        })
        menu.addItem(.separator())
        menu.addItem(item("退出") { NSApp.terminate(nil) })

        return menu
    }

    func showContextMenu() {
        NSApp.activate(ignoringOtherApps: true)
        let menu = buildMenu(into: &popupBoxes)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: view)
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let img = NSImage(systemSymbolName: "yensign.circle.fill", accessibilityDescription: "DSH 余额") {
                button.image = img
            } else {
                button.title = "¥"
            }
            button.toolTip = "DSH 余额桌宠"
        }
        item.menu = buildMenu(into: &statusBoxes)
        statusItem = item
    }

    private func refreshStatusMenu() {
        statusItem?.menu = buildMenu(into: &statusBoxes)
    }

    // MARK: - Actions

    private func setSize(index: Int) {
        state.sizeIndex = min(max(index, 0), Self.sizePresets.count - 1)
        state.save()
        let newSize = NSSize(width: side, height: side * (1 + PetView.floatBand))
        var origin = window.frame.origin
        origin.y -= (newSize.height - window.frame.height)
        window.setFrame(NSRect(origin: origin, size: newSize), display: true)
        state.windowOrigin = window.frame.origin
        state.save()
    }

    private func reloadCredential() {
        credential = CredentialStore.resolve()
        model.setCredentialSource(credentialSourceLabel())
        if credential == nil {
            model.setNoCredential()
        }
        pollAccum = currentDelay
        Log.write("credential reloaded: \(credential?.shortDescription ?? "none")")
    }

    private func askForKey() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "设置 DeepSeek API Key"
        alert.informativeText = """
        填入 sk- 开头的 DeepSeek API Key，会保存到：
        \(PetPaths.userKeyURL.path)

        留空直接点「保存」= 不改动，继续使用当前的 DSH 账号凭证。
        """
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "sk-..."
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        if alert.runModal() == .alertFirstButtonReturn {
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            try? value.write(to: PetPaths.userKeyURL, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                   ofItemAtPath: PetPaths.userKeyURL.path)
            reloadCredential()
        }
    }
}
