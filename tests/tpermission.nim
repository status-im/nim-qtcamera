import std/unittest
import ../qtcamera/[types, permission]
import ./testutils

ensureApp()

suite "permission":
  test "status is a valid enum value and does not prompt":
    check cameraPermissionStatus() in {psUndetermined, psGranted, psDenied}
