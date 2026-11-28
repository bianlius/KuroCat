#pragma once

#include "CatPhysics.hpp"
#include "CharacterDragPose.hpp"
#include <objidl.h>
#include <gdiplus.h>
#include <array>
#include <initializer_list>

// GDI+ port of Sources/PikachuRenderer.swift. The artwork and pose use the same figure coordinates.
class PikachuRenderer {
    using Color = Gdiplus::Color;
    using Graphics = Gdiplus::Graphics;
    using GraphicsPath = Gdiplus::GraphicsPath;
    using Matrix = Gdiplus::Matrix;
    using PointF = Gdiplus::PointF;

    static constexpr float Pi = 3.14159265f;
    static constexpr float RadToDeg = 180.0f / Pi;
    static constexpr float ArtworkScale = 1.04f;
    static constexpr float LineWidth = 1.15f;
    static constexpr Pt LeftEarTip{4, 7};
    static constexpr Gdiplus::ARGB Ink = 0xff171812;
    static constexpr Gdiplus::ARGB Yellow = 0xffffe232;
    static constexpr Gdiplus::ARGB Gold = 0xffe9a51d;
    static constexpr Gdiplus::ARGB Brown = 0xffa85e1c;
    static constexpr Gdiplus::ARGB HeadHighlight = 0xffffe73b;

    static Pt lerp(Pt start, Pt end, float t) {
        return {start.x + (end.x - start.x) * t, start.y + (end.y - start.y) * t};
    }

    static Pt transformed(Pt point, const Matrix& transform) {
        PointF result{point.x, point.y};
        transform.TransformPoints(&result);
        return {result.X, result.Y};
    }

    static float clamp01(float value) { return std::clamp(value, 0.0f, 1.0f); }

    struct Contour {
        GraphicsPath path{Gdiplus::FillModeWinding};
        Pt cursor;

        void move(Pt point) {
            path.StartFigure();
            cursor = point;
        }

        void line(Pt end) {
            path.AddLine(cursor.x, cursor.y, end.x, end.y);
            cursor = end;
        }

        void cubic(Pt first, Pt second, Pt end) {
            path.AddBezier(cursor.x, cursor.y, first.x, first.y, second.x, second.y, end.x, end.y);
            cursor = end;
        }

        void quad(Pt control, Pt end) {
            cubic(lerp(cursor, control, 2.0f / 3.0f), lerp(end, control, 2.0f / 3.0f), end);
        }

        void close() { path.CloseFigure(); }

        void polygon(std::initializer_list<PointF> points) {
            path.AddPolygon(points.begin(), static_cast<INT>(points.size()));
        }
    };

    struct Pose {
        Matrix body, head, leftEar, rightEar;
        CharacterDragPose drag;

        explicit Pose(const CatPhysics& physics) : drag(physics) {
            const float lie = clamp01(physics.lieIntensity.value);
            const float dizzy = clamp01(physics.dizzyIntensity.value);
            const float squash = 1 + (physics.bodySquash.value - 1) * 0.35f;
            body.Translate(CatPhysics::SeatAnchor.x + physics.bodyShiftX.value,
                           CatPhysics::SeatAnchor.y + 16 + lie * 6 + dizzy * 6);
            body.Rotate((physics.bodyTilt.value * 0.45f - dizzy * 0.18f) * (1 - drag.lift) * RadToDeg);
            body.Scale(ArtworkScale, ArtworkScale * squash);
            body.Translate(-96, -207);

            head.Translate(96 + physics.headYaw.value * 1.8f,
                           94 + physics.headPitch.value * 1.1f + physics.breathingOffset() * 0.3f);
            head.Rotate(physics.headTilt.value * 0.4f * (1 - drag.lift * 0.75f) * RadToDeg);
            head.Translate(-96, -94);

            const float earAngle = -clamp01(physics.earFold.value) * 0.18f + std::sin(physics.time * 3.1f) * 0.012f;
            leftEar.Translate(59, 58);
            leftEar.Rotate(earAngle * RadToDeg);
            leftEar.Translate(-59, -58);
            Matrix mirror{-1, 0, 0, 1, 192, 0};
            rightEar.Multiply(&leftEar);
            rightEar.Multiply(&mirror, Gdiplus::MatrixOrderAppend);

            const Pt grip = transformed({96, kurorig::PikachuArtGripY}, head);
            drag.suspend(body, grip, ScruffGrip, 0.12f);
            const auto canvasY = [&](Pt point) {
                return transformed(transformed(point, head), body).y;
            };
            const float top = std::min({
                canvasY(transformed(LeftEarTip, leftEar)),
                canvasY(transformed(LeftEarTip, rightEar)),
                canvasY({96, 44})
            });
            body.Translate(0, std::max(0.0f, 6 - top), Gdiplus::MatrixOrderAppend);
        }

        CharacterDragPose::Hands wrists(const CatPhysics& physics, const Matrix& inverse) const {
            const Pt left = wrist(physics.leftPaw.point(), CatPhysics::LeftPawRest, {84, 201}, inverse);
            const Pt right = wrist(physics.rightPaw.point(), CatPhysics::RightPawRest, {108, 201}, inverse);
            const float spread = kurorig::PikachuWristSpread;
            return {drag.wrist(left, {96 - spread, kurorig::PikachuWristY}),
                    drag.wrist(right, {96 + spread, kurorig::PikachuKeyboardWristY})};
        }
    };

    Contour head, body, foot, toes, ear, earTipInk, tail, tailRoot, chinShadow, nose, mouth;

public:
    static constexpr Pt ScruffGrip{kurorig::SeatX, kurorig::PikachuCanvasGripY};

    PikachuRenderer() {
        head.move({96, 44});
        head.cubic({72, 43}, {57, 51}, {52, 66});
        head.cubic({48, 80}, {51, 90}, {48, 104});
        head.cubic({43, 121}, {48, 129}, {62, 135});
        head.cubic({78, 144}, {113, 144}, {131, 135});
        head.cubic({147, 128}, {148, 117}, {143, 104});
        head.cubic({140, 90}, {144, 76}, {136, 63});
        head.cubic({128, 49}, {113, 44}, {96, 44});
        head.close();

        body.move({57, 124});
        body.cubic({58, 151}, {38, 163}, {38, 187});
        body.cubic({38, 205}, {66, 205}, {96, 205});
        body.cubic({126, 205}, {154, 205}, {154, 187});
        body.cubic({154, 163}, {134, 151}, {135, 124});
        body.close();

        foot.move({28, 174});
        foot.cubic({35, 176}, {48, 185}, {53, 191});
        foot.cubic({62, 199}, {61, 204}, {55, 205});
        foot.cubic({49, 210}, {41, 205}, {37, 201});
        foot.cubic({30, 193}, {24, 184}, {23, 180});
        foot.quad({20.6f, 176.5f}, {24.1f, 176.4f});
        foot.quad({23, 174.1f}, {26.1f, 174.3f});
        foot.quad({26.5f, 172.6f}, {28, 174});
        foot.close();

        toes.move({23.8f, 176.7f});
        toes.quad({28.8f, 183.5f}, {38.2f, 190});
        toes.quad({29.8f, 182.45f}, {24.4f, 176.1f});
        toes.close();
        toes.move({25.8f, 174.6f});
        toes.quad({31.5f, 181.8f}, {42, 187.6f});
        toes.quad({32.5f, 180.7f}, {26.4f, 174});
        toes.close();

        ear.move({67, 57});
        ear.cubic({55, 39}, {25, 10}, LeftEarTip);
        ear.cubic({1, 5}, {15, 39}, {48, 61});
        ear.cubic({54, 65}, {62, 64}, {67, 57});
        ear.close();
        earTipInk.polygon({{-40, -34}, {12, -34}, {30, 74}, {-40, 74}});

        tail.polygon({{139, 151}, {159, 141}, {179, 134}, {156, 111}, {200, 89}, {208, 43},
                      {140, 61}, {150, 85}, {128, 104}, {150, 124}, {131, 137}});
        tailRoot.polygon({{128, 139}, {143, 132}, {144, 139}, {152, 136}, {160, 153}, {137, 160}});

        chinShadow.move({82, 138});
        chinShadow.cubic({89, 144}, {104, 146}, {111, 139});
        chinShadow.quad({96, 139}, {82, 138});
        chinShadow.close();

        nose.move({94, 95});
        nose.quad({96, 94}, {98, 95});
        nose.quad({98, 96}, {96, 97});
        nose.quad({95, 97}, {94, 95});
        nose.close();
        mouth.move({80, 105});
        mouth.cubic({84, 110}, {90, 110}, {96, 105});
        mouth.cubic({102, 110}, {108, 110}, {112, 104.5f});
    }

    CatHitZone hitTest(Pt point, const CatPhysics& physics) const {
        Pose pose(physics);
        pose.body.Invert();
        pose.head.Invert();
        pose.leftEar.Invert();
        pose.rightEar.Invert();
        const auto bodyPoint = transformed(point, pose.body);
        const auto headPoint = transformed(bodyPoint, pose.head);
        if (contains(head.path, headPoint)
            || contains(ear.path, transformed(headPoint, pose.leftEar))
            || contains(ear.path, transformed(headPoint, pose.rightEar))) {
            return CatHitZone::Head;
        }
        auto torso = pose.drag.torso(146);
        torso.Invert();
        const Pt torsoPoint = transformed(bodyPoint, torso);
        if (contains(body.path, torsoPoint) || contains(foot.path, torsoPoint)
            || contains(foot.path, {192 - torsoPoint.x, torsoPoint.y})) {
            return CatHitZone::Body;
        }
        return CatHitZone::None;
    }

    static CharacterDragPose::Hands dragHands(const CatPhysics& physics) {
        Pose pose(physics);
        Matrix inverse;
        inverse.Multiply(&pose.body);
        inverse.Invert();
        const auto wrists = pose.wrists(physics, inverse);
        return {transformed(wrists.left, pose.body), transformed(wrists.right, pose.body)};
    }

    void draw(Graphics& g, const CatPhysics& physics, Color eyeColor, const GraphicsPath& keyboardDeck) const {
        Pose pose(physics);
        Matrix inverse;
        inverse.Multiply(&pose.body);
        inverse.Invert();

        const auto scene = g.Save();
        g.MultiplyTransform(&pose.body);
        const bool tailInFront = physics.tailTyping.value >= 0.5f && pose.drag.lift < 0.5f;
        if (!tailInFront) drawTail(g, physics, inverse, pose.drag.lift);

        // The body's seat and feet sit behind the keyboard, while reaching paws overlap it.
        const auto behindKeyboard = g.Save();
        GraphicsPath deckInFigure;
        deckInFigure.AddPath(&keyboardDeck, FALSE);
        deckInFigure.Transform(&inverse);
        g.SetClip(&deckInFigure, Gdiplus::CombineModeExclude);
        const auto torso = pose.drag.torso(146);
        g.MultiplyTransform(&torso);
        fillBody(g, body.path);
        stroke(g, body.path);
        fillSolid(g, chinShadow.path, Color(0xffe5a329));
        drawFoot(g, false);
        drawFoot(g, true);
        g.Restore(behindKeyboard);

        if (tailInFront) drawTail(g, physics, inverse, pose.drag.lift);
        const auto [left, right] = pose.wrists(physics, inverse);
        drawArm(g, {71, 148}, left, -1);
        drawArm(g, {121, 148}, right, 1);

        // Paint the face after the moving paws and tail so it stays unobstructed.
        g.MultiplyTransform(&pose.head);
        GraphicsPath leftEar, rightEar;
        drawEar(g, pose.leftEar, leftEar);
        drawEar(g, pose.rightEar, rightEar);
        fill(g, head.path, Color(HeadHighlight), Color(Yellow), 44, 140);
        drawFace(g, physics, eyeColor);
        g.SetClip(&leftEar, Gdiplus::CombineModeExclude);
        g.SetClip(&rightEar, Gdiplus::CombineModeExclude);
        stroke(g, head.path);
        g.Restore(scene);
    }

private:
    static bool contains(const GraphicsPath& path, Pt point) { return path.IsVisible(point.x, point.y); }

    static void fillSolid(Graphics& g, const GraphicsPath& path, Color color) {
        Gdiplus::SolidBrush brush(color);
        g.FillPath(&brush, &path);
    }

    static void fill(Graphics& g, const GraphicsPath& path, Color top, Color bottom, float from, float to) {
        Gdiplus::RectF bounds;
        path.GetBounds(&bounds);
        const float firstY = std::min(bounds.GetTop(), from);
        const float range = std::max(bounds.GetBottom(), to) - firstY;
        const Gdiplus::RectF gradientBounds(bounds.X, firstY, bounds.Width, range);
        Gdiplus::LinearGradientBrush gradient(gradientBounds, top, bottom, Gdiplus::LinearGradientModeVertical);
        std::array<Color, 4> colors{top};
        std::array<Gdiplus::REAL, 4> stops{0};
        INT count = 1;
        if (firstY < from) {
            colors[count] = top;
            stops[count++] = (from - firstY) / range;
        }
        if (bounds.GetBottom() > to) {
            colors[count] = bottom;
            stops[count++] = (to - firstY) / range;
        }
        colors[count] = bottom;
        stops[count++] = 1;
        if (count > 2) gradient.SetInterpolationColors(colors.data(), stops.data(), count);
        g.FillPath(&gradient, &path);
    }

    static void fillBody(Graphics& g, const GraphicsPath& path) {
        fill(g, path, Color(Yellow), Color(0xffffd52b), 125, 207);
    }

    static void stroke(Graphics& g, const GraphicsPath& path, float width = LineWidth) {
        Gdiplus::Pen pen(Color(Ink), width);
        pen.SetLineJoin(Gdiplus::LineJoinRound);
        pen.SetStartCap(Gdiplus::LineCapRound);
        pen.SetEndCap(Gdiplus::LineCapRound);
        g.DrawPath(&pen, &path);
    }

    static Pt wrist(Pt paw, Pt rest, Pt idle, const Matrix& inverse) {
        const float t = std::min(1.0f, std::hypot(paw.x - rest.x, paw.y - rest.y) / 18);
        return lerp(idle, transformed(paw, inverse), t * t * (3 - 2 * t));
    }

    template <typename PointAt>
    float torsoExit(float end, PointAt pointAt) const {
        float inside = 0;
        float outside = end;
        for (int i = 0; i < 9; ++i) {
            const float middle = (inside + outside) / 2;
            if (contains(body.path, pointAt(middle))) inside = middle;
            else outside = middle;
        }
        return inside;
    }

    Pt shoulderJoint(Pt edge, float centerX) const {
        const float inset = edge.x < centerX ? 1.25f : -1.25f;
        const Pt probe{edge.x - inset, edge.y};
        if (contains(body.path, probe)) return edge;
        const Pt center{centerX, edge.y};
        const float boundary = torsoExit(1, [&](float t) { return lerp(center, probe, t); });
        return {lerp(center, probe, boundary).x + inset, edge.y};
    }

    void drawArm(Graphics& g, Pt shoulder, Pt wristPoint, float side) const {
        const float dx = wristPoint.x - shoulder.x;
        const float dy = wristPoint.y - shoulder.y;
        const float length = std::max(1.0f, std::hypot(dx, dy));
        auto offset = [&](Pt point, float width) -> Pt {
            return {point.x + dy / length * width, point.y - dx / length * width};
        };
        constexpr float widthScale = 0.78f;
        constexpr float pawHalfWidth = 11 * widthScale;
        const Pt outside = shoulderJoint(offset(shoulder, side * 21.5f), shoulder.x);
        const Pt inside = shoulderJoint(offset(shoulder, -side * 20), shoulder.x);
        const Pt outerWrist = offset(wristPoint, side * pawHalfWidth);
        const Pt innerWrist = offset(wristPoint, -side * pawHalfWidth);
        const Pt bend = offset(lerp(shoulder, wristPoint, 0.48f), side * 2.8f);
        const Pt outerControl = offset(bend, side * 20.5f * widthScale);
        const Pt innerControl = offset(bend, -side * 19.25f * widthScale);
        auto pawPoint = [&](float across, float advance) {
            return offset({wristPoint.x + dx / length * advance, wristPoint.y + dy / length * advance},
                          side * across);
        };
        auto armContour = [&](Contour& contour, Pt start, Pt control) {
            contour.move(start);
            contour.quad(control, outerWrist);
            contour.line(pawPoint(pawHalfWidth, 4));
            constexpr float toeWidth = pawHalfWidth * 2 / 3;
            constexpr float toeInset = 0.45f * widthScale;
            for (int toe = 0; toe < 3; ++toe) {
                const float from = pawHalfWidth - toe * toeWidth;
                const float to = from - toeWidth;
                contour.cubic(pawPoint(from - toeInset, 7.3f), pawPoint(to + toeInset, 7.3f), pawPoint(to, 4));
            }
            contour.line(innerWrist);
        };

        Contour arm;
        armContour(arm, outside, outerControl);
        arm.quad(innerControl, inside);
        arm.close();
        fillBody(g, arm.path);

        // Trim the resting contour below the shoulder, or to the exit point of a reaching arm.
        auto outerPoint = [&](float t) {
            return lerp(lerp(outside, outerControl, t), lerp(outerControl, outerWrist, t), t);
        };
        Gdiplus::Pen outlineBand(Color(Ink), 3.5f);
        outlineBand.SetLineJoin(Gdiplus::LineJoinRound);
        float t = 0.25f;
        Pt start = outerPoint(t);
        while (t < 1 && contains(body.path, start) && body.path.IsOutlineVisible(start.x, start.y, &outlineBand)) {
            t = std::min(1.0f, t + 0.025f);
            start = outerPoint(t);
        }
        if (!contains(body.path, start)) {
            t = torsoExit(t, outerPoint);
            start = outerPoint(t);
        }
        const Pt trimmedInnerControl = lerp(innerControl, innerWrist, 0.2f);
        const Pt trimmedInnerEdge = lerp(lerp(inside, innerControl, 0.2f), trimmedInnerControl, 0.2f);
        Contour outline;
        armContour(outline, start, lerp(outerControl, outerWrist, t));
        outline.quad(trimmedInnerControl, trimmedInnerEdge);
        stroke(g, outline.path, 0.95f);
    }

    void drawFoot(Graphics& g, bool mirrored) const {
        const auto state = g.Save();
        if (mirrored) {
            Matrix mirror{-1, 0, 0, 1, 192, 0};
            g.MultiplyTransform(&mirror);
        }
        fill(g, foot.path, Color(Yellow), Color(Gold), 174, 207);
        const auto clip = g.Save();
        g.SetClip(&foot.path, Gdiplus::CombineModeIntersect);
        fillSolid(g, toes.path, Color(Ink));
        g.Restore(clip);
        stroke(g, foot.path);
        g.Restore(state);
    }

    void drawTail(Graphics& g, const CatPhysics& physics, const Matrix& inverse, float lift) const {
        const Pt root{141, 151};
        const Pt target = transformed(physics.tailTip.point(), inverse);
        const float active = clamp01(physics.tailTyping.value);
        const float baseAngle = std::atan2(-103.0f, 67.0f);
        const float delta = std::remainder(std::atan2(target.y - root.y, target.x - root.x) - baseAngle, 2 * Pi);
        const float seatedAngle = std::sin(physics.tailPhase) * 0.045f * (1 - active) + delta * active;
        const float angle = seatedAngle * (1 - lift) + (1.75f - physics.scruffTailSwing.value * 0.22f) * lift;
        const float reach = std::clamp(std::hypot(target.x - root.x, target.y - root.y) / 123, 0.5f, 1.15f);
        const float scale = (1 + (reach - 1) * active) * (1 - lift) + kurorig::PikachuTailLiftScale * lift;
        PointF offset{0, 4};
        inverse.TransformVectors(&offset);

        const auto state = g.Save();
        g.TranslateTransform(root.x + offset.X, root.y + offset.Y);
        g.RotateTransform(angle * RadToDeg);
        g.ScaleTransform(scale, scale);
        g.TranslateTransform(-141, -146);
        fill(g, tail.path, Color(HeadHighlight), Color(Yellow), 43, 149);
        const auto clip = g.Save();
        g.SetClip(&tail.path, Gdiplus::CombineModeIntersect);
        fillSolid(g, tailRoot.path, Color(Brown));
        g.Restore(clip);
        stroke(g, tail.path);
        g.Restore(state);
    }

    void drawEar(Graphics& g, const Matrix& transform, GraphicsPath& outline) const {
        outline.AddPath(&ear.path, FALSE);
        outline.Transform(&transform);
        fill(g, outline, Color(HeadHighlight), Color(Yellow), 44, 140);
        const auto clip = g.Save();
        g.SetClip(&outline, Gdiplus::CombineModeIntersect);
        g.MultiplyTransform(&transform);
        fillSolid(g, earTipInk.path, Color(Ink));
        g.Restore(clip);
        stroke(g, outline);
    }

    void drawFace(Graphics& g, const CatPhysics& physics, Color eyeColor) const {
        const float faceX = physics.headYaw.value * 2.8f;
        const float faceY = physics.headPitch.value * 1.6f;
        const auto clip = g.Save();
        g.SetClip(&head.path, Gdiplus::CombineModeIntersect);
        g.TranslateTransform(faceX, faceY);
        for (const float side : {-1.0f, 1.0f}) {
            const auto cheekState = g.Save();
            g.TranslateTransform(96 + side * 42, 113);
            g.RotateTransform(-side * 0.22f * RadToDeg);
            GraphicsPath cheek;
            cheek.AddEllipse(-9.7f, -12.0f, 19.4f, 24.0f);
            fillSolid(g, cheek, Color(0xfff33b22));
            stroke(g, cheek, 0.9f);
            g.Restore(cheekState);
        }
        g.Restore(clip);

        const auto face = g.Save();
        g.TranslateTransform(faceX, faceY);
        for (const float side : {-1.0f, 1.0f}) {
            drawEye(g, {96 + side * 25.5f, 88.5f}, physics, eyeColor);
        }
        fillSolid(g, nose.path, Color(Ink));
        stroke(g, mouth.path, 0.95f);
        g.Restore(face);
    }

    static void drawEye(Graphics& g, Pt center, const CatPhysics& physics, Color eyeColor) {
        const float close = clamp01(physics.effectiveEyeClosure());
        if (close > 0.82f) {
            Contour lid;
            lid.move({center.x - 7.5f, center.y + 2});
            lid.quad({center.x, center.y + (physics.isHappyClosedEyes() ? -5.0f : 3.5f)},
                     {center.x + 7.5f, center.y + 2});
            stroke(g, lid.path, 1.4f);
            return;
        }

        const Pt gaze = physics.eyeGaze.point();
        const float cx = center.x + gaze.x * 1.2f;
        const float cy = center.y + gaze.y * 1.1f;
        const float width = 8.2f + clamp01(physics.huntIntensity.value) * 1.3f;
        const float height = 8.8f * (1 - close);
        GraphicsPath iris;
        iris.AddEllipse(cx - width, cy - height, width * 2, height * 2);
        fillSolid(g, iris, Color(Ink));

        const auto clip = g.Save();
        g.SetClip(&iris, Gdiplus::CombineModeIntersect);
        Gdiplus::SolidBrush shade(Color(0xff644624));
        g.FillEllipse(&shade, cx - 7.0f, cy + height * 0.43f, 14.0f, height * 0.7f);
        Gdiplus::SolidBrush tint(Color(46, eyeColor.GetR(), eyeColor.GetG(), eyeColor.GetB()));
        g.FillEllipse(&tint, cx - 6.0f, cy + height * 0.6f, 12.0f, height * 0.4f);

        constexpr float halfHighlightWidth = 3.2f;
        const float halfHighlightHeight = height * 0.425f;
        // Ease from the upper-left resting highlight toward the edge in the gaze direction.
        const float magnitude = std::hypot(gaze.x, gaze.y);
        const float reach = clamp01(magnitude / 0.85f);
        const float blend = reach * (2 - reach);
        const float limit = 0.95f - std::max(halfHighlightWidth / width, halfHighlightHeight / height);
        const float travel = blend * limit / std::max(magnitude, 0.001f);
        const float highlightX = -1.6f * (1 - blend) + width * gaze.x * travel;
        const float highlightY = height * (-0.395f * (1 - blend) + gaze.y * travel);
        Gdiplus::SolidBrush white(Color(0xffffffff));
        g.FillEllipse(&white, cx + highlightX - halfHighlightWidth, cy + highlightY - halfHighlightHeight,
                      halfHighlightWidth * 2, halfHighlightHeight * 2);
        g.Restore(clip);
    }
};
