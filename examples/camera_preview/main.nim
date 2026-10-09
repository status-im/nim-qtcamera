## Minimal camera preview: Qt's QML camera types + NimQtCamera.FrameTap stats.
## Run: make example

import std/os
import nimqml
import qtcamera/qml

let app = newQGuiApplication()
let engine = newQQmlApplicationEngine()
install(engine)
engine.load(currentSourcePath().parentDir() / "main.qml")
app.exec()
