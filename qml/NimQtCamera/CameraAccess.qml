import QtQuick

// Camera permission: status, request, and the OS settings page where access is
// granted. `status` refreshes whenever the app becomes active (e.g. back from
// the settings). Requires the `nimQtCameraBackend` context property
// (qtcamera/qml install()). Named CameraAccess to avoid clashing with QtCore's
// CameraPermission.
QtObject {
    // "undetermined" | "granted" | "denied"
    readonly property string status: nimQtCameraBackend.cameraPermission
    readonly property bool granted: status === "granted"
    // False where the OS has no such page (Linux): show instructions instead.
    readonly property bool canOpenSettings: nimQtCameraBackend.canOpenCameraSettings

    // Shows the OS prompt when the status is "undetermined".
    function request() {
        nimQtCameraBackend.requestCameraPermission()
    }

    // Returns false if the page could not be opened.
    function openSettings() {
        return nimQtCameraBackend.openCameraSettings()
    }
}
