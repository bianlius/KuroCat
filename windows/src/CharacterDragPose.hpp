#pragma once

#include "CatPhysics.hpp"
#include "../../shared/Rig.hpp"
#include <objidl.h>
#include <gdiplus.h>

struct CharacterDragPose {
    struct Hands { Pt left, right; };

    explicit CharacterDragPose(const CatPhysics& physics)
        : lift(ease(physics.scruffDrag.value)),
          swing(std::clamp(physics.scruffSwing.value, -1.0f, 1.0f)),
          verticalSwing(std::clamp(physics.scruffSwingY.value, -1.0f, 1.0f)) {}

    const float lift;

    static Pt map(Pt point, const Gdiplus::Matrix& transform) {
        Gdiplus::PointF value(point.x, point.y);
        transform.TransformPoints(&value, 1);
        return {value.X, value.Y};
    }

    void suspend(Gdiplus::Matrix& body, Pt localGrip, Pt canvasGrip, float maxAngle = 0.23f) const {
        const Pt grip = map(localGrip, body);
        const auto suspension = transform(grip, interpolate(grip, canvasGrip), swing * lift * maxAngle);
        body.Multiply(&suspension, Gdiplus::MatrixOrderAppend);
    }

    Gdiplus::Matrix torso(float shoulderY) const {
        const float stretch = 1.0f + lift * (0.12f + verticalSwing * 0.04f);
        return {1, 0, 0, stretch, 0, shoulderY * (1 - stretch)};
    }

    Pt wrist(Pt seated, Pt hanging) const {
        return interpolate(seated, {hanging.x - swing * 4, hanging.y + verticalSwing * 4});
    }

    Gdiplus::Matrix keyboardTransform(Pt hand, bool isPikachu) const {
        const float u = isPikachu ? kurorig::PikachuKeyboardGripU : kurorig::DoraemonKeyboardGripU;
        const Pt desk = KeyboardLayout::screenQuadPoint(u, kurorig::KeyboardGripV);
        return device(desk, hand, 0.26f);
    }

    Gdiplus::Matrix pointerTransform(const CatPhysics& physics, Pt hand) const {
        const Pt offset = physics.mouseOffset.point();
        const Pt desk = physics.isTabletActive ? CatPhysics::tabletQuadPoint(0.62f, 0.12f)
            : Pt{CatPhysics::MouseBaseCenter.x + offset.x, CatPhysics::MouseBaseCenter.y + offset.y - 10};
        return device(desk, hand, 0.54f);
    }

private:
    float swing;
    float verticalSwing;

    static float ease(float value) {
        const float p = std::clamp(value, 0.0f, 1.0f);
        return p * p * (3 - 2 * p);
    }

    Pt interpolate(Pt start, Pt end) const {
        return {start.x + (end.x - start.x) * lift, start.y + (end.y - start.y) * lift};
    }

    Gdiplus::Matrix device(Pt desk, Pt grip, float angle) const {
        return transform(desk, interpolate(desk, grip), (angle + swing * 0.23f) * lift);
    }

    static Gdiplus::Matrix transform(Pt from, Pt to, float angle) {
        const float c = std::cos(angle);
        const float s = std::sin(angle);
        return {c, s, -s, c, to.x - from.x * c + from.y * s, to.y - from.x * s - from.y * c};
    }
};
