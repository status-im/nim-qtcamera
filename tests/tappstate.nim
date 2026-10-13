## "Returning to the app refreshes the camera permission", through the real
## QGuiApplication state-change hook. Simulating the state change needs Qt's
## private QPA header; where it isn't installed (e.g. distro Qt without the
## -private-dev package) this suite is skipped, so the rest of `make test`
## still builds.

import std/[unittest, os, strutils]
import nimqml
import seaqt/QtGui/qtgui_pkg
import ../qtcamera/[types, permission, qml]

const qpaHeaderDir = block:
  # QtGui's private headers (qpa/) live under <QtGui headers>/<version>/QtGui.
  var dir = ""
  let version = QtGuiBuildVersion.strip()
  for f in QtGuiCFlags.splitWhitespace:
    if f.startsWith("-I") and (f.endsWith("QtGui.framework/Headers") or f.endsWith("/QtGui")):
      let candidate = f[2 .. ^1] / version / "QtGui"
      if fileExists(candidate / "qpa" / "qwindowsysteminterface.h"):
        dir = candidate
  dir

const
  simulateMissingQpa {.booldefine: "qtcameraTestNoQpa".} = false
    ## -d:qtcameraTestNoQpa exercises the skip path on a Qt that has the header
  haveQpa = qpaHeaderDir.len > 0 and not simulateMissingQpa

when haveQpa:
  {.compile("appstate.cpp", "-std=c++17 " & QtGuiCFlags & " -I" & qpaHeaderDir.parentDir &
    " -I" & qpaHeaderDir).}
  proc setAppStateForTest(active: cint) {.importc: "qtcamera_test_set_app_state".}

putEnv("QT_QPA_PLATFORM", "offscreen")
let app = newQGuiApplication()

suite "app activation":
  test "returning to the app refreshes the status": # Review Focus 1 (real hook)
    when not haveQpa:
      skip()
    else:
      let b = qtCameraBackend()
      var notified {.global.} = 0
      b.setCameraPermissionChangedHookForTest(proc() {.gcsafe, raises: [].} =
        {.cast(gcsafe).}: inc notified)
      setAppStateForTest(0) # user leaves for the OS settings
      let stale = if cameraPermissionStatus() == psDenied: psGranted else: psDenied
      b.setCameraPermissionForTest(stale)
      notified = 0
      setAppStateForTest(1) # ...and comes back
      check notified == 1
      check b.cameraPermissionValue() == permissionName(cameraPermissionStatus())
      b.setCameraPermissionChangedHookForTest(nil)
