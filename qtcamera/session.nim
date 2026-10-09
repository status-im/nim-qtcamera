## Capture session: one QCamera feeding either a headless QVideoSink owned by
## the session, or a preview output (e.g. a QML VideoOutput).
##
## Activation does not request camera permission; do that first
## (qtcamera/permission), otherwise the camera stays inactive.

{.push raises: [], gcsafe.}

import results
import seaqt/[qcamera, qmediacapturesession, qvideosink, qobject]
import ./[types, devices]

export results

const
  focusModeAutoNear = 1 # QCamera::FocusModeAutoNear
  cameraNoError = 0     # QCamera::NoError

type
  StateCallback* = proc() {.gcsafe, raises: [].}

  StateCallbackBox = ref object
    cb: StateCallback

  CameraSessionObj = object
    session: QMediaCaptureSession
    camera: QCamera
    ownSink: QVideoSink
    hasCamera: bool
    deviceId: string
    front: bool
    err: CameraErrorKind
    errStr: string
    stateCb: StateCallbackBox

  CameraSession* = ref CameraSessionObj

proc notify(s: ptr CameraSessionObj) =
  let box = s.stateCb
  if box != nil:
    # Keep the callback (and what it captured) alive for the call: it may
    # replace or clear itself, or close the session, while running.
    GC_ref(box)
    box.cb()
    GC_unref(box)

proc onStateChanged*(s: CameraSession, cb: StateCallback) =
  ## Called after active/error/device/output changes, on the GUI thread.
  s.stateCb = if cb == nil: nil else: StateCallbackBox(cb: cb)

proc newCameraSession*(): CameraSession =
  let s = CameraSession(
    session: QMediaCaptureSession.create(),
    camera: QCamera.create(),
    ownSink: QVideoSink.create())
  s.session.setVideoSink(s.ownSink)
  # The camera's slots die with the camera, which dies with the session object,
  # so a raw pointer avoids a ref cycle through C++.
  let sp = cast[ptr CameraSessionObj](s)
  s.camera.onActiveChanged(proc(active: bool) = sp.notify())
  s.camera.onErrorOccurred(proc(e: cint, msg: openArray[char]) =
    if e != cameraNoError:
      var text = newString(msg.len)
      for i, c in msg:
        text[i] = c
      sp.err = ceCamera
      sp.errStr = text
      sp.notify())
  s

proc setError(s: CameraSession, k: CameraErrorKind, msg: string) =
  s.err = k
  s.errStr = msg
  cast[ptr CameraSessionObj](s).notify()

proc selectDevice*(s: CameraSession, id: string): Result[void, CameraErrorKind] =
  ## `""` selects the system default. Keeps the session active if it was.
  let d = findDevice(id)
  if d.isNone:
    let k = if id.len == 0: ceNoDevice else: ceDeviceNotFound
    s.setError(k, if id.len == 0: "No camera available" else: "Camera not found: " & id)
    return err(k)
  let
    wasActive = s.hasCamera and s.camera.isActive()
    info = d.get.toCameraInfo
  s.camera.setCameraDevice(d.get)
  if not s.hasCamera:
    s.session.setCamera(s.camera)
    s.hasCamera = true
  s.deviceId = info.id
  s.front = info.position == cpFront
  if s.camera.isFocusModeSupported(focusModeAutoNear.cint):
    s.camera.setFocusMode(focusModeAutoNear.cint)
  s.err = ceNone
  s.errStr = ""
  if wasActive:
    s.camera.setActive(true)
  cast[ptr CameraSessionObj](s).notify()
  ok()

proc setActive*(s: CameraSession, on: bool) =
  ## Activating without a selected device selects the default one first.
  if on and not s.hasCamera:
    if s.selectDevice("").isErr:
      return
  if s.hasCamera:
    s.camera.setActive(on)

proc isActive*(s: CameraSession): bool =
  s.hasCamera and s.camera.isActive()

proc deviceId*(s: CameraSession): string =
  s.deviceId

proc isFrontFacing*(s: CameraSession): bool =
  s.front

proc errorKind*(s: CameraSession): CameraErrorKind =
  s.err

proc errorString*(s: CameraSession): string =
  s.errStr

proc setPreviewOutput*(s: CameraSession, output: pointer) =
  ## `output` is a QObject* accepted by QMediaCaptureSession::setVideoOutput
  ## (QML VideoOutput, QVideoSink, ...). nil restores the headless sink.
  ## The session's videoSink changes: re-attach FrameTaps afterwards.
  if output == nil:
    s.session.setVideoSink(s.ownSink)
  else:
    s.session.setVideoOutput(QObject(h: output, owned: false))
  cast[ptr CameraSessionObj](s).notify()

proc videoSink*(s: CameraSession): QVideoSink =
  ## The sink frames currently flow into (preview's or the session's own).
  s.session.videoSink()

proc close*(s: CameraSession) =
  ## Stops the camera and detaches it. The session must not be used afterwards.
  s.stateCb = nil
  if s.hasCamera:
    s.camera.setActive(false)
    s.session.setCamera(QCamera(h: nil, owned: false))
    s.hasCamera = false
