## Camera permission (QCameraPermission) status and request.

{.push raises: [], gcsafe.}

import results
import ./types
import ./private/shim

export results

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

func cameraSettingsUrl*(): Opt[string] =
  ## The OS URL that opens the camera-permission settings, where one exists.
  ## Android uses an intent instead (see openCameraSettings); Linux has none.
  when defined(macosx):
    Opt.some("x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
  elif defined(windows):
    Opt.some("ms-settings:privacy-webcam")
  elif defined(ios):
    Opt.some("app-settings:")
  else:
    Opt.none(string)

proc canOpenCameraSettings*(): bool =
  ## True where openCameraSettings() can take the user to the OS page that
  ## grants camera access (macOS, Windows, iOS, Android). False on Linux.
  shimCanOpenCameraSettings() != 0

proc openCameraSettings*(): bool =
  ## Opens that page. GUI thread only. False if unsupported, called without a
  ## QGuiApplication / off the GUI thread, or the OS refused.
  shimOpenCameraSettings() != 0
