import AppKit
import CoreGraphics

final class RenderSettings {
    static let shared = RenderSettings()
    var coatTheme = CatCoatTheme.pikachu
    var characterCoat: CatCoatTheme? { coatTheme.supportsFootEasterEgg ? nil : coatTheme }
    var activeSkin: SkinSpec { SkinSpec.builtIn(coatTheme) }
    var eyeTheme = EyeColorTheme.warmAmber
    var keyboardTheme = KeyboardTheme.classicMilk
    var activeKeyboardSkin: KeyboardSkinSpec { KeyboardSkinSpec.builtIn(keyboardTheme) }
    let rotationDeg: CGFloat = 0
    let whiteOutline = true
    let overrideSkinIris = false
    var showKeyLegends = true
    let showKeyBadges = false
    let keyboardMarquee = false
    let obsCaptureMode = 0
    let flipHorizontal = false
    let isEditMode = false
    let isEnglish = false
    let scale: CGFloat = 1
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func physics(_ state: Int) -> CatPhysics {
    let p = CatPhysics()
    switch state {
    case 1:
        p.headYaw.value = -1; p.headPitch.value = -0.65; p.eyeGaze.x.value = -0.8
    case 2:
        p.headYaw.value = 1; p.headPitch.value = 0.65; p.eyeGaze.x.value = 0.8
    case 3:
        p.leftPaw.x.value = 78; p.leftPaw.y.value = 252; p.leftPawOnMouse = true
        p.rightPaw.x.value = 240; p.rightPaw.y.value = 268; p.rightPawTyping = true
    case 4:
        p.petHeadIntensity = 0.9; p.earFold.value = 0.55
    case 5:
        p.sleepiness = 1; p.earFold.value = 0.3
    case 6:
        p.huntIntensity.value = 1; p.pupilScale.value = 1.12
    case 7:
        p.tailTyping.value = 1; p.tailTip.x.value = 230; p.tailTip.y.value = 260
    case 8:
        p.scruffDrag.value = 1; p.scruffSwing.value = 0.34; p.bodySquash.value = 1.16
        p.headTilt.value = -0.18
    case 9:
        p.dizzyIntensity.value = 1; p.bodyTilt.value = -0.2; p.headTilt.value = 0.18
    default: break
    }
    return p
}

func render(_ p: CatPhysics, scale: Int = 2, doraemonOnly: Bool = false,
            keyboardCutout: CGPath? = nil) -> CGImage {
    let ctx = CGContext(data: nil, width: 360 * scale, height: 320 * scale, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(320 * scale)); ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
    if doraemonOnly {
        DoraemonRenderer.bundled!.draw(in: ctx, physics: p, eyeColor: NSColor.cyan.cgColor,
                                      keyboardDeck: keyboardCutout ?? CGMutablePath())
    } else {
        CatRenderer.draw(in: ctx, physics: p, showPermissionPill: false)
    }
    return ctx.makeImage()!
}
func save(_ image: CGImage, _ name: String) throws {
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try data.write(to: output.appendingPathComponent(name))
}

func renderMouseOnly(_ p: CatPhysics) -> CGImage {
    let ctx = CGContext(data: nil, width: 720, height: 640, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: 640); ctx.scaleBy(x: 2, y: -2)
    let hand = DoraemonRenderer.dragHands(p).left
    ctx.concatenate(CharacterDragPose(p).pointerTransform(physics: p, to: hand))
    CatRenderer.drawMouse(in: ctx, physics: p, kbSkin: RenderSettings.shared.activeKeyboardSkin)
    return ctx.makeImage()!
}
func crop(_ image: CGImage, _ rect: CGRect) -> Data {
    let cropped = image.cropping(to: rect)!
    return cropped.dataProvider!.data! as Data
}

func inkRows(in region: CGRect, of image: CGImage) -> Int {
    let bytes = image.dataProvider!.data! as Data
    return bytes.withUnsafeBytes { (pixels: UnsafeRawBufferPointer) in
        (Int(region.minY)..<Int(region.maxY)).filter { y in
            (Int(region.minX)..<Int(region.maxX)).contains { x in
                let offset = y * image.bytesPerRow + x * 4
                return pixels[offset] < 70 && pixels[offset + 1] < 70
                    && pixels[offset + 2] < 70 && pixels[offset + 3] > 220
            }
        }.count
    }
}

func opaqueConnected(in image: CGImage, from start: CGPoint, to end: CGPoint, scale: Int) -> Bool {
    let width = image.width, height = image.height
    let startIndex = Int(start.y * CGFloat(scale)) * width + Int(start.x * CGFloat(scale))
    let endIndex = Int(end.y * CGFloat(scale)) * width + Int(end.x * CGFloat(scale))
    let bytes = image.dataProvider!.data! as Data
    return bytes.withUnsafeBytes { (pixels: UnsafeRawBufferPointer) in
        var visited = [Bool](repeating: false, count: width * height)
        var pending = [startIndex]
        while let index = pending.popLast() {
            if visited[index] { continue }
            visited[index] = true
            let x = index % width, y = index / width
            if pixels[y * image.bytesPerRow + x * 4 + 3] < 200 { continue }
            if index == endIndex { return true }
            if x > 0 { pending.append(index - 1) }
            if x + 1 < width { pending.append(index + 1) }
            if y > 0 { pending.append(index - width) }
            if y + 1 < height { pending.append(index + width) }
        }
        return false
    }
}

func highlight(in region: CGRect, of image: CGImage) -> (center: CGPoint, area: Int) {
    precondition(image.bitsPerPixel == 32)
    let bytes = image.dataProvider!.data! as Data
    var area = 0
    var xTotal = 0
    var yTotal = 0
    bytes.withUnsafeBytes { (pixels: UnsafeRawBufferPointer) in
        for y in Int(region.minY)..<Int(region.maxY) {
            for x in Int(region.minX)..<Int(region.maxX) {
                let offset = y * image.bytesPerRow + x * 4
                if pixels[offset..<(offset + 4)].allSatisfy({ $0 >= 240 }) {
                    area += 1
                    xTotal += x
                    yTotal += y
                }
            }
        }
    }
    precondition(area > 0, "No white highlight detected in the eye")
    return (CGPoint(x: CGFloat(xTotal) / CGFloat(area), y: CGFloat(yTotal) / CGFloat(area)), area)
}

func renderGaze(x: CGFloat, y: CGFloat) -> CGImage {
    let p = physics(0)
    p.eyeGaze.x.value = x
    p.eyeGaze.y.value = y
    return render(p)
}

let idle = render(physics(0))
let typing = render(physics(3))
let face = CGRect(x: 265, y: 96, width: 215, height: 208)
precondition(crop(idle, face) == crop(typing, face), "A reaching arm changed the face")
let eyes = CGRect(x: 286, y: 210, width: 162, height: 55)
precondition(crop(idle, eyes) != crop(render(physics(4)), eyes), "Petting does not close the eyes")
let lookRight = renderGaze(x: 0.35, y: 0)
let lookDown = renderGaze(x: 0, y: 0.35)
let lookDownRight = renderGaze(x: 0.65, y: 0.65)
for eyeX in [286, 392] {
    let eye = CGRect(x: eyeX, y: 210, width: 56, height: 55)
    let resting = highlight(in: eye, of: idle)
    let right = highlight(in: eye, of: lookRight)
    let down = highlight(in: eye, of: lookDown)
    let diagonal = highlight(in: eye, of: lookDownRight)
    precondition(right.center.x > resting.center.x + 6, "Highlight travel to the right is too small")
    precondition(down.center.y > resting.center.y + 7, "Highlight travel downward is too small")
    precondition(diagonal.center.x > resting.center.x + 6 && diagonal.center.y > resting.center.y + 7,
                 "The highlight fails to follow a diagonal gaze")
    precondition(diagonal.area * 5 >= resting.area * 4, "The eye edge clips the highlight")
}
precondition(PikachuRenderer.hitTest(point: CGPoint(x: 184, y: 110), physics: physics(0)) == .head)
precondition(PikachuRenderer.hitTest(point: CGPoint(x: 184, y: 190), physics: physics(0)) == .body)
precondition(PikachuRenderer.hitTest(point: CGPoint(x: 10, y: 10), physics: physics(0)) == nil)
for state in 0...9 {
    let image = render(physics(state))
    try save(image, "pikachu-\(state).png")
    let pixels = image.dataProvider!.data! as Data
    precondition(pixels.filter { $0 != 0 }.count > 20_000, "Empty skin render in pose \(state)")
}

let sheet = CGContext(data: nil, width: 2160, height: 1360, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
sheet.setFillColor(NSColor(calibratedRed: 0.97, green: 0.96, blue: 0.93, alpha: 1).cgColor)
sheet.fill(CGRect(x: 0, y: 0, width: 2160, height: 1360))
let titles = ["正面坐姿", "向左看", "向右看", "键盘与鼠标", "摸头闭眼", "打瞌睡"]
for state in 0..<6 {
    let x = CGFloat(state % 3) * 720
    let y = CGFloat(1 - state / 3) * 680
    sheet.draw(render(physics(state)), in: CGRect(x: x, y: y + 40, width: 720, height: 640))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: sheet, flipped: false)
    let title = NSAttributedString(string: titles[state], attributes: [
        .font: NSFont.systemFont(ofSize: 24, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 0.3, alpha: 1)
    ])
    title.draw(at: CGPoint(x: x + (720 - title.size().width) / 2, y: y + 14))
    NSGraphicsContext.restoreGraphicsState()
}
try save(sheet.makeImage()!, "preview_pikachu.png")
print("PASS: Pikachu renders ten poses including scruff drag and dizzy; mouse/keyboard arms preserve the face; petting closes eyes; gaze tracks the pointer; head/body/transparent hit testing is correct")

precondition(DoraemonRenderer.bundled != nil, "The test bundle is missing Doraemon artwork")
for coat in [CatCoatTheme.doraemon, .pikachu] {
    RenderSettings.shared.coatTheme = coat
    RenderSettings.shared.eyeTheme = coat == .doraemon ? .iceCyan : .warmAmber
    let name = coat == .doraemon ? "doraemon" : "pikachu"
    let isPikachu = coat == .pikachu
    let hands = coat == .doraemon ? DoraemonRenderer.dragHands : PikachuRenderer.dragHands
    let grip = CatRenderer.scruffPinchCanvasPoint(skin: RenderSettings.shared.activeSkin, flipped: false, rotationDeg: 0)
    let rotated = CatRenderer.scruffPinchCanvasPoint(skin: RenderSettings.shared.activeSkin, flipped: true, rotationDeg: 25)
    let unrotated = CatRenderer.canvasPointToCatSpace(rotated, flipped: true, rotationDeg: 25)
    precondition(hypot(unrotated.x - grip.x, unrotated.y - grip.y) < 0.001, "The grip moved after rotation and mirroring")

    let pose = CatPhysics()
    let seated = render(pose)
    try save(seated, "\(name)-seated.png")
    let restingHands = hands(pose)
    pose.scruffDrag.value = 0.001
    let liftStart = hands(pose)
    precondition(hypot(liftStart.left.x - restingHands.left.x, liftStart.left.y - restingHands.left.y) < 0.01)
    precondition(hypot(liftStart.right.x - restingHands.right.x, liftStart.right.y - restingHands.right.y) < 0.01)
    pose.scruffDrag.value = 1
    pose.bodySquash.value = 1.16
    pose.headTilt.value = 0.4
    for swing in [-1.0, 0.0, 1.0] as [CGFloat] {
        pose.scruffSwing.value = swing
        pose.scruffTailSwing.value = swing
        precondition(CatRenderer.hitTest(point: grip, physics: pose, showPermissionPill: false) == .head,
                     "\(name) swings away from its drag grip")
        let wrists = hands(pose)
        precondition(wrists.left.x < wrists.right.x && wrists.left.y > grip.y && wrists.right.y > grip.y)
        let drag = CharacterDragPose(pose)
        let keyboard = drag.keyboardTransform(to: wrists.right, isPikachu: isPikachu)
        let carried = CharacterDragPose.keyboardGrip(isPikachu: isPikachu).applying(keyboard)
        precondition(hypot(carried.x - wrists.right.x, carried.y - wrists.right.y) < 0.001,
                     "The carried keyboard must meet the right wrist")
        pose.isTabletActive = true
        let tablet = drag.pointerTransform(physics: pose, to: wrists.left)
        pose.isTabletActive = false
        let mouse = drag.pointerTransform(physics: pose, to: wrists.left)
        for transform in [keyboard, tablet, mouse] {
            precondition(abs(hypot(transform.a, transform.b) - 1) < 0.001
                         && abs(hypot(transform.c, transform.d) - 1) < 0.001, "Carrying a device changed its size")
        }
        for level in [true, false] {
            KeyboardLayout.levelKeyboard = level
            for vertical in [-1.0, 0.0, 1.0] as [CGFloat] {
                pose.scruffSwingY.value = vertical
                for tilt in [-0.5, 0.5] as [CGFloat] {
                    pose.headTilt.value = tilt
                    let transform = CharacterDragPose(pose).keyboardTransform(to: hands(pose).right, isPikachu: isPikachu)
                    for (u, v) in [(-0.016, -0.04), (1.016, -0.04), (-0.016, 1.04), (1.016, 1.04)] as [(CGFloat, CGFloat)] {
                        var corner = KeyboardLayout.screenQuadPoint(su: u, sv: v)
                        if v > 1 { corner.y += 7.5 } // Include the chassis and its shadow.
                        let point = corner.applying(transform)
                        precondition(CGRect(origin: .zero, size: CatPhysics.canvasSize).contains(point),
                                     "\(name) keyboard outside the canvas at \(point), swing \(swing), vertical \(vertical), level \(level), tilt \(tilt)")
                    }
                }
            }
        }
        KeyboardLayout.levelKeyboard = true
        pose.scruffSwingY.value = 0
        pose.headTilt.value = 0.4
        let hanging = render(pose)
        if coat == .doraemon && swing == 0 {
            // Check the inner edges just below the collar, where the seated mask
            // used to erase the hanging sleeves. These strips exclude the hands.
            for region in [CGRect(x: 260, y: 332, width: 8, height: 12),
                           CGRect(x: 391, y: 332, width: 9, height: 12)] {
                precondition(inkRows(in: region, of: hanging) >= 10,
                             "Doraemon's hanging arm has lost its black inner outline")
            }
        }
        precondition(crop(seated, CGRect(x: 140, y: 40, width: 440, height: 530)) !=
                     crop(hanging, CGRect(x: 140, y: 40, width: 440, height: 530)), "Missing hanging pose")
        try save(hanging, "\(name)-drag-\(Int(swing)).png")
    }
    pose.scruffSwing.value = 0
    pose.isTabletActive = true
    try save(render(pose), "\(name)-drag-tablet.png")
}
print("PASS: Doraemon and Pikachu keep device size and keyboard clearance as they lift and swing")
print("PASS: both Doraemon hanging arms retain continuous black inner outlines below the collar")

let shoulderPose = CatPhysics()
shoulderPose.scruffDrag.value = 1
shoulderPose.headTilt.value = 0.4
for scale in [1, 2, 3, 4] {
    let image = render(shoulderPose, scale: scale, doraemonOnly: true)
    let bytes = image.dataProvider!.data! as Data
    bytes.withUnsafeBytes { (pixels: UnsafeRawBufferPointer) in
        // Flat blue areas crossing the two shoulder joins, away from the collar,
        // belly and arm outlines. Any dark diagonal here is an unwanted seam.
        for region in [CGRect(x: 122, y: 155.5, width: 8, height: 4.5),
                       CGRect(x: 200, y: 155, width: 6, height: 5)] {
            for y in Int(ceil(region.minY * CGFloat(scale)))..<Int(region.maxY * CGFloat(scale)) {
                for x in Int(region.minX * CGFloat(scale))..<Int(region.maxX * CGFloat(scale)) {
                    let offset = y * image.bytesPerRow + x * 4
                    // Image resampling can slightly brighten the coat at 1x;
                    // the unwanted butt-cap fringe instead darkens it.
                    precondition(pixels[offset] <= 3 && pixels[offset + 1] >= 156
                                 && pixels[offset + 2] >= 219 && pixels[offset + 3] >= 250,
                                 "Doraemon has a dark seam across the shoulder at scale \(scale), pixel \(x),\(y)")
                }
            }
        }
    }
}
RenderSettings.shared.coatTheme = .doraemon
for lift in [0.25, 0.5, 0.75, 1.0] as [CGFloat] {
    shoulderPose.scruffDrag.value = lift
    for swing in [-1.0, 0.0, 1.0] as [CGFloat] {
        shoulderPose.scruffSwing.value = swing
        shoulderPose.scruffSwingY.value = swing
        try save(render(shoulderPose), "doraemon-lift-\(Int(lift * 100))-swing-\(Int(swing)).png")
    }
}
print("PASS: Doraemon's shoulder joins remain flat blue without diagonal seams at 1x, 2x, 3x and 4x")

// Hide the entire torso as a deliberately oversized carried keyboard would.
// Both foreground arms must still join the head through the collar, rather
// than ending in an exposed diagonal cap on top of the keyboard.
let fullKeyboardCutout = CGPath(rect: CGRect(origin: .zero, size: CatPhysics.canvasSize), transform: nil)
let occludedPose = CatPhysics()
occludedPose.scruffDrag.value = 1
for scale in [1, 2, 4] {
    for swing in [-1.0, 0.0, 1.0] as [CGFloat] {
        occludedPose.scruffSwing.value = swing
        for vertical in [-1.0, 1.0] as [CGFloat] {
            occludedPose.scruffSwingY.value = vertical
            occludedPose.headTilt.value = vertical * 0.5
            let foreground = render(occludedPose, scale: scale, doraemonOnly: true,
                                    keyboardCutout: fullKeyboardCutout)
            let hands = DoraemonRenderer.dragHands(occludedPose)
            for hand in [hands.left, hands.right] {
                precondition(opaqueConnected(in: foreground, from: hand, to: CGPoint(x: 184, y: 90), scale: scale),
                             "A foreground Doraemon arm is disconnected above the keyboard at scale \(scale), swing \(swing), vertical \(vertical)")
            }
        }
    }
}
print("PASS: both Doraemon foreground arms stay connected to the collar when the keyboard hides the torso, across scales and swings")

RenderSettings.shared.coatTheme = .doraemon
let mousePose = CatPhysics()
mousePose.bodySquash.value = 1.16
mousePose.headTilt.value = 0.4
for lift in [0.5, 1.0] as [CGFloat] {
    mousePose.scruffDrag.value = lift
    for swing in [-1.0, 0.0, 1.0] as [CGFloat] {
        mousePose.scruffSwing.value = swing
        for vertical in [-1.0, 0.0, 1.0] as [CGFloat] {
            mousePose.scruffSwingY.value = vertical
            let mouse = renderMouseOnly(mousePose)
            let foreground = render(mousePose, doraemonOnly: true, keyboardCutout: fullKeyboardCutout)
            let scene = render(mousePose)
            let reference = mouse.dataProvider!.data! as Data
            let hands = foreground.dataProvider!.data! as Data
            let actual = scene.dataProvider!.data! as Data
            var visibleMousePixels = 0
            reference.withUnsafeBytes { (expected: UnsafeRawBufferPointer) in
                hands.withUnsafeBytes { (mask: UnsafeRawBufferPointer) in
                    actual.withUnsafeBytes { (pixels: UnsafeRawBufferPointer) in
                        for y in 0..<mouse.height {
                            for x in 0..<mouse.width {
                                let offset = y * mouse.bytesPerRow + x * 4
                                // Only the foreground hands may cover the opaque mouse.
                                if expected[offset + 3] != 255 || mask[offset + 3] != 0 { continue }
                                visibleMousePixels += 1
                                for channel in 0..<4 {
                                    precondition(abs(Int(pixels[offset + channel]) - Int(expected[offset + channel])) <= 2,
                                                 "A Doraemon foot hides the carried mouse at lift \(lift), swing \(swing), vertical \(vertical)")
                                }
                            }
                        }
                    }
                }
            }
            precondition(visibleMousePixels > 50, "The carried mouse is hidden by the hands")
            if lift == 1 && swing == 0 && vertical == 0 {
                try save(mouse, "mouse-reference.png")
                try save(foreground, "mouse-hand-mask.png")
            }
        }
    }
}
print("PASS: Doraemon's carried mouse stays in front of the feet and behind the hands in 18 lifting/swinging poses")
