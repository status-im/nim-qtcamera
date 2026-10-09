# nim-qtcamera

Camera access for Nim applications, built on Qt Multimedia through
[nim-seaqt](https://github.com/seaqt/nim-seaqt). Work in progress — see
`docs/spike-results.md`.

```sh
make deps    # clone pinned dependencies into .deps/
make test    # headless test suites (never opens the camera)
make spike   # real-camera spike (macOS: grants permission via Info.plist)
```
