import AppKit
import CoreGraphics

final class RenderSettings {
    static let shared = RenderSettings()
    var coatTheme = CatCoatTheme.pikachu
    var eyeTheme = EyeColorTheme.warmAmber
    var keyboardTheme = KeyboardTheme.classicMilk
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

func render(_ p: CatPhysics) -> CGImage {
    let ctx = CGContext(data: nil, width: 720, height: 640, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: 640); ctx.scaleBy(x: 2, y: -2)
    CatRenderer.draw(in: ctx, physics: p, showPermissionPill: false)
    return ctx.makeImage()!
}
func save(_ image: CGImage, _ name: String) throws {
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try data.write(to: output.appendingPathComponent(name))
}
func crop(_ image: CGImage, _ rect: CGRect) -> Data {
    let cropped = image.cropping(to: rect)!
    return cropped.dataProvider!.data! as Data
}

let idle = render(physics(0))
let typing = render(physics(3))
let face = CGRect(x: 265, y: 96, width: 215, height: 208)
precondition(crop(idle, face) == crop(typing, face), "A reaching arm changed the face")
let eyes = CGRect(x: 285, y: 175, width: 160, height: 42)
precondition(crop(idle, eyes) != crop(render(physics(4)), eyes), "Petting does not close the eyes")
precondition(crop(idle, eyes) != crop(render(physics(1)), eyes), "Eyes do not follow the pointer")
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
