#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Seated proportions referenced from Kitan Club's front photograph:
// https://kitan.jp/products/suwaru_doraemon/
// Each layer uses the same 128-point canvas so the animation can share its anchors.
let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = project.appendingPathComponent("Resources/Doraemon", isDirectory: true)
let frame = CGRect(x: 0, y: 0, width: 128, height: 128)
let shoulderMaskBounds = frame.insetBy(dx: -64, dy: -64)
let ink = CGColor(srgbRed: 0.044, green: 0.067, blue: 0.085, alpha: 1)
let blue = CGColor(srgbRed: 0, green: 159.0 / 255, blue: 222.0 / 255, alpha: 1)
let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
let red = CGColor(srgbRed: 0.88, green: 0.11, blue: 0.15, alpha: 1)
let bell = CGColor(srgbRed: 1, green: 0.80, blue: 0.15, alpha: 1)
let bellyBounds = CGRect(x: 46.1, y: 80.8, width: 35.8, height: 34.8)
let bellBounds = CGRect(x: 58.5, y: 81.4, width: 11, height: 10.6)
let soleBounds = CGRect(x: -12.2, y: -14.1, width: 24.4, height: 28.2)

func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

func paint(_ ctx: CGContext, color: CGColor? = nil, line: CGFloat = 1.4,
           path makePath: (CGMutablePath) -> Void) {
    let path = CGMutablePath()
    makePath(path)
    ctx.addPath(path)
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(line)
    if let color {
        ctx.setFillColor(color)
        ctx.drawPath(using: .fillStroke)
    } else {
        ctx.strokePath()
    }
}

func oval(_ ctx: CGContext, _ rect: CGRect, color: CGColor, line: CGFloat = 1.4) {
    paint(ctx, color: color, line: line) { $0.addEllipse(in: rect) }
}

func drawHand(_ ctx: CGContext) {
    oval(ctx, CGRect(x: 91.2, y: 99.8, width: 15.6, height: 14.8), color: white)
}

func soleTransform(isLeft: Bool) -> CGAffineTransform {
    CGAffineTransform(translationX: isLeft ? 43 : 85, y: 112.4)
        .scaledBy(x: isLeft ? -1 : 1, y: 1)
        .rotated(by: 0.13)
}

func drawSole(_ ctx: CGContext, isLeft: Bool) {
    ctx.saveGState()
    ctx.concatenate(soleTransform(isLeft: isLeft))
    oval(ctx, soleBounds, color: white)
    ctx.restoreGState()
}

func torsoOutline(_ path: CGMutablePath) {
    path.move(to: p(43, 76))
    path.addQuadCurve(to: p(85, 76), control: p(64, 72.5))
    path.addCurve(to: p(94, 115), control1: p(91, 82), control2: p(94, 100))
    path.addCurve(to: p(34, 115), control1: p(87, 124), control2: p(41, 124))
    path.addCurve(to: p(43, 76), control1: p(34, 100), control2: p(37, 82))
    path.closeSubpath()
}

func collarOutline(_ path: CGMutablePath) {
    path.move(to: p(40.4, 76.1))
    path.addQuadCurve(to: p(87.6, 76.1), control: p(64, 80.8))
    path.addCurve(to: p(87.1, 82.8), control1: p(91.3, 75.6), control2: p(91.1, 82.2))
    path.addQuadCurve(to: p(40.9, 82.8), control: p(64, 87.0))
    path.addCurve(to: p(40.4, 76.1), control1: p(36.9, 82.2), control2: p(36.7, 75.6))
    path.closeSubpath()
}

func drawBody(_ ctx: CGContext) {
    paint(ctx, color: blue, path: torsoOutline)
    oval(ctx, bellyBounds, color: white, line: 1.1)

    paint(ctx, line: 1.15) { pocket in
        pocket.move(to: p(48.8, 98.1))
        pocket.addLine(to: p(79.2, 98.1))
        pocket.addCurve(to: p(64, 111.5), control1: p(78.5, 106.5), control2: p(72.6, 111.5))
        pocket.addCurve(to: p(48.8, 98.1), control1: p(55.4, 111.5), control2: p(49.5, 106.5))
    }

    paint(ctx, color: red, path: collarOutline)
    oval(ctx, bellBounds, color: bell, line: 1.15)
    ctx.setStrokeColor(CGColor(srgbRed: 0.63, green: 0.43, blue: 0.08, alpha: 1))
    ctx.setLineWidth(0.85)
    ctx.move(to: p(60.4, 86.3))
    ctx.addQuadCurve(to: p(67.6, 86.3), control: p(64, 85.4))
    ctx.strokePath()

    paint(ctx, line: 0.95) { detail in
        detail.move(to: p(64, 88.8))
        detail.addLine(to: p(64, 91.5))
    }
    ctx.setFillColor(ink)
    ctx.fillEllipse(in: CGRect(x: 62.9, y: 87.8, width: 2.2, height: 1.9))
    drawSole(ctx, isLeft: true)
}

func drawShoulderMask(_ ctx: CGContext) {
    ctx.setFillColor(gray: 1, alpha: 1)
    ctx.fill(shoulderMaskBounds)

    // Only mask the shoulder on this side. The renderer mirrors it for the other arm.
    ctx.clip(to: CGRect(x: 0, y: 0, width: 64, height: 104))
    let torso = CGMutablePath()
    torsoOutline(torso)
    ctx.addPath(torso)
    ctx.setFillColor(gray: 0, alpha: 1)
    ctx.fillPath()

    let collar = CGMutablePath()
    collarOutline(collar)
    ctx.setFillColor(gray: 1, alpha: 1)
    ctx.addPath(collar)
    ctx.fillPath()
    ctx.fillEllipse(in: bellyBounds)
    ctx.fillEllipse(in: bellBounds)
    ctx.concatenate(soleTransform(isLeft: true))
    ctx.fillEllipse(in: soleBounds)
}

func drawHead(_ ctx: CGContext) {
    paint(ctx, color: blue, line: 1.65) { h in
        h.move(to: p(64, 12.5))
        h.addCurve(to: p(102.6, 47), control1: p(87.1, 12.5), control2: p(102.6, 25.6))
        h.addCurve(to: p(86.6, 77.8), control1: p(102.6, 61.1), control2: p(96, 72))
        h.addQuadCurve(to: p(41.4, 77.8), control: p(64, 81.7))
        h.addCurve(to: p(25.4, 47), control1: p(32, 72), control2: p(25.4, 61.1))
        h.addCurve(to: p(64, 12.5), control1: p(25.4, 25.6), control2: p(40.9, 12.5))
        h.closeSubpath()
    }
    paint(ctx, color: white, line: 1.2) { face in
        face.move(to: p(64, 38.3))
        face.addCurve(to: p(96.2, 53.7), control1: p(81.1, 33.8), control2: p(96.2, 42.4))
        face.addCurve(to: p(84.4, 75.9), control1: p(96.2, 63.1), control2: p(91.3, 71.1))
        face.addQuadCurve(to: p(43.6, 75.9), control: p(64, 80))
        face.addCurve(to: p(31.8, 53.7), control1: p(36.7, 71.1), control2: p(31.8, 63.1))
        face.addCurve(to: p(64, 38.3), control1: p(31.8, 42.4), control2: p(46.9, 33.8))
        face.closeSubpath()
    }
    oval(ctx, CGRect(x: 47.8, y: 23.4, width: 16.2, height: 21), color: white, line: 1.1)
    oval(ctx, CGRect(x: 64, y: 23.4, width: 16.2, height: 21), color: white, line: 1.1)

    paint(ctx, line: 1.35) { features in
        features.move(to: p(41, 61.1))
        features.addCurve(to: p(87, 61.1), control1: p(53, 74.2), control2: p(75, 74.2))
        features.move(to: p(64, 47))
        features.addLine(to: p(64, 70.9))
        for side: CGFloat in [-1, 1] {
            features.move(to: p(64 + side * 9, 48.7))
            features.addLine(to: p(64 + side * 26, 44.5))
            features.move(to: p(64 + side * 9, 52.8))
            features.addLine(to: p(64 + side * 27.5, 52.4))
            features.move(to: p(64 + side * 9, 57.4))
            features.addLine(to: p(64 + side * 25.7, 61))
        }
    }
    oval(ctx, CGRect(x: 58.4, y: 39.3, width: 11.2, height: 10.7), color: red, line: 1.25)
    ctx.setFillColor(white)
    ctx.fillEllipse(in: CGRect(x: 60.7, y: 41, width: 2.8, height: 2.5))
}

func export(_ name: String, bounds: CGRect = frame, monochrome: Bool = false, _ render: (CGContext) -> Void) {
    let width = Int(bounds.width) * 4
    let height = Int(bounds.height) * 4
    let colorSpace = monochrome ? CGColorSpaceCreateDeviceGray() : CGColorSpace(name: CGColorSpace.sRGB)!
    let alpha: CGImageAlphaInfo = monochrome ? .none : .premultipliedLast
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: colorSpace, bitmapInfo: alpha.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 4, y: -4)
    ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    render(ctx)

    let file = output.appendingPathComponent(name + ".png")
    let png = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(png, ctx.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(png))
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
export("head", drawHead)
export("body", drawBody)
export("hand", drawHand)
export("foot-right") { drawSole($0, isLeft: false) }
export("shoulder-mask", bounds: shoulderMaskBounds, monochrome: true, drawShoulderMask)
