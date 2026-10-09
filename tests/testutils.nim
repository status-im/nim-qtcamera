## Shared helpers for the test suites.

import std/os
import seaqt/[qguiapplication, qcoreapplication]

var app {.threadvar.}: QGuiApplication

proc ensureApp*() =
  ## One offscreen QGuiApplication per test binary.
  if app.h == nil:
    putEnv("QT_QPA_PLATFORM", "offscreen")
    app = QGuiApplication.create()

proc processEvents*() =
  QCoreApplication.processEvents()
