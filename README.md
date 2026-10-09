# nim-qtcamera

Camera access for Nim applications, built on Qt Multimedia through
[nim-seaqt](https://github.com/seaqt/nim-seaqt) (Qt 6.8+).

It provides:

- a **headless Nim API** (no QML): camera discovery and hot-plug, camera
  permission, a capture session, and a pull-model **frame tap** that hands out
  8-bit luma (`GrayFrame`) frames, for decoders such as QR scanners;
- a **QML component**, `NimQtCamera.FrameTap`, that taps frames from any
  `VideoOutput.videoSink`. In QML the camera itself is Qt's own `Camera` /
  `CaptureSession` / `VideoOutput` / `MediaDevices` / `CameraPermission`.

## Modules

| Module | Purpose |
|---|---|
| `qtcamera/types` | `GrayFrame`, `NormRect`, `CameraInfo`, error/permission enums |
| `qtcamera/luma` | `extractLuma(QVideoFrame, LumaOptions)`: Y plane for NV12/NV21/YUV420P/YV12/IMC*/Y8, one byte per pixel for UYVY/YUYV/Y16/P010/P016, `toImage()` fallback otherwise; ROI crop + integer downscale |
| `qtcamera/frametap` | `FrameTap`: `attach(sink)`, `arm()`, `detach()`, `minIntervalMs`, stats |
| `qtcamera/devices` | `listCameras`, `defaultCamera`, `findDevice`, `CameraDevicesWatcher` |
| `qtcamera/permission` | `cameraPermissionStatus`, `requestCameraPermission` |
| `qtcamera/session` | `CameraSession`: device selection, active, errors, preview output, `videoSink` |
| `qtcamera/qml` | QML backend + `install(engine)`; `findTap` / `armTap` / `setTapConsumer` for other Nim libraries |
| `qml/NimQtCamera` | `FrameTap.qml` |

`import qtcamera` re-exports the core (everything except `qml`).

## Pull model and threading

A tap attached to a sink does nothing per frame except count it, until it is
**armed**. An armed tap maps the next frame, copies its luma, disarms itself and
calls the consumer. The consumer arms it again when it is ready for another
frame, so a slow decoder never builds a backlog and no timer is involved.
`minIntervalMs` caps the pull rate.

Frames are delivered on the sink's thread: the GUI thread for sinks created
there, including QML `VideoOutput` sinks. Call `arm`/`detach` on that thread.
Consumers that work elsewhere should move the `GrayFrame` into their own
channel.

## QML usage

```nim
import nimqml, qtcamera/qml
let engine = newQQmlApplicationEngine()
install(engine)  # import path + `nimQtCameraBackend` context property
```

C++ hosts linking a Nim static library call `installOnEngine(qqmlEnginePtr)`
(`raises: []`) from an exported C function, once per engine. Every engine
shares the GUI thread's backend.

```qml
import QtMultimedia
import NimQtCamera 1.0

CaptureSession { camera: Camera { id: camera; active: true }; videoOutput: preview }
VideoOutput { id: preview }
FrameTap { videoSink: preview.videoSink; enabled: camera.active; maxFps: 10; maxDim: 640 }
```

`maxFps` defaults to 5. `0` pulls every frame, which costs one luma copy per
frame on the GUI thread.

A Nim library can consume a QML tap's frames through its `handle`:

```nim
setTapConsumer(handle, proc(f: sink GrayFrame) {.gcsafe, raises: [].} =
  decode(f)
  armTap(handle))  # request the next frame
```

`findTap`, `armTap` and `setTapConsumer` are `gcsafe, raises: []`, so they
work from inside a consumer. `armTap` is ignored while the QML `FrameTap` is
disabled. A consumer may replace or clear itself while running.
`setTapConsumer(handle, nil)` restores the default consumer and, if the tap is
enabled, resumes pulling.

Why a backend object and not registered QML types: nimqml-seaqt's
`qmlRegisterType` is currently a stub, so Nim cannot register QML types.

## Why there is a small C++ shim

`qtcamera/private/shim.cpp` (≈60 lines) fills gaps in seaqt:

1. `QCameraPermission` / `QCoreApplication::requestPermission` are not bound.
2. `onVideoFrameChanged` returns no connection handle, so a tap could never
   detach from a sink it does not own.
3. Extracting a `QObject*` from a `QVariant` handed in from QML (nimqml wraps
   slot arguments in a nested `QVariant`).

## Host application requirements

- Compile with `--mm:orc --threads:on`.
- Declare camera permission: `NSCameraUsageDescription` (iOS/macOS
  Info.plist), `android.permission.CAMERA`, and on macOS
  `com.apple.security.device.camera` when sandboxed / hardened.
- Apple platforms: this library links Qt's static camera-permission plugin
  (`qtcamera/private/darwin_permission_plugin.nim`). Hosts that already import
  `Qt6::QDarwinCameraPermissionPlugin` (for example via CMake
  `qt_import_plugins`) must compile with `-d:qtcameraNoPermissionPlugin`.
  `-d:qtPluginsDir=<dir>` overrides the `qmake -query QT_INSTALL_PLUGINS` lookup
  (the Makefile passes it from `$(QMAKE)`). The build fails with a clear error
  if the plugin can't be found.
- Request camera permission before activating a camera; Qt does not do it.

## Development

```sh
make deps          # clone pinned dependencies into .deps/ (same commits as status-desktop)
make test          # headless suites — never opens the camera or prompts
make camera-test   # adds the real-camera CameraSession suite
make spike         # real-camera measurements (see docs/spike-results.md)
make example       # examples/camera_preview
```

`qmake` must be on `PATH` (Qt is located through pkg-config via
[prl-to-pc](https://github.com/status-im/prl-to-pc)). On macOS, test and
example binaries embed `resources/Info.plist` so camera permission can be
granted. After editing `shim.cpp`, run `make test EXTRA_NIMFLAGS=-f`: Nim does
not rebuild `{.compile.}`'d C++ on its own.
