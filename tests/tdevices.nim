import std/unittest
import results
import ../qtcamera/[types, devices]
import ./testutils

ensureApp()

suite "devices":
  test "listCameras is consistent with defaultCamera":
    let cams = listCameras()
    let def = defaultCamera()
    check def.isSome == (cams.len > 0)
    for c in cams:
      check c.id.len > 0
      check c.description.len > 0
    if def.isSome:
      check def.get.isDefault

  test "findDevice unknown id":
    check findDevice("definitely-not-a-camera-id").isNone

  test "findDevice empty id = default":
    check findDevice("").isSome == defaultCamera().isSome

  test "findDevice round-trips every listed id":
    for c in listCameras():
      let d = findDevice(c.id)
      check d.isSome
      check d.get.toCameraInfo.id == c.id

  test "watcher constructs and is idle without hotplug":
    local:
      var calls = 0
      let w = newCameraDevicesWatcher(proc() = inc calls)
      processEvents()
      check calls == 0
      check w != nil
