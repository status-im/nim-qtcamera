## Plain value types shared by every qtcamera module.

{.push raises: [], gcsafe.}

type
  NormRect* = object
    ## Rectangle in normalized frame coordinates (0..1 on both axes).
    x*, y*, w*, h*: float32

  RoiSpace* = enum
    rsFrame    ## raw frame coordinates (default)
    rsDisplay  ## the frame as displayed: its rotation and mirroring applied

  FrameTransform* = object
    ## How a frame is shown: rotated clockwise, then mirrored horizontally
    ## (Qt's order; see qtmultimedia's qvideotransformation_p.h).
    rotation*: int   ## clockwise degrees: 0, 90, 180, 270
    mirrored*: bool

  PreviewFill* = enum
    ## How the preview lays the video out (= VideoOutput.fillMode values).
    pfStretch = 0  ## fills the item, ignoring the aspect ratio
    pfFit = 1      ## scaled to fit inside the item
    pfCrop = 2     ## scaled to cover the item, cropped

  PreviewRoi* = object
    ## A rect on the preview item (item pixels), plus how the preview shows
    ## the video. Converted for each frame from that frame's own size and
    ## transformation, so it holds from the first frame on.
    x*, y*, w*, h*: float32
    itemWidth*, itemHeight*: float32
    fill*: PreviewFill
    mirrored*: bool  ## the preview's own mirror (VideoOutput.mirrored)

  GrayFrame* = object
    ## 8-bit luma image. `data` is tightly packed: row stride == width.
    data*: seq[byte]
    width*, height*: int
    timestampUs*: int64

  CameraPosition* = enum
    cpUnspecified
    cpBack
    cpFront

  CameraInfo* = object
    id*, description*: string
    position*: CameraPosition
    isDefault*: bool

  CameraErrorKind* = enum
    ceNone
    ceNoDevice
    ceDeviceNotFound
    ceCamera

  PermissionStatus* = enum
    ## Same order as Qt::PermissionStatus.
    psUndetermined
    psGranted
    psDenied

func clamp01(v: float32): float32 =
  max(0'f32, min(1'f32, v))

func normalized*(r: NormRect): NormRect =
  ## Clamp into [0,1]x[0,1]. A degenerate result means "full frame".
  let
    x = clamp01(r.x)
    y = clamp01(r.y)
  NormRect(x: x, y: y, w: clamp01(r.x + r.w) - x, h: clamp01(r.y + r.h) - y)

func isEmpty*(r: NormRect): bool =
  r.w <= 0 or r.h <= 0

func normalizedRotation(t: FrameTransform): int =
  ((t.rotation mod 360) + 360) mod 360

func displayRectToFrame*(r: NormRect, t: FrameTransform): NormRect =
  ## Maps a rect in displayed-frame coordinates (rotated, then mirrored) back
  ## to raw frame coordinates, all normalized.
  let d = if t.mirrored: NormRect(x: 1 - r.x - r.w, y: r.y, w: r.w, h: r.h) else: r
  case normalizedRotation(t)
  of 90: NormRect(x: d.y, y: 1 - d.x - d.w, w: d.h, h: d.w)
  of 180: NormRect(x: 1 - d.x - d.w, y: 1 - d.y - d.h, w: d.w, h: d.h)
  of 270: NormRect(x: 1 - d.y - d.h, y: d.x, w: d.h, h: d.w)
  else: d

func frameRectToDisplay*(r: NormRect, t: FrameTransform): NormRect =
  ## Inverse of displayRectToFrame: raw frame coordinates to displayed ones.
  let d =
    case normalizedRotation(t)
    of 90: NormRect(x: 1 - r.y - r.h, y: r.x, w: r.h, h: r.w)
    of 180: NormRect(x: 1 - r.x - r.w, y: 1 - r.y - r.h, w: r.w, h: r.h)
    of 270: NormRect(x: r.y, y: 1 - r.x - r.w, w: r.h, h: r.w)
    else: r
  if t.mirrored: NormRect(x: 1 - d.x - d.w, y: d.y, w: d.w, h: d.h) else: d

func previewRectToDisplay*(p: PreviewRoi, displayWidth, displayHeight: float32): NormRect =
  ## The part of a displayed frame (displayWidth x displayHeight, its own
  ## rotation applied) under `p`, normalized, as VideoOutput lays it out: the
  ## frame scaled per `fill` and centred in the item, then the preview's
  ## mirror undone. The whole frame for degenerate input.
  const whole = NormRect(x: 0, y: 0, w: 1, h: 1)
  if displayWidth <= 0 or displayHeight <= 0 or p.itemWidth <= 0 or p.itemHeight <= 0:
    return whole
  let
    (cw, ch) =
      case p.fill
      of pfStretch: (p.itemWidth, p.itemHeight)
      of pfFit, pfCrop:
        let s =
          if p.fill == pfFit: min(p.itemWidth / displayWidth, p.itemHeight / displayHeight)
          else: max(p.itemWidth / displayWidth, p.itemHeight / displayHeight)
        (displayWidth * s, displayHeight * s)
    cx = (p.itemWidth - cw) / 2
    cy = (p.itemHeight - ch) / 2
    left = clamp((p.x - cx) / cw, 0'f32, 1'f32)
    top = clamp((p.y - cy) / ch, 0'f32, 1'f32)
    right = clamp((p.x + p.w - cx) / cw, 0'f32, 1'f32)
    bottom = clamp((p.y + p.h - cy) / ch, 0'f32, 1'f32)
  if right <= left or bottom <= top:
    return whole
  let x = if p.mirrored: 1 - right else: left
  NormRect(x: x, y: top, w: right - left, h: bottom - top)

