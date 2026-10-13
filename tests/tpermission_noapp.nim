## Must not create a QGuiApplication: covers calls made before the app exists.
import std/unittest
import ../qtcamera/permission

suite "no app instance":
  test "openCameraSettings without QGuiApplication returns false": # Review Focus 5
    check not openCameraSettings()
