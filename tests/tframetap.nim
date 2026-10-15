import std/[unittest, os]
import seaqt/[qvideosink, qvideoframe, qmediadevices]
import ../qtcamera/[types, luma, frametap]
import ./testutils

ensureApp()

const
  NV12 = 18
  JPEG = 29

type Probe = object
  v: int

var
  probeDestroyed: bool
  freedDuringCallback: bool
  selfDroppingTap: FrameTap

proc `=destroy`(p: var Probe) =
  if p.v != 0:
    probeDestroyed = true

proc makeSelfDroppingTap() =
  ## After this returns, only the tap's closure holds `probe`.
  var probe = Probe(v: 1)
  selfDroppingTap = newFrameTap(proc(f: sink GrayFrame) =
    {.cast(gcsafe).}:
      selfDroppingTap.detach()
      selfDroppingTap = nil
      freedDuringCallback = probeDestroyed
      doAssert probe.v == 1)

proc pushFromThread(sink: pointer) {.thread.} =
  {.cast(gcsafe).}:
    let f = makeFrame(16, 8, 18, proc(plane: int, p: ptr UncheckedArray[byte], bpl, rows: int) =
      for i in 0 ..< bpl * rows:
        p[i] = 50)
    QVideoSink(h: sink, owned: false).setVideoFrame(f)

proc nv12(w, h: int, y = 200'u8): QVideoFrame =
  makeFrame(w, h, NV12, proc(plane: int, p: ptr UncheckedArray[byte], bpl, rows: int) =
    for i in 0 ..< bpl * rows:
      p[i] = (if plane == 0: y else: 128'u8))

suite "FrameTap":
  test "pull model: delivers only when armed, once per arm":
    local:
      var got = 0
      let vs = QVideoSink.create()
      let tap = newFrameTap(proc(f: sink GrayFrame) = inc got)
      tap.attach(vs)
      vs.setVideoFrame(nv12(16, 8))
      processEvents()
      check got == 0
      check tap.stats.framesSeen == 1
      check tap.stats.framesPulled == 0
      tap.arm()
      vs.setVideoFrame(nv12(16, 8, 10))
      vs.setVideoFrame(nv12(16, 8, 20))
      processEvents()
      check got == 1
      check tap.stats.framesSeen == 3
      check tap.stats.framesPulled == 1
      check tap.stats.lastWidth == 16
      check tap.stats.lastHeight == 8
      check tap.stats.lastPixelFormat == NV12
      tap.detach()

  test "stats record how the last frame is displayed":
    local:
      let vs = QVideoSink.create()
      let tap = newFrameTap(proc(f: sink GrayFrame) = discard)
      tap.attach(vs)
      tap.arm()
      let f = nv12(16, 8)
      f.setRotation(90)
      f.setMirrored(true)
      vs.setVideoFrame(f)
      processEvents()
      check tap.stats.lastRotation == 90
      check tap.stats.lastMirrored
      tap.arm()
      vs.setVideoFrame(nv12(16, 8))
      processEvents()
      check tap.stats.lastRotation == 0
      check not tap.stats.lastMirrored
      tap.detach()

  test "delivered frame content and options":
    local:
      var last: GrayFrame
      let vs = QVideoSink.create()
      let tap = newFrameTap(proc(f: sink GrayFrame) = last = f, LumaOptions(maxDim: 8))
      tap.attach(vs)
      tap.arm()
      vs.setVideoFrame(nv12(32, 16))
      processEvents()
      check last.width == 8
      check last.height == 4
      check last.data[0] == 200
      tap.detach()

  test "detach stops callbacks": # Review Focus 1
    local:
      var got = 0
      let vs = QVideoSink.create()
      let tap = newFrameTap(proc(f: sink GrayFrame) = inc got)
      tap.attach(vs)
      tap.arm()
      tap.detach()
      vs.setVideoFrame(nv12(16, 8))
      processEvents()
      check got == 0
      check not tap.isAttached

  test "detach after sink destroyed": # Review Focus 1
    local:
      let tap = newFrameTap(proc(f: sink GrayFrame) = discard)
      block:
        let vs = QVideoSink.create()
        tap.attach(vs)
      processEvents()
      tap.detach()
      check not tap.isAttached

  test "unmappable frame is skipped": # Review Focus 4
    local:
      var got = 0
      let vs = QVideoSink.create()
      let tap = newFrameTap(proc(f: sink GrayFrame) = inc got)
      tap.attach(vs)
      tap.arm()
      # Valid frame whose Jpeg payload is garbage: not mappable as luma and
      # toImage() fails, so it must be skipped without disarming the tap.
      vs.setVideoFrame(makeFrame(8, 8, JPEG, proc(plane: int, p: ptr UncheckedArray[byte], bpl, rows: int) =
        for i in 0 ..< bpl * rows:
          p[i] = 0))
      processEvents()
      check tap.stats.framesSeen == 1
      check got == 0
      check tap.stats.framesSkipped == 1
      vs.setVideoFrame(nv12(16, 8))
      processEvents()
      check got == 1
      tap.detach()

  test "re-attach moves to the new sink":
    local:
      var got = 0
      let a = QVideoSink.create()
      let b = QVideoSink.create()
      let tap = newFrameTap(proc(f: sink GrayFrame) = inc got)
      tap.attach(a)
      tap.attach(b)
      tap.arm()
      a.setVideoFrame(nv12(16, 8))
      processEvents()
      check got == 0
      b.setVideoFrame(nv12(16, 8))
      processEvents()
      check got == 1
      tap.detach()

  test "minInterval skips armed frames until the interval elapses":
    local:
      var got = 0
      let vs = QVideoSink.create()
      let tap = newFrameTap(proc(f: sink GrayFrame) = inc got)
      tap.minIntervalMs = 200
      tap.attach(vs)
      tap.arm()
      vs.setVideoFrame(nv12(16, 8, 1))
      processEvents()
      check got == 1 # first pull is never throttled
      tap.arm()
      vs.setVideoFrame(nv12(16, 8, 2))
      processEvents()
      check got == 1 # too soon: not mapped, still armed
      check tap.isArmed
      check tap.stats.framesPulled == 1
      sleep(250)
      vs.setVideoFrame(nv12(16, 8, 3))
      processEvents()
      check got == 2
      tap.detach()

  test "disarm cancels a pending pull":
    local:
      var got = 0
      let vs = QVideoSink.create()
      let tap = newFrameTap(proc(f: sink GrayFrame) = inc got)
      tap.attach(vs)
      tap.arm()
      tap.disarm()
      check not tap.isArmed
      vs.setVideoFrame(nv12(16, 8))
      processEvents()
      check got == 0
      tap.detach()

  test "attach by raw QVideoSink pointer":
    local:
      var got = 0
      let vs = QVideoSink.create()
      let tap = newFrameTap(proc(f: sink GrayFrame) = inc got)
      tap.attachRaw(vs.h)
      tap.arm()
      vs.setVideoFrame(nv12(16, 8))
      processEvents()
      check got == 1
      tap.detach()

  test "queued frame posted before detach is not delivered": # review C1
    local:
      var got = 0
      let vs = QVideoSink.create()
      let tap = newFrameTap(proc(f: sink GrayFrame) = inc got)
      tap.attach(vs)
      tap.arm()
      var th: Thread[pointer]
      createThread(th, pushFromThread, vs.h) # emitted off-thread -> queued
      joinThread(th)
      tap.detach()                            # before the queued event runs
      processEvents()
      check got == 0
      check tap.stats.framesSeen == 0

  test "callback may detach and drop the last reference to its tap": # review I1
    let vs = QVideoSink.create()
    makeSelfDroppingTap()
    selfDroppingTap.attach(vs)
    selfDroppingTap.arm()
    vs.setVideoFrame(nv12(16, 8))
    processEvents()
    check selfDroppingTap == nil
    check not freedDuringCallback
    check probeDestroyed

  test "attaching to a QObject that is not a QVideoSink is refused": # review I2
    let other = QMediaDevices.create()
    let tap = newFrameTap(proc(f: sink GrayFrame) = discard)
    tap.attachRaw(other.h)
    check not tap.isAttached
    tap.detach()

  test "attaching to a null sink is refused": # review M5
    let tap = newFrameTap(proc(f: sink GrayFrame) = discard)
    tap.attachRaw(nil)
    check not tap.isAttached

  test "fps to interval conversion never overflows": # review M2
    check fpsToIntervalMs(0) == 0
    check fpsToIntervalMs(-5) == 0
    check fpsToIntervalMs(10) == 100
    check fpsToIntervalMs(1e-20) == maxIntervalMs
    check fpsToIntervalMs(Inf) == 0
    check fpsToIntervalMs(NaN) == 0
