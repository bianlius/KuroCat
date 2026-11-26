import CoreGraphics
import Foundation

/// A native vector skin based on the front-facing seated reference in assets/references.
/// Artwork coordinates follow a 210 × 215 figure; the paws still reach real keyboard/mouse targets.
enum PikachuRenderer {
    private static let ink = color(0x171812)
    private static let yellow = color(0xFFE232)
    private static let gold = color(0xE9A51D)
    private static let red = color(0xF33B22)
    private static let brown = color(0xA85E1C)
    private static let white = color(0xFFFFFF)
    private static let lineWidth: CGFloat = 1.15
    private static let artworkScale: CGFloat = 1.04
    // Move the seated figure to the back edge of the keyboard deck.
    private static let seatOffsetY: CGFloat = 16

    private struct Pose {
        let body: CGAffineTransform
        let head: CGAffineTransform
        let leftEar: CGAffineTransform
        let rightEar: CGAffineTransform

        init(_ physics: CatPhysics) {
            let scruff = clamp(physics.scruffDrag.value)
            let lie = clamp(physics.lieIntensity.value)
            let dizzy = clamp(physics.dizzyIntensity.value)
            let squash = 1 + (physics.bodySquash.value - 1) * 0.35
            var bodyTransform = CGAffineTransform(translationX: CatPhysics.seatAnchor.x + physics.bodyShiftX.value,
                                     y: CatPhysics.seatAnchor.y + seatOffsetY - scruff * 20 + lie * 6 + dizzy * 6)
                .rotated(by: physics.bodyTilt.value * 0.45 + physics.scruffSwing.value * 0.5 - dizzy * 0.18)
                .scaledBy(x: artworkScale, y: artworkScale * squash)
                .translatedBy(x: -96, y: -207)
            // Turn and look without changing the character's size as the pointer crosses the screen.
            let headTransform = CGAffineTransform(translationX: 96 + physics.headYaw.value * 1.8,
                                     y: 94 + physics.headPitch.value * 1.1 + physics.breathingOffset * 0.3)
                .rotated(by: physics.headTilt.value * 0.4)
                .translatedBy(x: -96, y: -94)
            let earAngle = -clamp(physics.earFold.value) * 0.18 + sin(physics.time * 3.1) * 0.012
            let leftEarTransform = CGAffineTransform(translationX: 59, y: 58)
                .rotated(by: earAngle)
                .translatedBy(x: -59, y: -58)
            let mirror = CGAffineTransform(translationX: 192, y: 0).scaledBy(x: -1, y: 1)
            let rightEarTransform = leftEarTransform.concatenating(mirror)
            // Long ears need more room than cat ears when the scruff pose stretches the body.
            let top = [leftEarTip.applying(leftEarTransform), leftEarTip.applying(rightEarTransform), point(96, 44)]
                .map { $0.applying(headTransform).applying(bodyTransform).y }.min()!
            bodyTransform.ty += max(0, 6 - top)
            body = bodyTransform
            head = headTransform
            leftEar = leftEarTransform
            rightEar = rightEarTransform
        }
    }

    static func hitTest(point: CGPoint, physics: CatPhysics) -> CatHitZone? {
        let pose = Pose(physics)
        let body = point.applying(pose.body.inverted())
        let head = body.applying(pose.head.inverted())
        if headPath.contains(head)
            || leftEarPath.contains(head.applying(pose.leftEar.inverted()))
            || leftEarPath.contains(head.applying(pose.rightEar.inverted())) { return .head }
        if bodyPath.contains(body) || leftFootPath.contains(body)
            || leftFootPath.contains(body.applying(CGAffineTransform(translationX: 192, y: 0).scaledBy(x: -1, y: 1))) {
            return .body
        }
        return nil
    }

    static func draw(in ctx: CGContext, physics: CatPhysics, eyeColor: CGColor, keyboardDeck: CGPath) {
        let pose = Pose(physics)
        let inverse = pose.body.inverted()
        ctx.saveGState()
        ctx.concatenate(pose.body)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)

        if physics.tailTyping.value < 0.5 { drawTail(in: ctx, physics: physics, toFigure: inverse) }

        // The body and seated feet stay behind the keyboard; reaching forepaws are in front.
        ctx.saveGState()
        let visible = CGMutablePath()
        visible.addRect(CGRect(origin: .zero, size: CatPhysics.canvasSize), transform: inverse)
        visible.addPath(keyboardDeck, transform: inverse)
        ctx.addPath(visible)
        ctx.clip(using: .evenOdd)
        fillBodyCoat(bodyPath, in: ctx)
        stroke(bodyPath, in: ctx)
        let chinShadow = path {
            $0.move(to: point(82, 138))
            $0.addCurve(to: point(111, 139), control1: point(89, 144), control2: point(104, 146))
            $0.addQuadCurve(to: point(82, 138), control: point(96, 139))
            $0.closeSubpath()
        }
        ctx.setFillColor(color(0xE5A329))
        ctx.addPath(chinShadow)
        ctx.fillPath()
        drawFoot(in: ctx, mirrored: false)
        drawFoot(in: ctx, mirrored: true)
        ctx.restoreGState()

        if physics.tailTyping.value >= 0.5 { drawTail(in: ctx, physics: physics, toFigure: inverse) }
        let left = wrist(physics.leftPaw.point, rest: CatPhysics.leftPawRest,
                         idle: point(84, 201), inverse: inverse)
        let right = wrist(physics.rightPaw.point, rest: CatPhysics.rightPawRest,
                          idle: point(108, 201), inverse: inverse)
        drawArm(in: ctx, shoulder: point(71, 148), wrist: left, side: -1)
        drawArm(in: ctx, shoulder: point(121, 148), wrist: right, side: 1)

        // Drawing the head last prevents an extended arm or tail from cutting through the face.
        ctx.saveGState()
        ctx.concatenate(pose.head)
        let leftEar = drawEar(in: ctx, transform: pose.leftEar)
        let rightEar = drawEar(in: ctx, transform: pose.rightEar)
        fillHeadCoat(headPath, in: ctx)
        drawFace(in: ctx, physics: physics, eyeColor: eyeColor)

        // Keep the head outline only where it is part of the outer silhouette.
        let outlineArea = CGMutablePath()
        outlineArea.addRect(headPath.boundingBoxOfPath.insetBy(dx: -lineWidth, dy: -lineWidth))
        outlineArea.addPath(leftEar)
        outlineArea.addPath(rightEar)
        ctx.saveGState()
        ctx.addPath(outlineArea)
        ctx.clip(using: .evenOdd)
        stroke(headPath, in: ctx)
        ctx.restoreGState()
        ctx.restoreGState()
        ctx.restoreGState()
    }

    private static func wrist(_ paw: CGPoint, rest: CGPoint, idle: CGPoint,
                              inverse: CGAffineTransform) -> CGPoint {
        let t = min(1, hypot(paw.x - rest.x, paw.y - rest.y) / 18)
        let blend = t * t * (3 - 2 * t)
        let target = paw.applying(inverse)
        return point(idle.x + (target.x - idle.x) * blend, idle.y + (target.y - idle.y) * blend)
    }

    private static func drawArm(in ctx: CGContext, shoulder: CGPoint, wrist: CGPoint, side: CGFloat) {
        let dx = wrist.x - shoulder.x
        let dy = wrist.y - shoulder.y
        let length = max(1, hypot(dx, dy))
        let normal = point(dy / length, -dx / length)
        func offset(_ p: CGPoint, _ width: CGFloat) -> CGPoint {
            point(p.x + normal.x * width, p.y + normal.y * width)
        }
        let armWidthScale: CGFloat = 0.78
        let pawHalfWidth = 11 * armWidthScale
        let outside = shoulderJoint(offset(shoulder, side * 21.5), centerX: shoulder.x)
        let inside = shoulderJoint(offset(shoulder, -side * 20), centerX: shoulder.x)
        let outerWrist = offset(wrist, side * pawHalfWidth)
        let innerWrist = offset(wrist, -side * pawHalfWidth)
        // Give both edges the same bend so the foreleg tapers without pinching as it reaches.
        let bend = offset(point(shoulder.x + dx * 0.48, shoulder.y + dy * 0.48), side * 2.8)
        let outerControl = offset(bend, side * 20.5 * armWidthScale)
        let innerControl = offset(bend, -side * 19.25 * armWidthScale)
        func pawPoint(across: CGFloat, advance: CGFloat) -> CGPoint {
            offset(point(wrist.x + dx / length * advance, wrist.y + dy / length * advance), side * across)
        }
        let toeWidth = pawHalfWidth * 2 / 3
        let toeControlInset = 0.45 * armWidthScale
        func armContour(from start: CGPoint, control: CGPoint) -> CGMutablePath {
            let contour = CGMutablePath()
            contour.move(to: start)
            contour.addQuadCurve(to: outerWrist, control: control)
            contour.addLine(to: pawPoint(across: pawHalfWidth, advance: 4))
            for toe in 0..<3 {
                let start = pawHalfWidth - CGFloat(toe) * toeWidth
                let end = start - toeWidth
                contour.addCurve(to: pawPoint(across: end, advance: 4),
                                 control1: pawPoint(across: start - toeControlInset, advance: 7.3),
                                 control2: pawPoint(across: end + toeControlInset, advance: 7.3))
            }
            contour.addLine(to: innerWrist)
            return contour
        }

        let forearm = armContour(from: outside, control: outerControl)
        forearm.addQuadCurve(to: inside, control: innerControl)
        forearm.closeSubpath()
        fillBodyCoat(forearm, in: ctx)

        func outerCurve(at t: CGFloat) -> (start: CGPoint, control: CGPoint) {
            trimQuadratic(from: outside, control: outerControl, to: outerWrist, at: t)
        }
        // Start the resting line below the shoulder. A reaching arm takes over the silhouette at the torso edge.
        var outerStart: CGFloat = 0.25
        while outerStart < 1,
              bodyPath.contains(outerCurve(at: outerStart).start),
              bodyOutlineBand.contains(outerCurve(at: outerStart).start) {
            outerStart = min(1, outerStart + 0.025)
        }
        if !bodyPath.contains(outerCurve(at: outerStart).start) {
            outerStart = torsoExit(upTo: outerStart) { outerCurve(at: $0).start }
        }
        let outer = outerCurve(at: outerStart)
        let inner = trimQuadratic(from: inside, control: innerControl, to: innerWrist, at: 0.2)
        let contour = armContour(from: outer.start, control: outer.control)
        contour.addQuadCurve(to: inner.start, control: inner.control)
        stroke(contour, in: ctx, width: 0.95)
    }

    private static func shoulderJoint(_ edge: CGPoint, centerX: CGFloat) -> CGPoint {
        let inset: CGFloat = edge.x < centerX ? 1.25 : -1.25
        let probe = point(edge.x - inset, edge.y)
        guard !bodyPath.contains(probe) else { return edge }
        let center = point(centerX, edge.y)
        let boundary = torsoExit(upTo: 1) { interpolate(from: center, to: probe, at: $0) }
        let joint = interpolate(from: center, to: probe, at: boundary)
        return point(joint.x + inset, edge.y)
    }

    private static func torsoExit(upTo end: CGFloat, pointAt: (CGFloat) -> CGPoint) -> CGFloat {
        var inside: CGFloat = 0
        var outside = end
        for _ in 0..<9 {
            let middle = (inside + outside) / 2
            if bodyPath.contains(pointAt(middle)) { inside = middle }
            else { outside = middle }
        }
        return inside
    }

    private static func trimQuadratic(from start: CGPoint, control: CGPoint, to end: CGPoint, at t: CGFloat)
        -> (start: CGPoint, control: CGPoint) {
        let leading = interpolate(from: start, to: control, at: t)
        let trailing = interpolate(from: control, to: end, at: t)
        return (interpolate(from: leading, to: trailing, at: t), trailing)
    }

    private static func interpolate(from start: CGPoint, to end: CGPoint, at t: CGFloat) -> CGPoint {
        point(start.x + (end.x - start.x) * t, start.y + (end.y - start.y) * t)
    }

    private static func drawFoot(in ctx: CGContext, mirrored: Bool) {
        ctx.saveGState()
        if mirrored { ctx.translateBy(x: 192, y: 0); ctx.scaleBy(x: -1, y: 1) }
        fill(leftFootPath, in: ctx, top: yellow, bottom: gold, from: 174, to: 207)
        ctx.saveGState()
        ctx.addPath(leftFootPath)
        ctx.clip()
        ctx.setFillColor(ink)
        ctx.addPath(footToeSeparators)
        ctx.fillPath()
        ctx.restoreGState()
        stroke(leftFootPath, in: ctx)
        ctx.restoreGState()
    }

    private static func drawTail(in ctx: CGContext, physics: CatPhysics, toFigure: CGAffineTransform) {
        let artworkRoot = point(141, 146)
        let root = point(artworkRoot.x, artworkRoot.y + 5)
        let active = clamp(physics.tailTyping.value)
        let target = physics.tailTip.point.applying(toFigure)
        let baseAngle = atan2(CGFloat(-103), CGFloat(67))
        var delta = atan2(target.y - root.y, target.x - root.x) - baseAngle
        if delta > .pi { delta -= .pi * 2 }
        if delta < -.pi { delta += .pi * 2 }
        let angle = sin(physics.tailPhase) * 0.045 * (1 - active) + delta * active
        let reach = min(1.15, max(0.5, hypot(target.x - root.x, target.y - root.y) / 123))
        let scale = 1 + (reach - 1) * active
        // Convert the downward canvas offset to figure space for tilted poses.
        let offset = CGSize(width: 0, height: 4).applying(toFigure)
        ctx.saveGState()
        ctx.translateBy(x: root.x + offset.width, y: root.y + offset.height)
        ctx.rotate(by: angle)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -artworkRoot.x, y: -artworkRoot.y)
        fill(tailPath, in: ctx, top: color(0xFFE73B), bottom: yellow, from: 43, to: 149)
        ctx.saveGState()
        ctx.addPath(tailPath)
        ctx.clip()
        ctx.setFillColor(brown)
        ctx.addPath(polygon([point(128, 139), point(143, 132), point(144, 139), point(152, 136),
                             point(160, 153), point(137, 160)]))
        ctx.fillPath()
        ctx.restoreGState()
        stroke(tailPath, in: ctx)
        ctx.restoreGState()
    }

    private static func drawEar(in ctx: CGContext, transform: CGAffineTransform) -> CGPath {
        let ear = CGMutablePath()
        ear.addPath(leftEarPath, transform: transform)
        fillHeadCoat(ear, in: ctx)
        ctx.saveGState()
        ctx.addPath(ear)
        ctx.clip()
        ctx.concatenate(transform)
        ctx.setFillColor(ink)
        // The color boundary crosses the entire ear. Clip the rest of the mask to its outline.
        ctx.addPath(earTipInkPath)
        ctx.fillPath()
        ctx.restoreGState()
        stroke(ear, in: ctx)
        return ear
    }

    private static func fillHeadCoat(_ path: CGPath, in ctx: CGContext) {
        fill(path, in: ctx, top: color(0xFFE73B), bottom: yellow, from: 44, to: 140)
    }

    private static func fillBodyCoat(_ path: CGPath, in ctx: CGContext) {
        fill(path, in: ctx, top: yellow, bottom: color(0xFFD52B), from: 125, to: 207)
    }

    private static func drawFace(in ctx: CGContext, physics: CatPhysics, eyeColor: CGColor) {
        let gaze = physics.eyeGaze.point
        let yaw = physics.headYaw.value
        let pitch = physics.headPitch.value
        let face = CGAffineTransform(translationX: yaw * 2.8, y: pitch * 1.6)
        ctx.saveGState()
        // Clip the cheeks before moving the facial features so they stay inside the head as it turns.
        ctx.addPath(headPath)
        ctx.clip()
        ctx.concatenate(face)
        for side: CGFloat in [-1, 1] {
            ctx.saveGState()
            ctx.translateBy(x: 96 + side * 42, y: 113)
            ctx.rotate(by: -side * 0.22)
            let cheek = CGPath(ellipseIn: CGRect(x: -9.7, y: -12, width: 19.4, height: 24), transform: nil)
            ctx.setFillColor(red)
            ctx.addPath(cheek)
            ctx.fillPath()
            stroke(cheek, in: ctx, width: 0.9)
            ctx.restoreGState()
        }
        ctx.restoreGState()

        ctx.saveGState()
        ctx.concatenate(face)
        for side: CGFloat in [-1, 1] {
            drawEye(in: ctx, center: point(96 + side * 25.5, 88.5), gaze: gaze,
                    closure: physics.effectiveEyeClosure, happy: physics.isHappyClosedEyes,
                    hunt: clamp(physics.huntIntensity.value), eyeColor: eyeColor)
        }
        let nose = path {
            $0.move(to: point(94, 95)); $0.addQuadCurve(to: point(98, 95), control: point(96, 94))
            $0.addQuadCurve(to: point(96, 97), control: point(98, 96))
            $0.addQuadCurve(to: point(94, 95), control: point(95, 97)); $0.closeSubpath()
        }
        ctx.setFillColor(ink); ctx.addPath(nose); ctx.fillPath()
        let mouth = path {
            $0.move(to: point(80, 105))
            $0.addCurve(to: point(96, 105), control1: point(84, 110), control2: point(90, 110))
            $0.addCurve(to: point(112, 104.5), control1: point(102, 110), control2: point(108, 110))
        }
        stroke(mouth, in: ctx, width: 0.95)
        ctx.restoreGState()
    }

    private static func drawEye(in ctx: CGContext, center: CGPoint, gaze: CGPoint,
                                closure: CGFloat, happy: Bool, hunt: CGFloat, eyeColor: CGColor) {
        let close = clamp(closure)
        let cx = center.x + gaze.x * 1.2
        let cy = center.y + gaze.y * 1.1
        if close > 0.82 {
            let eyelid = path {
                $0.move(to: point(center.x - 7.5, center.y + 2))
                $0.addQuadCurve(to: point(center.x + 7.5, center.y + 2),
                                control: point(center.x, center.y + (happy ? -5 : 3.5)))
            }
            stroke(eyelid, in: ctx, width: 1.4)
            return
        }
        let width: CGFloat = 8.2 + hunt * 1.3
        let height: CGFloat = 8.8 * (1 - close)
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: cx - width, y: cy - height, width: width * 2, height: height * 2))
        ctx.clip()
        ctx.setFillColor(ink)
        ctx.fill(CGRect(x: cx - 11, y: cy - 12, width: 22, height: 24))
        ctx.setFillColor(color(0x644624))
        ctx.fillEllipse(in: CGRect(x: cx - 7.0, y: cy + height * 0.43, width: 14, height: height * 0.7))
        ctx.setFillColor(eyeColor.copy(alpha: 0.18) ?? brown)
        ctx.fillEllipse(in: CGRect(x: cx - 6, y: cy + height * 0.6, width: 12, height: height * 0.4))

        let highlightHalfWidth: CGFloat = 3.2
        let highlightHalfHeight = height * 0.425
        // Ease from the upper-left resting highlight toward the edge in the gaze direction.
        let magnitude = hypot(gaze.x, gaze.y)
        let reach = clamp(magnitude / 0.85)
        let blend = reach * (2 - reach)
        let limit = 0.95 - max(highlightHalfWidth / width, highlightHalfHeight / height)
        let travel = blend * limit / max(magnitude, 0.001)
        let highlightX = -1.6 * (1 - blend) + width * gaze.x * travel
        let highlightY = height * (-0.395 * (1 - blend) + gaze.y * travel)
        ctx.setFillColor(white)
        ctx.fillEllipse(in: CGRect(x: cx + highlightX - highlightHalfWidth,
                                  y: cy + highlightY - highlightHalfHeight,
                                  width: highlightHalfWidth * 2, height: highlightHalfHeight * 2))
        ctx.restoreGState()
    }

    private static let headPath = path {
        $0.move(to: point(96, 44))
        $0.addCurve(to: point(52, 66), control1: point(72, 43), control2: point(57, 51))
        $0.addCurve(to: point(48, 104), control1: point(48, 80), control2: point(51, 90))
        $0.addCurve(to: point(62, 135), control1: point(43, 121), control2: point(48, 129))
        $0.addCurve(to: point(131, 135), control1: point(78, 144), control2: point(113, 144))
        $0.addCurve(to: point(143, 104), control1: point(147, 128), control2: point(148, 117))
        $0.addCurve(to: point(136, 63), control1: point(140, 90), control2: point(144, 76))
        $0.addCurve(to: point(96, 44), control1: point(128, 49), control2: point(113, 44))
        $0.closeSubpath()
    }
    private static let bodyPath = path {
        $0.move(to: point(57, 124))
        $0.addCurve(to: point(38, 187), control1: point(58, 151), control2: point(38, 163))
        $0.addCurve(to: point(96, 205), control1: point(38, 205), control2: point(66, 205))
        $0.addCurve(to: point(154, 187), control1: point(126, 205), control2: point(154, 205))
        $0.addCurve(to: point(135, 124), control1: point(154, 163), control2: point(134, 151))
        $0.closeSubpath()
    }
    private static let bodyOutlineBand = bodyPath.copy(strokingWithWidth: 3.5, lineCap: .round,
                                                       lineJoin: .round, miterLimit: 0)
    private static let leftFootPath = path {
        $0.move(to: point(28, 174))
        $0.addCurve(to: point(53, 191), control1: point(35, 176), control2: point(48, 185))
        $0.addCurve(to: point(55, 205), control1: point(62, 199), control2: point(61, 204))
        $0.addCurve(to: point(37, 201), control1: point(49, 210), control2: point(41, 205))
        $0.addCurve(to: point(23, 180), control1: point(30, 193), control2: point(24, 184))
        $0.addQuadCurve(to: point(24.1, 176.4), control: point(20.6, 176.5))
        $0.addQuadCurve(to: point(26.1, 174.3), control: point(23, 174.1))
        $0.addQuadCurve(to: point(28, 174), control: point(26.5, 172.6))
        $0.closeSubpath()
    }
    private static let footToeSeparators = path {
        // Both marks start at the toe notches and taper into the foot.
        $0.move(to: point(23.8, 176.7))
        $0.addQuadCurve(to: point(38.2, 190), control: point(28.8, 183.5))
        $0.addQuadCurve(to: point(24.4, 176.1), control: point(29.8, 182.45))
        $0.closeSubpath()
        $0.move(to: point(25.8, 174.6))
        $0.addQuadCurve(to: point(42, 187.6), control: point(31.5, 181.8))
        $0.addQuadCurve(to: point(26.4, 174), control: point(32.5, 180.7))
        $0.closeSubpath()
    }
    private static let leftEarTip = point(4, 7)
    private static let leftEarPath = path {
        $0.move(to: point(67, 57))
        $0.addCurve(to: leftEarTip, control1: point(55, 39), control2: point(25, 10))
        $0.addCurve(to: point(48, 61), control1: point(1, 5), control2: point(15, 39))
        $0.addCurve(to: point(67, 57), control1: point(54, 65), control2: point(62, 64))
        $0.closeSubpath()
    }
    private static let earTipInkPath = polygon([point(-40, -34), point(12, -34), point(30, 74), point(-40, 74)])
    private static let tailPath = polygon([
        point(139, 151), point(159, 141), point(179, 134), point(156, 111), point(200, 89),
        point(208, 43), point(140, 61), point(150, 85), point(128, 104), point(150, 124),
        point(131, 137)
    ])

    private static func fill(_ path: CGPath, in ctx: CGContext, top: CGColor, bottom: CGColor,
                             from: CGFloat, to: CGFloat) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [top, bottom] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: point(96, from), end: point(96, max(from + 1, to)),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        ctx.restoreGState()
    }
    private static func stroke(_ path: CGPath, in ctx: CGContext, width: CGFloat = lineWidth) {
        ctx.setStrokeColor(ink); ctx.setLineWidth(width); ctx.addPath(path); ctx.strokePath()
    }
    private static func path(_ draw: (CGMutablePath) -> Void) -> CGPath {
        let result = CGMutablePath(); draw(result); return result
    }
    private static func polygon(_ points: [CGPoint]) -> CGPath {
        path { p in
            guard let first = points.first else { return }
            p.move(to: first)
            for point in points.dropFirst() { p.addLine(to: point) }
            p.closeSubpath()
        }
    }
    private static func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    private static func clamp(_ x: CGFloat) -> CGFloat { min(1, max(0, x)) }
    private static func color(_ hex: Int) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}
