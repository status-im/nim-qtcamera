## Headless host: only a QCoreApplication exists (no QGuiApplication). Built with
## UndefinedBehaviorSanitizer so an invalid QCoreApplication -> QGuiApplication
## downcast (e.g. through Qt's qApp macro) aborts the test.
{.passC: "-fsanitize=undefined -fno-sanitize-recover=undefined".}
{.passL: "-fsanitize=undefined".}

import std/unittest
import seaqt/qcoreapplication
import ../qtcamera/[types, permission]

let app = QCoreApplication.create()

suite "core-only application":
  test "permission status works without a QGuiApplication":
    check cameraPermissionStatus() in {psUndetermined, psGranted, psDenied}
  test "opening settings is refused without a QGuiApplication":
    check not openCameraSettings()
