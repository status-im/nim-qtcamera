import std/[unittest, os]
import nimqml
import ../qtcamera/[types, frametap, qml]
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
