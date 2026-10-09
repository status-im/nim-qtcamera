## Luma (8-bit grayscale) extraction from QVideoFrame.
##
## Planar YUV / Y-only formats copy the Y plane directly; packed YUV and 16-bit
## formats pick one byte per pixel; everything else (RGB, Jpeg, texture-only
## frames) goes through QVideoFrame::toImage() -> Grayscale8.

{.push raises: [], gcsafe.}

import results
import seaqt/[qvideoframe, qimage]
import ./types

export results

type LumaOptions* = object
  roi*: Opt[NormRect]
    ## Frame coordinates (before any preview mirroring). None/empty = full frame.
  maxDim*: int
    ## 0 = no downscale; otherwise the largest side is <= maxDim (integer decimation).

const
  fmtYUV420P = 13
  fmtYUV422P = 14
  fmtYV12 = 15
  fmtUYVY = 16
  fmtYUYV = 17
  fmtNV12 = 18
  fmtNV21 = 19
  fmtIMC1 = 20
  fmtIMC4 = 23
  fmtY8 = 24
  fmtY16 = 25
  fmtP010 = 26
  fmtP016 = 27
  imgGrayscale8 = 24 # QImage::Format_Grayscale8
  mapReadOnly = 1

func cropAndDecimate*(src: openArray[byte], w, h, stride, step, offset: int,
                      roi: Opt[NormRect], maxDim: int): GrayFrame =
  ## Copies luma out of `src`. Pixel (x, y) lives at
  ## `src[y * stride + x * step + offset]`.
  var
    x0 = 0
    y0 = 0
    cw = w
    ch = h
  if roi.isSome:
    let r = roi.get.normalized
    if not r.isEmpty:
      x0 = min(w - 1, int(r.x * w.float32))
      y0 = min(h - 1, int(r.y * h.float32))
      cw = max(1, min(w - x0, int(r.w * w.float32)))
      ch = max(1, min(h - y0, int(r.h * h.float32)))
  let
    k = if maxDim > 0: max(1, (max(cw, ch) + maxDim - 1) div maxDim) else: 1
    ow = (cw + k - 1) div k
    oh = (ch + k - 1) div k
  var data = newSeq[byte](ow * oh)
  for oy in 0 ..< oh:
    let row = (y0 + oy * k) * stride
    for ox in 0 ..< ow:
      data[oy * ow + ox] = src[row + (x0 + ox * k) * step + offset]
  GrayFrame(width: ow, height: oh, data: data)

func lumaLayout(pixelFormat: int): Opt[tuple[step, offset: int]] =
  case pixelFormat
  of fmtYUV420P, fmtYUV422P, fmtYV12, fmtNV12, fmtNV21, fmtIMC1 .. fmtIMC4, fmtY8:
    Opt.some((1, 0))
  of fmtUYVY:
    Opt.some((2, 1))
  of fmtYUYV:
    Opt.some((2, 0))
  of fmtY16, fmtP010, fmtP016:
    # Little-endian 16-bit with significant bits at the top: keep the high byte.
    # (YUV420P10 keeps its 10 bits at the bottom, so it goes through toImage().)
    Opt.some((2, 1))
  else:
    Opt.none(tuple[step, offset: int])

proc fromImage(frame: QVideoFrame, opts: LumaOptions): Opt[GrayFrame] =
  let img = frame.toImage()
  if img.isNull():
    return Opt.none(GrayFrame)
  let
    gray = img.convertToFormat(imgGrayscale8.cint)
    w = gray.width().int
    h = gray.height().int
    bpl = gray.bytesPerLine().int
  if w <= 0 or h <= 0:
    return Opt.none(GrayFrame)
  let p = cast[ptr UncheckedArray[byte]](gray.constBits())
  Opt.some(cropAndDecimate(p.toOpenArray(0, bpl * h - 1), w, h, bpl, 1, 0,
                           opts.roi, opts.maxDim))

proc extractLuma*(frame: QVideoFrame, opts: LumaOptions): Opt[GrayFrame] =
  ## Returns none for invalid or unconvertible frames.
  if not frame.isValid():
    return Opt.none(GrayFrame)
  let
    w = frame.width().int
    h = frame.height().int
    layout = lumaLayout(frame.pixelFormat().int)
  if w <= 0 or h <= 0:
    return Opt.none(GrayFrame)
  var g: Opt[GrayFrame]
  if layout.isSome and frame.map(mapReadOnly.cint):
    let
      bpl = frame.bytesPerLine(0).int
      bytes = frame.mappedBytes(0).int
      (step, offset) = layout.get
    if bpl * (h - 1) + (w - 1) * step + offset < bytes:
      let p = cast[ptr UncheckedArray[byte]](frame.bits(0))
      g = Opt.some(cropAndDecimate(p.toOpenArray(0, bytes - 1), w, h, bpl,
                                   step, offset, opts.roi, opts.maxDim))
    frame.unmap()
  if g.isNone:
    g = fromImage(frame, opts)
  if g.isSome:
    g.get.timestampUs = frame.startTime().int64
  g
