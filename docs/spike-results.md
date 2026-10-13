# Spike results (architecture spikes 1 + 4)

Run: `make spike` — `tests/manual/tspike_camera.nim`. Default camera, bare
`QVideoSink` on a `QMediaCaptureSession`, 5 s capture.

## macOS 26 (Darwin 25.2), Qt 6.11.0, FaceTime HD Camera — 2026-10-09

| Measure | Result |
|---|---|
| Devices | 2 (FaceTime HD Camera default; iPhone Continuity Camera). `position()` = 0 (Unspecified) for both |
| Frames in 5 s | 149 (~30 fps) |
| Pixel format | NV12 (18) for every frame |
| Handle type | 0 = NoHandle (CPU memory), every frame |
| `map(ReadOnly)` | 149/149 succeeded |
| Frame size | 1552x1552, 2 planes |
| Emitted off the GUI thread | 0/149 |

Verdict: **go**. seaqt multimedia works end to end; Y-plane extraction from
NV12 is the main path on macOS; no GPU readback needed.

## Findings that changed the plan

1. **Permission plugin must be linked.** Qt ships Darwin permission backends as
   static plugins. Without `libqdarwincamerapermission.a` + its `_init` object,
   `QCameraPermission` can never be granted. Added
   `qtcamera/private/darwin_permission_plugin.nim` (opt-out
   `-d:qtcameraNoPermissionPlugin` for hosts such as StatusQ that already import
   it).
2. **The request half needs `-Wl,-u,_QDarwinCameraPermissionRequest`.** Qt's CMake
   adds it only when the app declares `NSCameraUsageDescription`; without it
   `requestPermission` logs "Could not request QCameraPermission" and denies.
3. **Unbundled binaries need an embedded Info.plist** (`-sectcreate __TEXT
   __info_plist resources/Info.plist`) carrying `NSCameraUsageDescription`.
   The Makefile adds it on macOS for tests and examples.
4. **`QCamera` does not request permission itself.** Activating the camera before
   permission is granted logs "Access to camera not granted" and yields no
   frames; the session must request first (CameraPermission unit).
5. Camera `position()` is Unspecified on macOS desktop cameras, so front/back
   (and mirroring) cannot be derived from it there — same as today's
   `StatusQrCodeCapture.qml` comment.

## Still to measure

Linux, Windows, Android, iOS — when Phase 5 build wiring starts. Android/iOS
texture-backed frames are the main open risk (`toImage()` fallback in
`qtcamera/luma.nim`).

## Camera-settings shim cross-compile (2026-10-13)

`qtcamera/private/shim.cpp` (with `qtcamera_open_camera_settings`) compiles for:

```sh
# QT: directory holding the Qt 6.11 kits (macos/, ios/, android_arm64_v8a/ ...)
QT=$(dirname "$(qmake -query QT_INSTALL_PREFIX)")
# iOS simulator arm64 → Mach-O arm64 object (QDesktopServices path)
xcrun --sdk iphonesimulator clang++ -std=c++17 -c qtcamera/private/shim.cpp -o shim-ios.o \
  -target arm64-apple-ios17.0-simulator -F$QT/ios/lib -I$QT/ios/include -I$QT/ios/mkspecs/macx-ios-clang
# Android arm64-v8a → ELF aarch64 object (JNI path: QJniObject/QJniEnvironment)
# NDK: ANDROID_NDK_ROOT; host tag darwin-x86_64 (macOS) or linux-x86_64 (Linux)
NDK=$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/darwin-x86_64/bin
A=$QT/android_arm64_v8a
$NDK/aarch64-linux-android28-clang++ -std=c++17 -fPIC -c qtcamera/private/shim.cpp -o shim-android.o \
  -I$A/include -I$A/include/QtCore -I$A/include/QtGui -I$A/include/QtMultimedia -I$A/mkspecs/android-clang
```

Compile-only: opening the settings page on a device is verified in Phase 4/5.
