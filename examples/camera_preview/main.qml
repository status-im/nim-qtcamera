import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import NimQtCamera 1.0

ApplicationWindow {
    width: 900
    height: 640
    visible: true
    title: "nim-qtcamera preview"

    MediaDevices { id: mediaDevices }

    CameraAccess {
        id: access
        Component.onCompleted: if (status === "undetermined") request()
    }

    CaptureSession {
        camera: Camera {
            id: camera
            active: access.granted
                    && activeSwitch.checked
                    && Qt.application.state === Qt.ApplicationActive
            focusMode: Camera.FocusModeAutoNear
        }
        videoOutput: preview
    }

    FrameTap {
        id: tap
        videoSink: preview.videoSink
        enabled: camera.active
        maxFps: fpsSlider.value
        maxDim: 640
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12

        RowLayout {
            ComboBox {
                Layout.preferredWidth: 260
                model: mediaDevices.videoInputs
                textRole: "description"
                onActivated: camera.cameraDevice = mediaDevices.videoInputs[currentIndex]
            }
            Switch { id: activeSwitch; text: "Active"; checked: true }
            Label { text: "max fps" }
            Slider { id: fpsSlider; from: 0; to: 30; stepSize: 1; value: 10 }
            Label { text: fpsSlider.value === 0 ? "all" : fpsSlider.value }
            Label {
                visible: access.status === "denied"
                text: access.canOpenSettings ? "Camera access is off"
                                             : "Enable camera access in your system settings"
                color: "red"
            }
            Button {
                visible: access.status === "denied" && access.canOpenSettings
                text: "Open settings"
                onClicked: access.openSettings()
            }
        }

        VideoOutput {
            id: preview
            Layout.fillWidth: true
            Layout.fillHeight: true
            fillMode: VideoOutput.PreserveAspectCrop
        }

        Label {
            text: `seen ${tap.framesSeen}   pulled ${tap.framesPulled}   format ${tap.pixelFormat}   ${tap.frameWidth}x${tap.frameHeight}`
                  + (camera.errorString ? `   error: ${camera.errorString}` : "")
        }
    }
}
