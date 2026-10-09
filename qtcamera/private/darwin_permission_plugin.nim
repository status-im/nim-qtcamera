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
    # The init object's directory is named after the Qt build config
    # (objects-RelWithDebInfo in the Qt installer, objects-Release elsewhere).
    initObj = staticExec("ls -d \"" & permDir &
      "\"/objects-*/QDarwinCameraPermissionPlugin_init/*.o 2>/dev/null | head -n 1").strip()

  when initObj.len == 0:
    {.error: "Qt camera permission plugin not found under " & permDir &
      " (pass -d:qtPluginsDir=<dir> or -d:qtcameraNoPermissionPlugin)".}

  {.passL: "\"" & initObj & "\"".}
  {.passL: "\"" & permDir & "/libqdarwincamerapermission.a\"".}
  # The request half lives in a separate archive member that Qt's CMake only
  # pulls in (via -u) when the app declares NSCameraUsageDescription. Any host
  # using this library must declare it, so always pull it in.
  {.passL: "-Wl,-u,_QDarwinCameraPermissionRequest".}
  {.passL: "-framework AVFoundation -framework Foundation".}
