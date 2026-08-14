import QtQuick
import QtQuick.Shapes

// Same radial fillet as Walker's tidy Omarchy menu. Rotate by quarter turns
// for drawers attached to other frame sides.
Shape {
    id: root

    FrameStyle { id: style }

    width: style.cornerRadius
    height: style.cornerRadius
    preferredRendererType: Shape.GeometryRenderer

    ShapePath {
        strokeWidth: 0
        fillGradient: RadialGradient {
            centerX: 0
            centerY: root.height
            centerRadius: root.width
            focalX: centerX
            focalY: centerY
            GradientStop { position: 0.98; color: "transparent" }
            GradientStop { position: 1; color: style.frameColor }
        }
        PathSvg {
            path: "M 0 0 L " + root.width + " 0 L " + root.width + " " + root.height
                + " L 0 " + root.height + " Z"
        }
    }
}
