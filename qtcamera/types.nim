## Plain value types shared by every qtcamera module.

{.push raises: [], gcsafe.}

type
  NormRect* = object
    ## Rectangle in normalized frame coordinates (0..1 on both axes).
    x*, y*, w*, h*: float32

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
