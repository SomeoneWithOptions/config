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
            // 0.98→1 feather (~0.36px) — minimal halo, CurveRenderer does antialias.
            // 0.96 left faint soft edge that read as gap; 0.86 was too haloed.
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.98; color: "transparent" }
            GradientStop { position: 1.0; color: style.frameColor }
        }
        PathSvg {
            path: "M 0 0 L " + root.width + " 0 L " + root.width + " " + root.height
                + " L 0 " + root.height + " Z"
        }
    }
}
