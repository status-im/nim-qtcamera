## Camera permission (QCameraPermission) status and request.

{.push raises: [], gcsafe.}

import ./types
import ./private/shim

type
  PermissionCallback* = proc(s: PermissionStatus) {.gcsafe, raises: [].}
  PermCbBox = ref object
    cb: PermissionCallback

func toStatus(v: cint): PermissionStatus =
  case v
  of 1: psGranted
  of 2: psDenied
  else: psUndetermined

proc cameraPermissionStatus*(): PermissionStatus =
  ## Never prompts. Platforms without a permission system report psGranted.
  shimCameraPermissionStatus().toStatus

proc permThunk(ctx: pointer, status: cint) {.cdecl, gcsafe, raises: [].} =
  let box = cast[PermCbBox](ctx)
  box.cb(status.toStatus)
  GC_unref(box)

proc requestCameraPermission*(cb: PermissionCallback) =
  ## Must be called on the GUI thread; `cb` runs there too. May show the OS
  ## prompt. Without a permission system `cb` fires synchronously (psGranted).
  let box = PermCbBox(cb: cb)
  GC_ref(box)
  shimRequestCameraPermission(cast[pointer](box), permThunk)
