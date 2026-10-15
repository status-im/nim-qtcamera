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

