## Real-camera spike (architecture spikes 1 + 4). Records which pixel formats the
## platform delivers, whether frames are mappable, their handle type, and which
## thread QVideoSink::videoFrameChanged is emitted on.
##
## Run: make spike   (needs a camera; may trigger the OS permission prompt)

import std/[os, tables, strformat]
import seaqt/[qguiapplication, qcoreapplication, qthread, qtimer, qmediadevices,
              qcameradevice, qcamera, qmediacapturesession, qvideosink, qvideoframe]
import ../../qtcamera/private/shim

if getEnv("QTCAMERA_TEST_WITH_CAMERA") != "1":
  quit(0)

let app = QGuiApplication.create()
let mainThread = QThread.currentThread()
let devs = QMediaDevices.videoInputs()
echo &"devices: {devs.len}"
for d in devs:
  echo &"  {d.description()} pos={d.position()} default={d.isDefault()}"
if devs.len == 0:
  quit(0)

let cam = QCamera.create(QMediaDevices.defaultVideoInput())
let sink = QVideoSink.create()
let session = QMediaCaptureSession.create()
session.setCamera(cam)
session.setVideoSink(sink)

var
  formats = initCountTable[int]()
  handles = initCountTable[int]()
  offMain, mapped, total: int
  firstSize = ""

sink.onVideoFrameChanged(proc(f: QVideoFrame) =
  inc total
  if QThread.currentThread().h != mainThread.h:
    inc offMain
  formats.inc(f.pixelFormat().int)
  handles.inc(f.handleType().int)
  if firstSize.len == 0:
    firstSize = &"{f.width()}x{f.height()} planes={f.planeCount()}"
  if f.map(1):
    inc mapped
    f.unmap())

cam.onErrorOccurred(proc(e: cint, msg: openArray[char]) =
  echo &"camera error {e}: {$msg}")

let t = QTimer.create()
t.setSingleShot(true)
t.onTimeout(proc() = QCoreApplication.quit())

proc onPermission(ctx: pointer, status: cint) {.cdecl, gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    echo &"camera permission status: {status}"
    if status == 1:
      cam.start()
      t.start(5000)
    else:
      QCoreApplication.quit()

echo &"initial permission status: {shimCameraPermissionStatus()}"
shimRequestCameraPermission(nil, onPermission)
discard QGuiApplication.exec()
cam.stop()
echo &"frames={total} mappedOk={mapped} emittedOffGuiThread={offMain} first={firstSize}"
echo &"pixelFormats={formats} handleTypes={handles}"
discard app
