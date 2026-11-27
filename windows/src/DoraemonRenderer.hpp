#pragma once

#include "CatPhysics.hpp"
#include "CharacterDragPose.hpp"
#include "ResourceIds.h"
#include <objidl.h>
#include <gdiplus.h>
#include <memory>

class DoraemonRenderer {
public:
    static constexpr Pt ScruffGrip{kurorig::SeatX, kurorig::DoraemonCanvasGripY};

    static std::unique_ptr<DoraemonRenderer> load() {
        auto skin = std::make_unique<DoraemonRenderer>();
        Sprite mask;
        if (!skin->head.load(IDR_DORAEMON_HEAD) ||
            !skin->body.load(IDR_DORAEMON_BODY) ||
            !skin->hand.load(IDR_DORAEMON_HAND) ||
            !skin->rightFoot.load(IDR_DORAEMON_RIGHT_FOOT) ||
            !mask.load(IDR_DORAEMON_SHOULDER_MASK) ||
            !skin->buildShoulderMasks(*mask.image)) {
            return nullptr;
        }
        return skin;
    }

    static CatHitZone hitTest(Pt point, const CatPhysics& physics) {
        Pose pose(physics);
        pose.body.Invert();
        pose.figure.Invert();
        pose.head.Invert();
        Gdiplus::PointF bodyPoint(point.x, point.y);
        pose.body.TransformPoints(&bodyPoint, 1);
        Gdiplus::PointF facePoint = bodyPoint;
        pose.figure.TransformPoints(&facePoint, 1);
        pose.head.TransformPoints(&facePoint, 1);

        float headX = (facePoint.X - 64.0f) / 39.0f;
        float headY = (facePoint.Y - 46.0f) / 34.0f;
        if (headX * headX + headY * headY <= 1.0f) return CatHitZone::Head;

        auto torso = pose.drag.torso(86);
        torso.Invert();
        torso.TransformPoints(&bodyPoint, 1);
        pose.figure.TransformPoints(&bodyPoint, 1);
        float bodyX = (bodyPoint.X - 64.0f) / 44.0f;
        float bodyY = (bodyPoint.Y - 105.0f) / 24.0f;
        if (bodyX * bodyX + bodyY * bodyY <= 1.0f) return CatHitZone::Body;
        return CatHitZone::None;
    }

    static CharacterDragPose::Hands dragHands(const CatPhysics& physics) {
        Pose pose(physics);
        const auto wrists = pose.wrists(physics);
        return {CharacterDragPose::map({wrists.left.point.X, wrists.left.point.Y}, pose.body),
                CharacterDragPose::map({wrists.right.point.X, wrists.right.point.Y}, pose.body)};
    }

    void draw(Gdiplus::Graphics& g, const CatPhysics& physics, Gdiplus::Color eyeColor,
              const Gdiplus::GraphicsPath& keyboardDeck) const {
        using namespace Gdiplus;
        Pose pose(physics);
        GraphicsState scene = g.Save();
        g.SetInterpolationMode(InterpolationModeHighQualityBicubic);

        GraphicsState behindKeyboard = g.Save();
        g.SetClip(&keyboardDeck, CombineModeExclude);
        g.MultiplyTransform(&pose.body);
        const auto torso = pose.drag.torso(86);
        g.MultiplyTransform(&torso);
        g.MultiplyTransform(&pose.figure);
        body.draw(g);
        rightFoot.draw(g);
        g.Restore(behindKeyboard);

        g.MultiplyTransform(&pose.body);
        const auto [left, right] = pose.wrists(physics);
        drawSleeve(g, pose.figure, left, true);
        drawSleeve(g, pose.figure, right, false);
        hand.draw(g, left.point.X - 99.0f, left.point.Y - 107.2f);
        hand.draw(g, right.point.X - 99.0f, right.point.Y - 107.2f);

        g.MultiplyTransform(&pose.figure);
        g.MultiplyTransform(&pose.head);
        head.draw(g);
        drawEyes(g, physics, eyeColor);
        g.Restore(scene);
    }

private:
    static constexpr float SpriteSize = 128.0f;
    static constexpr float RadToDeg = 57.2957795f;
    static constexpr float BodyScale = 1.6f;
    static constexpr float ArtworkScale = 1.12f;
    static Gdiplus::Color ink(BYTE alpha = 255) { return Gdiplus::Color(alpha, 11, 17, 22); }

    struct Sprite {
        struct ReleaseStream {
            void operator()(IStream* stream) const { stream->Release(); }
        };
        // GDI+ decodes stream-backed images lazily. Destroy the bitmap before releasing the stream.
        std::unique_ptr<IStream, ReleaseStream> stream;
        std::unique_ptr<Gdiplus::Bitmap> image;

        bool load(int id) {
            HMODULE module = GetModuleHandleW(nullptr);
            HRSRC resource = FindResourceW(module, MAKEINTRESOURCEW(id), RT_RCDATA);
            if (!resource) return false;
            const void* bytes = LockResource(LoadResource(module, resource));
            const DWORD size = SizeofResource(module, resource);
            if (!bytes || !size) return false;

            IStream* backing = nullptr;
            if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &backing))) return false;
            stream.reset(backing);
            ULONG written = 0;
            LARGE_INTEGER beginning{};
            if (FAILED(stream->Write(bytes, size, &written)) || written != size ||
                FAILED(stream->Seek(beginning, STREAM_SEEK_SET, nullptr))) return false;
            image.reset(Gdiplus::Bitmap::FromStream(stream.get()));
            return image && image->GetLastStatus() == Gdiplus::Ok;
        }

        void draw(Gdiplus::Graphics& g, float x = 0, float y = 0) const {
            g.DrawImage(image.get(), Gdiplus::RectF(x, y, SpriteSize, SpriteSize));
        }
    };

    struct Wrist {
        Gdiplus::PointF point;
        float reach;
    };

    struct Wrists { Wrist left, right; };

    struct Pose {
        Gdiplus::Matrix body;
        Gdiplus::Matrix figure{ArtworkScale, 0, 0, ArtworkScale,
                               64.0f * (1 - ArtworkScale), 128.0f * (1 - ArtworkScale)};
        Gdiplus::Matrix head;
        CharacterDragPose drag;

        explicit Pose(const CatPhysics& physics) : drag(physics) {
            body.Translate(CatPhysics::SeatAnchor.x + physics.bodyShiftX.value, CatPhysics::SeatAnchor.y + 24.0f);
            body.Rotate(physics.bodyTilt.value * 0.65f * (1 - drag.lift) * RadToDeg);
            body.Scale(BodyScale, BodyScale);
            body.Translate(-64.0f, -128.0f);

            const float yaw = physics.headYaw.value;
            const float breath = std::sin(physics.time * 2.1f) * 0.55f;
            head.Translate(64.0f + yaw * 1.4f, 78.0f + physics.headPitch.value * 0.85f + breath);
            head.Rotate(physics.headTilt.value * 0.45f * RadToDeg);
            head.Translate(-64.0f, -78.0f);
            const Pt grip = CharacterDragPose::map({64, kurorig::DoraemonArtGripY}, head);
            drag.suspend(body, CharacterDragPose::map(grip, figure), ScruffGrip);
        }

        Wrists wrists(const CatPhysics& physics) const {
            Gdiplus::Matrix inverse;
            inverse.Multiply(&body);
            inverse.Invert();
            const Wrist left = wristPose(physics.leftPaw.point(), CatPhysics::LeftPawRest, {27.5f, 98.1f}, inverse);
            const Wrist right = wristPose(physics.rightPaw.point(), CatPhysics::RightPawRest, {100.5f, 98.1f}, inverse);
            const auto suspend = [&](Wrist wrist, float side, float y) -> Wrist {
                const Pt hanging{64 + side * kurorig::DoraemonWristSpread, y};
                const Pt point = drag.wrist({wrist.point.X, wrist.point.Y}, hanging);
                return {{point.x, point.y}, wrist.reach * (1 - drag.lift)};
            };
            return {suspend(left, -1, kurorig::DoraemonWristY),
                    suspend(right, 1, kurorig::DoraemonKeyboardWristY)};
        }
    };

    Sprite head;
    Sprite body;
    Sprite hand;
    Sprite rightFoot;
    Gdiplus::GraphicsPath leftShoulderMask;
    Gdiplus::GraphicsPath rightShoulderMask;

    bool buildShoulderMasks(Gdiplus::Bitmap& mask) {
        using namespace Gdiplus;
        // GDI+ clips to paths. Convert the dark part of the shared grayscale mask
        // to a path, then mirror it to preserve the stroke on a cross-body reach.
        const Rect pixels(0, 0, static_cast<INT>(mask.GetWidth()), static_cast<INT>(mask.GetHeight()));
        if (pixels.Width == 0 || pixels.Height == 0) return false;
        BitmapData data{};
        if (mask.LockBits(&pixels, ImageLockModeRead, PixelFormat32bppARGB, &data) != Ok) return false;

        constexpr int maskSize = 256;
        constexpr float maskOrigin = -64.0f;
        for (int y = 0; y < maskSize; ++y) {
            const auto* row = static_cast<const BYTE*>(data.Scan0) + data.Stride * (y * pixels.Height / maskSize);
            int start = -1;
            for (int x = 0; x <= maskSize; ++x) {
                const bool covered = x < maskSize && row[(x * pixels.Width / maskSize) * 4] < 128;
                if (covered && start < 0) {
                    start = x;
                } else if (!covered && start >= 0) {
                    leftShoulderMask.AddRectangle(RectF(
                        64.0f + (start + maskOrigin - 64.0f) * ArtworkScale,
                        128.0f + (y + maskOrigin - 128.0f) * ArtworkScale,
                        (x - start) * ArtworkScale, ArtworkScale));
                    start = -1;
                }
            }
        }
        mask.UnlockBits(&data);
        Matrix mirror(-1.0f, 0, 0, 1.0f, SpriteSize, 0);
        return leftShoulderMask.GetPointCount() > 0 &&
               rightShoulderMask.AddPath(&leftShoulderMask, FALSE) == Ok &&
               rightShoulderMask.Transform(&mirror) == Ok;
    }

    static Wrist wristPose(Pt paw, Pt rest, Gdiplus::PointF idle, const Gdiplus::Matrix& toBody) {
        const float progress = std::min(1.0f, std::hypot(paw.x - rest.x, paw.y - rest.y) / 10.0f);
        const float reach = progress * progress * (3.0f - 2.0f * progress);
        Gdiplus::PointF target(paw.x, paw.y);
        toBody.TransformPoints(&target, 1);
        return {{idle.X + (target.X - idle.X) * reach, idle.Y + (target.Y - idle.Y) * reach}, reach};
    }

    static Gdiplus::PointF scaled(Gdiplus::PointF point, float scale) {
        return {point.X * scale, point.Y * scale};
    }

    static void addCurve(Gdiplus::GraphicsPath& path, Gdiplus::PointF start,
                         Gdiplus::PointF control, Gdiplus::PointF end) {
        const auto first = start + scaled(control - start, 2.0f / 3.0f);
        const auto second = end + scaled(control - end, 2.0f / 3.0f);
        path.AddBezier(start, first, second, end);
    }

    void drawSleeve(Gdiplus::Graphics& g, const Gdiplus::Matrix& figure, const Wrist& wrist, bool isLeft) const {
        using namespace Gdiplus;
        const float side = isLeft ? -1.0f : 1.0f;
        const float relaxed = 1.0f - wrist.reach;
        PointF shoulder(64.0f + side * (20.0f + 0.5f * relaxed), 86.0f);
        figure.TransformPoints(&shoulder, 1);
        const PointF delta = wrist.point - shoulder;
        // In the resting pose the upper arm angles out toward the hand from the collar.
        const float shoulderOutward = side * (0.38f + 0.30f * relaxed);
        const float shoulderDown = 0.925f - 0.192f * relaxed;
        const float shoulderCurveLength = std::min(std::hypot(delta.X, delta.Y) * 0.35f, 10.0f);
        const PointF shoulderControl = shoulder + scaled({shoulderOutward, shoulderDown}, shoulderCurveLength);
        const PointF wristControl = wrist.point - scaled(delta, 0.33f);

        GraphicsPath sleeve;
        sleeve.AddBezier(shoulder, shoulderControl, wristControl, wrist.point);
        constexpr float sleeveWidth = 10.9f;
        constexpr float outlineWidth = 1.45f;

        // Keep the short inner edge visible just above the hand in the resting pose.
        if (relaxed > 0.0f) {
            const RectF bounds(wrist.point.X - side * 8.0f - 7.0f, wrist.point.Y - 11.0f, 14.0f, 16.0f);
            const Color restInk = ink(static_cast<BYTE>(relaxed * 255.0f));
            const Color transparentInk = ink(0);
            const Color colors[] = {transparentInk, transparentInk, restInk, restInk};
            const REAL stops[] = {0.0f, 2.0f / 16.0f, 7.0f / 16.0f, 1.0f};
            LinearGradientBrush fade(bounds, transparentInk, restInk, LinearGradientModeVertical);
            fade.SetInterpolationColors(colors, stops, 4);
            Pen innerEdge(&fade, sleeveWidth + outlineWidth);
            GraphicsPath nearHand;
            nearHand.AddEllipse(bounds);
            GraphicsState innerOutline = g.Save();
            g.SetClip(&nearHand, CombineModeIntersect);
            g.DrawPath(&innerEdge, &sleeve);
            g.Restore(innerOutline);
        }

        GraphicsState outline = g.Save();
        g.SetClip(isLeft ? &leftShoulderMask : &rightShoulderMask, CombineModeExclude);
        Pen edge(ink(), sleeveWidth + outlineWidth);
        g.DrawPath(&edge, &sleeve);
        g.Restore(outline);

        Pen blue(Color(255, 0, 159, 222), sleeveWidth - outlineWidth);
        g.DrawPath(&blue, &sleeve);
    }

    static void drawEyes(Gdiplus::Graphics& g, const CatPhysics& physics, Gdiplus::Color tint) {
        using namespace Gdiplus;
        const float closure = physics.effectiveEyeClosure();
        const float hunt = std::clamp(physics.huntIntensity.value, 0.0f, 1.0f);
        const Pt gaze = physics.eyeGaze.point();
        SolidBrush pupil(ink());
        SolidBrush glow(Color(static_cast<BYTE>(hunt * 0.85f * 255), tint.GetR(), tint.GetG(), tint.GetB()));
        for (const float side : {-1.0f, 1.0f}) {
            const PointF center(64.0f + side * 8.1f, 34.4f);
            if (closure >= 0.62f) {
                GraphicsPath lid;
                addCurve(lid, center + PointF(-4.0f, 2.0f),
                         center + PointF(0, physics.isHappyClosedEyes() ? -3.0f : 0.0f),
                         center + PointF(4.0f, 2.0f));
                Pen line(ink(), 1.6f);
                line.SetStartCap(LineCapRound);
                line.SetEndCap(LineCapRound);
                g.DrawPath(&line, &lid);
                continue;
            }

            const float x = center.X - side + gaze.x * 2.4f;
            const float y = center.Y + 1.4f + gaze.y * 2.4f;
            const float w = (2.1f + hunt * 1.8f) * physics.pupilScale.value;
            const float h = (3.1f + hunt * 0.8f) * (1.0f - closure);
            GraphicsState eye = g.Save();
            GraphicsPath eyeShape;
            eyeShape.AddEllipse(center.X - 7.3f, center.Y - 8.7f, 14.6f, 16.5f);
            g.SetClip(&eyeShape, CombineModeIntersect);
            if (hunt > 0.01f) g.FillEllipse(&glow, x - w - 1.1f, y - h - 1.1f, 2 * w + 2.2f, 2 * h + 2.2f);
            g.FillEllipse(&pupil, x - w, y - h, 2 * w, 2 * h);
            g.Restore(eye);
        }
    }
};
