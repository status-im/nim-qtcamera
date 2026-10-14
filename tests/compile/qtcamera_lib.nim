## Compile check for targets where tests aren't run (iOS, Android): the core
## and the QML layer, built as a static library by scripts/build-mobile.sh.
import ../../qtcamera
import ../../qtcamera/qml

proc qtcameraCompileCheck() {.exportc.} =
  discard qtCameraBackend()
  discard listCameras()
