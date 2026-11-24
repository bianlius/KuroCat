import Foundation
import AppKit

final class CatCanvasView: NSView {
    let physics = CatPhysics()
    var onRequestPermission: (() -> Void)?
    var onRightClickMenu: ((NSEvent) -> Void)?

    private var lastHoverCanvasPt: CGPoint?
    private var isDragging = false
    private var activeResizeCorner: Int = -1 // -1 = none, 0=TL, 1=TR, 2=BL, 3=BR
    private var resizeAnchorScreenPt: CGPoint = .zero
    private var resizeStartFrame: CGRect = .zero
    private var dragStartScreenPt: CGPoint = .zero
    private var dragStartWindowOrigin: CGPoint = .zero
    private var isShowingOpenHand = false

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)

        let scaleX = bounds.width / CatPhysics.canvasSize.width
        let scaleY = bounds.height / CatPhysics.canvasSize.height
        ctx.saveGState()
        ctx.scaleBy(x: scaleX, y: scaleY)

        let status = InputEngine.shared.status
        CatRenderer.draw(in: ctx, physics: physics, showPermissionPill: status.needsAttention,
                         permissionPillText: status.permissionPillText)

        ctx.restoreGState()
    }

    func canvasPoint(fromScreenPoint screenPt: CGPoint) -> CGPoint? {
        guard let win = window else { return nil }
        let frame = win.frame
        guard frame.contains(screenPt) else { return nil }
        let localX = (screenPt.x - frame.minX) / frame.width * CatPhysics.canvasSize.width
        // Convert bottom-up screen Y to flipped top-down canvas Y
        let localY = (frame.maxY - screenPt.y) / frame.height * CatPhysics.canvasSize.height
        return CGPoint(x: localX, y: localY)
    }

    /// Called on every 60fps tick to handle smart click-through AND petting strokes.
    func updateHoverAndClickThrough() {
        guard let win = window else { return }
        let screenPt = NSEvent.mouseLocation
        let showPill = InputEngine.shared.status.needsAttention

        if isDragging || activeResizeCorner >= 0 {
            win.ignoresMouseEvents = false
            return
        }

        guard let pt = canvasPoint(fromScreenPoint: screenPt) else {
            lastHoverCanvasPt = nil
            physics.updateTailHover(canvasPoint: nil)
            if !win.ignoresMouseEvents {
                win.ignoresMouseEvents = true
            }
            resetCursorIfNeeded()
            return
        }

        if CatSettings.shared.isEditMode {
            let editHit = CatRenderer.hitTestEditOverlay(point: pt)
            win.ignoresMouseEvents = (editHit < 0)
            if editHit == 10 || editHit == 11 {
                NSCursor.pointingHand.set()
                isShowingOpenHand = false
            } else if editHit >= 0 && editHit <= 3 {
                NSCursor.crosshair.set()
                isShowingOpenHand = false
            } else if editHit == 12 {
                if !isShowingOpenHand {
                    NSCursor.openHand.set()
                    isShowingOpenHand = true
                }
            } else {
                resetCursorIfNeeded()
            }
            return
        }

        let catPt = CatSettings.shared.flipHorizontal
            ? CGPoint(x: CatPhysics.canvasSize.width - pt.x, y: pt.y)
            : pt
        let zone = CatRenderer.hitTest(point: catPt, physics: physics, showPermissionPill: showPill)
        physics.updateTailHover(canvasPoint: catPt)

        // Petting triggers strictly on the cat's head (never on keyboard or torso)!
        if zone == .head {
            if let prev = lastHoverCanvasPt {
                let delta = hypot(catPt.x - prev.x, catPt.y - prev.y)
                if delta > 1.2 && delta < 80 {
                    physics.registerPetStroke(canvasPoint: catPt, delta: delta, isHead: true)
                }
            }
            lastHoverCanvasPt = catPt
        } else {
            lastHoverCanvasPt = nil
        }

        // Smart Click-Through logic (hold Option ⌥ to temporarily unlock Full Click-Through!)
        let optionHeld = NSEvent.modifierFlags.contains(.option)
        if CatSettings.shared.fullClickThrough && !optionHeld {
            // Keep permission pill clickable only if permission isn't granted yet
            win.ignoresMouseEvents = (zone != .permissionPill)
            resetCursorIfNeeded()
        } else {
            let shouldCapture = (zone != .none)
            if win.ignoresMouseEvents == shouldCapture {
                win.ignoresMouseEvents = !shouldCapture
            }
            if zone == .head || zone == .body {
                if !isShowingOpenHand {
                    NSCursor.openHand.set()
                    isShowingOpenHand = true
                }
            } else if zone == .permissionPill {
                NSCursor.pointingHand.set()
                isShowingOpenHand = false
            } else {
                resetCursorIfNeeded()
            }
        }
    }

    private func resetCursorIfNeeded() {
        if isShowingOpenHand {
            NSCursor.arrow.set()
            isShowingOpenHand = false
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let win = window else { return }
        let screenPt = NSEvent.mouseLocation
        let showPill = InputEngine.shared.status.needsAttention

        if let pt = canvasPoint(fromScreenPoint: screenPt) {
            if CatSettings.shared.isEditMode {
                let hit = CatRenderer.hitTestEditOverlay(point: pt)
                if hit == 10 {
                    CatSettings.shared.flipHorizontal.toggle()
                    needsDisplay = true
                    return
                }
                if hit == 11 {
                    CatSettings.shared.isEditMode = false
                    needsDisplay = true
                    return
                }
                if hit >= 0 && hit <= 3 {
                    activeResizeCorner = hit
                    resizeStartFrame = win.frame
                    // Anchor the opposite corner in screen space (AppKit Y is bottom-up)
                    let f = win.frame
                    switch hit {
                    case 0: resizeAnchorScreenPt = CGPoint(x: f.maxX, y: f.minY) // dragging TL -> anchor BR
                    case 1: resizeAnchorScreenPt = CGPoint(x: f.minX, y: f.minY) // dragging TR -> anchor BL
                    case 2: resizeAnchorScreenPt = CGPoint(x: f.maxX, y: f.maxY) // dragging BL -> anchor TR
                    default: resizeAnchorScreenPt = CGPoint(x: f.minX, y: f.maxY) // dragging BR -> anchor TL
                    }
                    return
                }
            }

            let catPt = CatSettings.shared.flipHorizontal
                ? CGPoint(x: CatPhysics.canvasSize.width - pt.x, y: pt.y)
                : pt
            let zone = CatRenderer.hitTest(point: catPt, physics: physics, showPermissionPill: showPill)
            if zone == .permissionPill {
                onRequestPermission?()
                return
            }

            // Double-clicking the cat toggles the interactive resize & flip box!
            if event.clickCount == 2 && (zone == .head || zone == .body || CatSettings.shared.isEditMode) {
                CatSettings.shared.isEditMode.toggle()
                needsDisplay = true
                return
            }
        }

        isDragging = true
        dragStartScreenPt = screenPt
        dragStartWindowOrigin = win.frame.origin
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let win = window else { return }
        let currentScreenPt = NSEvent.mouseLocation
        if activeResizeCorner >= 0 {
            let dx = abs(currentScreenPt.x - resizeAnchorScreenPt.x)
            let dy = abs(currentScreenPt.y - resizeAnchorScreenPt.y)
            let sx = dx / CatPhysics.canvasSize.width
            let sy = dy / CatPhysics.canvasSize.height
            let newScale = max(0.45, min(2.50, max(sx, sy)))
            let newW = CatPhysics.canvasSize.width * newScale
            let newH = CatPhysics.canvasSize.height * newScale
            let originX = (activeResizeCorner == 0 || activeResizeCorner == 2)
                ? (resizeAnchorScreenPt.x - newW)
                : resizeAnchorScreenPt.x
            let originY = (activeResizeCorner == 2 || activeResizeCorner == 3)
                ? (resizeAnchorScreenPt.y - newH)
                : resizeAnchorScreenPt.y
            CatSettings.shared.scale = newScale
            win.setFrame(CGRect(x: originX, y: originY, width: newW, height: newH), display: true)
            return
        }
        guard isDragging else { return }
        let newOrigin = CGPoint(
            x: dragStartWindowOrigin.x + (currentScreenPt.x - dragStartScreenPt.x),
            y: dragStartWindowOrigin.y + (currentScreenPt.y - dragStartScreenPt.y)
        )
        win.setFrameOrigin(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        guard let win = window else { return }
        if activeResizeCorner >= 0 {
            activeResizeCorner = -1
            UserDefaults.standard.set(Double(win.frame.origin.x), forKey: "KuroCat.PosX")
            UserDefaults.standard.set(Double(win.frame.origin.y), forKey: "KuroCat.PosY")
            return
        }
        guard isDragging else { return }
        isDragging = false
        NSCursor.openHand.set()
        // Save position
        UserDefaults.standard.set(Double(win.frame.origin.x), forKey: "KuroCat.PosX")
        UserDefaults.standard.set(Double(win.frame.origin.y), forKey: "KuroCat.PosY")
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClickMenu?(event)
    }
}

final class OverlayWindow: NSPanel {
    let catView = CatCanvasView()

    init() {
        let scale = CatSettings.shared.scale
        let size = CGSize(
            width: CatPhysics.canvasSize.width * scale,
            height: CatPhysics.canvasSize.height * scale
        )
        let origin = OverlayWindow.initialOrigin(for: size)

        super.init(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true

        applyWindowLevelAndBehavior()
        applyOBSMode()

        catView.frame = CGRect(origin: .zero, size: size)
        catView.autoresizingMask = [.width, .height]
        contentView = catView
    }

    func applyOBSMode() {
        let mode = CatSettings.shared.obsCaptureMode
        title = "KuroCat"
        sharingType = .readOnly
        if mode == 2 {
            isOpaque = true
            backgroundColor = NSColor(calibratedRed: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)
        } else {
            isOpaque = false
            backgroundColor = .clear
        }
        catView.needsDisplay = true
    }

    func applyWindowLevelAndBehavior() {
        if CatSettings.shared.fullScreenOverlay {
            level = .statusBar
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        } else {
            level = .floating
            collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        }
    }

    func applyScale(_ newScale: CGFloat) {
        CatSettings.shared.scale = newScale
        let oldFrame = frame
        let newSize = CGSize(
            width: CatPhysics.canvasSize.width * newScale,
            height: CatPhysics.canvasSize.height * newScale
        )
        // Anchor bottom-center so scaling feels grounded
        let newOrigin = CGPoint(
            x: oldFrame.midX - newSize.width * 0.5,
            y: oldFrame.minY
        )
        setFrame(CGRect(origin: newOrigin, size: newSize), display: true)
        UserDefaults.standard.set(Double(newOrigin.x), forKey: "KuroCat.PosX")
        UserDefaults.standard.set(Double(newOrigin.y), forKey: "KuroCat.PosY")
    }

    func resetPosition() {
        let origin = OverlayWindow.defaultOrigin(for: frame.size)
        setFrameOrigin(origin)
        UserDefaults.standard.set(Double(origin.x), forKey: "KuroCat.PosX")
        UserDefaults.standard.set(Double(origin.y), forKey: "KuroCat.PosY")
    }

    private static func initialOrigin(for size: CGSize) -> CGPoint {
        let d = UserDefaults.standard
        if d.object(forKey: "KuroCat.PosX") != nil && d.object(forKey: "KuroCat.PosY") != nil {
            let x = CGFloat(d.double(forKey: "KuroCat.PosX"))
            let y = CGFloat(d.double(forKey: "KuroCat.PosY"))
            let saved = CGPoint(x: x, y: y)
            // Ensure saved origin is still on a connected display
            let rect = CGRect(origin: saved, size: size)
            if NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) {
                return saved
            }
        }
        return defaultOrigin(for: size)
    }

    private static func defaultOrigin(for size: CGSize) -> CGPoint {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGPoint(
            x: screen.maxX - size.width - 28,
            y: screen.minY + 18
        )
    }
}
