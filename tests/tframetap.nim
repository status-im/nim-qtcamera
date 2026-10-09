import std/unittest
import seaqt/[qvideosink, qvideoframe]
import ../qtcamera/[types, luma, frametap]
import ./testutils

ensureApp()

const
  NV12 = 18
  JPEG = 29

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
