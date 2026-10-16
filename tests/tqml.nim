import std/[unittest, os]
import nimqml
import ../qtcamera/[types, frametap, permission, qml]
import ../qtcamera/private/shim
import ./testutils

putEnv("QT_QPA_PLATFORM", "offscreen")

QtObject:
  type Reporter = ref object of QObject
    failures: seq[string]
    handle: int
    sink: pointer
    pulledInQml: int
    pulledSignals: int
    completed: bool
    accessStatus: string
    accessCanOpen: bool
    previewAfterSet: Opt[PreviewRoi]
    accessCanRequest: string ## String(): an undefined property must not pass as false
    accessReported: bool

  proc setup(self: Reporter)
  proc delete(self: Reporter)

  proc newReporter(): Reporter =
    new(result, delete)
    result.setup

  proc setup(self: Reporter) =
    self.QObject.setup

  proc delete(self: Reporter) =
    self.QObject.delete

  proc fail(self: Reporter, what: string) {.slot.} =
    self.failures.add what

  proc ready(self: Reporter, handle: int, sink: QVariant) {.slot.} =
    self.handle = handle
    self.sink = shimQObjectFromVariant(cast[pointer](sink.vptr))
    self.completed = true

  proc pulled(self: Reporter, count: int) {.slot.} =
    self.pulledInQml = count
    inc self.pulledSignals

  proc setEnabled*(self: Reporter, enabled: bool) {.signal.}

  proc previewSet(self: Reporter, handle: int) {.slot.} =
    let t = findTap(handle)
    if t.isSome:
      self.previewAfterSet = t.get.options.preview

  proc access(self: Reporter, status: string, canOpen: bool, canRequest: string) {.slot.} =
    self.accessStatus = status
    self.accessCanOpen = canOpen
    self.accessCanRequest = canRequest
    self.accessReported = true

type Probe = object
  marker: int

var
  probeDestroyed: bool
  freedDuringConsumer: bool
  selfRemovingHandle: int

proc `=destroy`(p: var Probe) =
  if p.marker != 0:
    probeDestroyed = true

proc installSelfRemovingConsumer(handle: int) =
  ## After this returns, only the consumer closure holds `probe`.
  var probe = Probe(marker: 123)
  selfRemovingHandle = handle
  setTapConsumer(handle, proc(f: sink GrayFrame) =
    {.cast(gcsafe).}:
      setTapConsumer(selfRemovingHandle, nil)
      freedDuringConsumer = probeDestroyed
      doAssert probe.marker == 123)

proc rearmingConsumer(handle: int): FrameCallback =
  ## The documented pattern: a custom consumer re-arms through armTap.
  proc(f: sink GrayFrame) {.gcsafe, raises: [].} =
    armTap(handle)

let app = newQGuiApplication()
let engine = newQQmlApplicationEngine()
install(engine)
let reporter = newReporter()
engine.setRootContextProperty("reporter", newQVariant(reporter))

const qmlSrc = """
import QtQuick
import QtMultimedia
import NimQtCamera 1.0
Item {
  VideoOutput { id: vo; width: 64; height: 32 }
  Connections {
    target: reporter
    function onSetEnabled(enabled) { tap.enabled = enabled }
  }
  FrameTap {
    id: tap
    videoSink: vo.videoSink
    enabled: true
    maxFps: 0 // these tests push frames back-to-back
    maxDim: 8
    onFramePulled: reporter.pulled(tap.framesPulled)
  }
  function expect(cond, what) { if (!cond) reporter.fail(what) }
  Component.onCompleted: {
    expect(tap.handle > 0, "tap has a backend handle")
    expect(tap.framesPulled === 0, "no frames pulled yet")
    expect(tap.maxDim === 8, "maxDim round-trips")
    tap.setRoi(0.0, 0.0, 0.5, 0.5)
    tap.clearRoi()
    expect(tap.frameRotation === 0 && tap.frameMirrored === false, "no frame yet: identity")
    tap.setPreviewRoi(10, 20, 30, 40, 100, 200, 2, true) // VideoOutput.PreserveAspectCrop
    reporter.previewSet(tap.handle)
    tap.setDisplayRoi(0.125, 0.25, 0.5, 0.375)
    reporter.ready(tap.handle, vo.videoSink)
  }
}
"""

engine.loadData(qmlSrc)
for i in 0 ..< 20:
  processEvents()

suite "qml FrameTap":
  test "module loads and the tap gets a backend handle":
    check reporter.completed
    check reporter.failures.len == 0
    if reporter.failures.len > 0:
      echo reporter.failures
    check findTap(reporter.handle).isSome
    # setPreviewRoi from QML: the preview rect and layout
    check reporter.previewAfterSet == Opt.some(PreviewRoi(x: 10, y: 20, w: 30, h: 40,
      itemWidth: 100, itemHeight: 200, fill: pfCrop, mirrored: true))
    # setDisplayRoi from QML: the rect, in display space (and no preview rect)
    let tap = findTap(reporter.handle).get
    let o = tap.options
    check o.preview.isNone
    check o.roiSpace == rsDisplay
    check o.roi == Opt.some(NormRect(x: 0.125, y: 0.25, w: 0.5, h: 0.375))
    tap.options = LumaOptions(maxDim: o.maxDim) # the frame tests below use no ROI

  test "frames pushed into the VideoOutput sink are pulled and reported to QML":
    require reporter.sink != nil
    pushNv12(reporter.sink, 32, 16, 77)
    for i in 0 ..< 10:
      processEvents()
    pushNv12(reporter.sink, 32, 16, 77)
    for i in 0 ..< 10:
      processEvents()
    let tap = findTap(reporter.handle).get
    check tap.stats.framesPulled == 2 # default consumer re-arms while enabled
    check reporter.pulledSignals == 2
    check reporter.pulledInQml == 2

  test "custom consumer receives frames and controls re-arming":
    local:
      var got: seq[GrayFrame]
      let h = reporter.handle
      setTapConsumer(h, proc(f: sink GrayFrame) = got.add f)
      armTap(h)
      pushNv12(reporter.sink, 32, 16, 77)
      pushNv12(reporter.sink, 32, 16, 77)
      for i in 0 ..< 10:
        processEvents()
      check got.len == 1 # not re-armed by the consumer
      check got[0].width == 8
      check got[0].data[0] == 77
      setTapConsumer(h, nil)

  test "unknown handles are ignored":
    check findTap(987654).isNone
    armTap(987654) # must not crash

  test "restoring the default consumer resumes pulling": # review 4
    let h = reporter.handle
    let tap = findTap(h).get
    setTapConsumer(h, proc(f: sink GrayFrame) = discard)
    armTap(h)
    pushNv12(reporter.sink, 32, 16, 1)
    check not tap.isArmed # custom consumer did not re-arm
    let pulled = tap.stats.framesPulled
    setTapConsumer(h, nil)
    pushNv12(reporter.sink, 32, 16, 2)
    pushNv12(reporter.sink, 32, 16, 3)
    check tap.stats.framesPulled == pulled + 2
    check tap.isArmed

  test "a disabled tap ignores armTap": # review 3
    let h = reporter.handle
    let tap = findTap(h).get
    reporter.setEnabled(false)
    processEvents()
    armTap(h)
    check not tap.isArmed
    let pulled = tap.stats.framesPulled
    pushNv12(reporter.sink, 32, 16, 4)
    check tap.stats.framesPulled == pulled
    reporter.setEnabled(true)
    processEvents()
    check tap.isArmed

  test "a consumer can re-arm with armTap from inside the callback": # review 2
    let h = reporter.handle
    let tap = findTap(h).get
    setTapConsumer(h, rearmingConsumer(h))
    let pulled = tap.stats.framesPulled
    pushNv12(reporter.sink, 32, 16, 5)
    pushNv12(reporter.sink, 32, 16, 6)
    check tap.stats.framesPulled == pulled + 2
    setTapConsumer(h, nil)

  test "a consumer may remove itself while running": # review 1
    installSelfRemovingConsumer(reporter.handle)
    pushNv12(reporter.sink, 32, 16, 7)
    check not freedDuringConsumer
    check probeDestroyed

proc newEngineWithInstall(): QQmlApplicationEngine =
  result = newQQmlApplicationEngine()
  installOnEngine(cast[pointer](result.vptr))

suite "installOnEngine":
  test "raw-engine install exposes NimQtCamera and the backend":
    let e2 = newEngineWithInstall()
    let r2 = newReporter()
    e2.setRootContextProperty("reporter", newQVariant(r2))
    e2.loadData("""
import QtQuick
import NimQtCamera 1.0
Item {
  FrameTap { id: t }
  Component.onCompleted: {
    if (t.handle <= 0) reporter.fail("handle")
    if (t.maxFps !== 5) reporter.fail("default maxFps " + t.maxFps)
    reporter.ready(t.handle, null)
  }
}
""")
    for i in 0 ..< 10:
      processEvents()
    check r2.completed
    check r2.failures.len == 0
    if r2.failures.len > 0:
      echo r2.failures

  test "install twice on two engines": # Phase 2 Review Focus 1
    let before = qtCameraBackend().tapCount()
    let a = newEngineWithInstall()
    let b = newEngineWithInstall()
    let backend = qtCameraBackend()
    check backend != nil
    check qtCameraBackend() == backend # one shared backend
    check backend.tapCount() == before # installing creates no taps
    a.delete()
    b.delete()

  test "backend survives engine teardown": # Phase 2 Review Focus 2
    let e3 = newEngineWithInstall()
    let r3 = newReporter()
    e3.setRootContextProperty("reporter", newQVariant(r3))
    e3.loadData("""
import QtQuick
import NimQtCamera 1.0
Item { FrameTap { id: t } Component.onCompleted: reporter.ready(t.handle, null) }
""")
    for i in 0 ..< 10:
      processEvents()
    let handle = r3.handle
    check handle > 0
    check findTap(handle).isSome
    e3.delete()
    for i in 0 ..< 10:
      processEvents()
    check findTap(handle).isNone # destroyed with its component
    check qtCameraBackend().tapCount() == 1 # only the long-lived test tap
    let e4 = newEngineWithInstall() # still usable afterwards
    e4.delete()

suite "camera access":
  test "backend exposes permission and capability":
    let b = qtCameraBackend()
    check b.cameraPermissionValue() in ["undetermined", "granted", "denied"]
    check b.cameraPermissionValue() == permissionName(cameraPermissionStatus())
    check b.canOpenCameraSettingsValue() == canOpenCameraSettings()

  test "refresh updates status and notifies": # Review Focus 1
    let b = qtCameraBackend()
    var notified {.global.} = 0
    b.setCameraPermissionChangedHookForTest(proc() {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: inc notified)
    # Pretend the user had denied access (or the OS hadn't answered) before
    # going to Settings; refreshing must re-read the real OS status.
    let stale = if cameraPermissionStatus() == psDenied: psGranted else: psDenied
    b.setCameraPermissionForTest(stale)
    notified = 0
    b.refreshCameraPermission()
    check b.cameraPermissionValue() == permissionName(cameraPermissionStatus())
    check notified == 1
    b.setCameraPermissionChangedHookForTest(nil)

  test "refresh without change does not notify": # Review Focus 2
    let b = qtCameraBackend()
    b.refreshCameraPermission()
    var notified {.global.} = 0
    b.setCameraPermissionChangedHookForTest(proc() {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: inc notified)
    notified = 0
    b.refreshCameraPermission()
    check notified == 0
    b.setCameraPermissionChangedHookForTest(nil)

  test "CameraAccess component mirrors the backend":
    let e = newEngineWithInstall()
    let r = newReporter()
    e.setRootContextProperty("reporter", newQVariant(r))
    e.loadData("""
import QtQuick
import NimQtCamera 1.0
Item {
  CameraAccess { id: access }
  Component.onCompleted: reporter.access(access.status, access.canOpenSettings, String(access.canRequest))
}
""")
    for i in 0 ..< 10:
      processEvents()
    check r.accessReported
    check r.accessStatus == qtCameraBackend().cameraPermissionValue()
    check r.accessCanOpen == canOpenCameraSettings()
    # Asking again can still show the OS prompt: when undetermined, and on
    # Android after an ordinary denial (Qt reports it as "denied" for the rest
    # of the process, "don't ask again" or not).
    let expected = r.accessStatus == "undetermined" or
                   (r.accessStatus == "denied" and defined(android))
    check r.accessCanRequest == $expected
    e.delete()
