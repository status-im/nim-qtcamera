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

import std/[math, monotimes, times]
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
    minInterval: Duration
    lastPull: MonoTime
    pulledOnce: bool
    conn: pointer
    stats: FrameTapStats

  FrameTap* = ref FrameTapObj

proc frameThunk(ctx: pointer, frame: pointer) {.cdecl, gcsafe, raises: [].} =
  let t = cast[FrameTap](ctx)
  inc t.stats.framesSeen
  if not t.armed:
    return
  if t.pulledOnce and getMonoTime() - t.lastPull < t.minInterval:
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
  t.pulledOnce = true
  t.lastPull = getMonoTime()
  inc t.stats.framesPulled
  # Hold the tap and the closure for the call: the consumer may detach and drop
  # the last reference to the tap from inside the callback.
  GC_ref(t)
  let cb = t.onFrame
  cb(move g.get)
  GC_unref(t)

proc newFrameTap*(onFrame: FrameCallback, opts = LumaOptions()): FrameTap =
  FrameTap(onFrame: onFrame, opts: opts)

proc detach*(t: FrameTap) =
  ## Safe to call repeatedly, and after the sink has been destroyed.
  if t.conn != nil:
    shimDisconnect(t.conn)
    t.conn = nil
    GC_unref(t) # balances attach()

proc attachRaw*(t: FrameTap, sink: pointer) =
  ## `sink` is a QVideoSink*. Replaces any previous attachment; the tap stays
  ## alive until `detach()`.
  t.detach()
  if sink == nil:
    return
  t.conn = shimConnectFrames(sink, cast[pointer](t), frameThunk)
  if t.conn != nil:
    GC_ref(t) # the C++ lambda holds a raw pointer to t

proc attach*(t: FrameTap, sink: QVideoSink) =
  t.attachRaw(sink.h)

proc arm*(t: FrameTap) =
  t.armed = true

proc disarm*(t: FrameTap) =
  t.armed = false

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

proc minIntervalMs*(t: FrameTap): int =
  t.minInterval.inMilliseconds.int

proc `minIntervalMs=`*(t: FrameTap, ms: int) =
  ## Armed frames arriving sooner than `ms` after the last pull are ignored
  ## (not mapped), so the pull rate is capped without a timer. 0 = no cap.
  t.minInterval = initDuration(milliseconds = max(0, ms))

const maxIntervalMs* = 3_600_000 ## Longest pull interval (1 hour).

func fpsToIntervalMs*(fps: float): int =
  ## Pull interval for a max rate; 0 (no cap) for non-positive or invalid rates.
  if fps.isNaN or fps <= 0:
    0
  else:
    int(min(1000.0 / fps, maxIntervalMs.float))
