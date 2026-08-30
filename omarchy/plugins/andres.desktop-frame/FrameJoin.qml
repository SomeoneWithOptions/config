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
    smooth: true
    antialiasing: true
    // Supersample the curve edge (cheap at this size, visibly smoother).
    layer.enabled: true
    layer.smooth: true
    layer.samples: 4

    ShapePath {
        strokeWidth: 0
        fillGradient: RadialGradient {
            centerX: 0
            centerY: root.height
            centerRadius: root.width
            focalX: centerX
            focalY: centerY
            // Feather last ~14% (≈2.5px at 18px) — soft edge, zero stair.
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.86; color: "transparent" }
            GradientStop { position: 1.0; color: style.frameColor }
        }
        PathSvg {
            path: "M 0 0 L " + root.width + " 0 L " + root.width + " " + root.height
                + " L 0 " + root.height + " Z"
        }
    }
}
