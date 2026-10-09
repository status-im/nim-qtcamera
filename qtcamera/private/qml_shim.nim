## Bindings to qml_shim.cpp; imported only by qtcamera/qml.

{.push raises: [], gcsafe.}

import seaqt/QtCore/qtcore_pkg
import seaqt/QtQml/qtqml_pkg

{.compile("qml_shim.cpp", "-std=c++17 " & QtCoreCFlags & " " & QtQmlCFlags).}
{.passl: QtQmlLibs.}

proc shimQmlInstall*(engine: pointer, importPath, name: cstring, qobject: pointer) {.
  importc: "qtcamera_qml_install".}
