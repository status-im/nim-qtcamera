import QtQuick

// Pulls luma frames from a QVideoSink (e.g. VideoOutput.videoSink).
// Requires the `nimQtCameraBackend` context property (qtcamera/qml install()).
QtObject {
    id: root

    property var videoSink: null
    property bool enabled: true
    // Pull cap. 0 = every frame (costly: one luma copy per frame).
    property real maxFps: 5
    // 0 = full resolution; otherwise the largest side is <= maxDim.
    property int maxDim: 0

    // Backend handle; other Nim libraries use it to consume frames.
    readonly property int handle: d.handle

    readonly property int framesSeen: d.framesSeen
    readonly property int framesPulled: d.framesPulled
    readonly property int pixelFormat: d.pixelFormat
    readonly property int frameWidth: d.frameWidth
    readonly property int frameHeight: d.frameHeight
    // How the last pulled frame is displayed: clockwise degrees, then mirrored.
    readonly property int frameRotation: d.frameRotation
    readonly property bool frameMirrored: d.frameMirrored

    signal framePulled()

    // Normalized raw-frame coordinates (0..1), before the frame's rotation
    // and any mirroring. See setDisplayRoi for rects taken from the preview.
    function setRoi(x, y, w, h) {
        nimQtCameraBackend.setTapRoi(d.handle, x, y, w, h)
    }

    // Normalized coordinates of the frame as displayed: its rotation and
    // mirroring applied (e.g. a rect taken from a VideoOutput), before the
    // VideoOutput's own mirroring. Converted per frame.
    function setDisplayRoi(x, y, w, h) {
        nimQtCameraBackend.setTapDisplayRoi(d.handle, x, y, w, h)
    }

    // A rect on the preview item (item pixels), with the preview's size, its
    // fillMode (VideoOutput.fillMode) and mirrored. Mapped for each frame from
    // that frame's own size and rotation, as VideoOutput lays it out, so it
    // holds from the first frame and through size or rotation changes
    // (VideoOutput.contentRect follows a new frame size only later).
    function setPreviewRoi(x, y, w, h, previewWidth, previewHeight, fillMode, mirrored) {
        nimQtCameraBackend.setTapPreviewRoi(d.handle, x, y, w, h, previewWidth,
                                            previewHeight, fillMode, mirrored)
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

        // Created on first read and cached: re-evaluating this binding (e.g. if
        // the context property is set again) must not create another tap.
        // `cache` is a plain JS object so writing to it notifies nothing.
        readonly property var cache: ({ handle: 0 })
        readonly property int handle: {
            if (cache.handle === 0)
                cache.handle = nimQtCameraBackend.createTap()
            return cache.handle
        }
        property int framesSeen: 0
        property int framesPulled: 0
        property int pixelFormat: 0
        property int frameWidth: 0
        property int frameHeight: 0
        property int frameRotation: 0
        property bool frameMirrored: false

        function refresh() {
            framesSeen = nimQtCameraBackend.tapFramesSeen(handle)
            framesPulled = nimQtCameraBackend.tapFramesPulled(handle)
            pixelFormat = nimQtCameraBackend.tapPixelFormat(handle)
            frameWidth = nimQtCameraBackend.tapFrameWidth(handle)
            frameHeight = nimQtCameraBackend.tapFrameHeight(handle)
            frameRotation = nimQtCameraBackend.tapFrameRotation(handle)
            frameMirrored = nimQtCameraBackend.tapFrameMirrored(handle)
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
