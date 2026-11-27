import CoreGraphics
import Foundation
import ImageIO

struct DoraemonRenderer {
    private let head: CGImage
    private let body: CGImage
    private let hand: CGImage
    private let rightFoot: CGImage
    private let shoulderMask: CGImage

    // These layers share the seated pose drawn by scripts/generate-doraemon-pose.swift.
    static let bundled: DoraemonRenderer? = {
        func image(_ name: String) -> CGImage? {
            guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Doraemon"),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary)
        }
        guard let head = image("head"), let body = image("body"), let hand = image("hand"),
              let rightFoot = image("foot-right"), let shoulderMask = image("shoulder-mask") else { return nil }
        return DoraemonRenderer(head: head, body: body, hand: hand, rightFoot: rightFoot, shoulderMask: shoulderMask)
    }()

    private static let ink = CGColor(srgbRed: 0.044, green: 0.067, blue: 0.085, alpha: 1)
    private static let restingOutlineFade = CGGradient(colorsSpace: nil,
                                                      colors: [ink.copy(alpha: 0)!, ink] as CFArray,
                                                      locations: nil)
    private static let coatBlue = CGColor(srgbRed: 0, green: 159.0/255, blue: 222.0/255, alpha: 1)
    private static let handCenter = CGPoint(x: 99, y: 107.2)
    private static let bodyScale: CGFloat = 1.6
    private static let figureArtwork = CGAffineTransform(translationX: 64, y: 128)
        .scaledBy(x: 1.12, y: 1.12)
        .translatedBy(x: -64, y: -128)
    private static let shoulderMaskTransform = figureArtwork.translatedBy(x: 0, y: 128).scaledBy(x: 1, y: -1)
    private static let shoulderMaskBounds = CGRect(x: -64, y: -64, width: 256, height: 256)
    static let scruffGrip = CGPoint(x: KuroRig.seatX, y: KuroRig.doraemonCanvasGripY)

    private struct Pose {
        let body: CGAffineTransform
        let head: CGAffineTransform
        let torso: CGAffineTransform
        let drag: CharacterDragPose

        init(_ physics: CatPhysics) {
            let seat = CatPhysics.seatAnchor
            let drag = CharacterDragPose(physics)
            self.drag = drag
            let seated = CGAffineTransform(translationX: seat.x + physics.bodyShiftX.value, y: seat.y + 24)
                .rotated(by: physics.bodyTilt.value * 0.65 * (1 - drag.lift))
                .scaledBy(x: bodyScale, y: bodyScale)
                .translatedBy(x: -64, y: -128)

            let yaw = physics.headYaw.value
            let breath = sin(physics.time * 2.1) * 0.55
            head = CGAffineTransform(translationX: 64 + yaw * 1.4,
                                     y: 78 + physics.headPitch.value * 0.85 + breath)
                .rotated(by: physics.headTilt.value * 0.45)
                .translatedBy(x: -64, y: -78)
            let grip = CGPoint(x: 64, y: KuroRig.doraemonArtGripY).applying(head).applying(figureArtwork)
            body = drag.hangingBody(seated, localGrip: grip, canvasGrip: scruffGrip)
            torso = drag.torso(shoulderY: 86)
        }

        func wrists(_ physics: CatPhysics) -> (left: Wrist, right: Wrist) {
            let toSprite = body.inverted()
            let left = wristPose(paw: physics.leftPaw.point, rest: CatPhysics.leftPawRest,
                                 idleHand: CGPoint(x: 27.5, y: 98.1), toSprite: toSprite)
            let right = wristPose(paw: physics.rightPaw.point, rest: CatPhysics.rightPawRest,
                                  idleHand: CGPoint(x: 100.5, y: 98.1), toSprite: toSprite)
            func suspend(_ wrist: Wrist, side: CGFloat, y: CGFloat) -> Wrist {
                let hanging = CGPoint(x: 64 + side * KuroRig.doraemonWristSpread, y: y)
                return (drag.wrist(wrist.point, hanging: hanging), wrist.reach * (1 - drag.lift))
            }
            return (suspend(left, side: -1, y: KuroRig.doraemonWristY),
                    suspend(right, side: 1, y: KuroRig.doraemonKeyboardWristY))
        }
    }

    private typealias Wrist = (point: CGPoint, reach: CGFloat)

    static func dragHands(_ physics: CatPhysics) -> (left: CGPoint, right: CGPoint) {
        let pose = Pose(physics)
        let hands = pose.wrists(physics)
        return (hands.left.point.applying(pose.body), hands.right.point.applying(pose.body))
    }

    static func hitTest(point: CGPoint, physics: CatPhysics) -> CatHitZone? {
        let pose = Pose(physics)
        let local = point.applying(pose.body.inverted())
        let face = local.applying(figureArtwork.inverted()).applying(pose.head.inverted())
        if pow((face.x - 64) / 39, 2) + pow((face.y - 46) / 34, 2) <= 1 { return .head }
        let body = local.applying(pose.torso.inverted()).applying(figureArtwork.inverted())
        if pow((body.x - 64) / 44, 2) + pow((body.y - 105) / 24, 2) <= 1 { return .body }
        return nil
    }

    func draw(in ctx: CGContext, physics: CatPhysics, eyeColor: CGColor, keyboardDeck: CGPath) {
        let pose = Pose(physics)
        let toSprite = pose.body.inverted()

        ctx.saveGState()
        ctx.interpolationQuality = .high
        ctx.concatenate(pose.body)

        ctx.saveGState()
        let visibleBody = CGMutablePath()
        visibleBody.addRect(CGRect(origin: .zero, size: CatPhysics.canvasSize), transform: toSprite)
        visibleBody.addPath(keyboardDeck, transform: toSprite)
        ctx.addPath(visibleBody)
        ctx.clip(using: .evenOdd)
        ctx.concatenate(pose.torso)
        ctx.concatenate(Self.figureArtwork)
        drawSprite(body, in: ctx)
        drawSprite(rightFoot, in: ctx)
        ctx.restoreGState()

        let (leftHand, rightHand) = pose.wrists(physics)
        drawSleeve(in: ctx, wrist: leftHand.point, reach: leftHand.reach, isLeft: true)
        drawSleeve(in: ctx, wrist: rightHand.point, reach: rightHand.reach, isLeft: false)
        drawHand(in: ctx, at: leftHand.point)
        drawHand(in: ctx, at: rightHand.point)

        ctx.concatenate(Self.figureArtwork)
        ctx.concatenate(pose.head)
        drawSprite(head, in: ctx)
        drawEyes(in: ctx, physics: physics, tint: eyeColor)
        ctx.restoreGState()
    }

    private static func wristPose(paw: CGPoint, rest: CGPoint, idleHand: CGPoint,
                                  toSprite: CGAffineTransform) -> Wrist {
        let distance = hypot(paw.x - rest.x, paw.y - rest.y)
        let progress = min(1, distance / 10)
        let reach = progress * progress * (3 - 2 * progress)
        let target = paw.applying(toSprite)
        let point = CGPoint(x: idleHand.x + (target.x - idleHand.x) * reach,
                            y: idleHand.y + (target.y - idleHand.y) * reach)
        return (point, reach)
    }

    private func drawHand(in ctx: CGContext, at point: CGPoint) {
        drawSprite(hand, in: ctx, offset: CGPoint(x: point.x - Self.handCenter.x, y: point.y - Self.handCenter.y))
    }

    private func drawSleeve(in ctx: CGContext, wrist: CGPoint, reach: CGFloat, isLeft: Bool) {
        let side: CGFloat = isLeft ? -1 : 1
        let relaxed = 1 - reach
        let shoulder = CGPoint(x: 64 + side * (20 + 0.5 * relaxed), y: 86).applying(Self.figureArtwork)
        let dx = wrist.x - shoulder.x
        let dy = wrist.y - shoulder.y
        // In the resting pose the upper arm angles out toward the hand from the collar.
        let shoulderOutward = side * (0.38 + 0.30 * relaxed)
        let shoulderDown = 0.925 - 0.192 * relaxed
        let shoulderCurveLength = min(hypot(dx, dy) * 0.35, 10)
        let shoulderControl = CGPoint(x: shoulder.x + shoulderOutward * shoulderCurveLength,
                                      y: shoulder.y + shoulderDown * shoulderCurveLength)
        let wristControl = CGPoint(x: wrist.x - dx * 0.33, y: wrist.y - dy * 0.33)

        let sleeve = CGMutablePath()
        sleeve.move(to: shoulder)
        sleeve.addCurve(to: wrist, control1: shoulderControl, control2: wristControl)
        let sleeveWidth: CGFloat = 10.9
        let outlineWidth: CGFloat = 1.45

        ctx.saveGState()
        ctx.setLineCap(.butt)
        ctx.setStrokeColor(Self.ink)
        ctx.setLineWidth(sleeveWidth + outlineWidth)

        // Keep the short inner edge visible just above the hand in the resting pose.
        if relaxed > 0, let fade = Self.restingOutlineFade {
            ctx.saveGState()
            let innerEdge = CGRect(x: wrist.x - side * 8 - 7, y: wrist.y - 11, width: 14, height: 16)
            ctx.addEllipse(in: innerEdge)
            ctx.clip()
            ctx.setAlpha(relaxed)
            ctx.addPath(sleeve)
            ctx.replacePathWithStrokedPath()
            ctx.clip()
            ctx.drawLinearGradient(fade, start: CGPoint(x: wrist.x, y: wrist.y - 9),
                                   end: CGPoint(x: wrist.x, y: wrist.y - 4), options: .drawsAfterEndLocation)
            ctx.restoreGState()
        }

        // Preserve the arm outline where it overlaps the belly or feet.
        ctx.saveGState()
        let maskTransform = isLeft ? Self.shoulderMaskTransform
            : Self.shoulderMaskTransform.translatedBy(x: 128, y: 0).scaledBy(x: -1, y: 1)
        ctx.concatenate(maskTransform)
        ctx.clip(to: Self.shoulderMaskBounds, mask: shoulderMask)
        ctx.concatenate(maskTransform.inverted())
        ctx.addPath(sleeve)
        ctx.strokePath()
        ctx.restoreGState()

        ctx.addPath(sleeve)
        ctx.setStrokeColor(Self.coatBlue)
        ctx.setLineWidth(sleeveWidth - outlineWidth)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawEyes(in ctx: CGContext, physics: CatPhysics, tint: CGColor) {
        let closure = physics.effectiveEyeClosure
        let hunt = min(1, max(0, physics.huntIntensity.value))
        let gaze = physics.eyeGaze.point
        for side: CGFloat in [-1, 1] {
            let center = CGPoint(x: 64 + side * 8.1, y: 34.4)
            ctx.setFillColor(Self.ink)
            if closure >= 0.62 {
                ctx.setStrokeColor(Self.ink)
                ctx.setLineWidth(1.6)
                ctx.setLineCap(.round)
                ctx.move(to: CGPoint(x: center.x - 4, y: center.y + 2))
                ctx.addQuadCurve(to: CGPoint(x: center.x + 4, y: center.y + 2),
                                 control: CGPoint(x: center.x, y: center.y - (physics.isHappyClosedEyes ? 3 : 0)))
                ctx.strokePath()
            } else {
                let x = center.x - side * 1.0 + gaze.x * 2.4
                let y = center.y + 1.4 + gaze.y * 2.4
                let w = (2.1 + hunt * 1.8) * physics.pupilScale.value
                let h = (3.1 + hunt * 0.8) * (1 - closure)
                let pupil = CGRect(x: x - w, y: y - h, width: w * 2, height: h * 2)
                ctx.saveGState()
                ctx.addEllipse(in: CGRect(x: center.x - 7.3, y: center.y - 8.7, width: 14.6, height: 16.5))
                ctx.clip()
                if hunt > 0.01 {
                    ctx.setFillColor(tint.copy(alpha: hunt * 0.85) ?? tint)
                    ctx.fillEllipse(in: pupil.insetBy(dx: -1.1, dy: -1.1))
                    ctx.setFillColor(Self.ink)
                }
                ctx.fillEllipse(in: pupil)
                ctx.restoreGState()
            }
        }
    }

    private func drawSprite(_ image: CGImage, in ctx: CGContext, offset: CGPoint = .zero) {
        ctx.saveGState()
        ctx.translateBy(x: offset.x, y: 128 + offset.y)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 128, height: 128))
        ctx.restoreGState()
    }
}
