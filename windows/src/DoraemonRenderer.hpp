#pragma once

#include "CatPhysics.hpp"
#include "ResourceIds.h"
#include <objidl.h>
#include <gdiplus.h>
#include <memory>

class DoraemonRenderer {
public:
    static std::unique_ptr<DoraemonRenderer> load() {
        auto skin = std::make_unique<DoraemonRenderer>();
        Sprite mask;
        if (!skin->head.load(IDR_DORAEMON_HEAD) ||
            !skin->body.load(IDR_DORAEMON_BODY) ||
            !skin->hand.load(IDR_DORAEMON_HAND) ||
            !skin->rightFoot.load(IDR_DORAEMON_RIGHT_FOOT) ||
            !mask.load(IDR_DORAEMON_SHOULDER_MASK) ||
            !skin->buildShoulderMask(*mask.image)) {
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
        pose.figure.TransformPoints(&bodyPoint, 1);
        Gdiplus::PointF facePoint = bodyPoint;
        pose.head.TransformPoints(&facePoint, 1);

        float headX = (facePoint.X - 64.0f) / 39.0f;
        float headY = (facePoint.Y - 46.0f) / 34.0f;
        if (headX * headX + headY * headY <= 1.0f) return CatHitZone::Head;

        float bodyX = (bodyPoint.X - 64.0f) / 44.0f;
        float bodyY = (bodyPoint.Y - 105.0f) / 24.0f;
        if (bodyX * bodyX + bodyY * bodyY <= 1.0f) return CatHitZone::Body;
        return CatHitZone::None;
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
        g.MultiplyTransform(&pose.figure);
        body.draw(g);
        rightFoot.draw(g);
        g.Restore(behindKeyboard);

        g.MultiplyTransform(&pose.body);
        pose.body.Invert();
        const Wrist left = wristPose(physics.leftPaw.point(), CatPhysics::LeftPawRest, {27.5f, 98.1f}, pose.body);
        const Wrist right = wristPose(physics.rightPaw.point(), CatPhysics::RightPawRest, {100.5f, 98.1f}, pose.body);
        PointF shoulders[] = {{43.0f, 87.5f}, {85.0f, 87.5f}};
        pose.figure.TransformPoints(shoulders, 2);
        drawSleeve(g, shoulders[0], left);
        drawSleeve(g, shoulders[1], right);
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
    static constexpr float ArtworkScale = 1.12f;
    static Gdiplus::Color ink() { return Gdiplus::Color(255, 11, 17, 22); }

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

    struct Pose {
        Gdiplus::Matrix body;
        Gdiplus::Matrix figure{ArtworkScale, 0, 0, ArtworkScale,
                               64.0f * (1 - ArtworkScale), 128.0f * (1 - ArtworkScale)};
        Gdiplus::Matrix head;

        explicit Pose(const CatPhysics& physics) {
            const float size = 1.50f * (1.0f - physics.huntIntensity.value * 0.05f);
            body.Translate(CatPhysics::SeatAnchor.x + physics.bodyShiftX.value, CatPhysics::SeatAnchor.y + 24.0f);
            body.Rotate(physics.bodyTilt.value * 0.65f * RadToDeg);
            body.Scale(size, size);
            body.Translate(-64.0f, -128.0f);

            const float yaw = physics.headYaw.value;
            const float breath = std::sin(physics.time * 2.1f) * 0.55f;
            head.Translate(64.0f + yaw * 1.4f, 78.0f + physics.headPitch.value * 0.85f + breath);
            head.Rotate(physics.headTilt.value * 0.45f * RadToDeg);
            head.Scale(1.0f - std::abs(yaw) * 0.035f, 1.0f);
            head.Translate(-64.0f, -78.0f);
        }
    };

    struct Wrist {
        Gdiplus::PointF point;
        float reach;
    };

    Sprite head;
    Sprite body;
    Sprite hand;
    Sprite rightFoot;
    Gdiplus::GraphicsPath shoulderMask;

    bool buildShoulderMask(Gdiplus::Bitmap& mask) {
        using namespace Gdiplus;
        // GDI+ clips to paths. Convert the dark part of the shared grayscale mask
        // into a path once, so the outlines can join the body without a dark seam.
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
                    shoulderMask.AddRectangle(RectF(
                        64.0f + (start + maskOrigin - 64.0f) * ArtworkScale,
                        128.0f + (y + maskOrigin - 128.0f) * ArtworkScale,
                        (x - start) * ArtworkScale, ArtworkScale));
                    start = -1;
                }
            }
        }
        mask.UnlockBits(&data);
        return shoulderMask.GetPointCount() > 0;
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

    void drawSleeve(Gdiplus::Graphics& g, Gdiplus::PointF shoulder, const Wrist& wrist) const {
        using namespace Gdiplus;
        const PointF delta = wrist.point - shoulder;
        const float length = std::max(1.0f, std::hypot(delta.X, delta.Y));
        const PointF normal(-delta.Y / length, delta.X / length);
        const PointF middle = scaled(shoulder + wrist.point, 0.5f);
        const float middleHalfWidth = (5.8f + 5.45f) / 2.0f + 1.6f * (1.0f - wrist.reach);
        const PointF shoulderEdge = scaled(normal, 5.8f);
        const PointF wristEdge = scaled(normal, 5.45f);
        const PointF middleEdge = scaled(normal, middleHalfWidth);

        GraphicsPath sleeve;
        addCurve(sleeve, shoulder + shoulderEdge, middle + middleEdge, wrist.point + wristEdge);
        sleeve.AddLine(wrist.point + wristEdge, wrist.point - wristEdge);
        addCurve(sleeve, wrist.point - wristEdge, middle - middleEdge, shoulder - shoulderEdge);
        addCurve(sleeve, shoulder - shoulderEdge, shoulder - scaled(delta, 5.0f / length), shoulder + shoulderEdge);
        sleeve.CloseFigure();

        SolidBrush blue(Color(255, 0, 159, 222));
        g.FillPath(&blue, &sleeve);

        GraphicsState outline = g.Save();
        g.SetClip(&shoulderMask, CombineModeExclude);
        Pen edge(ink(), 1.45f);
        edge.SetLineJoin(LineJoinRound);
        g.DrawPath(&edge, &sleeve);
        g.Restore(outline);
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
