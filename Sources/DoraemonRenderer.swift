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
    private static let coatBlue = CGColor(srgbRed: 0, green: 159.0/255, blue: 222.0/255, alpha: 1)
    private static let handCenter = CGPoint(x: 99, y: 107.2)
    private static let figureArtwork = CGAffineTransform(translationX: 64, y: 128)
        .scaledBy(x: 1.12, y: 1.12)
        .translatedBy(x: -64, y: -128)
    private static let shoulderMaskTransform = figureArtwork.translatedBy(x: 0, y: 128).scaledBy(x: 1, y: -1)
    private static let shoulderMaskBounds = CGRect(x: -64, y: -64, width: 256, height: 256)

    private struct Pose {
        let body: CGAffineTransform
        let head: CGAffineTransform

        init(_ physics: CatPhysics) {
            let seat = CatPhysics.seatAnchor
            let size = 1.50 * (1 - physics.huntIntensity.value * 0.05)
            body = CGAffineTransform(translationX: seat.x + physics.bodyShiftX.value, y: seat.y + 24)
                .rotated(by: physics.bodyTilt.value * 0.65)
                .scaledBy(x: size, y: size)
                .translatedBy(x: -64, y: -128)

            let yaw = physics.headYaw.value
            let breath = sin(physics.time * 2.1) * 0.55
            head = CGAffineTransform(translationX: 64 + yaw * 1.4,
                                     y: 78 + physics.headPitch.value * 0.85 + breath)
                .rotated(by: physics.headTilt.value * 0.45)
                .scaledBy(x: 1 - abs(yaw) * 0.035, y: 1)
                .translatedBy(x: -64, y: -78)
        }
    }

    static func hitTest(point: CGPoint, physics: CatPhysics) -> CatHitZone? {
        let pose = Pose(physics)
        let body = point.applying(pose.body.inverted()).applying(figureArtwork.inverted())
        let face = body.applying(pose.head.inverted())
        if pow((face.x - 64) / 39, 2) + pow((face.y - 46) / 34, 2) <= 1 { return .head }
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
        ctx.concatenate(Self.figureArtwork)
        drawSprite(body, in: ctx)
        drawSprite(rightFoot, in: ctx)
        ctx.restoreGState()

        let leftShoulder = CGPoint(x: 43, y: 87.5).applying(Self.figureArtwork)
        let rightShoulder = CGPoint(x: 85, y: 87.5).applying(Self.figureArtwork)
        let leftHand = wristPose(paw: physics.leftPaw.point, rest: CatPhysics.leftPawRest,
                                 idleHand: CGPoint(x: 27.5, y: 98.1), toSprite: toSprite)
        let rightHand = wristPose(paw: physics.rightPaw.point, rest: CatPhysics.rightPawRest,
                                  idleHand: CGPoint(x: 100.5, y: 98.1), toSprite: toSprite)
        drawSleeve(in: ctx, shoulder: leftShoulder, wrist: leftHand.point, reach: leftHand.reach)
        drawSleeve(in: ctx, shoulder: rightShoulder, wrist: rightHand.point, reach: rightHand.reach)
        drawHand(in: ctx, at: leftHand.point)
        drawHand(in: ctx, at: rightHand.point)

        ctx.concatenate(Self.figureArtwork)
        ctx.concatenate(pose.head)
        drawSprite(head, in: ctx)
        drawEyes(in: ctx, physics: physics, tint: eyeColor)
        ctx.restoreGState()
    }

    private func wristPose(paw: CGPoint, rest: CGPoint, idleHand: CGPoint,
                           toSprite: CGAffineTransform) -> (point: CGPoint, reach: CGFloat) {
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

    private func drawSleeve(in ctx: CGContext, shoulder: CGPoint, wrist: CGPoint, reach: CGFloat) {
        let dx = wrist.x - shoulder.x
        let dy = wrist.y - shoulder.y
        let length = max(1, hypot(dx, dy))
        let normal = CGPoint(x: -dy / length, y: dx / length)
        let shoulderHalfWidth: CGFloat = 5.8
        let wristHalfWidth: CGFloat = 5.45
        let mid = CGPoint(x: (shoulder.x + wrist.x) / 2, y: (shoulder.y + wrist.y) / 2)
        let middleHalfWidth = (shoulderHalfWidth + wristHalfWidth) / 2 + 1.6 * (1 - reach)

        let sleeve = CGMutablePath()
        let start = CGPoint(x: shoulder.x + normal.x * shoulderHalfWidth,
                            y: shoulder.y + normal.y * shoulderHalfWidth)
        sleeve.move(to: start)
        sleeve.addQuadCurve(to: CGPoint(x: wrist.x + normal.x * wristHalfWidth,
                                        y: wrist.y + normal.y * wristHalfWidth),
                            control: CGPoint(x: mid.x + normal.x * middleHalfWidth,
                                             y: mid.y + normal.y * middleHalfWidth))
        sleeve.addLine(to: CGPoint(x: wrist.x - normal.x * wristHalfWidth, y: wrist.y - normal.y * wristHalfWidth))
        sleeve.addQuadCurve(to: CGPoint(x: shoulder.x - normal.x * shoulderHalfWidth,
                                        y: shoulder.y - normal.y * shoulderHalfWidth),
                            control: CGPoint(x: mid.x - normal.x * middleHalfWidth,
                                             y: mid.y - normal.y * middleHalfWidth))
        sleeve.addQuadCurve(to: start, control: CGPoint(x: shoulder.x - dx / length * 5,
                                                       y: shoulder.y - dy / length * 5))
        sleeve.closeSubpath()

        ctx.addPath(sleeve)
        ctx.setFillColor(Self.coatBlue)
        ctx.fillPath()

        // Join the blue fills, preserving the sleeve outline where it crosses the belly.
        ctx.saveGState()
        ctx.concatenate(Self.shoulderMaskTransform)
        ctx.clip(to: Self.shoulderMaskBounds, mask: shoulderMask)
        ctx.concatenate(Self.shoulderMaskTransform.inverted())
        ctx.addPath(sleeve)
        ctx.setStrokeColor(Self.ink)
        ctx.setLineWidth(1.45)
        ctx.setLineJoin(.round)
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
