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
    // Whether request() may still show the OS prompt. Android lets the user be
    // asked again after an ordinary denial, but Qt reports every denial as
    // "denied" for the rest of the process, "don't ask again" or not: request
    // again and let the OS decide (no prompt -> status stays "denied"). On
    // iOS/macOS a denial is final; only the settings page can change it.
    readonly property bool canRequest: status === "undetermined"
                                       || (status === "denied" && Qt.platform.os === "android")
    // False where the OS has no such page (Linux): show instructions instead.
    readonly property bool canOpenSettings: nimQtCameraBackend.canOpenCameraSettings

    // Shows the OS prompt when it can be shown (see canRequest).
    function request() {
        nimQtCameraBackend.requestCameraPermission()
    }

    // Returns false if the page could not be opened.
    function openSettings() {
        return nimQtCameraBackend.openCameraSettings()
    }
}
