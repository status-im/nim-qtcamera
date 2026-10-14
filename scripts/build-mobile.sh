#!/usr/bin/env bash
# Cross-compiles nim-qtcamera (core + QML layer) as a static library: the CI
# compile check for mobile. Run through `make mobile-lib`, which sets QT_KIT and
# exports prl-to-pc's pkg-config environment for the kit selected by QMAKE.
#   scripts/build-mobile.sh ios-sim | ios | android-arm64 | android-x86_64
set -euo pipefail
cd "$(dirname "$0")/.."
TARGET=${1:?target: ios-sim | ios | android-arm64 | android-x86_64}
QT_KIT=${QT_KIT:?QT_KIT (Qt mobile kit root) is not set; use make mobile-lib}
OUT=build/mobile/$TARGET
WRAP=$OUT/bin
mkdir -p "$WRAP"
EXTRA=()

case "$TARGET" in
  ios|ios-sim)
    if [[ $TARGET == ios ]]; then SDK=iphoneos; TRIPLE=arm64-apple-ios17.0
    else SDK=iphonesimulator; TRIPLE=arm64-apple-ios17.0-simulator; fi
    printf '#!/bin/sh\nexec xcrun --sdk %s clang -target %s "$@"\n' "$SDK" "$TRIPLE" > "$WRAP/cc"
    chmod +x "$WRAP/cc"
    CC=$PWD/$WRAP/cc
    NIM_TARGET=(--os:ios --cpu:arm64)
    # prl-to-pc's generated iOS Qt6Multimedia.pc lists only Qt6Core in Requires
    # (macOS and Android list Qt6Gui/Qt6Network), so seaqt's Multimedia glue
    # can't find QtGui headers. Remove once prl-to-pc's iOS tree is fixed.
    EXTRA=(--passC:"-I$QT_KIT/lib/QtGui.framework/Headers"
           --passC:"-I$QT_KIT/lib/QtNetwork.framework/Headers") ;;
  android-arm64|android-x86_64)
    SDK_DIR=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
    NDK=${ANDROID_NDK_ROOT:-${ANDROID_NDK_HOME:-}}
    if [[ -z "$NDK" && -n "$SDK_DIR" && -d "$SDK_DIR/ndk" ]]; then
      NDK=$SDK_DIR/ndk/$(ls "$SDK_DIR/ndk" | sort -V | tail -1)
    fi
    [[ -n "$NDK" && -d "$NDK" ]] || { echo "Android NDK not found: set ANDROID_NDK_ROOT" >&2; exit 2; }
    case "$(uname -s)" in Darwin) HOST=darwin-x86_64 ;; *) HOST=linux-x86_64 ;; esac
    BIN=$NDK/toolchains/llvm/prebuilt/$HOST/bin
    if [[ $TARGET == android-arm64 ]]; then CC=$BIN/aarch64-linux-android28-clang; CPU=arm64
    else CC=$BIN/x86_64-linux-android28-clang; CPU=amd64; fi
    # ELF archives: Nim's clang backend runs `llvm-ar` on Linux hosts and `ar`
    # on macOS (whose ar can't write ELF archives), so expose both.
    ln -sf "$BIN/llvm-ar" "$WRAP/ar"; ln -sf "$BIN/llvm-ar" "$WRAP/llvm-ar"
    export PATH="$PWD/$WRAP:$PATH"
    NIM_TARGET=(--os:android --cpu:$CPU -d:androidNDK) ;;
  *) echo "unknown target: $TARGET" >&2; exit 2 ;;
esac

nim c --app:staticlib --noMain -d:release --hints:off --mm:orc --threads:on \
  "${NIM_TARGET[@]}" --cc:clang --clang.exe="$CC" --clang.linkerexe="$CC" \
  -d:qtcameraNoPermissionPlugin ${EXTRA[@]+"${EXTRA[@]}"} \
  --nimcache:"$OUT/cache" --out:"$PWD/$OUT/libqtcamera.a" tests/compile/qtcamera_lib.nim
ls -l "$OUT/libqtcamera.a"
echo "mobile-lib $TARGET: OK"
