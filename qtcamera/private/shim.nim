## Low-level bindings to shim.cpp. See shim.h for why it exists.

{.push raises: [], gcsafe.}

import std/os
import seaqt/QtCore/qtcore_pkg
import seaqt/QtMultimedia/qtmultimedia_pkg
import ./darwin_permission_plugin

const shimHeader = currentSourcePath().parentDir() / "shim.h"

{.compile("shim.cpp", "-std=c++17 " & QtCoreCFlags & " " & QtMultimediaCFlags).}
{.passl: QtCoreLibs.}

type
  FrameCb* = proc(ctx: pointer, frame: pointer) {.cdecl, gcsafe, raises: [].}
  PermissionCb* = proc(ctx: pointer, status: cint) {.cdecl, gcsafe, raises: [].}

proc shimConnectFrames*(sink, ctx: pointer, cb: FrameCb): pointer {.
  importc: "qtcamera_connect_frames", header: shimHeader.}
proc shimDisconnect*(conn: pointer) {.
  importc: "qtcamera_disconnect", header: shimHeader.}
proc shimCameraPermissionStatus*(): cint {.
  importc: "qtcamera_camera_permission_status", header: shimHeader.}
proc shimRequestCameraPermission*(ctx: pointer, cb: PermissionCb) {.
  importc: "qtcamera_request_camera_permission", header: shimHeader.}
proc shimQObjectFromVariant*(v: pointer): pointer {.
  importc: "qtcamera_qobject_from_variant", header: shimHeader.}
