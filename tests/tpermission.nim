import std/unittest
import results
import ../qtcamera/[types, permission]
import ./testutils

ensureApp()

suite "permission":
  test "status is a valid enum value and does not prompt":
    check cameraPermissionStatus() in {psUndetermined, psGranted, psDenied}

suite "camera settings":
  test "platform capability table": # Review Focus 4
    when defined(macosx):
      check cameraSettingsUrl().get ==
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
      check canOpenCameraSettings()
    elif defined(windows):
      check cameraSettingsUrl().get == "ms-settings:privacy-webcam"
      check canOpenCameraSettings()
    elif defined(ios):
      check cameraSettingsUrl().get == "app-settings:"
      check canOpenCameraSettings()
    elif defined(android):
      check cameraSettingsUrl().isNone # an intent, not a URL
      check canOpenCameraSettings()
    else:
      check cameraSettingsUrl().isNone
      check not canOpenCameraSettings()
      check not openCameraSettings() # never attempts anything on Linux
