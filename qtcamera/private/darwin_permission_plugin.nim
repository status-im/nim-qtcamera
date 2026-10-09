## Links Qt's static camera-permission plugin on Apple platforms.
##
## Qt ships the Darwin permission backends only as static plugins; without one,
## QCameraPermission is never granted and the camera stays black. CMake hosts get
## it via `qt_import_plugins(... Qt6::QDarwinCameraPermissionPlugin)`; this
## module does the same for Nim builds.
##
## Hosts that already import the plugin (status-desktop's StatusQ does) must
## compile with `-d:qtcameraNoPermissionPlugin` to avoid duplicate symbols.
## `-d:qtPluginsDir=<dir>` overrides the qmake lookup.

when (defined(macosx) or defined(ios)) and not defined(qtcameraNoPermissionPlugin):
  import std/strutils

  const
    qtPluginsDir {.strdefine.} = staticExec("qmake -query QT_INSTALL_PLUGINS").strip()
    permDir = qtPluginsDir & "/permissions"
    initObj = permDir &
      "/objects-RelWithDebInfo/QDarwinCameraPermissionPlugin_init/" &
      "QDarwinCameraPermissionPlugin_init.cpp.o"

  {.passL: "\"" & initObj & "\"".}
  {.passL: "\"" & permDir & "/libqdarwincamerapermission.a\"".}
  # The request half lives in a separate archive member that Qt's CMake only
  # pulls in (via -u) when the app declares NSCameraUsageDescription. Any host
  # using this library must declare it, so always pull it in.
  {.passL: "-Wl,-u,_QDarwinCameraPermissionRequest".}
  {.passL: "-framework AVFoundation -framework Foundation".}
