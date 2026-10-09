## Shared helpers for the test suites.

import std/os
import seaqt/[qguiapplication, qcoreapplication]

var app {.threadvar.}: QGuiApplication

proc ensureApp*() =
  ## One offscreen QGuiApplication per test binary.
  if app.h == nil:
    putEnv("QT_QPA_PLATFORM", "offscreen")
    app = QGuiApplication.create()

proc processEvents*() =
  QCoreApplication.processEvents()

import seaqt/[qvideoframe, qvideoframeformat, qsize]

type PlaneFiller* = proc(plane: int, p: ptr UncheckedArray[byte], bpl, rows: int)

proc makeFrame*(w, h, pixelFormat: int, fill: PlaneFiller): QVideoFrame =
  ## CPU-backed synthetic frame; `fill` writes each mapped plane.
  let fmt = QVideoFrameFormat.create(QSize.create(w.cint, h.cint), pixelFormat.cint)
  result = QVideoFrame.create(fmt)
  doAssert result.map(2) # WriteOnly
  for p in 0 ..< result.planeCount().int:
    let
      bpl = result.bytesPerLine(p.cint).int
      rows = result.mappedBytes(p.cint).int div bpl
    fill(p, cast[ptr UncheckedArray[byte]](result.bits(p.cint)), bpl, rows)
  result.unmap()

func gradientY*(x, y: int): byte =
  byte((x + 3 * y) and 0xFF)
