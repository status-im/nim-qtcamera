import std/[unittest, os]
import results
import ../qtcamera
import ./testutils

ensureApp()

suite "CameraSession (no activation)":
  test "fresh session is inactive with a headless sink":
    let s = newCameraSession()
    check not s.isActive
    check s.errorKind == ceNone
    check s.videoSink.h != nil
    s.close()

  test "unknown device": # Review Focus 5
    let s = newCameraSession()
    let r = s.selectDevice("definitely-not-a-camera-id")
    check r.isErr
    check r.error == ceDeviceNotFound
    check s.errorKind == ceDeviceNotFound
    check s.errorString.len > 0
    check not s.isActive
    s.close()

  test "default device selection matches availability":
    let s = newCameraSession()
    let r = s.selectDevice("")
    if defaultCamera().isSome:
      check r.isOk
      check s.deviceId == defaultCamera().get.id
      check s.errorKind == ceNone
    else:
      check r.isErr
      check r.error == ceNoDevice
    s.close()

  test "state callback fires on device selection":
    local:
      var calls = 0
      let s = newCameraSession()
      s.onStateChanged(proc() = inc calls)
      discard s.selectDevice("definitely-not-a-camera-id")
      check calls >= 1
      s.close()

  test "setActive(false) on an idle session is a no-op":
    let s = newCameraSession()
    s.setActive(false)
    processEvents()
    check not s.isActive
    check s.errorKind == ceNone
    s.close()

if getEnv("QTCAMERA_TEST_WITH_CAMERA") == "1":
  suite "CameraSession (real camera)":
    test "frames flow into a FrameTap on the session sink":
      local:
        let s = newCameraSession()
        check s.selectDevice("").isOk
        var got = 0
        let tap = newFrameTap(proc(f: sink GrayFrame) = inc got)
        tap.attach(s.videoSink)
        tap.arm()
        s.setActive(true)
        for i in 0 ..< 500:
          processEvents()
          sleep(10)
          if got > 0:
            break
        check got == 1
        check s.isActive
        tap.detach()
        s.close()
        check not s.isActive
