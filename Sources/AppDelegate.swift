import Foundation
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum RenderCadence {
        case paused
        case fullscreenHidden // 2 Hz check while hidden behind a fullscreen app
        case asleep           // 15 Hz adaptive cadence while sleeping
        case idle             // 30 Hz adaptive cadence while awake at rest
        case active           // 60 Hz full cadence during input or motion

        var interval: TimeInterval {
            switch self {
            case .paused:           return 0
            case .fullscreenHidden: return 0.5
            case .asleep:           return 1.0 / 15.0
            case .idle:             return 1.0 / 30.0
            case .active:           return 1.0 / 60.0
            }
        }

        var tolerance: TimeInterval {
            switch self {
            case .paused:           return 0
            case .fullscreenHidden: return 0.15
            case .asleep:           return 0.012
            case .idle:             return 0.004
            case .active:           return 0.002
            }
        }
    }

    private var statusItem: NSStatusItem!
    private var overlayWindow: OverlayWindow!
    private var renderTimer: Timer?
    private var renderCadence: RenderCadence = .paused
    private var windowWatchdogTimer: Timer?
    private var lastFrameTime: CFTimeInterval = CACurrentMediaTime()
    private var lastFullscreenCheckTime: CFTimeInterval = 0
    private var hiddenByFullscreen = false
    private var screensAsleep = false
    private var lastDemoKeyTime: CFTimeInterval = 0
    private var isPetVisible = true
    private var isHandingOverToNewerCopy = false
    private var dressingRoom: DressingRoomWindowController?
    private var settingsWindow: SettingsWindowController?

    // MARK: - Hourly Announcement
    private var minuteTimer: Timer?
    private var lastAnnouncedHour: Int = -1

    private var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.4.7"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if resolveDuplicateRunningCopies() { return }

        overlayWindow = OverlayWindow()
        overlayWindow.orderFrontRegardless()

        let catView = overlayWindow.catView
        catView.onRequestPermission = { [weak self] in
            self?.openInputMonitoringSettings()
        }
        catView.onRightClickMenu = { [weak self] event in
            guard let self else { return }
            self.wakeToActive()
            let menu = self.buildMenu()
            NSMenu.popUpContextMenu(menu, with: event, for: self.overlayWindow.catView)
        }
        catView.onUserInteraction = { [weak self] in
            self?.wakeToActive()
        }
        catView.onDropSkinFiles = { [weak self] urls in
            for url in urls { self?.importDroppedFile(from: url) }
        }

        // Wire dual-layer InputEngine -> CatPhysics
        let engine = InputEngine.shared
        engine.onKeyDown = { [weak self] key in
            DispatchQueue.main.async {
                guard let self else { return }
                self.overlayWindow.catView.physics.triggerKeyDown(key)
                self.wakeToActive()
            }
        }
        engine.onMouseClick = { [weak self] button, isDown in
            DispatchQueue.main.async {
                guard let self else { return }
                self.overlayWindow.catView.physics.triggerMouseClick(button: button, isDown: isDown)
                self.wakeToActive()
            }
        }
        engine.start()

        setupStatusItem()
        if isAutoStartEnabled() {
            // Keep LaunchAgent path updated if user moved KuroCat.app into /Applications
            _ = setAutoStartEnabled(true)
        }
        observePowerNotifications()
        startRenderLoop()
        startWindowWatchdog()
        startHourlyAnnouncement()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Quitting during launch because a newer copy is running: leave its stats alone.
        if isHandingOverToNewerCopy { return }
        renderTimer?.invalidate()
        renderTimer = nil
        renderCadence = .paused
        windowWatchdogTimer?.invalidate()
        minuteTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        InputEngine.shared.flushStats()
        InputEngine.shared.stop()
    }

    // MARK: - One KuroCat at a time (newest copy wins)

    /// Users often download a new KuroCat.app while an older copy is still running (or is started
    /// by the login item from another folder). That old process kept running and kept announcing
    /// "new version available" even though they had already updated. Keep only the newest copy:
    /// quit older ones, or hand over to an already-running newer one. Returns true if THIS process quits.
    private func resolveDuplicateRunningCopies() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let myPID = ProcessInfo.processInfo.processIdentifier
        let myURL = Bundle.main.bundleURL.standardizedFileURL
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID }
        if others.isEmpty { return false }

        for other in others {
            guard let otherURL = other.bundleURL?.standardizedFileURL, otherURL != myURL,
                  let otherVersion = Self.shortVersion(ofAppAt: otherURL) else { continue }
            if isVersion(otherVersion, newerThan: currentAppVersion) {
                isHandingOverToNewerCopy = true
                _ = other.activate(options: [])
                NSApp.terminate(nil)
                return true
            }
        }
        for other in others {
            // Same path (replaced in place by an update) or an older/equal copy elsewhere.
            if !other.terminate() { _ = other.forceTerminate() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if !other.isTerminated { _ = other.forceTerminate() }
            }
        }
        return false
    }

    /// Reads CFBundleShortVersionString straight from disk (Bundle(url:) may return cached info).
    private static func shortVersion(ofAppAt url: URL) -> String? {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: plistURL) as? [String: Any] else { return nil }
        return dict["CFBundleShortVersionString"] as? String
    }

    private func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        func parse(_ v: String) -> [Int] {
            let trimmed = v.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            return trimmed.split(separator: ".").map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
        }
        let a = parse(lhs)
        let b = parse(rhs)
        let count = max(a.count, b.count)
        for i in 0..<count {
            let va = i < a.count ? a[i] : 0
            let vb = i < b.count ? b[i] : 0
            if va != vb { return va > vb }
        }
        return false
    }

    // MARK: - Adaptive Redraw

    private func observePowerNotifications() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(handleScreenOrSystemSleep),
                       name: NSWorkspace.screensDidSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleScreenOrSystemWake),
                       name: NSWorkspace.screensDidWakeNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleScreenOrSystemSleep),
                       name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleScreenOrSystemWake),
                       name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func handleScreenOrSystemSleep() {
        screensAsleep = true
        configureRenderTimer(for: .paused)
    }

    @objc private func handleScreenOrSystemWake() {
        screensAsleep = false
        lastFrameTime = CACurrentMediaTime()
        wakeToActive(immediateRedraw: true)
    }

    private func startRenderLoop() {
        lastFrameTime = CACurrentMediaTime()
        wakeToActive()
    }

    private func wakeToActive(immediateRedraw: Bool = false) {
        guard isPetVisible, !screensAsleep else { return }
        if !hiddenByFullscreen && renderCadence != .active {
            configureRenderTimer(for: .active)
        }
        if immediateRedraw && !hiddenByFullscreen {
            overlayWindow?.catView.needsDisplay = true
        }
    }

    private func configureRenderTimer(for cadence: RenderCadence) {
        guard cadence != renderCadence || (cadence != .paused && renderTimer == nil) else { return }
        renderTimer?.invalidate()
        renderTimer = nil
        renderCadence = cadence
        guard cadence != .paused else { return }
        let timer = Timer(timeInterval: cadence.interval, repeats: true) { [weak self] _ in
            self?.renderTick()
        }
        timer.tolerance = cadence.tolerance
        RunLoop.main.add(timer, forMode: .common)
        renderTimer = timer
    }

    private func updateFullscreenAutoHide(now: CFTimeInterval) -> Bool {
        if now - lastFullscreenCheckTime <= 0.5 {
            return hiddenByFullscreen
        }
        lastFullscreenCheckTime = now
        let s = CatSettings.shared
        let obsBg = (s.obsCaptureMode > 0 && s.obsHideDesktop)
        if s.autoHideFullscreen && !obsBg {
            let fs = Self.isOtherAppFullscreen()
            if fs != hiddenByFullscreen {
                hiddenByFullscreen = fs
                overlayWindow.alphaValue = fs ? 0.0 : 1.0
                if fs {
                    overlayWindow.ignoresMouseEvents = true
                } else {
                    lastFrameTime = now
                    overlayWindow.catView.needsDisplay = true
                }
            }
        } else if hiddenByFullscreen {
            hiddenByFullscreen = false
            overlayWindow.alphaValue = 1.0
            lastFrameTime = now
            overlayWindow.catView.needsDisplay = true
        }
        return hiddenByFullscreen
    }

    private func renderTick() {
        guard isPetVisible, !screensAsleep else {
            configureRenderTimer(for: .paused)
            return
        }
        let now = CACurrentMediaTime()
        if updateFullscreenAutoHide(now: now) {
            configureRenderTimer(for: .fullscreenHidden)
            return
        }

        let dt = CGFloat(now - lastFrameTime)
        lastFrameTime = now

        let view = overlayWindow.catView
        let physics = view.physics
        let input = InputEngine.shared
        let windowFrame = overlayWindow.frame
        let physicsFrame = overlayWindow.physicsFrameInScreen
        let previousMouseMoveTime = input.lastMouseMoveTime
        let wasBlinking = physics.isBlinking
        let wasYawning = physics.isYawning
        let wasToastActive = view.toastActive
        physics.step(dt: dt, windowFrameInScreen: physicsFrame)
        view.updateHoverAndClickThrough()
        view.tickToast(dt: dt)

        let lastDirectInput = max(input.lastKeyActivityTime, input.lastMouseClickTime, lastDemoKeyTime)
        let mouseMoving = now - input.lastMouseMoveTime < 0.12
        let mouseStartedMoving = mouseMoving && now - previousMouseMoveTime >= 0.12
        let mouseNearPet = mouseMoving && windowFrame.insetBy(dx: -24, dy: -24).contains(input.lastMouseLocation)
        let isAsleep = physics.sleepiness >= 0.95
        let hasActiveSparkles = physics.sparkles.contains { !$0.isSleepZ }
        let hasMotion = hasActiveSparkles || !physics.floatingKeycaps.isEmpty
            || !physics.keyGlow.isEmpty || !physics.tabletTrail.isEmpty
            || physics.kbSparkTimer > 0.005
            || physics.petHeadIntensity > 0.02 || physics.petBodyIntensity > 0.02
            || physics.huntIntensity.value > 0.02
            || physics.scruffDrag.value > 0.02 || physics.isChangingLie
            || abs(physics.scruffSwing.value) > 0.01 || abs(physics.scruffSwingY.value) > 0.01
            || abs(physics.scruffTailSwing.value) > 0.01
            || (physics.douniLoafBlend.value > 0.005 && physics.douniLoafBlend.value < 0.995)
            || abs(physics.douniLoafBlend.velocity) > 0.02
            || abs(physics.douniLeftRaise.velocity) > 0.05 || abs(physics.douniRightRaise.velocity) > 0.05
            || abs(physics.douniMouseBlend.velocity) > 0.05
            || abs(physics.kbImpactY.value) > 0.01 || abs(physics.kbImpactTilt.value) > 0.01
            || physics.angerIntensity.value > 0.02 || physics.dizzyIntensity.value > 0.02
            || physics.scruffDizzyIntensity.value > 0.02 || physics.mousePressMiddle.value > 0.02
            || wasYawning || physics.isYawning
            || (!isAsleep && (wasBlinking || physics.isBlinking))
        let isActive = now - lastDirectInput < 0.8 || !input.activeKeys.isEmpty
            || mouseStartedMoving || mouseNearPet
            || input.leftMouseDown || input.rightMouseDown || input.otherMouseDown
            || view.isDraggingOrResizing || hasMotion
            || wasToastActive || view.toastActive  // hourly toast animates at full rate

        let desiredCadence: RenderCadence = isActive ? .active : (isAsleep ? .asleep : .idle)
        if desiredCadence != renderCadence {
            configureRenderTimer(for: desiredCadence)
        }
        if isActive || view.poseNeedsDisplay() {
            view.needsDisplay = true
        }
    }

    // MARK: - Menu Bar Icon & Menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = makeMenuBarCatIcon()
            button.toolTip = "KuroCat 黑猫键盘桌宠"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for item in buildMenu().items {
            item.menu?.removeItem(item)
            menu.addItem(item)
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let engine = InputEngine.shared
        let settings = CatSettings.shared
        let physics = overlayWindow.catView.physics
        let en = settings.isEnglish

        func tr(_ zh: String, _ eng: String) -> String { en ? eng : zh }

        // Status header
        let statusPrefix = engine.status.needsAttention ? "⚠️" : "🟢"
        let statusText: String
        if en {
            switch engine.status {
            case .fullHardware: statusText = "Hardware Input Active (HID + EventTap)"
            case .hidOnly: statusText = "Hardware HID Active"
            case .eventTapOnly: statusText = "Global EventTap Active"
            case .needsPermission: statusText = "Input Monitoring Permission Needed"
            case .needsRestart: statusText = "Authorized — Restart to Retry"
            }
        } else {
            statusText = engine.status.rawValue
        }
        let statusItem = NSMenuItem(title: "\(statusPrefix) \(statusText)", action: engine.status.needsAttention ? #selector(openInputMonitoringSettings) : nil, keyEquivalent: "")
        statusItem.target = self
        menu.addItem(statusItem)

        if engine.status == .needsPermission {
            let grantItem = NSMenuItem(title: tr("🔑 前往系统设置开启「输入监控」...", "🔑 Open Input Monitoring Settings..."), action: #selector(openInputMonitoringSettings), keyEquivalent: "")
            grantItem.target = self
            menu.addItem(grantItem)
        }

        // Live stats
        let statsTitle = en
            ? "⌨️ Today \(engine.totalKeystrokesToday)  ·  KPM \(engine.currentKPM)  ·  Pets \(physics.totalPetSessions)"
            : "⌨️ 今日击键 \(engine.totalKeystrokesToday)  ·  KPM \(engine.currentKPM)  ·  摸猫 \(physics.totalPetSessions) 次"
        let statsItem = NSMenuItem(title: statsTitle, action: nil, keyEquivalent: "")
        statsItem.isEnabled = false
        menu.addItem(statsItem)

        menu.addItem(.separator())

        // Essential everyday actions only — everything else lives cleanly in the unified Settings window!
        let visItem = NSMenuItem(title: isPetVisible ? tr("隐藏桌宠", "Hide Pet") : tr("显示桌宠", "Show Pet"), action: #selector(toggleVisibility), keyEquivalent: "")
        visItem.target = self
        menu.addItem(visItem)

        // Quick Cat Skin switcher submenu
        let coatMenu = NSMenu()
        let library = SkinLibrary.shared
        let customActive = library.skin(id: settings.customSkin) != nil
        for coat in CatCoatTheme.allCases {
            let coatTitle: String
            if en {
                switch coat {
                case .classicBlack: coatTitle = "Classic Black Cat"
                case .siamese: coatTitle = "Siamese Cat"
                case .shorthair: coatTitle = "Silver Tabby Shorthair"
                case .orangeWhite: coatTitle = "Orange & White Cat"
                case .doraemon: coatTitle = "Doraemon"
                case .pikachu: coatTitle = "Pikachu"
                }
            } else {
                coatTitle = coat.rawValue
            }
            let item = NSMenuItem(title: coatTitle, action: #selector(selectCoatTheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = coat.rawValue
            item.state = !customActive && settings.coatTheme == coat ? .on : .off
            coatMenu.addItem(item)
        }
        if !library.skins.isEmpty {
            coatMenu.addItem(.separator())
            for skin in library.skins {
                let item = NSMenuItem(title: library.displayName(for: skin), action: #selector(selectCustomSkin(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = skin.id
                item.state = settings.customSkin == skin.id ? .on : .off
                if !skin.author.isEmpty { item.toolTip = tr("作者：\(skin.author)", "Author: \(skin.author)") }
                coatMenu.addItem(item)
            }
        }
        coatMenu.addItem(.separator())
        let importItem = NSMenuItem(title: tr("导入皮肤…", "Import Skin…"), action: #selector(showDressingRoom), keyEquivalent: "")
        importItem.target = self
        coatMenu.addItem(importItem)
        let workshopItem = NSMenuItem(title: tr("打开皮肤工坊…", "Open Skin Workshop…"), action: #selector(openSkinWorkshop), keyEquivalent: "")
        workshopItem.target = self
        coatMenu.addItem(workshopItem)
        let openDirItem = NSMenuItem(title: tr("打开皮肤文件夹", "Open Skins Folder"), action: #selector(openSkinsFolder), keyEquivalent: "")
        openDirItem.target = self
        coatMenu.addItem(openDirItem)
        if !library.skins.isEmpty {
            coatMenu.addItem(.separator())
            let renameMenu = NSMenu()
            for skin in library.skins {
                let item = NSMenuItem(title: "✏️ " + library.displayName(for: skin), action: #selector(renameCustomSkin(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = skin.id
                renameMenu.addItem(item)
            }
            let renameParent = NSMenuItem(title: tr("✏️ 重命名皮肤…", "✏️ Rename Skin…"), action: nil, keyEquivalent: "")
            renameParent.submenu = renameMenu
            coatMenu.addItem(renameParent)

            let deleteMenu = NSMenu()
            for skin in library.skins {
                let delTitle = "🗑 " + library.displayName(for: skin)
                let item = NSMenuItem(title: delTitle, action: #selector(deleteCustomSkin(_:)), keyEquivalent: "")
                item.attributedTitle = NSAttributedString(
                    string: delTitle,
                    attributes: [.foregroundColor: NSColor.systemRed, .font: NSFont.menuFont(ofSize: 0)]
                )
                item.target = self
                item.representedObject = skin.id
                deleteMenu.addItem(item)
            }
            let deleteTitle = tr("🗑 删除已导入皮肤…", "🗑 Delete Imported Skin…")
            let deleteParent = NSMenuItem(title: deleteTitle, action: nil, keyEquivalent: "")
            deleteParent.attributedTitle = NSAttributedString(
                string: deleteTitle,
                attributes: [.foregroundColor: NSColor.systemRed, .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)]
            )
            deleteParent.submenu = deleteMenu
            coatMenu.addItem(deleteParent)
        }
        let coatParent = NSMenuItem(title: tr("猫咪皮肤 🐱", "Cat Skin 🐱"), action: nil, keyEquivalent: "")
        coatParent.submenu = coatMenu
        menu.addItem(coatParent)

        let topWorkshopItem = NSMenuItem(
            title: tr("🎨 皮肤工坊（制作皮肤）…", "🎨 Skin Workshop (Create Skins)…"),
            action: #selector(openSkinWorkshop),
            keyEquivalent: ""
        )
        topWorkshopItem.target = self
        menu.addItem(topWorkshopItem)

        let websiteItem = NSMenuItem(
            title: tr("🌐 软件官网 (kurocat.cc)", "🌐 Website (kurocat.cc)"),
            action: #selector(openWebsite),
            keyEquivalent: ""
        )
        websiteItem.target = self
        menu.addItem(websiteItem)

        let levelKbItem = NSMenuItem(
            title: tr("键盘水平摆放（平行屏幕）", "Level Keyboard (Parallel to Screen)"),
            action: #selector(toggleLevelKeyboard),
            keyEquivalent: ""
        )
        levelKbItem.target = self
        levelKbItem.state = settings.levelKeyboard ? .on : .off
        menu.addItem(levelKbItem)

        let settingsItem = NSMenuItem(title: tr("⚙️ 设置…", "⚙️ Settings…"), action: #selector(openSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let testToastItem = NSMenuItem(title: "🕒 测试整点报时弹窗", action: #selector(testHourlyToast), keyEquivalent: "")
        testToastItem.target = self
        menu.addItem(testToastItem)

        let relaunchItem = NSMenuItem(title: tr("重启 KuroCat", "Restart KuroCat"), action: #selector(relaunchApp), keyEquivalent: "")
        relaunchItem.target = self
        menu.addItem(relaunchItem)

        let quitItem = NSMenuItem(title: tr("退出 KuroCat", "Quit KuroCat"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func openSettingsWindow() {
        if settingsWindow == nil {
            let ctrl = SettingsWindowController()
            ctrl.onSettingsChanged = { [weak self] in
                self?.wakeToActive(immediateRedraw: true)
                self?.dressingRoom?.refresh()
            }
            ctrl.onScaleChanged = { [weak self] newScale in
                self?.overlayWindow.applyScale(newScale)
                self?.wakeToActive()
            }
            ctrl.onResetPoseAndPosition = { [weak self] in
                self?.overlayWindow.applyScale(1.0)
                self?.overlayWindow.resetPosition()
                self?.wakeToActive(immediateRedraw: true)
            }
            ctrl.onOpenDressingRoom = { [weak self] in
                self?.showDressingRoom()
            }
            ctrl.onSkinsDirectoryChanged = { [weak self] in
                self?.overlayWindow.catView.needsDisplay = true
                self?.dressingRoom?.refresh()
            }
            ctrl.onRenameSkin = { [weak self] id in
                self?.performRenameSkin(id: id)
            }
            ctrl.onDeleteSkin = { [weak self] id in
                self?.performDeleteSkin(id: id)
            }
            ctrl.onImportKeyboardSkin = { [weak self] in
                self?.promptImportKeyboardSkin()
            }
            ctrl.onApplyWindowLevel = { [weak self] in
                self?.overlayWindow.applyWindowLevelAndBehavior()
                self?.syncWindowTopmost()
            }
            ctrl.onApplyOBSMode = { [weak self] in
                self?.overlayWindow.applyOBSMode()
                self?.wakeToActive(immediateRedraw: true)
            }
            ctrl.onAutoHideChanged = { [weak self] in
                guard let self else { return }
                if !CatSettings.shared.autoHideFullscreen && self.hiddenByFullscreen {
                    self.hiddenByFullscreen = false
                    self.overlayWindow.alphaValue = 1.0
                    self.wakeToActive(immediateRedraw: true)
                }
            }
            ctrl.getAutoStart = { [weak self] in
                self?.isAutoStartEnabled() ?? false
            }
            ctrl.setAutoStart = { [weak self] on in
                _ = self?.setAutoStartEnabled(on)
            }
            ctrl.onLanguageChanged = { [weak self] in
                self?.wakeToActive(immediateRedraw: true)
            }
            settingsWindow = ctrl
        }
        settingsWindow?.present()
    }

    // MARK: - Actions

    @objc private func openInputMonitoringSettings() {
        if InputEngine.shared.status == .needsRestart {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "已授权，键盘监听启动失败"
            alert.informativeText = "请重启 KuroCat，让系统重新建立键盘监听。\n当前程序位置：\(Bundle.main.bundlePath)"
            alert.addButton(withTitle: "重启 KuroCat")
            alert.addButton(withTitle: "打开输入监控")
            alert.addButton(withTitle: "取消")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                relaunchApp()
                return
            }
            if response != .alertSecondButtonReturn { return }
        }
        InputEngine.shared.requestPermissionsAndOpenSettings()
    }

    @objc private func toggleVisibility() {
        isPetVisible.toggle()
        if isPetVisible {
            lastFrameTime = CACurrentMediaTime()
            overlayWindow.orderFrontRegardless()
            wakeToActive(immediateRedraw: true)
        } else {
            configureRenderTimer(for: .paused)
            overlayWindow.orderOut(nil)
        }
    }

    @objc private func selectTabletMode(_ sender: NSMenuItem) {
        if let mode = sender.representedObject as? Int {
            CatSettings.shared.tabletMode = mode
            wakeToActive(immediateRedraw: true)
        }
    }

    @objc private func toggleClickThrough() {
        CatSettings.shared.fullClickThrough.toggle()
    }

    @objc private func toggleFullScreenOverlay() {
        CatSettings.shared.fullScreenOverlay.toggle()
        overlayWindow.applyWindowLevelAndBehavior()
        syncWindowTopmost()
    }

    // MARK: - Topmost Watchdog (Space / App Activation)

    private func startWindowWatchdog() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(handleWorkspaceStateChanged),
                       name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleWorkspaceStateChanged),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)

        windowWatchdogTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.syncWindowTopmost()
        }
        timer.tolerance = 0.4
        RunLoop.main.add(timer, forMode: .common)
        windowWatchdogTimer = timer
    }

    @objc private func handleWorkspaceStateChanged() {
        syncWindowTopmost()
    }

    private func syncWindowTopmost() {
        guard let overlayWindow, isPetVisible, !hiddenByFullscreen, !screensAsleep else { return }
        let s = CatSettings.shared
        let obsBg = (s.obsCaptureMode > 0 && s.obsHideDesktop)
        if obsBg { return }
        if s.fullScreenOverlay {
            overlayWindow.orderFrontRegardless()
        }
    }

    // MARK: - Launch at Login (macOS LaunchAgent — works reliably for signed & ad-hoc builds)

    private var launchAgentURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        return dir.appendingPathComponent("com.chanke.kurocat.plist")
    }

    private func isAutoStartEnabled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    @discardableResult
    private func setAutoStartEnabled(_ enable: Bool) -> Bool {
        let fm = FileManager.default
        let url = launchAgentURL
        if enable {
            do {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let appPath = Bundle.main.bundlePath
                let plist: [String: Any] = [
                    "Label": "com.chanke.kurocat",
                    "ProgramArguments": ["/usr/bin/open", "-a", appPath],
                    "RunAtLoad": true,
                    "KeepAlive": false
                ]
                let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                try data.write(to: url, options: .atomic)
                return true
            } catch {
                return false
            }
        } else {
            do {
                if fm.fileExists(atPath: url.path) {
                    try fm.removeItem(at: url)
                }
                return true
            } catch {
                return false
            }
        }
    }

    @objc private func toggleAutoStart() {
        _ = setAutoStartEnabled(!isAutoStartEnabled())
    }

    @objc private func toggleKeyBadges() {
        CatSettings.shared.showKeyBadges.toggle()
        wakeToActive(immediateRedraw: true)
    }

    @objc private func toggleMouseBadges() {
        CatSettings.shared.showMouseBadges.toggle()
        wakeToActive(immediateRedraw: true)
    }

    @objc private func toggleKeyLegends() {
        CatSettings.shared.showKeyLegends.toggle()
        wakeToActive(immediateRedraw: true)
    }

    @objc private func toggleFootEgg() {
        CatSettings.shared.footEasterEgg.toggle()
        wakeToActive(immediateRedraw: true)
    }

    @objc private func toggleTailEgg() {
        CatSettings.shared.tailEasterEgg.toggle()
        wakeToActive(immediateRedraw: true)
    }

    @objc private func toggleKeyboardMarquee() {
        CatSettings.shared.keyboardMarquee.toggle()
        wakeToActive(immediateRedraw: true)
    }

    @objc private func toggleLevelKeyboard() {
        CatSettings.shared.levelKeyboard.toggle()
        wakeToActive(immediateRedraw: true)
        settingsWindow?.refresh()
    }

    @objc private func togglePetInteraction() {
        CatSettings.shared.petInteraction.toggle()
    }

    @objc private func selectOBSCaptureMode(_ sender: NSMenuItem) {
        guard let num = sender.representedObject as? NSNumber else { return }
        CatSettings.shared.obsCaptureMode = num.intValue
        if num.intValue == 0 {
            CatSettings.shared.obsHideDesktop = false
        }
        overlayWindow.applyOBSMode()
        wakeToActive(immediateRedraw: true)
    }

    @objc private func toggleOBSHideDesktop() {
        CatSettings.shared.obsHideDesktop.toggle()
        overlayWindow.applyOBSMode()
        wakeToActive(immediateRedraw: true)
    }

    @objc private func toggleAutoHideFullscreen() {
        CatSettings.shared.autoHideFullscreen.toggle()
        if !CatSettings.shared.autoHideFullscreen && hiddenByFullscreen {
            hiddenByFullscreen = false
            overlayWindow.alphaValue = 1.0
            wakeToActive(immediateRedraw: true)
        }
    }

    private static func isOtherAppFullscreen() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              front.bundleIdentifier != "com.apple.finder" else {
            return false
        }
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let pid = front.processIdentifier
        for w in list {
            guard let ownerPID = w[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid,
                  let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = w[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            for screen in NSScreen.screens {
                if rect.width >= screen.frame.width - 2 && rect.height >= screen.frame.height - 2 {
                    return true
                }
            }
        }
        return false
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        CatSettings.shared.language = code
        wakeToActive(immediateRedraw: true)
    }

    @objc private func selectScale(_ sender: NSMenuItem) {
        guard let num = sender.representedObject as? NSNumber else { return }
        overlayWindow.applyScale(CGFloat(num.doubleValue))
        wakeToActive()
    }

    @objc private func selectCoatTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let coat = CatCoatTheme(rawValue: raw) else { return }
        CatSettings.shared.overrideSkinIris = false
        CatSettings.shared.customSkin = ""
        CatSettings.shared.coatTheme = coat
        // Auto-pair signature eye color (still freely overridable via 瞳色切换!)
        switch coat {
        case .classicBlack:
            CatSettings.shared.eyeTheme = .neonChartreuse
        case .siamese:
            CatSettings.shared.eyeTheme = .siameseBlue
        case .shorthair:
            CatSettings.shared.eyeTheme = .referenceHazel
        case .orangeWhite:
            CatSettings.shared.eyeTheme = .warmAmber
        case .doraemon:
            CatSettings.shared.eyeTheme = .iceCyan
        case .pikachu:
            CatSettings.shared.eyeTheme = .warmAmber
        }
        wakeToActive(immediateRedraw: true)
        dressingRoom?.refresh()
        settingsWindow?.refresh()
    }

    // MARK: - Imported skins (换装间)

    private static let skinWorkshopURLString = "https://chanke17.github.io/KuroCat-Workshop/"
    private static let keyboardPlazaURLString = "https://chanke17.github.io/KuroCat-Workshop/#keyboards"
    private static let websiteURLString = "https://kurocat.cc"

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            importDroppedFile(from: url)
        }
    }

    private func importDroppedFile(from url: URL) {
        if KeyboardSkinSpec.looksLikeKeyboardJSON(url) {
            importKeyboardSkin(from: url)
        } else if url.pathExtension.lowercased() == "kurocat" {
            importSkin(from: url)
        }
    }

    @objc private func openSkinWorkshop() {
        if let url = URL(string: Self.skinWorkshopURLString) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openWebsite() {
        if let url = URL(string: Self.websiteURLString) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openSkinsFolder() {
        let dir = SkinLibrary.directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc private func showDressingRoom() {
        if dressingRoom == nil {
            let controller = DressingRoomWindowController()
            controller.onImport = { [weak self] url in self?.importSkin(from: url) }
            dressingRoom = controller
        }
        dressingRoom?.present()
    }

    /// Validates and stores a `.kurocat`, then wears it. Invalid files get a Chinese explanation.
    private func importSkin(from url: URL) {
        do {
            let id = try SkinLibrary.shared.importFile(url)
            CatSettings.shared.overrideSkinIris = false
            CatSettings.shared.customSkin = id
            let skin = SkinLibrary.shared.skin(id: id)
            var message = "已换上「\(skin?.name ?? "新皮肤")」"
            if let author = skin?.author, !author.isEmpty { message += "（作者：\(author)）" }
            if let sk = skin, SkinLibrary.shared.skins.filter({ $0.name == sk.name }).count > 1 {
                message += " · 存在同名皮肤，已附加短编号区分"
            }
            dressingRoom?.setStatus("✓ " + message, kind: 1)
            wakeToActive(immediateRedraw: true)
            dressingRoom?.refresh()
            settingsWindow?.refresh()
        } catch {
            let reason = error.localizedDescription
            // With 换装间 open the red status line explains it in place; an alert is only for drops onto the cat.
            if let room = dressingRoom, room.isVisible {
                room.setStatus("没能导入「\(url.lastPathComponent)」：\(reason)", kind: 2)
                return
            }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "无法导入这个皮肤"
            alert.informativeText = "「\(url.lastPathComponent)」：\(reason)"
            alert.addButton(withTitle: "知道了")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func selectCustomSkin(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        CatSettings.shared.overrideSkinIris = false
        CatSettings.shared.customSkin = id
        wakeToActive(immediateRedraw: true)
        dressingRoom?.refresh()
        settingsWindow?.refresh()
    }

    @objc private func renameCustomSkin(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        performRenameSkin(id: id)
    }

    private func performRenameSkin(id: String) {
        guard let skin = SkinLibrary.shared.skin(id: id) else { return }
        let en = CatSettings.shared.isEnglish
        let alert = NSAlert()
        alert.messageText = en ? "Rename Skin" : "重命名皮肤"
        alert.informativeText = en ? "Enter a new name for \"\(skin.name)\" (up to 40 characters):" : "为「\(skin.name)」输入新的名称（最多 40 字）："
        alert.addButton(withTitle: en ? "Rename" : "保存")
        alert.addButton(withTitle: en ? "Cancel" : "取消")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = skin.name
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let newName = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if newName.isEmpty || newName == skin.name { return }
        do {
            let newId = try SkinLibrary.shared.rename(id: id, newName: newName)
            if CatSettings.shared.customSkin == id {
                CatSettings.shared.customSkin = newId
            }
            dressingRoom?.refresh()
            settingsWindow?.refresh()
        } catch {
            let failed = NSAlert()
            failed.alertStyle = .warning
            failed.messageText = en ? "Rename Failed" : "重命名失败"
            failed.informativeText = error.localizedDescription
            failed.runModal()
        }
    }

    @objc private func deleteCustomSkin(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        performDeleteSkin(id: id)
    }

    private func performDeleteSkin(id: String) {
        guard let skin = SkinLibrary.shared.skin(id: id) else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "删除皮肤「\(skin.name)」？"
        alert.informativeText = "会从皮肤文件夹里删除这个文件，删除后需要重新导入。"
        let delBtn = alert.addButton(withTitle: "🗑 删除")
        if #available(macOS 11.0, *) { delBtn.hasDestructiveAction = true }
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if !SkinLibrary.shared.remove(id: id) {
            let failed = NSAlert()
            failed.messageText = "删除失败"
            failed.informativeText = "无法删除 \(SkinLibrary.directory.appendingPathComponent("\(id).kurocat").path)"
            failed.runModal()
            return
        }
        if CatSettings.shared.customSkin == id { CatSettings.shared.customSkin = "" }
        wakeToActive(immediateRedraw: true)
        dressingRoom?.refresh()
        settingsWindow?.refresh()
    }

    @objc private func selectKeyboardTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let theme = KeyboardTheme(rawValue: raw) else { return }
        CatSettings.shared.customKeyboard = ""
        CatSettings.shared.keyboardTheme = theme
        wakeToActive(immediateRedraw: true)
    }

    @objc private func selectCustomKeyboard(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        CatSettings.shared.customKeyboard = id
        wakeToActive(immediateRedraw: true)
    }

    @objc private func openKeyboardPlaza() {
        if let url = URL(string: Self.keyboardPlazaURLString) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openKeyboardsFolder() {
        let dir = KeyboardSkinLibrary.directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc private func promptImportKeyboardSkin() {
        let en = CatSettings.shared.isEnglish
        let panel = NSOpenPanel()
        panel.title = en ? "Choose Keyboard Skin (.kurokb / .json)" : "选择键盘皮肤文件 (.kurokb / .json)"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["kurokb", "json"]
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            importKeyboardSkin(from: url)
        }
    }

    private func importKeyboardSkin(from url: URL) {
        do {
            let id = try KeyboardSkinLibrary.shared.importFile(url)
            CatSettings.shared.customKeyboard = id
            let kb = KeyboardSkinLibrary.shared.skin(id: id)
            var message = "已换上键盘皮肤「\(kb?.name ?? "新键盘")」"
            if let author = kb?.author, !author.isEmpty { message += "（作者：\(author)）" }
            dressingRoom?.setStatus("✓ " + message, kind: 1)
            wakeToActive(immediateRedraw: true)
            settingsWindow?.refresh()
        } catch {
            let en = CatSettings.shared.isEnglish
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = en ? "Failed to Import Keyboard Skin" : "无法导入这个键盘皮肤"
            alert.informativeText = "「\(url.lastPathComponent)」：\(error.localizedDescription)"
            alert.addButton(withTitle: en ? "OK" : "知道了")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func deleteCustomKeyboard(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let kb = KeyboardSkinLibrary.shared.skin(id: id) else { return }
        let alert = NSAlert()
        alert.messageText = "删除键盘皮肤「\(kb.name)」？"
        alert.informativeText = "会从键盘皮肤文件夹里删除这个文件，删除后需要重新导入。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if !KeyboardSkinLibrary.shared.remove(id: id) {
            let failed = NSAlert()
            failed.messageText = "删除失败"
            failed.informativeText = "无法删除 \(KeyboardSkinLibrary.directory.appendingPathComponent("\(id).kurokb").path)"
            failed.runModal()
            return
        }
        if CatSettings.shared.customKeyboard == id { CatSettings.shared.customKeyboard = "" }
        wakeToActive(immediateRedraw: true)
        settingsWindow?.refresh()
    }

    @objc private func selectEyeTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let theme = EyeColorTheme(rawValue: raw) else { return }
        CatSettings.shared.overrideSkinIris = true
        CatSettings.shared.eyeTheme = theme
        dressingRoom?.refresh()
        settingsWindow?.refresh()
        wakeToActive(immediateRedraw: true)
    }

    @objc private func resetPosition() {
        overlayWindow.resetPosition()
    }

    @objc private func runDemoBurst() {
        let keys: [PhysicalKey] = [.w, .a, .s, .d, .f, .j, .o, .e, .space, .leftShift]
        wakeToActive()
        for (idx, k) in keys.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(idx) * 0.13) { [weak self] in
                guard let self else { return }
                let now = CACurrentMediaTime()
                self.lastDemoKeyTime = now
                self.overlayWindow.catView.physics.triggerKeyDown(k, at: now)
                self.wakeToActive()
            }
        }
    }

    @objc private func testHourlyToast() {
        let cal = Calendar.current
        let now = Date()
        let hour = cal.component(.hour, from: now)
        showHourlyToast(hour: hour)
    }

    @objc private func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Crisp Vector Menu Bar Cat Silhouette Icon

    private func makeMenuBarCatIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.black.cgColor)

            // Cute cat head silhouette with ears
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 3.0, y: 8.5))
            path.addLine(to: CGPoint(x: 3.5, y: 2.5))
            path.addLine(to: CGPoint(x: 7.2, y: 6.0))
            path.addQuadCurve(to: CGPoint(x: 10.8, y: 6.0), control: CGPoint(x: 9.0, y: 5.5))
            path.addLine(to: CGPoint(x: 14.5, y: 2.5))
            path.addLine(to: CGPoint(x: 15.0, y: 8.5))
            path.addCurve(to: CGPoint(x: 9.0, y: 15.5), control1: CGPoint(x: 16.0, y: 12.8), control2: CGPoint(x: 13.0, y: 15.5))
            path.addCurve(to: CGPoint(x: 3.0, y: 8.5), control1: CGPoint(x: 5.0, y: 15.5), control2: CGPoint(x: 2.0, y: 12.8))
            path.closeSubpath()

            // Punch out cute cat eyes
            path.addEllipse(in: CGRect(x: 5.4, y: 8.8, width: 2.4, height: 2.2))
            path.addEllipse(in: CGRect(x: 10.2, y: 8.8, width: 2.4, height: 2.2))

            ctx.addPath(path)
            ctx.fillPath(using: .evenOdd)
            return true
        }
        img.isTemplate = true
        return img
    }

    // MARK: - Hourly Announcement

    private func startHourlyAnnouncement() {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.second], from: now)
        let secondsUntilNextMinute = Double(60 - (components.second ?? 0))
        DispatchQueue.main.asyncAfter(deadline: .now() + secondsUntilNextMinute) { [weak self] in
            guard let self else { return }
            self.checkAndAnnounceHourly()
            self.minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                self?.checkAndAnnounceHourly()
            }
            RunLoop.main.add(self.minuteTimer!, forMode: .common)
        }
    }

    private func checkAndAnnounceHourly() {
        guard CatSettings.shared.hourlyAnnouncement else { return }
        let cal = Calendar.current
        let now = Date()
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let second = cal.component(.second, from: now)
        if minute == 0 && second < 5 && hour != lastAnnouncedHour {
            lastAnnouncedHour = hour
            showHourlyToast(hour: hour)
        }
    }

    private func showHourlyToast(hour: Int) {
        let period: String
        let displayHour: Int
        if hour == 0 {
            period = "凌晨"; displayHour = 12
        } else if hour < 6 {
            period = "凌晨"; displayHour = hour
        } else if hour == 12 {
            period = "中午"; displayHour = 12
        } else if hour < 12 {
            period = "上午"; displayHour = hour
        } else {
            period = hour < 18 ? "下午" : "晚上"
            displayHour = hour - 12
        }
        let text = "🕐 \(period) \(displayHour) 点整"
        overlayWindow.catView.showToast(text: text)
        wakeToActive(immediateRedraw: true)
    }
}
