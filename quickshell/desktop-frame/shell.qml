import QtQuick
import Quickshell

ShellRoot {
    id: root

    readonly property bool testMode: Quickshell.env("DESKTOP_FRAME_TEST") === "1"

    FrameService {
        enabled: !root.testMode
    }

    Launcher {
        id: launcher
    }

    Notifications {}

    Component.onCompleted: {
        if (!testMode) return
        var exact = launcher.score({ name: "Firefox", genericName: "Browser", comment: "", keywords: [] }, "firefox")
        var prefix = launcher.score({ name: "Firefox", genericName: "Browser", comment: "", keywords: [] }, "fire")
        var miss = launcher.score({ name: "Firefox", genericName: "Browser", comment: "", keywords: [] }, "terminal")
        if (!(exact < prefix && prefix >= 0 && miss === -1)) throw new Error("desktop-frame search self-test failed")
        Qt.callLater(Qt.quit)
    }
}
