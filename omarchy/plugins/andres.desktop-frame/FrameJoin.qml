import QtQuick
import QtQuick.Shapes

// Concave fillet between top strip and drawer — same geometry as Walker's
// tidy menu, feathered for crisp curves on fractional scale.
// CurveRenderer + feathered radial avoids the 0.98→1 aliased ring that
// showed pixels on black unions.
Shape {
    id: root

    FrameStyle { id: style }

    width: style.cornerRadius
    height: style.cornerRadius
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: 0
        fillGradient: RadialGradient {
            centerX: 0
            centerY: root.height
            centerRadius: root.width
            focalX: centerX
            focalY: centerY
            // Tight 0.96→1 feather (~0.7px at 18px) — crisp flush edge, just enough for antialias
            // on fractional scale. Previous 0.86 left a visible halo/soft look.
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.96; color: "transparent" }
            GradientStop { position: 1.0; color: style.frameColor }
        }
        PathSvg {
            path: "M 0 0 L " + root.width + " 0 L " + root.width + " " + root.height
                + " L 0 " + root.height + " Z"
        }
    }
}
