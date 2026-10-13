## Low-level bindings to shim.cpp. See shim.h for why it exists.

{.push raises: [], gcsafe.}

import seaqt/QtCore/qtcore_pkg
import seaqt/QtGui/qtgui_pkg
import seaqt/QtMultimedia/qtmultimedia_pkg
import ./darwin_permission_plugin


{.compile("shim.cpp", "-std=c++17 " & QtCoreCFlags & " " & QtGuiCFlags & " " &
  QtMultimediaCFlags).}
{.passl: QtCoreLibs.}
{.passl: QtGuiLibs.}

type
  FrameCb* = proc(ctx: pointer, frame: pointer) {.cdecl, gcsafe, raises: [].}
  PermissionCb* = proc(ctx: pointer, status: cint) {.cdecl, gcsafe, raises: [].}

proc shimConnectFrames*(sink, ctx: pointer, cb: FrameCb): pointer {.
  importc: "qtcamera_connect_frames".}
proc shimDisconnect*(conn: pointer) {.
  importc: "qtcamera_disconnect".}
proc shimCameraPermissionStatus*(): cint {.
  importc: "qtcamera_camera_permission_status".}
proc shimRequestCameraPermission*(ctx: pointer, cb: PermissionCb) {.
  importc: "qtcamera_request_camera_permission".}
proc shimQObjectFromVariant*(v: pointer): pointer {.
  importc: "qtcamera_qobject_from_variant".}
proc shimCanOpenCameraSettings*(): cint {.
  importc: "qtcamera_can_open_camera_settings".}
proc shimOpenCameraSettings*(): cint {.
  importc: "qtcamera_open_camera_settings".}

type AppActivatedCb* = proc(ctx: pointer) {.cdecl, gcsafe, raises: [].}
proc shimOnAppActivated*(ctx: pointer, cb: AppActivatedCb): pointer {.
  importc: "qtcamera_on_app_activated".}
proc shimDisconnectAppActivated*(handle: pointer) {.
  importc: "qtcamera_disconnect_app_activated".}
