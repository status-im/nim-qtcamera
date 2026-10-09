import QtQuick

// Pulls luma frames from a QVideoSink (e.g. VideoOutput.videoSink).
// Requires the `nimQtCameraBackend` context property (qtcamera/qml install()).
QtObject {
    id: root

    property var videoSink: null
    property bool enabled: true
    // 0 = every frame; otherwise pulls are capped at this rate.
    property real maxFps: 0
    // 0 = full resolution; otherwise the largest side is <= maxDim.
    property int maxDim: 0

    // Backend handle; other Nim libraries use it to consume frames.
    readonly property int handle: d.handle

    readonly property int framesSeen: d.framesSeen
    readonly property int framesPulled: d.framesPulled
    readonly property int pixelFormat: d.pixelFormat
    readonly property int frameWidth: d.frameWidth
    readonly property int frameHeight: d.frameHeight

    signal framePulled()

    // Normalized frame coordinates (0..1), before preview mirroring.
    function setRoi(x, y, w, h) {
        nimQtCameraBackend.setTapRoi(d.handle, x, y, w, h)
    }

    function clearRoi() {
        nimQtCameraBackend.clearTapRoi(d.handle)
    }

    onVideoSinkChanged: nimQtCameraBackend.attachTap(d.handle, videoSink)
    onEnabledChanged: nimQtCameraBackend.setTapEnabled(d.handle, enabled)
    onMaxFpsChanged: nimQtCameraBackend.setTapOptions(d.handle, maxFps, maxDim)
    onMaxDimChanged: nimQtCameraBackend.setTapOptions(d.handle, maxFps, maxDim)

    Component.onCompleted: {
        nimQtCameraBackend.setTapOptions(d.handle, maxFps, maxDim)
        nimQtCameraBackend.setTapEnabled(d.handle, enabled)
        nimQtCameraBackend.attachTap(d.handle, videoSink)
    }

    Component.onDestruction: nimQtCameraBackend.destroyTap(d.handle)

    readonly property QtObject _d: QtObject {
        id: d

        readonly property int handle: nimQtCameraBackend.createTap()
        property int framesSeen: 0
        property int framesPulled: 0
        property int pixelFormat: 0
        property int frameWidth: 0
        property int frameHeight: 0

        function refresh() {
            framesSeen = nimQtCameraBackend.tapFramesSeen(handle)
            framesPulled = nimQtCameraBackend.tapFramesPulled(handle)
            pixelFormat = nimQtCameraBackend.tapPixelFormat(handle)
            frameWidth = nimQtCameraBackend.tapFrameWidth(handle)
            frameHeight = nimQtCameraBackend.tapFrameHeight(handle)
        }
    }

    readonly property Connections _backendConnection: Connections {
        target: nimQtCameraBackend

        function onTapPulled(h) {
            if (h !== d.handle)
                return
            d.refresh()
            root.framePulled()
        }
    }
}
