version     = "0.1.0"
author      = "Status Research & Development GmbH"
description = "Camera access for Nim apps on Qt Multimedia (seaqt)"
license     = "MIT"

requires "nim >= 2.0.0", "results"
# seaqt and nimqml-seaqt are consumed by path (pinned in the Makefile), matching
# how status-desktop vendors them.

task test, "Run tests":
  exec "make test"
