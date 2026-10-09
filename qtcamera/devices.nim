## Camera discovery and hot-plug notifications.

{.push raises: [], gcsafe.}

import results
import seaqt/[qmediadevices, qcameradevice]
import ./types

export results

const
  posBack = 1  # QCameraDevice::BackFace
  posFront = 2 # QCameraDevice::FrontFace

proc toCameraInfo*(d: QCameraDevice): CameraInfo =
  let idBytes = d.id()
  var id = newString(idBytes.len)
  for i, b in idBytes:
    id[i] = char(b)
  CameraInfo(
    id: id,
    description: d.description(),
    isDefault: d.isDefault(),
    position:
      case d.position().int
      of posBack: cpBack
      of posFront: cpFront
      else: cpUnspecified)

proc listCameras*(): seq[CameraInfo] =
  for d in QMediaDevices.videoInputs():
    result.add d.toCameraInfo

proc defaultCamera*(): Opt[CameraInfo] =
  let d = QMediaDevices.defaultVideoInput()
  if d.isNull(): Opt.none(CameraInfo) else: Opt.some(d.toCameraInfo)

proc findDevice*(id: string): Opt[QCameraDevice] =
  ## `""` selects the system default camera.
  if id.len == 0:
    let d = QMediaDevices.defaultVideoInput()
    return if d.isNull(): Opt.none(QCameraDevice) else: Opt.some(d)
  for d in QMediaDevices.videoInputs():
    if d.toCameraInfo.id == id:
      return Opt.some(QCameraDevice.create(d))
  Opt.none(QCameraDevice)

type CameraDevicesWatcher* = ref object
  ## Calls `onChanged` (on the GUI thread) when cameras are plugged/unplugged.
  md: QMediaDevices

proc newCameraDevicesWatcher*(
    onChanged: proc() {.gcsafe, raises: [].}): CameraDevicesWatcher =
  let w = CameraDevicesWatcher(md: QMediaDevices.create())
  w.md.onVideoInputsChanged(onChanged)
  w
