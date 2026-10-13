## Must not create a QGuiApplication: covers calls made before the app exists.
import std/unittest
import ../qtcamera/[types, permission]

suite "no app instance":
  test "openCameraSettings without QGuiApplication returns false": # Review Focus 5
    check not openCameraSettings()
  test "cameraPermissionStatus without QGuiApplication is undetermined":
    check cameraPermissionStatus() == psUndetermined
