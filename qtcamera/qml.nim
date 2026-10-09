## QML integration.
##
## nimqml-seaqt cannot register Nim types with QML (its qmlRegisterType is a
## stub), so the QML side is a set of plain .qml components (qml/NimQtCamera)
## driven by one Nim backend object installed as the context property
## `nimQtCameraBackend`.
##
## The camera itself is Qt's own QML Camera / CaptureSession / VideoOutput (and
## MediaDevices / CameraPermission); what QML lacks is a frame tap, which is
## what this module provides:
##
##   import NimQtCamera 1.0
##   FrameTap { videoSink: videoOutput.videoSink; enabled: true; maxFps: 10 }
##
## Other Nim libraries reach a QML FrameTap through its `handle`
## (`findTap`, `armTap`, `setTapConsumer`).

import std/[os, tables]
import results
import nimqml
import ./[types, luma, frametap]
import ./private/[shim, qml_shim]

export results

const qmlImportDir* = currentSourcePath().parentDir().parentDir() / "qml"
  ## Directory to add to the QML import path; contains `NimQtCamera/`.

const backendContextName* = "nimQtCameraBackend"

type
  ConsumerBox = ref object
    cb: FrameCallback

  TapEntry = ref object
    core: FrameTap
    enabled: bool
    consumer: ConsumerBox

QtObject:
  type QtCameraBackend* = ref object of QObject
    taps: Table[int, TapEntry]
    nextHandle: int

  proc setup(self: QtCameraBackend)
  proc delete(self: QtCameraBackend)

  proc newQtCameraBackend*(): QtCameraBackend =
    new(result, delete)
    result.setup
    result.nextHandle = 1

  proc setup(self: QtCameraBackend) =
    self.QObject.setup

  proc delete(self: QtCameraBackend) =
    for e in self.taps.values:
      e.core.detach()
    self.taps.clear()
    self.QObject.delete

  proc tapPulled*(self: QtCameraBackend, handle: int) {.signal.}

  proc entry(self: QtCameraBackend, handle: int): TapEntry =
    self.taps.getOrDefault(handle, nil)

  proc createTap(self: QtCameraBackend): int {.slot.} =
    let
      handle = self.nextHandle
      e = TapEntry()
      backend = self
    inc self.nextHandle
    e.core = newFrameTap(proc(f: sink GrayFrame) {.gcsafe, raises: [].} =
      {.cast(gcsafe), cast(raises: []).}:
        let box = e.consumer
        if box != nil:
          # Keep the consumer (and what it captured) alive for the call: it
          # may replace or clear itself while running.
          GC_ref(box)
          box.cb(f) # custom consumers re-arm themselves
          GC_unref(box)
        elif e.enabled:
          e.core.arm()
        backend.tapPulled(handle))
    self.taps[handle] = e
    handle

  proc destroyTap(self: QtCameraBackend, handle: int) {.slot.} =
    let e = self.entry(handle)
    if e != nil:
      e.core.detach()
      self.taps.del(handle)

  proc attachTap(self: QtCameraBackend, handle: int, sink: QVariant) {.slot.} =
    ## Stays attached while a sink is set (the connection dies with the sink);
    ## `enabled` only controls whether frames are pulled.
    let e = self.entry(handle)
    if e == nil:
      return
    let p = if sink.isNil or sink.isNull: nil
            else: shimQObjectFromVariant(cast[pointer](sink.vptr))
    if p == nil:
      e.core.detach()
    else:
      e.core.attachRaw(p)
      if e.enabled:
        e.core.arm()

  proc setTapEnabled(self: QtCameraBackend, handle: int, on: bool) {.slot.} =
    let e = self.entry(handle)
    if e == nil:
      return
    e.enabled = on
    if on: e.core.arm() else: e.core.disarm()

  proc setTapOptions(self: QtCameraBackend, handle: int, maxFps: float, maxDim: int) {.slot.} =
    let e = self.entry(handle)
    if e == nil:
      return
    e.core.minIntervalMs = fpsToIntervalMs(maxFps)
    var o = e.core.options
    o.maxDim = max(0, maxDim)
    e.core.options = o

  proc setTapRoi(self: QtCameraBackend, handle: int, x: float, y: float, w: float, h: float) {.slot.} =
    let e = self.entry(handle)
    if e == nil:
      return
    var o = e.core.options
    o.roi = Opt.some(NormRect(x: x.float32, y: y.float32, w: w.float32, h: h.float32))
    e.core.options = o

  proc clearTapRoi(self: QtCameraBackend, handle: int) {.slot.} =
    let e = self.entry(handle)
    if e == nil:
      return
    var o = e.core.options
    o.roi = Opt.none(NormRect)
    e.core.options = o

  proc tapFramesSeen(self: QtCameraBackend, handle: int): int {.slot.} =
    let e = self.entry(handle)
    if e == nil: 0 else: e.core.stats.framesSeen

  proc tapFramesPulled(self: QtCameraBackend, handle: int): int {.slot.} =
    let e = self.entry(handle)
    if e == nil: 0 else: e.core.stats.framesPulled

  proc tapPixelFormat(self: QtCameraBackend, handle: int): int {.slot.} =
    let e = self.entry(handle)
    if e == nil: 0 else: e.core.stats.lastPixelFormat

  proc tapFrameWidth(self: QtCameraBackend, handle: int): int {.slot.} =
    let e = self.entry(handle)
    if e == nil: 0 else: e.core.stats.lastWidth

  proc tapFrameHeight(self: QtCameraBackend, handle: int): int {.slot.} =
    let e = self.entry(handle)
    if e == nil: 0 else: e.core.stats.lastHeight

var backend {.threadvar.}: QtCameraBackend

proc qtCameraBackend*(): QtCameraBackend =
  ## The GUI thread's backend, created on first use.
  if backend == nil:
    backend = newQtCameraBackend()
  backend

proc installOnEngine*(engine: pointer) {.raises: [].} =
  ## For C++ hosts: `engine` is a QQmlEngine*. Adds the NimQtCamera import path
  ## and the `nimQtCameraBackend` context property. Call once per engine; all
  ## engines share the GUI thread's backend.
  # qtCameraBackend() can only raise if nimqml fails to set up its QObject,
  # which is unrecoverable at a C boundary anyway.
  {.cast(raises: []).}:
    let b = qtCameraBackend()
    shimQmlInstall(engine, qmlImportDir.cstring, backendContextName.cstring,
                   cast[pointer](b.vptr))

proc install*(engine: QQmlApplicationEngine) =
  ## For Nim (nimqml) hosts.
  installOnEngine(cast[pointer](engine.vptr))

proc existingEntry(handle: int): TapEntry {.gcsafe, raises: [].} =
  ## Never creates the backend, so handle operations stay effect-free and can be
  ## called from inside a FrameCallback.
  {.cast(gcsafe).}:
    if backend == nil: nil else: backend.taps.getOrDefault(handle, nil)

proc findTap*(handle: int): Opt[FrameTap] {.gcsafe, raises: [].} =
  let e = existingEntry(handle)
  if e == nil: Opt.none(FrameTap) else: Opt.some(e.core)

proc armTap*(handle: int) {.gcsafe, raises: [].} =
  ## Requests the next frame. Ignored for unknown handles and while the QML
  ## FrameTap is disabled.
  let e = existingEntry(handle)
  if e != nil and e.enabled:
    e.core.arm()

proc setTapConsumer*(handle: int, cb: FrameCallback) {.gcsafe, raises: [].} =
  ## Replaces the default consumer (which re-arms while enabled and only updates
  ## stats). `cb` must call `armTap(handle)` when it wants the next frame;
  ## `tapPulled` is still emitted. nil restores the default.
  let e = existingEntry(handle)
  if e != nil:
    e.consumer = if cb == nil: nil else: ConsumerBox(cb: cb)
    if cb == nil and e.enabled:
      e.core.arm() # the default consumer only re-arms after a pull
