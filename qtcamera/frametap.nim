## Pull-model frame source: attach to any QVideoSink, `arm()` to receive the
## next frame as a GrayFrame.
##
## Threading: the callback runs on the sink's thread (the GUI thread for sinks
## created there, including QML VideoOutput sinks). `arm`, `detach` and the
## callback must all stay on that thread. Consumers that decode elsewhere should
## move the GrayFrame (a `sink` parameter) into their own channel.
##
## Unarmed frames cost one counter increment: nothing is mapped or copied.

{.push raises: [], gcsafe.}

import results
import seaqt/[qvideosink, qvideoframe]
import ./[types, luma]
import ./private/shim

export luma

type
  FrameCallback* = proc(frame: sink GrayFrame) {.gcsafe, raises: [].}

  FrameTapStats* = object
    framesSeen*, framesPulled*, framesSkipped*: int
    lastPixelFormat*, lastWidth*, lastHeight*: int

  FrameTapObj = object
    onFrame: FrameCallback
    opts: LumaOptions
    armed: bool
    conn: pointer
    stats: FrameTapStats

  FrameTap* = ref FrameTapObj

proc frameThunk(ctx: pointer, frame: pointer) {.cdecl, gcsafe, raises: [].} =
  let t = cast[FrameTap](ctx)
  inc t.stats.framesSeen
  if not t.armed:
    return
  let f = QVideoFrame(h: frame, owned: false)
  t.stats.lastPixelFormat = f.pixelFormat().int
  t.stats.lastWidth = f.width().int
  t.stats.lastHeight = f.height().int
  var g = extractLuma(f, t.opts)
  if g.isNone:
    inc t.stats.framesSkipped
    return
  t.armed = false
  inc t.stats.framesPulled
  t.onFrame(move g.get)

proc newFrameTap*(onFrame: FrameCallback, opts = LumaOptions()): FrameTap =
  FrameTap(onFrame: onFrame, opts: opts)

proc detach*(t: FrameTap) =
  ## Safe to call repeatedly, and after the sink has been destroyed.
  if t.conn != nil:
    shimDisconnect(t.conn)
    t.conn = nil
    GC_unref(t) # balances attach()

proc attach*(t: FrameTap, sink: QVideoSink) =
  ## Replaces any previous attachment. The tap stays alive until `detach()`.
  t.detach()
  GC_ref(t) # the C++ lambda holds a raw pointer to t
  t.conn = shimConnectFrames(sink.h, cast[pointer](t), frameThunk)

proc arm*(t: FrameTap) =
  t.armed = true

proc isArmed*(t: FrameTap): bool =
  t.armed

proc isAttached*(t: FrameTap): bool =
  t.conn != nil

proc stats*(t: FrameTap): FrameTapStats =
  t.stats

proc options*(t: FrameTap): LumaOptions =
  t.opts

proc `options=`*(t: FrameTap, opts: LumaOptions) =
  t.opts = opts
