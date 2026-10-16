import std/unittest
import results
import seaqt/[qvideoframe, qvideoframeformat, qsize]
import ../qtcamera/[types, luma]
import ./testutils

ensureApp()

const
  NV12 = 18
  YUV420P = 13
  Y8 = 24
  UYVY = 16
  YUYV = 17
  P010 = 26
  BGRA = 4

proc planarY(w, h, fmt: int): QVideoFrame =
  makeFrame(w, h, fmt, proc(plane: int, p: ptr UncheckedArray[byte], bpl, rows: int) =
    if plane == 0:
      for y in 0 ..< h:
        for x in 0 ..< w:
          p[y * bpl + x] = gradientY(x, y)
    else:
      for i in 0 ..< bpl * rows:
        p[i] = 128)

proc expectGradient(g: GrayFrame, w, h: int) =
  check g.width == w
  check g.height == h
  check g.data.len == w * h
  var mismatches = 0
  for y in 0 ..< h:
    for x in 0 ..< w:
      if g.data[y * w + x] != gradientY(x, y):
        inc mismatches
  check mismatches == 0

suite "extractLuma":
  test "NV12 Y plane copied":
    expectGradient(extractLuma(planarY(64, 48, NV12), LumaOptions()).get, 64, 48)

  test "YUV420P and Y8":
    expectGradient(extractLuma(planarY(32, 16, YUV420P), LumaOptions()).get, 32, 16)
    expectGradient(extractLuma(planarY(32, 16, Y8), LumaOptions()).get, 32, 16)

  test "padded stride": # Review Focus 2
    expectGradient(extractLuma(planarY(641, 479, NV12), LumaOptions()).get, 641, 479)

  test "UYVY and YUYV packed":
    for (fmt, yOff) in [(UYVY, 1), (YUYV, 0)]:
      let f = makeFrame(8, 4, fmt, proc(plane: int, p: ptr UncheckedArray[byte], bpl, rows: int) =
        for y in 0 ..< rows:
          for x in 0 ..< 8:
            p[y * bpl + 2 * x + yOff] = gradientY(x, y)
            p[y * bpl + 2 * x + (1 - yOff)] = 128)
      expectGradient(extractLuma(f, LumaOptions()).get, 8, 4)

  test "P010 takes high byte":
    let f = makeFrame(8, 4, P010, proc(plane: int, p: ptr UncheckedArray[byte], bpl, rows: int) =
      if plane == 0:
        for y in 0 ..< 4:
          for x in 0 ..< 8:
            p[y * bpl + 2 * x] = 0
            p[y * bpl + 2 * x + 1] = gradientY(x, y))
    expectGradient(extractLuma(f, LumaOptions()).get, 8, 4)

  test "fallback format (BGRA) via toImage": # Review Focus 4
    let f = makeFrame(4, 2, BGRA, proc(plane: int, p: ptr UncheckedArray[byte], bpl, rows: int) =
      for i in 0 ..< bpl * rows:
        p[i] = 255)
    let g = extractLuma(f, LumaOptions()).get
    check g.width == 4
    check g.height == 2
    for b in g.data:
      check b >= 250'u8

  test "invalid frame -> none":
    check extractLuma(QVideoFrame.create(), LumaOptions()).isNone

suite "cropAndDecimate":
  var src = newSeq[byte](100 * 50)
  for y in 0 ..< 50:
    for x in 0 ..< 100:
      src[y * 100 + x] = gradientY(x, y)

  test "roi crops":
    let g = cropAndDecimate(src, 100, 50, 100, 1, 0,
                            Opt.some NormRect(x: 0.5, y: 0.5, w: 0.5, h: 0.5), 0)
    check g.width == 50
    check g.height == 25
    check g.data[0] == gradientY(50, 25)

  test "roi clamping": # Review Focus 3
    for r in [NormRect(x: 0.9, y: 0.9, w: 0.5, h: 0.5),
              NormRect(x: -1, y: -1, w: 0, h: 0),
              NormRect(x: 2, y: 2, w: 1, h: 1)]:
      let g = cropAndDecimate(src, 100, 50, 100, 1, 0, Opt.some r, 0)
      check g.width in 1 .. 100
      check g.height in 1 .. 50
      check g.data.len == g.width * g.height

  test "maxDim decimates":
    let g = cropAndDecimate(src, 100, 50, 100, 1, 0, Opt.none NormRect, 25)
    check g.width == 25
    check g.height == 13
    check g.data[1] == gradientY(4, 0)

suite "displayRectToFrame":
  let d = NormRect(x: 0.1, y: 0.2, w: 0.3, h: 0.4)
  proc near(a, b: NormRect): bool =
    abs(a.x - b.x) < 1e-5 and abs(a.y - b.y) < 1e-5 and
      abs(a.w - b.w) < 1e-5 and abs(a.h - b.h) < 1e-5

  test "identity":
    check near(displayRectToFrame(d, FrameTransform()), d)
  test "rotated 90":
    check near(displayRectToFrame(d, FrameTransform(rotation: 90)),
               NormRect(x: 0.2, y: 0.6, w: 0.4, h: 0.3))
  test "rotated 180":
    check near(displayRectToFrame(d, FrameTransform(rotation: 180)),
               NormRect(x: 0.6, y: 0.4, w: 0.3, h: 0.4))
  test "rotated 270":
    check near(displayRectToFrame(d, FrameTransform(rotation: 270)),
               NormRect(x: 0.4, y: 0.1, w: 0.4, h: 0.3))
  test "mirrored":
    check near(displayRectToFrame(d, FrameTransform(mirrored: true)),
               NormRect(x: 0.6, y: 0.2, w: 0.3, h: 0.4))
  test "rotated 90 and mirrored":
    # un-mirror first: (0.6, 0.2, 0.3, 0.4), then un-rotate 90
    check near(displayRectToFrame(d, FrameTransform(rotation: 90, mirrored: true)),
               NormRect(x: 0.2, y: 0.1, w: 0.4, h: 0.3))
  test "round trip, all transforms":
    for rot in [0, 90, 180, 270, -90, 450]:
      for m in [false, true]:
        let t = FrameTransform(rotation: rot, mirrored: m)
        check near(displayRectToFrame(frameRectToDisplay(d, t), t), d)

suite "display-space roi on rotated frames":
  # 64x32 frame, black except a white 16x8 block at the raw top-left. Shown
  # rotated 90° clockwise, that block sits at the displayed top-right.
  const displayTopRight = NormRect(x: 0.75, y: 0.0, w: 0.25, h: 0.25)

  proc allWhite(g: GrayFrame): bool =
    g.data.len > 0 and (for b in g.data: (if b < 250: return false); true)

  proc blockFrame(fmt: int): QVideoFrame =
    makeFrame(64, 32, fmt, proc(plane: int, p: ptr UncheckedArray[byte], bpl, rows: int) =
      for y in 0 ..< rows:
        for x in 0 ..< bpl:
          let white = x < (if fmt == BGRA: 16 * 4 else: 16) and y < 8
          p[y * bpl + x] =
            if plane == 0: (if white: 255'u8 else: 0'u8)
            else: 128'u8)

  test "mapped planes: display roi follows the frame rotation":
    let f = blockFrame(NV12)
    f.setRotation(90)
    let g = extractLuma(f, LumaOptions(roi: Opt.some displayTopRight, roiSpace: rsDisplay))
    check g.isSome
    check g.get.width == 16 and g.get.height == 8
    check allWhite(g.get)
    let raw = extractLuma(f, LumaOptions(roi: Opt.some displayTopRight, roiSpace: rsFrame))
    check not allWhite(raw.get) # same numbers in raw space hit another area

  test "toImage fallback: display roi follows the frame rotation":
    let f = blockFrame(BGRA)
    f.setRotation(90)
    let g = extractLuma(f, LumaOptions(roi: Opt.some displayTopRight, roiSpace: rsDisplay))
    check g.isSome
    check g.get.width == 16 and g.get.height == 8
    check allWhite(g.get)

  test "mirrored frame":
    let f = blockFrame(NV12)
    f.setMirrored(true) # the raw top-left block shows at the displayed top-right
    let g = extractLuma(f, LumaOptions(roi: Opt.some NormRect(x: 0.75, y: 0, w: 0.25, h: 0.25),
                                       roiSpace: rsDisplay))
    check allWhite(g.get)

suite "display-space roi: transformation on the surface format":
  # Phones put the rotation (Android) or rotation + mirror (Darwin) on the
  # QVideoFrameFormat rather than the frame. Same 64x32 frame, white 16x8 block
  # at the raw top-left.
  proc allWhite(g: GrayFrame): bool =
    g.data.len > 0 and (for b in g.data: (if b < 250: return false); true)

  proc surfaceFrame(fmtId: int, rotation = 0, mirrored = false,
                    bottomToTop = false): QVideoFrame =
    let fmt = QVideoFrameFormat.create(QSize.create(64, 32), fmtId.cint)
    fmt.setRotation(rotation.cint)
    fmt.setMirrored(mirrored)
    if bottomToTop:
      fmt.setScanLineDirection(1) # QVideoFrameFormat::BottomToTop
    result = QVideoFrame.create(fmt)
    doAssert result.map(2) # WriteOnly
    for p in 0 ..< result.planeCount().int:
      let
        bpl = result.bytesPerLine(p.cint).int
        rows = result.mappedBytes(p.cint).int div bpl
        bits = cast[ptr UncheckedArray[byte]](result.bits(p.cint))
      for y in 0 ..< rows:
        for x in 0 ..< bpl:
          let white = x < (if fmtId == BGRA: 16 * 4 else: 16) and y < 8
          bits[y * bpl + x] = (if p == 0: (if white: 255'u8 else: 0'u8) else: 128'u8)
    result.unmap()

  proc display(roi: NormRect): LumaOptions =
    LumaOptions(roi: Opt.some roi, roiSpace: rsDisplay)

  test "surface rotation, mapped planes":
    let g = extractLuma(surfaceFrame(NV12, rotation = 90),
                        display(NormRect(x: 0.75, y: 0, w: 0.25, h: 0.25)))
    check g.get.width == 16 and g.get.height == 8
    check allWhite(g.get)

  test "surface rotation, toImage fallback (already applies the surface part)":
    let g = extractLuma(surfaceFrame(BGRA, rotation = 90),
                        display(NormRect(x: 0.75, y: 0, w: 0.25, h: 0.25)))
    check g.get.width * g.get.height == 16 * 8
    check allWhite(g.get)

  test "surface mirror":
    let g = extractLuma(surfaceFrame(NV12, mirrored = true),
                        display(NormRect(x: 0.75, y: 0, w: 0.25, h: 0.25)))
    check allWhite(g.get)

  test "bottom-to-top scan lines":
    # raw row 0 is the bottom of the displayed image
    let g = extractLuma(surfaceFrame(NV12, bottomToTop = true),
                        display(NormRect(x: 0, y: 0.75, w: 0.25, h: 0.25)))
    check allWhite(g.get)

  test "surface and frame rotation add up":
    let f = surfaceFrame(NV12, rotation = 90)
    f.setRotation(90) # 180 in total: the block shows at the bottom-right
    let g = extractLuma(f, display(NormRect(x: 0.75, y: 0.75, w: 0.25, h: 0.25)))
    check allWhite(g.get)

  test "Android front camera: surface rotation + frame mirror":
    let f = surfaceFrame(NV12, rotation = 270)
    f.setMirrored(true)
    check frameTransform(f) == FrameTransform(rotation: 270, mirrored: true)
    check frameTransform(f, includeSurface = false) == FrameTransform(rotation: 0, mirrored: true)

suite "previewRectToDisplay (as VideoOutput lays a frame out)":
  proc near(a, b: NormRect): bool =
    abs(a.x - b.x) < 1e-4 and abs(a.y - b.y) < 1e-4 and
      abs(a.w - b.w) < 1e-4 and abs(a.h - b.h) < 1e-4

  # 1600x900 frame in a 400x430 item; a centred 286x286 scan rect.
  let p = PreviewRoi(x: 57, y: 72, w: 286, h: 286, itemWidth: 400, itemHeight: 430,
                     fill: pfCrop)

  test "crop: the video is scaled to cover the item, centred":
    # scale = max(400/1600, 430/900) = 0.47778 -> 764.4 x 430, x offset -182.2
    let r = previewRectToDisplay(p, 1600, 900)
    check near(r, NormRect(x: (57 + 182.2) / 764.4, y: 72 / 430,
                           w: 286 / 764.4, h: 286 / 430))

  test "fit: the video is scaled to fit, letterboxed":
    var q = p
    q.fill = pfFit
    # scale = min(0.25, 0.4778) = 0.25 -> 400 x 225, y offset 102.5
    let r = previewRectToDisplay(q, 1600, 900)
    check near(r, NormRect(x: 57 / 400, y: 0.0, w: 286 / 400, h: 1.0))

  test "stretch: the video fills the item":
    var q = p
    q.fill = pfStretch
    check near(previewRectToDisplay(q, 1600, 900),
               NormRect(x: 57 / 400, y: 72 / 430, w: 286 / 400, h: 286 / 430))

  test "mirrored preview: x flipped back":
    var q = p
    q.mirrored = true
    q.x = 20 # off-centre so the flip shows
    let plain = previewRectToDisplay(PreviewRoi(x: 20, y: 72, w: 286, h: 286,
                  itemWidth: 400, itemHeight: 430, fill: pfCrop), 1600, 900)
    check near(previewRectToDisplay(q, 1600, 900),
               NormRect(x: 1 - plain.x - plain.w, y: plain.y, w: plain.w, h: plain.h))

  test "degenerate input: the whole frame":
    check near(previewRectToDisplay(p, 0, 900), NormRect(x: 0, y: 0, w: 1, h: 1))
    var q = p
    q.itemWidth = 0
    check near(previewRectToDisplay(q, 1600, 900), NormRect(x: 0, y: 0, w: 1, h: 1))

suite "preview roi through extractLuma":
  # 160x90 frame, black except a white 20x20 block at raw (30..50, 35..55),
  # left of centre. Preview: 40x43 item, crop, a centred 28x28 scan rect:
  # raw x ≈ 0.31..0.69 is inside, the block (x 0.19..0.31) is not.
  proc blockFrame(rotation = 0): QVideoFrame =
    result = makeFrame(160, 90, NV12, proc(plane: int, p: ptr UncheckedArray[byte], bpl, rows: int) =
      for y in 0 ..< rows:
        for x in 0 ..< bpl:
          p[y * bpl + x] =
            if plane == 0: (if x in 30 ..< 50 and y in 35 ..< 55: 255'u8 else: 0'u8)
            else: 128'u8)
    result.setRotation(rotation.cint)

  let scan = PreviewRoi(x: 6, y: 7.5, w: 28, h: 28, itemWidth: 40, itemHeight: 43, fill: pfCrop)

  proc hasWhite(g: GrayFrame): bool =
    for b in g.data:
      if b > 250: return true
    false

  test "only what the preview shows inside the scan rect is extracted":
    let g = extractLuma(blockFrame(), LumaOptions(preview: Opt.some scan))
    check g.isSome
    check not hasWhite(g.get)
    # the block is inside when the scan rect sits over it on screen:
    # display x 0.19..0.31 -> item x = 0.19*76.4-18.2 ≈ -3.7 .. 5.5 (cropped off)
    var left = scan
    left.x = 0
    left.w = 12
    check hasWhite(extractLuma(blockFrame(), LumaOptions(preview: Opt.some left)).get)

  test "the frame's own size decides the crop, not an earlier layout":
    # the same preview over a portrait (rotated) frame maps elsewhere
    let g = extractLuma(blockFrame(90), LumaOptions(preview: Opt.some scan))
    check g.isSome
    check g.get.width < g.get.height or g.get.width == g.get.height # portrait crop of raw
