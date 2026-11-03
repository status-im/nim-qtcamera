version     = "0.1.0"
author      = "Status Research & Development GmbH"
description = "Camera access for Nim apps on Qt Multimedia (seaqt)"
license     = "MIT"

requires "nim >= 2.0.0", "results"
# A dependent loads the QML module from the installed package.
installDirs = @["qtcamera", "qml"]
installFiles = @["qtcamera.nim"]
# seaqt and nimqml-seaqt are consumed by path (pinned in the Makefile), matching
# how status-desktop vendors them.

task test, "Run tests":
  exec "make test"
