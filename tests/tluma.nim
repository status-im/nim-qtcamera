import std/unittest
import results
import seaqt/qvideoframe
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
